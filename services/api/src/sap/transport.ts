import { AppError } from "../errors";

export interface SapCredentials {
  user: string;
  password: string;
}

export interface SapRequest {
  method: "GET" | "POST";
  /** Caminho relativo à API do add-on, ex.: /diagnostics/SD-01 */
  path: string;
  params?: Record<string, string>;
  credentials: SapCredentials;
}

export interface SapResponse {
  status: number;
  /** JSON já interpretado, ou o texto bruto quando o SAP não responde JSON (ex.: página de erro do ICF). */
  body: unknown;
}

/**
 * Como a API chega ao add-on ABAP:
 * - direct: HTTP para o SAP (self-hosted e desenvolvimento);
 * - connector: pelo conector on-premise, que abre a conexão de saída para a API (cloud, D35).
 * O sap-mock é só um SAP de mentira atrás do transporte direct.
 */
export interface SapTransport {
  readonly kind: "direct" | "connector";
  send(request: SapRequest): Promise<SapResponse>;
}

/** Requisição HTTP já montada, sem o endereço do SAP: o mesmo formato vai pelo fetch ou pelo conector. */
export interface HttpRequestSpec {
  method: "GET" | "POST";
  /** Caminho + query, relativo à origem do SAP (ex.: /sap/bc/zrx/api/v1/me?sap-client=100). */
  path: string;
  headers: Record<string, string>;
  body?: string;
}

export interface HttpResponseSpec {
  status: number;
  contentType?: string;
  body: string;
}

export interface SapEndpoint {
  apiPath: string;
  client?: string;
}

export function buildHttpRequest(endpoint: SapEndpoint, request: SapRequest): HttpRequestSpec {
  const url = new URL(`${endpoint.apiPath}${request.path}`, "http://sap.invalid");
  if (endpoint.client) url.searchParams.set("sap-client", endpoint.client);
  const auth = Buffer.from(`${request.credentials.user}:${request.credentials.password}`).toString("base64");
  const headers: Record<string, string> = { authorization: `Basic ${auth}`, accept: "application/json" };

  let body: string | undefined;
  if (request.method === "GET") {
    for (const [k, v] of Object.entries(request.params ?? {})) url.searchParams.set(k, v);
  } else {
    // Parâmetros planos em form: o ABAP lê com get_form_field, sem precisar de parser JSON (NW 7.00).
    body = new URLSearchParams(request.params ?? {}).toString();
    headers["content-type"] = "application/x-www-form-urlencoded";
  }
  return { method: request.method, path: `${url.pathname}${url.search}`, headers, body };
}

export function parseHttpResponse(response: HttpResponseSpec): SapResponse {
  const isJson = response.contentType?.includes("json") ?? false;
  let parsed: unknown = response.body;
  if (isJson && response.body) {
    try {
      parsed = JSON.parse(response.body);
    } catch {
      parsed = response.body;
    }
  }
  return { status: response.status, body: parsed };
}

export class DirectSapTransport implements SapTransport {
  readonly kind = "direct" as const;

  constructor(
    private readonly baseUrl: string,
    private readonly endpoint: SapEndpoint,
    private readonly timeoutMs: number,
  ) {}

  async send(request: SapRequest): Promise<SapResponse> {
    const spec = buildHttpRequest(this.endpoint, request);
    const url = new URL(spec.path, this.baseUrl);
    let response: Response;
    try {
      response = await fetch(url, {
        method: spec.method,
        headers: spec.headers,
        body: spec.body,
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      throw new AppError(503, "SAP_UNAVAILABLE", `Não foi possível conectar ao SAP (${url.origin}): ${reason}`);
    }
    return parseHttpResponse({
      status: response.status,
      contentType: response.headers.get("content-type") ?? undefined,
      body: await response.text(),
    });
  }
}

/**
 * Ponte com os conectores conectados (implementada pelo gateway de conectores, D35).
 * Deve lançar AppError 503 SAP_UNAVAILABLE quando o conector está offline ou não responde a tempo.
 */
export interface ConnectorHub {
  forward(connectorId: string, request: HttpRequestSpec, timeoutMs: number): Promise<HttpResponseSpec>;
  isOnline(connectorId: string): boolean;
}

/** Sem gateway ativo (ex.: Self-hosted): qualquer sistema "connector" responde indisponível. */
export const offlineConnectorHub: ConnectorHub = {
  forward: async () => {
    throw new AppError(503, "SAP_UNAVAILABLE", "Conector on-premise não conectado");
  },
  isOnline: () => false,
};

export class ConnectorSapTransport implements SapTransport {
  readonly kind = "connector" as const;

  constructor(
    private readonly hub: ConnectorHub,
    private readonly connectorId: string,
    private readonly endpoint: SapEndpoint,
    private readonly timeoutMs: number,
  ) {}

  async send(request: SapRequest): Promise<SapResponse> {
    const response = await this.hub.forward(this.connectorId, buildHttpRequest(this.endpoint, request), this.timeoutMs);
    return parseHttpResponse(response);
  }
}
