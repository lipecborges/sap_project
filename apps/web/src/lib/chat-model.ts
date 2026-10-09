import type { ChatEvent, ConversationDetail, ConversationSummary, DiagnosticResult } from "@raiox/contracts";

/** Modelo de exibição do chat e funções puras que o alimentam (ao vivo e ao reabrir o histórico). */

export interface ToolCall {
  callId: string;
  diagnosticId: string;
  title: string;
  params: Record<string, string>;
  status: "running" | "ok" | "error";
  result?: DiagnosticResult;
  error?: string;
}

export type AssistantItem = {
  id: string;
  role: "assistant";
  text: string;
  tools: ToolCall[];
  suggestions: string[];
  status: "streaming" | "done" | "error";
  error?: string;
};

export type ChatItem = { id: string; role: "user"; text: string } | AssistantItem;

export function emptyAssistant(id: string): AssistantItem {
  return { id, role: "assistant", text: "", tools: [], suggestions: [], status: "streaming" };
}

/** Aplica um evento do stream à mensagem do assistente (sem mutar). */
export function applyEvent(a: AssistantItem, event: ChatEvent): AssistantItem {
  switch (event.type) {
    case "text":
      return { ...a, text: a.text + event.delta };
    case "tool_start":
      return {
        ...a,
        tools: [
          ...a.tools,
          {
            callId: event.callId,
            diagnosticId: event.diagnosticId,
            title: event.title,
            params: event.params,
            status: "running",
          },
        ],
      };
    case "tool_result":
      return {
        ...a,
        tools: a.tools.map((t) =>
          t.callId === event.callId
            ? { ...t, status: event.error ? "error" : "ok", result: event.result, error: event.error?.message }
            : t,
        ),
      };
    case "suggestions":
      return { ...a, suggestions: event.items };
    case "done":
      return { ...a, status: "done" };
    case "error":
      return { ...a, status: "error", error: event.message };
    default:
      return a;
  }
}

/** Reconstrói as mensagens de uma conversa salva: cada turno vira pergunta + resposta. */
export function turnsToItems(turns: ConversationDetail["turns"], idPrefix = "h"): ChatItem[] {
  return turns.flatMap((turn, i): ChatItem[] => {
    let answer = emptyAssistant(`${idPrefix}${i}a`);
    for (const event of turn.events) answer = applyEvent(answer, event);
    // Turno interrompido (sem "done"): mostra o que existe, sem ficar "digitando" nem chamadas em andamento.
    if (answer.status === "streaming") answer = { ...answer, status: "done" };
    answer = {
      ...answer,
      tools: answer.tools.map((t) =>
        t.status === "running" ? { ...t, status: "error", error: "Consulta interrompida" } : t,
      ),
    };
    return [{ id: `${idPrefix}${i}q`, role: "user", text: turn.question }, answer];
  });
}

export interface ConversationGroup {
  label: string;
  conversations: ConversationSummary[];
}

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();

/** Agrupa pelo dia (local) da última atividade: Hoje, Ontem, Últimos 7 dias, Mais antigas. */
export function groupConversations(list: ConversationSummary[], now = new Date()): ConversationGroup[] {
  const today = startOfDay(now);
  const buckets: ConversationGroup[] = [
    { label: "Hoje", conversations: [] },
    { label: "Ontem", conversations: [] },
    { label: "Últimos 7 dias", conversations: [] },
    { label: "Mais antigas", conversations: [] },
  ];
  const sorted = [...list].sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt));
  for (const c of sorted) {
    const time = Date.parse(c.updatedAt);
    const days = Number.isNaN(time)
      ? Number.POSITIVE_INFINITY
      : Math.round((today - startOfDay(new Date(time))) / 86_400_000);
    const bucket = days <= 0 ? 0 : days === 1 ? 1 : days <= 7 ? 2 : 3;
    buckets[bucket]?.conversations.push(c);
  }
  return buckets.filter((b) => b.conversations.length > 0);
}
