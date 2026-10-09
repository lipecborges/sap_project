import { randomUUID } from "node:crypto";
import {
  type ChatEvent,
  type ChatRequest,
  type DiagnosticResult,
  findDiagnostic,
  validateParams,
} from "@raiox/contracts";
import { AppError } from "../errors";
import type { ConversationRepository, Owner } from "../repos/conversations";
import type { SapClient } from "../sap/client";
import type { SapCredentials } from "../sap/transport";
import type { LlmProvider, ToolOutcome } from "./provider";
import { suggestFollowUps } from "./summarize";

export interface ChatDeps {
  sap: SapClient;
  credentials: SapCredentials;
  owner: Owner;
  provider: LlmProvider;
  conversations: ConversationRepository;
  /** Executa um diagnóstico (com auditoria). */
  run: (diagnosticId: string, params: Record<string, string>) => Promise<DiagnosticResult>;
}

/** Executa um turno do assistente e emite os eventos SSE. Devolve quantas consultas ao SAP fez. */
export async function runChat(
  deps: ChatDeps,
  request: ChatRequest,
  sink: (event: ChatEvent) => void,
  signal: AbortSignal,
): Promise<{ conversationId: string; toolCalls: number }> {
  const { credentials } = deps;
  const [me, catalog] = await Promise.all([deps.sap.me(credentials), deps.sap.diagnostics(credentials)]);
  const allowed = catalog.diagnostics.filter((d) => me.diagnostics.includes(d.id));
  const conversation = await deps.conversations.open(deps.owner, request.conversationId);
  // O que a tela mostra fica gravado com o turno, para reabrir a conversa depois.
  const shown: ChatEvent[] = [];
  const emit = (event: ChatEvent) => {
    if (event.type !== "start" && event.type !== "done") shown.push(event);
    sink(event);
  };
  emit({ type: "start", conversationId: conversation.id, provider: deps.provider.name });
  let toolCalls = 0;

  const results: DiagnosticResult[] = [];
  const runTool = async (diagnosticId: string, params: Record<string, string>): Promise<ToolOutcome> => {
    const callId = randomUUID();
    const meta = allowed.find((d) => d.id === diagnosticId) ?? findDiagnostic(diagnosticId);
    emit({ type: "tool_start", callId, diagnosticId, title: meta?.title ?? diagnosticId, params });
    let outcome: ToolOutcome;
    if (!meta || !allowed.some((d) => d.id === diagnosticId)) {
      outcome = { error: { code: "NOT_AUTHORIZED", message: `Sem autorização para o diagnóstico ${diagnosticId}` } };
    } else {
      const errors = validateParams(meta, params);
      if (Object.keys(errors).length > 0) {
        outcome = {
          error: {
            code: "INVALID_PARAMS",
            message: Object.entries(errors)
              .map(([k, v]) => `${k}: ${v}`)
              .join("; "),
          },
        };
      } else {
        try {
          toolCalls++;
          const result = await deps.run(diagnosticId, params);
          results.push(result);
          outcome = { result };
        } catch (err) {
          outcome = {
            error:
              err instanceof AppError
                ? { code: err.code, message: err.message }
                : { code: "INTERNAL", message: "Falha na consulta" },
          };
        }
      }
    }
    emit({ type: "tool_result", callId, diagnosticId, ...outcome });
    return outcome;
  };

  const added = await deps.provider.respond({
    history: conversation.history,
    message: request.message,
    diagnostics: allowed,
    runTool,
    emitText: (delta) => emit({ type: "text", delta }),
    signal,
  });
  emit({ type: "suggestions", items: suggestFollowUps(results) });
  await deps.conversations.commitTurn(deps.owner, conversation.id, {
    previousLength: conversation.history.length,
    added,
    question: request.message,
    events: shown,
  });
  emit({ type: "done" });
  return { conversationId: conversation.id, toolCalls };
}
