import { randomUUID } from "node:crypto";
import type Anthropic from "@anthropic-ai/sdk";
import type { ChatEvent } from "@raiox/contracts";
import { and, asc, count, desc, eq, lt } from "drizzle-orm";
import type { Db } from "../db/client";
import { conversationMessages, conversations, conversationTurns } from "../db/schema";

type MessageParam = Anthropic.Beta.BetaMessageParam;

export interface Owner {
  tenantId: string;
  sapUser: string;
}

export interface ConversationSummary {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
}

export interface ConversationTurn {
  question: string;
  events: ChatEvent[];
  createdAt: string;
}

/**
 * Conversas no banco. Duas visões de cada turno:
 * - mensagens do modelo (append-only, devolvidas à API do modelo exatamente como vieram);
 * - o que a tela mostrou (pergunta + eventos), para reabrir a conversa no histórico.
 */
export class ConversationRepository {
  constructor(private readonly db: Db) {}

  /** Histórico de uma conversa do usuário, ou uma conversa nova se o id não existir ou for de outro usuário. */
  async open(owner: Owner, id?: string): Promise<{ id: string; history: MessageParam[]; isNew: boolean }> {
    if (id) {
      const [row] = await this.db
        .select({ id: conversations.id })
        .from(conversations)
        .where(this.ownedBy(owner, id))
        .limit(1);
      if (row) {
        const messages = await this.db
          .select({ role: conversationMessages.role, content: conversationMessages.content })
          .from(conversationMessages)
          .where(eq(conversationMessages.conversationId, id))
          .orderBy(asc(conversationMessages.seq));
        return {
          id,
          history: messages.map((m) => ({ role: m.role, content: m.content }) as MessageParam),
          isNew: false,
        };
      }
    }
    return { id: randomUUID(), history: [], isNew: true };
  }

  /**
   * Grava um turno completo numa transação: as mensagens novas do modelo e o que a tela mostrou.
   * Chamado só quando o turno termina sem erro.
   */
  async commitTurn(
    owner: Owner,
    id: string,
    input: { previousLength: number; added: MessageParam[]; question: string; events: ChatEvent[] },
  ): Promise<void> {
    await this.db.transaction(async (tx) => {
      const now = new Date();
      const [existing] = await tx
        .select({ id: conversations.id })
        .from(conversations)
        .where(this.ownedBy(owner, id))
        .limit(1);
      if (!existing) {
        await tx.insert(conversations).values({
          id,
          tenantId: owner.tenantId,
          sapUser: owner.sapUser,
          title: input.question.slice(0, 120),
          createdAt: now,
          updatedAt: now,
        });
      } else {
        await tx.update(conversations).set({ updatedAt: now }).where(eq(conversations.id, id));
      }
      if (input.added.length > 0) {
        await tx.insert(conversationMessages).values(
          input.added.map((m, i) => ({
            conversationId: id,
            seq: input.previousLength + i,
            role: m.role as "user" | "assistant",
            content: m.content as unknown,
          })),
        );
      }
      const [{ turns } = { turns: 0 }] = await tx
        .select({ turns: count() })
        .from(conversationTurns)
        .where(eq(conversationTurns.conversationId, id));
      await tx
        .insert(conversationTurns)
        .values({ conversationId: id, seq: turns, question: input.question, events: input.events });
    });
  }

  async list(owner: Owner, limit = 50): Promise<ConversationSummary[]> {
    const rows = await this.db
      .select()
      .from(conversations)
      .where(and(eq(conversations.tenantId, owner.tenantId), eq(conversations.sapUser, owner.sapUser)))
      .orderBy(desc(conversations.updatedAt))
      .limit(limit);
    return rows.map((r) => ({
      id: r.id,
      title: r.title,
      createdAt: r.createdAt.toISOString(),
      updatedAt: r.updatedAt.toISOString(),
    }));
  }

  async turns(owner: Owner, id: string): Promise<(ConversationSummary & { turns: ConversationTurn[] }) | undefined> {
    const [row] = await this.db.select().from(conversations).where(this.ownedBy(owner, id)).limit(1);
    if (!row) return undefined;
    const turns = await this.db
      .select()
      .from(conversationTurns)
      .where(eq(conversationTurns.conversationId, id))
      .orderBy(asc(conversationTurns.seq));
    return {
      id: row.id,
      title: row.title,
      createdAt: row.createdAt.toISOString(),
      updatedAt: row.updatedAt.toISOString(),
      turns: turns.map((t) => ({
        question: t.question,
        events: t.events as ChatEvent[],
        createdAt: t.createdAt.toISOString(),
      })),
    };
  }

  async delete(owner: Owner, id: string): Promise<boolean> {
    const removed = await this.db
      .delete(conversations)
      .where(this.ownedBy(owner, id))
      .returning({ id: conversations.id });
    return removed.length > 0;
  }

  /** Retenção: apaga conversas sem atividade há mais de `days` dias. */
  async purgeOlderThan(days: number): Promise<number> {
    const limit = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const removed = await this.db
      .delete(conversations)
      .where(lt(conversations.updatedAt, limit))
      .returning({ id: conversations.id });
    return removed.length;
  }

  private ownedBy(owner: Owner, id: string) {
    return and(
      eq(conversations.id, id),
      eq(conversations.tenantId, owner.tenantId),
      eq(conversations.sapUser, owner.sapUser),
    );
  }
}
