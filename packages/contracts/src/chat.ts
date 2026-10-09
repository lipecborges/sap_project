import { z } from "zod";
import { ErrorCode } from "./api";
import { DiagnosticResult } from "./result";

/** Assistente de IA: o cliente envia uma mensagem; a API responde com eventos SSE. */

export const AiProvider = z.enum(["anthropic", "demo"]);
export type AiProvider = z.infer<typeof AiProvider>;

export const ChatRequest = z.object({
  /** Ausente na primeira mensagem; a API devolve o id no evento "start". */
  conversationId: z.string().min(1).max(64).optional(),
  message: z.string().trim().min(1).max(4000),
});
export type ChatRequest = z.infer<typeof ChatRequest>;

export const ChatEvent = z.discriminatedUnion("type", [
  z.object({ type: z.literal("start"), conversationId: z.string(), provider: AiProvider }),
  z.object({ type: z.literal("text"), delta: z.string() }),
  z.object({
    type: z.literal("tool_start"),
    callId: z.string(),
    diagnosticId: z.string(),
    title: z.string(),
    params: z.record(z.string(), z.string()),
  }),
  z.object({
    type: z.literal("tool_result"),
    callId: z.string(),
    diagnosticId: z.string(),
    result: DiagnosticResult.optional(),
    error: z.object({ code: z.string(), message: z.string() }).optional(),
  }),
  z.object({ type: z.literal("suggestions"), items: z.array(z.string()) }),
  z.object({ type: z.literal("done") }),
  z.object({ type: z.literal("error"), code: ErrorCode.or(z.string()), message: z.string() }),
]);
export type ChatEvent = z.infer<typeof ChatEvent>;

/** Painel inicial: as três listas principais, cada uma pode falhar sozinha (ex.: sem autorização). */
export const OverviewSection = z.object({
  result: DiagnosticResult.optional(),
  error: z.object({ code: z.string(), message: z.string() }).optional(),
});
export type OverviewSection = z.infer<typeof OverviewSection>;

export const OverviewResponse = z.object({
  plant: z.string(),
  production: OverviewSection,
  sales: OverviewSection,
  purchasing: OverviewSection,
});
export type OverviewResponse = z.infer<typeof OverviewResponse>;

export const AppInfo = z.object({
  status: z.literal("ok"),
  version: z.string(),
  deploymentMode: z.enum(["cloud", "selfhosted"]),
  sapTransport: z.enum(["direct", "connector"]),
  ai: z.object({ provider: AiProvider, model: z.string().optional() }),
});
export type AppInfo = z.infer<typeof AppInfo>;
