import type { AiProvider, ConversationDetail } from "@raiox/contracts";
import { useSyncExternalStore } from "react";
import { toast } from "sonner";
import { api, RequestError } from "./api";
import { applyEvent, type ChatItem, emptyAssistant, turnsToItems } from "./chat-model";
import { CONVERSATIONS_KEY, queryClient } from "./query-client";

export type { ChatItem, ToolCall } from "./chat-model";

export interface Conversation {
  id: string;
  /** Id da conversa no servidor (fonte da verdade do histórico); ausente até a primeira resposta. */
  serverId?: string;
  title: string;
  provider?: AiProvider;
  items: ChatItem[];
  createdAt: number;
}

/**
 * Conversas abertas neste navegador (as que estão na tela ou em andamento). O histórico completo vem do servidor
 * (/conversations): abrir uma conversa antiga carrega seus turnos e a coloca aqui.
 */
interface State {
  conversations: Conversation[];
  activeId?: string;
  /** Conversa do servidor que está sendo carregada. */
  loadingServerId?: string;
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
const refreshHistory = () => void queryClient.invalidateQueries({ queryKey: CONVERSATIONS_KEY });

export const chatStore = {
  subscribe(listener: () => void) {
    listeners.add(listener);
    return () => listeners.delete(listener);
  },
  get: () => state,

  newConversation(): string {
    const id = uid();
    set({
      ...state,
      conversations: [{ id, title: "Nova conversa", items: [], createdAt: Date.now() }, ...state.conversations],
      activeId: id,
    });
    return id;
  },

  select(id?: string) {
    set({ ...state, activeId: id });
  },

  /** Abre uma conversa do histórico: usa a cópia em memória (pode estar em andamento) ou carrega do servidor. */
  async open(serverId: string) {
    const local = state.conversations.find((c) => c.serverId === serverId);
    if (local) return chatStore.select(local.id);
    if (state.loadingServerId === serverId) return;
    set({ ...state, loadingServerId: serverId });
    try {
      const detail = await queryClient.fetchQuery({
        queryKey: [...CONVERSATIONS_KEY, serverId],
        queryFn: () => api.conversation(serverId),
        staleTime: 0,
      });
      // O usuário pode ter aberto outra conversa enquanto esta carregava.
      if (state.loadingServerId === serverId) chatStore.hydrate(detail);
    } catch (err) {
      toast.error(err instanceof RequestError ? err.message : "Não foi possível abrir a conversa");
      if (err instanceof RequestError && err.status === 404) refreshHistory();
    } finally {
      if (state.loadingServerId === serverId) set({ ...state, loadingServerId: undefined });
    }
  },

  hydrate(detail: ConversationDetail) {
    const existing = state.conversations.find((c) => c.serverId === detail.id);
    if (existing) return chatStore.select(existing.id);
    const id = uid();
    const conversation: Conversation = {
      id,
      serverId: detail.id,
      title: detail.title,
      items: turnsToItems(detail.turns, `${id}-`),
      createdAt: Date.parse(detail.createdAt) || Date.now(),
    };
    set({
      ...state,
      conversations: [conversation, ...state.conversations],
      activeId: id,
      loadingServerId: undefined,
    });
  },

  /** Descarta a cópia local de uma conversa apagada no servidor. */
  forget(serverId: string) {
    for (const c of state.conversations.filter((c) => c.serverId === serverId)) chatStore.remove(c.id);
  },

  remove(id: string) {
    controllers.get(id)?.abort();
    const conversations = state.conversations.filter((c) => c.id !== id);
    set({ ...state, conversations, activeId: state.activeId === id ? undefined : state.activeId });
  },

  reset() {
    for (const c of controllers.values()) c.abort();
    controllers.clear();
    set({ conversations: [] });
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
      items: [...c.items, { id: uid(), role: "user", text }, emptyAssistant(uid())],
    }));
    const controller = new AbortController();
    controllers.set(id, controller);
    set({ ...state });

    try {
      await api.chat(
        { message: text, ...(conversation.serverId ? { conversationId: conversation.serverId } : {}) },
        (event) => {
          if (event.type === "start") {
            updateConversation(id, (c) => ({ ...c, serverId: event.conversationId, provider: event.provider }));
            refreshHistory();
          } else {
            updateLastAssistant(id, (a) => applyEvent(a, event));
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
      // O turno terminou (ou parou): atualiza o histórico com título e data finais.
      refreshHistory();
    }
  },
};

export function useChat() {
  return useSyncExternalStore(chatStore.subscribe, chatStore.get);
}
