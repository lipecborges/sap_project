import { WebSocket } from "ws";
import { z } from "zod";
import type { ConnectorConfig } from "./config";
import { createLogger, type Logger } from "./logger";
import { callSap, SapCallError } from "./sap";

export { checkPath } from "./sap";

export const CONNECTOR_VERSION = "0.1.0";
export const PROTOCOL_VERSION = 1;
const WS_PATH = "/connector/v1/ws";
const MAX_FRAME_BYTES = 5 * 1024 * 1024;

const RequestFrame = z.object({
  type: z.literal("request"),
  id: z.string().min(1).max(100),
  method: z.string(),
  path: z.string(),
  headers: z.record(z.string(), z.string()).default({}),
  body: z.string().optional(),
  timeoutMs: z.number().int().positive().max(300_000),
});
const ServerFrame = z.discriminatedUnion("type", [
  z.object({ type: z.literal("welcome"), v: z.number(), connectorId: z.string() }),
  RequestFrame,
]);

export interface ConnectorClientOptions {
  logger?: Logger;
  version?: string;
  /** Backoff da reconexão: começa em baseDelayMs, dobra até maxDelayMs, com jitter. */
  baseDelayMs?: number;
  maxDelayMs?: number;
  /** Sem ping do servidor por este tempo, a conexão é considerada morta (o servidor pinga a cada 20 s). */
  idleTimeoutMs?: number;
  /** Teto do corpo da resposta do SAP (precisa caber no quadro de 5 MB). */
  maxResponseBytes?: number;
  /** Espera por requisições em andamento ao encerrar. */
  shutdownGraceMs?: number;
}

export type ConnectorState = "idle" | "connecting" | "online" | "reconnecting" | "stopped";

/**
 * Cliente do conector: mantém a conexão de saída com a API, repassa as requisições ao SAP e reconecta
 * sozinho. Nada aqui registra credenciais, cabeçalhos ou corpos.
 */
export class ConnectorClient {
  private socket?: WebSocket;
  private _state: ConnectorState = "idle";
  private attempt = 0;
  private reconnectTimer?: NodeJS.Timeout;
  private idleTimer?: NodeJS.Timeout;
  private readonly inFlight = new Map<string, AbortController>();
  private readonly log: Logger;
  private readonly opts: Required<Omit<ConnectorClientOptions, "logger">>;
  private fatalHandler?: (reason: string) => void;
  private stateWaiters: Array<{ state: ConnectorState; resolve: () => void }> = [];

  constructor(
    private readonly config: ConnectorConfig,
    options: ConnectorClientOptions = {},
  ) {
    this.log = options.logger ?? createLogger(config.logLevel);
    this.opts = {
      version: options.version ?? CONNECTOR_VERSION,
      baseDelayMs: options.baseDelayMs ?? 1_000,
      maxDelayMs: options.maxDelayMs ?? 60_000,
      idleTimeoutMs: options.idleTimeoutMs ?? 60_000,
      maxResponseBytes: options.maxResponseBytes ?? 4 * 1024 * 1024,
      shutdownGraceMs: options.shutdownGraceMs ?? 10_000,
    };
  }

  get state(): ConnectorState {
    return this._state;
  }

  /** Chamado quando a API rejeita o token (401): não adianta tentar de novo. */
  onFatal(handler: (reason: string) => void): void {
    this.fatalHandler = handler;
  }

  start(): void {
    if (this._state !== "idle") return;
    this.connect();
  }

