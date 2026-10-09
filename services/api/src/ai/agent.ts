import { randomUUID } from "node:crypto";
import {
  type ChatEvent,
  type ChatRequest,
  type DiagnosticResult,
  findDiagnostic,
  validateParams,
} from "@raiox/contracts";
import { AppError } from "../errors";
import type { SapClient } from "../sap/client";
import type { SapCredentials } from "../sap/transport";
import type { LlmProvider, ToolOutcome } from "./provider";
import type { ConversationStore } from "./store";
import { suggestFollowUps } from "./summarize";

export interface ChatDeps {
  sap: SapClient;
  provider: LlmProvider;
  store: ConversationStore;
}

/** Executa um turno do assistente e emite os eventos SSE. */
export async function runChat(
  deps: ChatDeps,
  credentials: SapCredentials,
  request: ChatRequest,
  emit: (event: ChatEvent) => void,
  signal: AbortSignal,
): Promise<void> {
  const owner = credentials.user.toUpperCase();
  const [me, catalog] = await Promise.all([deps.sap.me(credentials), deps.sap.diagnostics(credentials)]);
  const allowed = catalog.diagnostics.filter((d) => me.diagnostics.includes(d.id));
  const conversation = deps.store.open(owner, request.conversationId);
  emit({ type: "start", conversationId: conversation.id, provider: deps.provider.name });

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
          const result = await deps.sap.run(credentials, diagnosticId, params);
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
  deps.store.commit(conversation.id, owner, [...conversation.history, ...added]);
  emit({ type: "suggestions", items: suggestFollowUps(results) });
  emit({ type: "done" });
}
