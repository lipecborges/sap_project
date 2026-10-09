import type { AiProvider, DiagnosticResult } from "@raiox/contracts";
import { useSyncExternalStore } from "react";
import { api, RequestError } from "./api";

export interface ToolCall {
  callId: string;
  diagnosticId: string;
  title: string;
  params: Record<string, string>;
  status: "running" | "ok" | "error";
  result?: DiagnosticResult;
  error?: string;
}

export type ChatItem =
  | { id: string; role: "user"; text: string }
  | {
      id: string;
      role: "assistant";
      text: string;
      tools: ToolCall[];
      suggestions: string[];
      status: "streaming" | "done" | "error";
      error?: string;
    };

export interface Conversation {
  id: string;
  serverId?: string;
  title: string;
  provider?: AiProvider;
  items: ChatItem[];
  createdAt: number;
}

/** Conversas da sessão do navegador (em memória). Fase 2: histórico no servidor. */
interface State {
  conversations: Conversation[];
  activeId?: string;
}

let state: State = { conversations: [] };
const listeners = new Set<() => void>();
const controllers = new Map<string, AbortController>();

function set(next: State) {
  state = next;
  for (const l of listeners) l();
}

function updateConversation(id: string, fn: (c: Conversation) => Conversation) {
  set({ ...state, conversations: state.conversations.map((c) => (c.id === id ? fn(c) : c)) });
}

function updateLastAssistant(id: string, fn: (item: Extract<ChatItem, { role: "assistant" }>) => ChatItem) {
  updateConversation(id, (c) => {
    const items = [...c.items];
    const last = items.at(-1);
    if (last?.role === "assistant") items[items.length - 1] = fn(last);
    return { ...c, items };
  });
}

const uid = () => Math.random().toString(36).slice(2, 10);

export const chatStore = {
  subscribe(listener: () => void) {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },
  get: () => state,

  newConversation(): string {
    const id = uid();
    set({
      conversations: [{ id, title: "Nova conversa", items: [], createdAt: Date.now() }, ...state.conversations],
      activeId: id,
    });
    return id;
  },

  select(id: string) {
    set({ ...state, activeId: id });
  },

  remove(id: string) {
    controllers.get(id)?.abort();
    const conversations = state.conversations.filter((c) => c.id !== id);
    set({ conversations, activeId: state.activeId === id ? conversations[0]?.id : state.activeId });
  },

  stop(id: string) {
    controllers.get(id)?.abort();
  },

  isBusy(id: string) {
    return controllers.has(id);
  },

  async send(text: string, conversationId?: string) {
    const id = conversationId ?? state.activeId ?? chatStore.newConversation();
    const conversation = state.conversations.find((c) => c.id === id);
    if (!conversation || controllers.has(id)) return;

    updateConversation(id, (c) => ({
      ...c,
      title: c.items.length === 0 ? text.slice(0, 60) : c.title,
      items: [
        ...c.items,
        { id: uid(), role: "user", text },
        { id: uid(), role: "assistant", text: "", tools: [], suggestions: [], status: "streaming" },
      ],
    }));
    const controller = new AbortController();
    controllers.set(id, controller);
    set({ ...state });

    try {
      await api.chat(
        { message: text, ...(conversation.serverId ? { conversationId: conversation.serverId } : {}) },
        (event) => {
          switch (event.type) {
            case "start":
              updateConversation(id, (c) => ({ ...c, serverId: event.conversationId, provider: event.provider }));
              break;
            case "text":
              updateLastAssistant(id, (a) => ({ ...a, text: a.text + event.delta }));
              break;
            case "tool_start":
              updateLastAssistant(id, (a) => ({
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
              }));
              break;
            case "tool_result":
              updateLastAssistant(id, (a) => ({
                ...a,
                tools: a.tools.map((t) =>
                  t.callId === event.callId
                    ? { ...t, status: event.error ? "error" : "ok", result: event.result, error: event.error?.message }
                    : t,
                ),
              }));
              break;
            case "suggestions":
              updateLastAssistant(id, (a) => ({ ...a, suggestions: event.items }));
              break;
            case "done":
              updateLastAssistant(id, (a) => ({ ...a, status: "done" }));
              break;
            case "error":
              updateLastAssistant(id, (a) => ({ ...a, status: "error", error: event.message }));
              break;
          }
        },
        controller.signal,
      );
      updateLastAssistant(id, (a) =>
        a.status === "streaming"
          ? {
              ...a,
              status: controller.signal.aborted ? "done" : "error",
              error: controller.signal.aborted ? undefined : "Conexão encerrada antes do fim.",
            }
          : a,
      );
    } catch (err) {
      updateLastAssistant(id, (a) => ({
        ...a,
        status: "error",
        error: err instanceof RequestError ? err.message : "Falha ao falar com o assistente",
      }));
    } finally {
      controllers.delete(id);
      set({ ...state });
    }
  },
};

export function useChat() {
  return useSyncExternalStore(chatStore.subscribe, chatStore.get);
}
