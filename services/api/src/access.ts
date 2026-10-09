import type { MeResponse } from "@raiox/contracts";
import { AppError } from "./errors";
import type { LicenseService } from "./license/service";
import type { UserRepository, UserRow } from "./repos/users";

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
  /** Aviso de licença para o SessionInfo (ex.: licença em carência). */
  notice?(tenantId: string, role: Role): Promise<string | undefined>;
  /** A administração mudou usuários ou licença: esquece o que estava em cache (neste processo). */
  invalidate?(tenantId: string, sapUser?: string): void;
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

const BLOCKED = "Usuário bloqueado no Raio-X. Fale com o administrador.";
/** Quanto tempo assertActive confia no que leu do banco (em outras réplicas, a mudança chega em até este prazo). */
const ACTIVE_CACHE_MS = 10_000;

/**
 * Política com licenciamento por usuário nomeado (D34).
 * - Administradores (ADMIN_USERS ou papel gravado) entram mesmo com a licença vencida ou o limite atingido,
 *   para poder instalar a licença e liberar usuários; ocupam uma licença só se houver sobra.
 * - Os demais precisam de licença utilizável (válida, avaliação ou carência) e de uma vaga; a primeira vaga
 *   livre é atribuída automaticamente no primeiro acesso.
 */
export class LicensedAccessPolicy implements AccessPolicy {
  private readonly cache = new Map<string, { at: number; user: UserRow }>();

  constructor(
    private readonly users: UserRepository,
    private readonly license: LicenseService,
    private readonly adminUsers: readonly string[],
    private readonly now: () => number = Date.now,
  ) {}

  async admitLogin(input: { tenantId: string; sapUser: string }): Promise<{ role: Role }> {
    const user = await this.users.recordLogin(input.tenantId, input.sapUser);
    this.cache.delete(`${input.tenantId}/${input.sapUser}`);
    return this.admit(input.tenantId, user);
  }

  async assertActive(tenantId: string, sapUser: string): Promise<{ role: Role }> {
    const key = `${tenantId}/${sapUser}`;
    const cached = this.cache.get(key);
    let user = cached && this.now() - cached.at < ACTIVE_CACHE_MS ? cached.user : undefined;
    if (!user) {
      user = await this.users.get(tenantId, sapUser);
      // Integração com Basic que nunca fez login: o primeiro uso conta como acesso (registra e tenta uma vaga).
      if (!user) return this.admitLogin({ tenantId, sapUser });
      this.cache.set(key, { at: this.now(), user });
    }
    if (user.blocked) throw new AppError(403, "FORBIDDEN", BLOCKED);
    const role = this.roleOf(sapUser, user.role);
    if (role === "admin") return { role };
    const { state } = await this.license.evaluate(tenantId);
    if (state === "expired" || state === "invalid") throw this.licenseRequired(state);
    if (!user.seatAssignedAt) {
      throw new AppError(403, "LICENSE_REQUIRED", "Você não tem licença de uso do Raio-X. Fale com o administrador.");
    }
    return { role };
  }

  notice(tenantId: string, role: Role): Promise<string | undefined> {
    return this.license.notice(tenantId, role);
  }

  invalidate(tenantId: string, sapUser?: string): void {
    if (sapUser) this.cache.delete(`${tenantId}/${sapUser}`);
    else for (const key of this.cache.keys()) if (key.startsWith(`${tenantId}/`)) this.cache.delete(key);
    this.license.invalidate(tenantId);
  }

  private async admit(tenantId: string, user: UserRow): Promise<{ role: Role }> {
    if (user.blocked) throw new AppError(403, "FORBIDDEN", BLOCKED);
    const role = this.roleOf(user.sapUser, user.role);
    const evaluation = await this.license.evaluate(tenantId);
    if (evaluation.state === "expired" || evaluation.state === "invalid") {
      if (role === "admin") return { role };
      throw this.licenseRequired(evaluation.state);
    }
    if (user.seatAssignedAt) return { role };
    const claimed = await this.license.claimSeat(tenantId, user.sapUser);
    if (claimed || role === "admin") return { role };
    throw new AppError(
      403,
      "LICENSE_REQUIRED",
      `Limite de ${evaluation.maxNamedUsers} usuários do Raio-X atingido. Fale com o administrador.`,
    );
  }

  private licenseRequired(state: string): AppError {
    return new AppError(
      403,
      "LICENSE_REQUIRED",
      state === "expired"
        ? "A licença do Raio-X venceu. Fale com o administrador."
        : "A licença do Raio-X é inválida. Fale com o administrador.",
    );
  }

  private roleOf(sapUser: string, stored: Role): Role {
    return this.adminUsers.includes(sapUser) ? "admin" : stored;
  }
}
