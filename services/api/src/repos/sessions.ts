import { createHash, randomBytes } from "node:crypto";
import type { MeResponse } from "@raiox/contracts";
import { and, count, eq, gt, lt } from "drizzle-orm";
import type { Cipher } from "../db/cipher";
import type { Db } from "../db/client";
import { sessions } from "../db/schema";
import type { SapCredentials } from "../sap/transport";

export interface Session {
  tenantId: string;
  sapSystemId: string;
  sapUser: string;
  credentials: SapCredentials;
  me: MeResponse;
  createdAt: Date;
}

export interface NewSession {
  tenantId: string;
  sapSystemId: string;
  credentials: SapCredentials;
  me: MeResponse;
  ip?: string;
  userAgent?: string;
}

/** Só grava "visto por último" se passou este tempo: evita um UPDATE por requisição. */
const TOUCH_INTERVAL_MS = 60_000;

const hashId = (id: string) => createHash("sha256").update(id).digest("base64url");

/**
 * Sessões no banco (D32): sobrevivem a reinício e funcionam com várias réplicas da API.
 * O cookie leva um id aleatório de 256 bits; o banco guarda só o hash dele e a senha SAP cifrada.
 */
export class SessionRepository {
  constructor(
    private readonly db: Db,
    private readonly cipher: Cipher,
    private readonly idleMs: number,
    private readonly maxAgeMs = 10 * 60 * 60 * 1000,
  ) {}

  async create(input: NewSession): Promise<string> {
    const id = randomBytes(32).toString("base64url");
    const now = Date.now();
    await this.db.insert(sessions).values({
      idHash: hashId(id),
      tenantId: input.tenantId,
      sapSystemId: input.sapSystemId,
      sapUser: input.credentials.user,
      credential: this.cipher.seal(input.credentials),
      me: input.me,
      ip: input.ip,
      userAgent: input.userAgent?.slice(0, 300),
      createdAt: new Date(now),
      lastSeenAt: new Date(now),
      expiresAt: new Date(Math.min(now + this.idleMs, now + this.maxAgeMs)),
    });
    return id;
  }

  async get(id: string | undefined): Promise<Session | undefined> {
    if (!id) return undefined;
    const idHash = hashId(id);
    const [row] = await this.db.select().from(sessions).where(eq(sessions.idHash, idHash)).limit(1);
    if (!row) return undefined;
    const now = Date.now();
    if (row.expiresAt.getTime() <= now) {
      await this.db.delete(sessions).where(eq(sessions.idHash, idHash));
      return undefined;
    }
    const credentials = this.cipher.open<SapCredentials>(row.credential);
    if (!credentials) {
      // Chave trocada (SESSION_SECRET novo): a sessão antiga não serve mais.
      await this.db.delete(sessions).where(eq(sessions.idHash, idHash));
      return undefined;
    }
    if (now - row.lastSeenAt.getTime() > TOUCH_INTERVAL_MS) {
      const hardLimit = row.createdAt.getTime() + this.maxAgeMs;
      await this.db
        .update(sessions)
        .set({ lastSeenAt: new Date(now), expiresAt: new Date(Math.min(now + this.idleMs, hardLimit)) })
        .where(eq(sessions.idHash, idHash));
    }
    return {
      tenantId: row.tenantId,
      sapSystemId: row.sapSystemId,
      sapUser: row.sapUser,
      credentials,
      me: row.me as MeResponse,
      createdAt: row.createdAt,
    };
  }

  async delete(id: string | undefined): Promise<void> {
    if (id) await this.db.delete(sessions).where(eq(sessions.idHash, hashId(id)));
  }

  /** Encerra todas as sessões de um usuário (ex.: bloqueado pelo administrador). */
  async deleteForUser(tenantId: string, sapUser: string): Promise<number> {
    const removed = await this.db
      .delete(sessions)
      .where(and(eq(sessions.tenantId, tenantId), eq(sessions.sapUser, sapUser)))
      .returning({ idHash: sessions.idHash });
    return removed.length;
  }

  /** Encerra as sessões de um sistema SAP (ex.: sistema removido). */
  async deleteForSystem(tenantId: string, sapSystemId: string): Promise<number> {
    const removed = await this.db
      .delete(sessions)
      .where(and(eq(sessions.tenantId, tenantId), eq(sessions.sapSystemId, sapSystemId)))
      .returning({ idHash: sessions.idHash });
    return removed.length;
  }

  /** Sessões ativas (não vencidas) por usuário do cliente. */
  async activeCounts(tenantId: string): Promise<Map<string, number>> {
    const rows = await this.db
      .select({ sapUser: sessions.sapUser, n: count() })
      .from(sessions)
      .where(and(eq(sessions.tenantId, tenantId), gt(sessions.expiresAt, new Date())))
      .groupBy(sessions.sapUser);
    return new Map(rows.map((r) => [r.sapUser, r.n]));
  }

  async purgeExpired(): Promise<number> {
    const removed = await this.db
      .delete(sessions)
      .where(lt(sessions.expiresAt, new Date()))
      .returning({ idHash: sessions.idHash });
    return removed.length;
  }
}
