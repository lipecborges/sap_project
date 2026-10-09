import { createHash, randomBytes } from "node:crypto";
import { and, asc, eq, isNull } from "drizzle-orm";
import type { Db } from "../db/client";
import { connectors } from "../db/schema";

export type ConnectorRow = typeof connectors.$inferSelect;

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** Conectores on-premise (D35). Só o hash do token é gravado; o token em claro aparece uma única vez. */
export class ConnectorRepository {
  constructor(private readonly db: Db) {}

  async create(tenantId: string, name: string): Promise<{ connector: ConnectorRow; token: string }> {
    const token = randomBytes(32).toString("base64url");
    const id = `cn_${randomBytes(6).toString("hex")}`;
    const [connector] = await this.db
      .insert(connectors)
      .values({ id, tenantId, name, tokenHash: hashToken(token) })
      .returning();
    if (!connector) throw new Error("falha ao criar o conector");
    return { connector, token };
  }

  async list(tenantId: string): Promise<ConnectorRow[]> {
    return this.db
      .select()
      .from(connectors)
      .where(eq(connectors.tenantId, tenantId))
      .orderBy(asc(connectors.createdAt));
  }

  async get(tenantId: string, id: string): Promise<ConnectorRow | undefined> {
    const [row] = await this.db
      .select()
      .from(connectors)
      .where(and(eq(connectors.tenantId, tenantId), eq(connectors.id, id)))
      .limit(1);
    return row;
  }

  /** Revoga (idempotente). Devolve o conector, ou undefined se não existe neste cliente. */
  async revoke(tenantId: string, id: string): Promise<ConnectorRow | undefined> {
    const existing = await this.get(tenantId, id);
    if (!existing) return undefined;
    if (existing.revokedAt) return existing;
    const [row] = await this.db
      .update(connectors)
      .set({ revokedAt: new Date() })
      .where(and(eq(connectors.tenantId, tenantId), eq(connectors.id, id), isNull(connectors.revokedAt)))
      .returning();
    return row ?? existing;
  }

  /** O conector dono do token, desde que não esteja revogado. */
  async verify(token: string): Promise<ConnectorRow | undefined> {
    if (!token) return undefined;
    const [row] = await this.db
      .select()
      .from(connectors)
      .where(eq(connectors.tokenHash, hashToken(token)))
      .limit(1);
    return row && !row.revokedAt ? row : undefined;
  }

  async touch(id: string, version?: string): Promise<void> {
    await this.db
      .update(connectors)
      .set({ lastSeenAt: new Date(), ...(version ? { version } : {}) })
      .where(eq(connectors.id, id));
  }
}
