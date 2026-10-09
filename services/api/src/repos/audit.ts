import { and, desc, eq, gte, lt, lte, type SQL } from "drizzle-orm";
import type { FastifyBaseLogger } from "fastify";
import type { Db } from "../db/client";
import { auditEvents } from "../db/schema";

/** Ações registradas: LOGIN, LOGIN_FAILED, LOGOUT, DIAGNOSTIC_RUN, CHAT_TURN e ADMIN_* (administração). */
export type AuditAction = string;

export interface AuditEvent {
  tenantId: string;
  action: AuditAction;
  /** "ok" ou o código de erro do contrato (ex.: NOT_AUTHORIZED). */
  outcome: string;
  sapUser?: string;
  sapSystemId?: string;
  target?: string;
  details?: Record<string, unknown>;
  httpStatus?: number;
  durationMs?: number;
  ip?: string;
  requestId?: string;
}

export interface AuditQuery {
  tenantId: string;
  sapUser?: string;
  action?: string;
  from?: Date;
  to?: Date;
  /** Paginação por id decrescente: devolve eventos com id menor que este. */
  before?: number;
  limit?: number;
}

/**
 * Trilha de auditoria (D36). Gravar nunca derruba a requisição: falha vira log de erro.
 * Senhas e conteúdo de respostas do SAP não entram aqui, só parâmetros e o resultado.
 */
export class AuditLog {
  constructor(
    private readonly db: Db,
    private readonly log: FastifyBaseLogger,
  ) {}

  async record(event: AuditEvent): Promise<void> {
    try {
      await this.db.insert(auditEvents).values({ ...event, at: new Date() });
    } catch (err) {
      this.log.error({ err, action: event.action }, "falha ao gravar auditoria");
    }
  }

  async query(q: AuditQuery) {
    const filters: SQL[] = [eq(auditEvents.tenantId, q.tenantId)];
    if (q.sapUser) filters.push(eq(auditEvents.sapUser, q.sapUser));
    if (q.action) filters.push(eq(auditEvents.action, q.action));
    if (q.from) filters.push(gte(auditEvents.at, q.from));
    if (q.to) filters.push(lte(auditEvents.at, q.to));
    if (q.before) filters.push(lt(auditEvents.id, q.before));
    return this.db
      .select()
      .from(auditEvents)
      .where(and(...filters))
      .orderBy(desc(auditEvents.id))
      .limit(Math.min(q.limit ?? 100, 500));
  }

  /** Retenção: apaga eventos com mais de `days` dias. */
  async purgeOlderThan(days: number): Promise<number> {
    const limit = new Date(Date.now() - days * 24 * 60 * 60 * 1000);
    const removed = await this.db
      .delete(auditEvents)
      .where(lt(auditEvents.at, limit))
      .returning({ id: auditEvents.id });
    return removed.length;
  }
}
