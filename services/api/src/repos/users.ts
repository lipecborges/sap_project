import { and, eq, sql } from "drizzle-orm";
import type { Db } from "../db/client";
import { users } from "../db/schema";

export type UserRow = typeof users.$inferSelect;

/** Usuários do Raio-X (usuário SAP por cliente). Base para papéis e licenças (D34). */
export class UserRepository {
  constructor(private readonly db: Db) {}

  async get(tenantId: string, sapUser: string): Promise<UserRow | undefined> {
    const [row] = await this.db
      .select()
      .from(users)
      .where(and(eq(users.tenantId, tenantId), eq(users.sapUser, sapUser)))
      .limit(1);
    return row;
  }

  /** Cria o usuário no primeiro login e atualiza o último acesso. */
  async recordLogin(tenantId: string, sapUser: string): Promise<UserRow> {
    const now = new Date();
    const [row] = await this.db
      .insert(users)
      .values({ tenantId, sapUser, firstLoginAt: now, lastLoginAt: now })
      .onConflictDoUpdate({
        target: [users.tenantId, users.sapUser],
        set: { lastLoginAt: sql`excluded.last_login_at` },
      })
      .returning();
    if (!row) throw new Error("falha ao gravar usuário");
    return row;
  }
}
