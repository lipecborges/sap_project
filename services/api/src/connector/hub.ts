import { randomUUID } from "node:crypto";
import type { FastifyBaseLogger } from "fastify";
import type { WebSocket } from "ws";
import { AppError } from "../errors";
import type { ConnectorHub, HttpRequestSpec, HttpResponseSpec } from "../sap/transport";
import { ConnectorFrame, MAX_FRAME_BYTES, PROTOCOL_VERSION, type RequestFrame, type WelcomeFrame } from "./protocol";
import type { ConnectorRepository, ConnectorRow } from "./repository";

export interface GatewayOptions {
  /** Requisições simultâneas por conector. */
  maxInFlight?: number;
  maxFrameBytes?: number;
  /** Intervalo do ping do WebSocket. */
  pingIntervalMs?: number;
  /** Sem pong por este tempo, a conexão é derrubada. */
  pongTimeoutMs?: number;
  /** Prazo para o conector enviar o hello depois de conectar. */
  helloTimeoutMs?: number;
  /** Folga somada ao prazo da requisição, para o conector responder o próprio timeout. */
  graceMs?: number;
}

interface Pending {
  resolve: (response: HttpResponseSpec) => void;
  reject: (err: AppError) => void;
  timer: NodeJS.Timeout;
}

interface Session {
  connector: ConnectorRow;
  socket: WebSocket;
  ready: boolean;
  pending: Map<string, Pending>;
  lastPong: number;
  timers: NodeJS.Timeout[];
}

const unavailable = (message: string) => new AppError(503, "SAP_UNAVAILABLE", message);

/** Sessões WebSocket vivas dos conectores e o encaminhamento de requisições HTTP até elas (D35). */
export class GatewayHub implements ConnectorHub {
  private readonly sessions = new Map<string, Session>();
  private readonly opts: Required<GatewayOptions>;

  constructor(
    readonly repository: ConnectorRepository,
    private readonly log: FastifyBaseLogger,
    options: GatewayOptions = {},
  ) {
    this.opts = {
      maxInFlight: options.maxInFlight ?? 32,
      maxFrameBytes: options.maxFrameBytes ?? MAX_FRAME_BYTES,
      pingIntervalMs: options.pingIntervalMs ?? 20_000,
      pongTimeoutMs: options.pongTimeoutMs ?? 45_000,
      helloTimeoutMs: options.helloTimeoutMs ?? 10_000,
      graceMs: options.graceMs ?? 2_000,
    };
  }

  get maxFrameBytes(): number {
    return this.opts.maxFrameBytes;
  }

  isOnline(connectorId: string): boolean {
    return this.sessions.get(connectorId)?.ready ?? false;
  }

  /** Assume um WebSocket já autenticado. Se o conector já estava conectado, a nova conexão substitui a antiga. */
  accept(connector: ConnectorRow, socket: WebSocket): void {
    const previous = this.sessions.get(connector.id);
    const session: Session = {
      connector,
      socket,
      ready: false,
      pending: new Map(),
      lastPong: Date.now(),
      timers: [],
    };
    this.sessions.set(connector.id, session);
    if (previous) {
      this.log.info({ connectorId: connector.id }, "conector reconectou: conexão anterior substituída");
      this.drop(previous, 4000, "substituída por nova conexão");
    }

    const helloTimer = setTimeout(() => {
      if (!session.ready) socket.close(4002, "hello não recebido");
    }, this.opts.helloTimeoutMs);
    const heartbeat = setInterval(() => {
      if (Date.now() - session.lastPong > this.opts.pongTimeoutMs) {
        this.log.warn({ connectorId: connector.id }, "conector sem pong: conexão encerrada");
        socket.terminate();
        return;
      }
      if (socket.readyState === socket.OPEN) socket.ping();
    }, this.opts.pingIntervalMs);
    session.timers.push(helloTimer, heartbeat);

    socket.on("pong", () => {
      session.lastPong = Date.now();
    });
    socket.on("message", (data, isBinary) => {
      if (isBinary) return socket.close(1003, "apenas texto");
      void this.onMessage(session, data.toString("utf8"));
    });
    socket.on("close", () => this.cleanup(session));
    socket.on("error", (err) => this.log.warn({ err, connectorId: connector.id }, "erro no WebSocket do conector"));
  }