  /** Resolve quando o estado é atingido (testes e diagnóstico). */
  waitFor(state: ConnectorState, timeoutMs = 5_000): Promise<void> {
    if (this._state === state) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const waiter = {
        state,
        resolve: () => {
          clearTimeout(timer);
          resolve();
        },
      };
      const timer = setTimeout(() => {
        this.stateWaiters = this.stateWaiters.filter((w) => w !== waiter);
        reject(new Error(`Tempo esgotado esperando o estado ${state} (atual: ${this._state})`));
      }, timeoutMs);
      this.stateWaiters.push(waiter);
    });
  }

  /** Encerramento gracioso: fecha o socket, aguarda as requisições em andamento (até o limite) e para. */
  async stop(): Promise<void> {
    if (this._state === "stopped") return;
    this.setState("stopped");
    clearTimeout(this.reconnectTimer);
    clearTimeout(this.idleTimer);
    const deadline = Date.now() + this.opts.shutdownGraceMs;
    while (this.inFlight.size > 0 && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
    for (const controller of this.inFlight.values()) controller.abort();
    this.inFlight.clear();
    const socket = this.socket;
    if (socket && socket.readyState !== WebSocket.CLOSED) {
      await new Promise<void>((resolve) => {
        const force = setTimeout(() => {
          socket.terminate();
          resolve();
        }, 2_000);
        socket.once("close", () => {
          clearTimeout(force);
          resolve();
        });
        socket.close(1001, "conector encerrando");
      });
    }
    this.log.info({}, "conector encerrado");
  }

  /** Derruba a conexão atual sem parar o cliente (testes de reconexão). */
  dropConnection(): void {
    this.socket?.terminate();
  }

  private setState(state: ConnectorState): void {
    this._state = state;
    this.log.info({ state }, "estado do conector");
    for (const waiter of this.stateWaiters.filter((w) => w.state === state)) waiter.resolve();
    this.stateWaiters = this.stateWaiters.filter((w) => w.state !== state);
  }

  private url(): string {
    const url = new URL(this.config.raioxUrl);
    if (url.pathname === "/" || url.pathname === "") url.pathname = WS_PATH;
    return url.toString();
  }

  private connect(): void {
    if (this._state === "stopped") return;
    this.setState(this.attempt === 0 ? "connecting" : "reconnecting");
    const url = this.url();
    const socket = new WebSocket(url, {
      headers: { authorization: `Bearer ${this.config.token}` },
      maxPayload: MAX_FRAME_BYTES,
      handshakeTimeout: 15_000,
    });
    this.socket = socket;

    socket.on("unexpected-response", (_req, res) => {
      res.resume();
      if (res.statusCode === 401 || res.statusCode === 403) {
        const reason = "Token do conector inválido ou revogado: gere um novo na tela de administração do Raio-X";
        this.log.error({ status: res.statusCode }, reason);
        void this.stop().then(() => this.fatalHandler?.(reason));
        return;
      }
      this.log.warn({ status: res.statusCode }, "a API recusou a conexão");
    });
    socket.on("open", () => {
      this.log.info({ host: new URL(url).host }, "conectado à API; enviando hello");
      this.armIdleTimer(socket);
      const hello = {
        type: "hello",
        v: PROTOCOL_VERSION,
        version: this.opts.version,
        sapBaseUrlHost: new URL(this.config.sapBaseUrl).host,
      };
      socket.send(JSON.stringify(hello));
    });
    socket.on("ping", () => this.armIdleTimer(socket));
    socket.on("message", (data, isBinary) => {
      if (isBinary) return;
      this.onMessage(socket, data.toString("utf8"));
    });
    socket.on("error", (err) => {
      this.log.warn({ error: err.message }, "erro na conexão com a API");
    });
    socket.on("close", (code) => {
      clearTimeout(this.idleTimer);
      if (this.socket !== socket) return;
      // O que estava em andamento perdeu o destino: cancela as chamadas ao SAP.
      for (const controller of this.inFlight.values()) controller.abort();
      this.inFlight.clear();
      if (this._state === "stopped") return;
      this.log.warn({ code }, "conexão com a API encerrada");
      this.scheduleReconnect();
    });
  }

  private armIdleTimer(socket: WebSocket): void {
    clearTimeout(this.idleTimer);
    this.idleTimer = setTimeout(() => {
      this.log.warn({}, "sem sinal da API: reiniciando a conexão");
      socket.terminate();
    }, this.opts.idleTimeoutMs);
  }

  private scheduleReconnect(): void {
    const ceiling = Math.min(this.opts.maxDelayMs, this.opts.baseDelayMs * 2 ** this.attempt);
    // Jitter: entre 50% e 100% do teto, para que vários conectores não reconectem juntos.
    const delay = Math.round(ceiling * (0.5 + Math.random() * 0.5));
    this.attempt += 1;
    this.setState("reconnecting");
    this.log.info({ delayMs: delay, attempt: this.attempt }, "nova tentativa de conexão agendada");
    this.reconnectTimer = setTimeout(() => this.connect(), delay);
  }

  private onMessage(socket: WebSocket, text: string): void {
    let frame: z.infer<typeof ServerFrame>;
    try {
      frame = ServerFrame.parse(JSON.parse(text));
    } catch {
      this.log.warn({}, "quadro desconhecido da API ignorado");
      return;
    }
    if (frame.type === "welcome") {
      this.attempt = 0;
      this.setState("online");
      this.log.info({ connectorId: frame.connectorId }, "conector online");
      return;
    }
    void this.handleRequest(socket, frame);
  }

  private send(socket: WebSocket, frame: unknown): void {
    if (socket.readyState !== WebSocket.OPEN) return;
    socket.send(JSON.stringify(frame));
  }

  private async handleRequest(socket: WebSocket, frame: z.infer<typeof RequestFrame>): Promise<void> {
    const started = Date.now();
    const controller = new AbortController();
    this.inFlight.set(frame.id, controller);
    // Só método e caminho sem query: a query pode carregar parâmetros do usuário.
    const where = { method: frame.method, path: frame.path.split("?")[0] };
    try {
      const result = await callSap(
        {
          method: frame.method,
          path: frame.path,
          headers: frame.headers,
          body: frame.body,
          timeoutMs: frame.timeoutMs,
        },
        {
          baseUrl: this.config.sapBaseUrl,
          apiPath: this.config.sapApiPath,
          ca: this.config.sapCa,
          maxResponseBytes: this.opts.maxResponseBytes,
        },
        controller.signal,
      );
      this.log.info({ ...where, status: result.status, durationMs: Date.now() - started }, "requisição atendida");
      this.send(socket, {
        type: "response",
        id: frame.id,
        status: result.status,
        ...(result.contentType ? { contentType: result.contentType } : {}),
        body: result.body,
      });
    } catch (err) {
      if (controller.signal.aborted) return;
      const code = err instanceof SapCallError ? err.code : "INTERNAL";
      const message = err instanceof SapCallError ? err.message : "Erro interno do conector";
      this.log.warn({ ...where, code, durationMs: Date.now() - started }, "requisição recusada ou com falha");
      this.send(socket, { type: "error", id: frame.id, code, message });
    } finally {
      this.inFlight.delete(frame.id);
    }
  }
}
