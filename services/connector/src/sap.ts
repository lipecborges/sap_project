import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";
import { rootCertificates } from "node:tls";

/** Cabeçalhos que o conector aceita repassar ao SAP; o resto é descartado. */
export const ALLOWED_HEADERS = ["authorization", "accept", "content-type"] as const;

export type SapErrorCode =
  | "FORBIDDEN_PATH"
  | "FORBIDDEN_METHOD"
  | "SAP_TIMEOUT"
  | "SAP_UNREACHABLE"
  | "RESPONSE_TOO_LARGE";

export class SapCallError extends Error {
  constructor(
    readonly code: SapErrorCode,
    message: string,
  ) {
    super(message);
  }
}

export interface SapCallOptions {
  baseUrl: string;
  apiPath: string;
  /** CA extra (PEM), somada às CAs do Node. */
  ca?: string;
  /** Teto do corpo da resposta, em bytes. */
  maxResponseBytes: number;
}

export interface SapCall {
  method: string;
  path: string;
  headers: Record<string, string>;
  body?: string;
  timeoutMs: number;
}

export interface SapResult {
  status: number;
  contentType?: string;
  body: string;
}

/**
 * Valida o caminho recebido da nuvem: só a API do add-on é alcançável. O caminho é normalizado
 * (resolve "..", "//" etc.) antes da checagem, então não há como escapar do prefixo.
 * Devolve o caminho normalizado + query.
 */
export function checkPath(path: string, apiPath: string): string {
  if (!path.startsWith("/") || path.startsWith("//") || path.includes("\\")) {
    throw new SapCallError("FORBIDDEN_PATH", "Caminho não permitido");
  }
  const url = new URL(path, "http://sap.invalid");
  if (url.host !== "sap.invalid") throw new SapCallError("FORBIDDEN_PATH", "Caminho não permitido");
  // Barras codificadas poderiam ser reinterpretadas pelo SAP como separadores.
  if (/%2f|%5c/i.test(url.pathname)) throw new SapCallError("FORBIDDEN_PATH", "Caminho não permitido");
  if (url.pathname !== apiPath && !url.pathname.startsWith(`${apiPath}/`)) {
    throw new SapCallError("FORBIDDEN_PATH", "Caminho fora da API do add-on Raio-X");
  }
  return `${url.pathname}${url.search}`;
}

/** Executa a chamada HTTP ao SAP. Lança SapCallError; mensagens não incluem credenciais nem corpos. */
export function callSap(call: SapCall, options: SapCallOptions, signal?: AbortSignal): Promise<SapResult> {
  if (call.method !== "GET" && call.method !== "POST") {
    return Promise.reject(new SapCallError("FORBIDDEN_METHOD", "Método não permitido"));
  }
  let target: URL;
  try {
    const path = checkPath(call.path, options.apiPath);
    target = new URL(path, options.baseUrl);
  } catch (err) {
    if (err instanceof SapCallError) return Promise.reject(err);
    return Promise.reject(new SapCallError("FORBIDDEN_PATH", "Caminho inválido"));
  }

  const headers: Record<string, string> = {};
  for (const name of ALLOWED_HEADERS) {
    const value = call.headers[name] ?? Object.entries(call.headers).find(([k]) => k.toLowerCase() === name)?.[1];
    if (typeof value === "string") headers[name] = value;
  }
  const payload = call.method === "POST" && call.body !== undefined ? Buffer.from(call.body, "utf8") : undefined;
  if (payload) headers["content-length"] = String(payload.length);

  const isHttps = target.protocol === "https:";
  const send = isHttps ? httpsRequest : httpRequest;

  return new Promise<SapResult>((resolve, reject) => {
    let settled = false;
    const finish = (fn: () => void) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fn();
    };
    const req = send(
      target,
      {
        method: call.method,
        headers,
        signal,
        ...(isHttps && options.ca ? { ca: [...rootCertificates, options.ca] } : {}),
      },
      (res) => {
        const chunks: Buffer[] = [];
        let size = 0;
        res.on("data", (chunk: Buffer) => {
          size += chunk.length;
          if (size > options.maxResponseBytes) {
            finish(() =>
              reject(new SapCallError("RESPONSE_TOO_LARGE", "Resposta do SAP maior que o limite do conector")),
            );
            req.destroy();
            return;
          }
          chunks.push(chunk);
        });
        res.on("end", () =>
          finish(() =>
            resolve({
              status: res.statusCode ?? 502,
              contentType: res.headers["content-type"],
              body: Buffer.concat(chunks).toString("utf8"),
            }),
          ),
        );
        res.on("error", () =>
          finish(() => reject(new SapCallError("SAP_UNREACHABLE", "Conexão com o SAP interrompida"))),
        );
      },
    );
    const timer = setTimeout(() => {
      finish(() => reject(new SapCallError("SAP_TIMEOUT", `O SAP não respondeu em ${call.timeoutMs} ms`)));
      req.destroy();
    }, call.timeoutMs);
    req.on("error", (err: NodeJS.ErrnoException) =>
      finish(() =>
        reject(new SapCallError("SAP_UNREACHABLE", `Não foi possível conectar ao SAP (${err.code ?? "erro de rede"})`)),
      ),
    );
    req.end(payload);
  });
}