  async forward(connectorId: string, request: HttpRequestSpec, timeoutMs: number): Promise<HttpResponseSpec> {
    const session = this.sessions.get(connectorId);
    if (!session?.ready || session.socket.readyState !== session.socket.OPEN) {
      throw unavailable(`Conector ${connectorId} offline`);
    }
    if (session.pending.size >= this.opts.maxInFlight) {
      throw unavailable(`Conector ${connectorId} sobrecarregado (${this.opts.maxInFlight} requisições em andamento)`);
    }
    const id = randomUUID();
    const frame: RequestFrame = {
      type: "request",
      id,
      method: request.method,
      path: request.path,
      headers: request.headers,
      ...(request.body !== undefined ? { body: request.body } : {}),
      timeoutMs,
    };
    const text = JSON.stringify(frame);
    if (Buffer.byteLength(text) > this.opts.maxFrameBytes) {
      throw new AppError(400, "INVALID_PARAMS", "Requisição grande demais para o conector");
    }
    return new Promise<HttpResponseSpec>((resolve, reject) => {
      const timer = setTimeout(() => {
        session.pending.delete(id);
        reject(unavailable(`Conector ${connectorId} não respondeu em ${timeoutMs} ms`));
      }, timeoutMs + this.opts.graceMs);
      session.pending.set(id, { resolve, reject, timer });
      session.socket.send(text, (err) => {
        if (!err) return;
        clearTimeout(timer);
        session.pending.delete(id);
        reject(unavailable(`Falha ao enviar ao conector ${connectorId}`));
      });
    });
  }

  /** Derruba a conexão do conector (ex.: token revogado). */
  disconnect(connectorId: string, reason = "revogado"): void {
    const session = this.sessions.get(connectorId);
    if (session) this.drop(session, 4001, reason);
  }

  /** Encerramento do servidor. */
  closeAll(): void {
    for (const session of [...this.sessions.values()]) this.drop(session, 1001, "servidor encerrando");
  }

  private drop(session: Session, code: number, reason: string): void {
    this.cleanup(session);
    try {
      session.socket.close(code, reason);
    } catch {
      session.socket.terminate();
    }
  }

  /** Remove a sessão (se ainda for a atual) e rejeita o que estava pendente. */
  private cleanup(session: Session): void {
    for (const timer of session.timers) {
      clearTimeout(timer);
      clearInterval(timer);
    }
    session.timers = [];
    session.ready = false;
    if (this.sessions.get(session.connector.id) === session) {
      this.sessions.delete(session.connector.id);
      this.repository
        .touch(session.connector.id)
        .catch((err) => this.log.error({ err }, "falha ao registrar lastSeenAt"));
    }
    for (const [id, pending] of session.pending) {
      clearTimeout(pending.timer);
      pending.reject(unavailable(`Conector ${session.connector.id} desconectou`));
      session.pending.delete(id);
    }
  }

  private async onMessage(session: Session, text: string): Promise<void> {
    let frame: ConnectorFrame;
    try {
      frame = ConnectorFrame.parse(JSON.parse(text));
    } catch {
      this.log.warn({ connectorId: session.connector.id }, "quadro inválido do conector");
      session.socket.close(1008, "quadro inválido");
      return;
    }
    if (frame.type === "hello") {
      if (session.ready) return;
      session.ready = true;
      const welcome: WelcomeFrame = { type: "welcome", v: PROTOCOL_VERSION, connectorId: session.connector.id };
      session.socket.send(JSON.stringify(welcome));
      this.log.info({ connectorId: session.connector.id, version: frame.version }, "conector online");
      await this.repository
        .touch(session.connector.id, frame.version)
        .catch((err) => this.log.error({ err }, "falha ao registrar lastSeenAt"));
      return;
    }
    const pending = session.pending.get(frame.id);
    if (!pending) return; // resposta tardia (já expirou)
    session.pending.delete(frame.id);
    clearTimeout(pending.timer);
    if (frame.type === "response") {
      pending.resolve({ status: frame.status, contentType: frame.contentType, body: frame.body });
    } else {
      pending.reject(unavailable(`Conector ${session.connector.id}: ${frame.message} (${frame.code})`));
    }
  }
}
