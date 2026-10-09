import type { Config } from "../config";
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
 * - connector: pelo conector on-premise (cloud, Fase 4).
 * O sap-mock é só um SAP de mentira atrás do transporte direct.
 */
export interface SapTransport {
  readonly kind: "direct" | "connector";
  send(request: SapRequest): Promise<SapResponse>;
}

export class DirectSapTransport implements SapTransport {
  readonly kind = "direct" as const;

  constructor(
    private readonly baseUrl: string,
    private readonly apiPath: string,
    private readonly client: string | undefined,
    private readonly timeoutMs: number,
  ) {}

  async send(request: SapRequest): Promise<SapResponse> {
    const url = new URL(`${this.apiPath}${request.path}`, this.baseUrl);
    if (this.client) url.searchParams.set("sap-client", this.client);
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

    let response: Response;
    try {
      response = await fetch(url, {
        method: request.method,
        headers,
        body,
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (err) {
      const reason = err instanceof Error ? err.message : String(err);
      throw new AppError(503, "SAP_UNAVAILABLE", `Não foi possível conectar ao SAP (${url.origin}): ${reason}`);
    }
    const text = await response.text();
    const isJson = response.headers.get("content-type")?.includes("json") ?? false;
    let parsed: unknown = text;
    if (isJson && text) {
      try {
        parsed = JSON.parse(text);
      } catch {
        parsed = text;
      }
    }
    return { status: response.status, body: parsed };
  }
}

export class ConnectorSapTransport implements SapTransport {
  readonly kind = "connector" as const;

  async send(): Promise<SapResponse> {
    throw new AppError(501, "NOT_IMPLEMENTED", "O transporte via conector chega na Fase 4. Use SAP_TRANSPORT=direct.");
  }
}

export function createTransport(config: Config): SapTransport {
  if (config.SAP_TRANSPORT === "connector") return new ConnectorSapTransport();
  return new DirectSapTransport(config.SAP_BASE_URL!, config.SAP_API_PATH, config.SAP_CLIENT, config.SAP_TIMEOUT_MS);
}
