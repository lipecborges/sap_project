import { z } from "zod";
import { DiagnosticMeta } from "./diagnostics";
import { SystemInfo } from "./result";

/** Respostas da API REST do add-on ABAP (/sap/bc/zrx/api/v1). */

export const HealthResponse = z.object({
  addonVersion: z.string(),
  apiVersion: z.string(),
  system: SystemInfo,
  diagnostics: z.array(z.string()),
});
export type HealthResponse = z.infer<typeof HealthResponse>;

export const MeResponse = z.object({
  user: z.string().min(1),
  /** Idioma ISO de logon, ex.: PT */
  language: z.string(),
  /** Diagnósticos que o usuário pode executar (objeto de autorização ZRX_DIAG). */
  diagnostics: z.array(z.string()),
});
export type MeResponse = z.infer<typeof MeResponse>;

/** Sessão do Raio-X: o usuário SAP + o sistema em que entrou e o papel no Raio-X. */
export const SessionInfo = MeResponse.extend({
  role: z.enum(["user", "admin"]),
  system: z.object({ id: z.string(), name: z.string() }),
});
export type SessionInfo = z.infer<typeof SessionInfo>;

/** Sistemas SAP disponíveis na tela de login (sem endereços: só id e nome). */
export const SystemsResponse = z.object({
  systems: z.array(z.object({ id: z.string(), name: z.string(), isDefault: z.boolean() })),
});
export type SystemsResponse = z.infer<typeof SystemsResponse>;

export const DiagnosticsResponse = z.object({
  diagnostics: z.array(DiagnosticMeta),
});
export type DiagnosticsResponse = z.infer<typeof DiagnosticsResponse>;

export const ErrorCode = z.enum([
  "UNAUTHENTICATED",
  "NOT_AUTHORIZED",
  "ROUTE_NOT_FOUND",
  "UNKNOWN_DIAGNOSTIC",
  "INVALID_PARAMS",
  "SAP_UNAVAILABLE",
  "SAP_BAD_RESPONSE",
  "NOT_IMPLEMENTED",
  "RATE_LIMITED",
  "LICENSE_REQUIRED",
  "FORBIDDEN",
  "INTERNAL",
]);
export type ErrorCode = z.infer<typeof ErrorCode>;

export const ApiError = z.object({
  error: z.object({
    code: ErrorCode,
    message: z.string(),
    /** Erros por parâmetro (INVALID_PARAMS). */
    params: z.record(z.string(), z.string()).optional(),
  }),
});
export type ApiError = z.infer<typeof ApiError>;
