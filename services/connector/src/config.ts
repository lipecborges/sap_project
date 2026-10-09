import { readFileSync } from "node:fs";
import { z } from "zod";

export const LOG_LEVELS = ["debug", "info", "warn", "error", "silent"] as const;
export type LogLevel = (typeof LOG_LEVELS)[number];

const Env = z.object({
  /** Endereço da API do Raio-X: wss://… (produção) ou ws://… (desenvolvimento). */
  RAIOX_URL: z.string().regex(/^wss?:\/\//, "RAIOX_URL deve começar com wss:// (ou ws:// em desenvolvimento)"),
  RAIOX_CONNECTOR_TOKEN: z.string().min(1, "RAIOX_CONNECTOR_TOKEN é obrigatório"),
  /** Origem do SAP na rede interna, ex.: https://sap.empresa.local:44300 */
  SAP_BASE_URL: z.string().regex(/^https?:\/\//, "SAP_BASE_URL deve começar com http:// ou https://"),
  SAP_API_PATH: z
    .string()
    .regex(/^\/[^?#]*[^/?#]$/, "SAP_API_PATH deve começar com / e não terminar com /")
    .default("/sap/bc/zrx/api/v1"),
  SAP_TIMEOUT_MS: z.coerce.number().int().min(1000).max(300_000).default(30_000),
  /** Certificado de CA adicional (PEM) para o TLS do SAP, além das CAs do sistema. */
  SAP_CA_FILE: z.string().optional(),
  LOG_LEVEL: z.enum(LOG_LEVELS).default("info"),
});

export interface ConnectorConfig {
  raioxUrl: string;
  token: string;
  sapBaseUrl: string;
  sapApiPath: string;
  sapTimeoutMs: number;
  sapCa?: string;
  logLevel: LogLevel;
}

export function loadConfig(env: Record<string, string | undefined> = process.env): ConnectorConfig {
  const parsed = Env.safeParse(env);
  if (!parsed.success) {
    const issues = parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ");
    throw new Error(`Configuração inválida: ${issues}`);
  }
  const e = parsed.data;
  let sapCa: string | undefined;
  if (e.SAP_CA_FILE) {
    try {
      sapCa = readFileSync(e.SAP_CA_FILE, "utf8");
    } catch {
      throw new Error(`Configuração inválida: não foi possível ler SAP_CA_FILE (${e.SAP_CA_FILE})`);
    }
  }
  return {
    raioxUrl: e.RAIOX_URL,
    token: e.RAIOX_CONNECTOR_TOKEN,
    sapBaseUrl: e.SAP_BASE_URL,
    sapApiPath: e.SAP_API_PATH,
    sapTimeoutMs: e.SAP_TIMEOUT_MS,
    sapCa,
    logLevel: e.LOG_LEVEL,
  };
}
