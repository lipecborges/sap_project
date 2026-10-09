import type { MeResponse } from "@raiox/contracts";
import { AppError } from "./errors";
import type { UserRepository } from "./repos/users";

export type Role = "user" | "admin";

/**
 * Quem pode usar o Raio-X, além da senha SAP (que o SAP valida).
 * A política com licenças (usuários nomeados, D34) substitui a básica.
 */
export interface AccessPolicy {
  /** Depois que o SAP aceitou a senha e antes de criar a sessão. Lança AppError para negar. */
  admitLogin(input: { tenantId: string; sapUser: string; me: MeResponse }): Promise<{ role: Role }>;
  /** Em cada requisição autenticada. Lança AppError se o usuário perdeu o acesso (ex.: bloqueado). */
  assertActive(tenantId: string, sapUser: string): Promise<{ role: Role }>;
}

/** Sem licenciamento: registra o usuário, respeita o bloqueio e dá admin a quem está em ADMIN_USERS. */
export class BasicAccessPolicy implements AccessPolicy {
  constructor(
    private readonly users: UserRepository,
    private readonly adminUsers: readonly string[],
  ) {}

  async admitLogin(input: { tenantId: string; sapUser: string }): Promise<{ role: Role }> {
    const user = await this.users.recordLogin(input.tenantId, input.sapUser);
    if (user.blocked) throw new AppError(403, "FORBIDDEN", "Usuário bloqueado no Raio-X. Fale com o administrador.");
    return { role: this.roleOf(input.sapUser, user.role) };
  }

  async assertActive(tenantId: string, sapUser: string): Promise<{ role: Role }> {
    const user = await this.users.get(tenantId, sapUser);
    if (user?.blocked) throw new AppError(403, "FORBIDDEN", "Usuário bloqueado no Raio-X. Fale com o administrador.");
    return { role: this.roleOf(sapUser, user?.role ?? "user") };
  }

  private roleOf(sapUser: string, stored: Role): Role {
    return this.adminUsers.includes(sapUser) ? "admin" : stored;
  }
}
