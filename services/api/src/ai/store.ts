import { randomUUID } from "node:crypto";
import type Anthropic from "@anthropic-ai/sdk";

interface Conversation {
  owner: string;
  messages: Anthropic.Beta.BetaMessageParam[];
  updatedAt: number;
}

/**
 * Conversas em memória, só acrescentadas (append-only): o histórico, incluindo blocos
 * de raciocínio do modelo, volta para a API exatamente como foi recebido.
 * Fase 2: mover para o PostgreSQL com retenção configurável.
 */
export class ConversationStore {
  private readonly conversations = new Map<string, Conversation>();

  constructor(
    private readonly ttlMs = 2 * 60 * 60 * 1000,
    private readonly maxConversations = 500,
  ) {}

  /** Devolve o histórico da conversa do usuário ou cria uma nova. */
  open(owner: string, id?: string): { id: string; history: Anthropic.Beta.BetaMessageParam[] } {
    this.evict();
    const existing = id ? this.conversations.get(id) : undefined;
    if (id && existing && existing.owner === owner) return { id, history: [...existing.messages] };
    const newId = randomUUID();
    this.conversations.set(newId, { owner, messages: [], updatedAt: Date.now() });
    return { id: newId, history: [] };
  }

  /** Grava o turno completo. Chamado só quando o turno termina sem erro. */
  commit(id: string, owner: string, messages: Anthropic.Beta.BetaMessageParam[]): void {
    this.conversations.set(id, { owner, messages, updatedAt: Date.now() });
  }

  private evict(): void {
    const now = Date.now();
    for (const [id, c] of this.conversations) {
      if (now - c.updatedAt > this.ttlMs) this.conversations.delete(id);
    }
    while (this.conversations.size >= this.maxConversations) {
      const oldest = this.conversations.keys().next().value;
      if (oldest === undefined) break;
      this.conversations.delete(oldest);
    }
  }
}
