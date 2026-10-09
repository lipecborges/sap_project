import type { KeyObject } from "node:crypto";
import { readFileSync } from "node:fs";
import type { LicenseStatus } from "@raiox/contracts";
import { and, count, eq, isNotNull, sql } from "drizzle-orm";
import type { Config } from "../config";
import type { Db } from "../db/client";
import { licenses, tenants, users } from "../db/schema";
import { AppError } from "../errors";
import {
  expiryInstant,
  LicenseFormatError,
  type LicensePayload,
  type ParsedLicense,
  parseLicense,
  parsePublicKey,
  VENDOR_PUBLIC_KEY,
  verifySignature,
} from "./format";

const DAY_MS = 24 * 60 * 60 * 1000;
/** Depois de vencida, a licença continua funcionando por este prazo, com avisos. */
export const GRACE_DAYS = 15;
/** Sem licença instalada: modo de avaliação com limite reduzido. */
export const EVALUATION_MAX_USERS = 5;
const EXPIRY_WARNING_DAYS = 30;
const SEAT_WARNING_RATIO = 0.9;
const CACHE_MS = 30_000;

/** Estado da licença sem a contagem de usuários (que muda a cada login). */
export interface LicenseEvaluation {
  state: LicenseStatus["state"];
  payload?: LicensePayload;
  maxNamedUsers: number;
  warnings: string[];
  /** De onde veio: tabela licenses, LICENSE_FILE ou nenhuma. */
  source: "database" | "file" | "none";
}

type LicenseConfig = Pick<Config, "LICENSE_FILE" | "LICENSE_PUBLIC_KEY" | "DEPLOYMENT_MODE">;

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

/**
 * Licenciamento por usuário nomeado (D34).
 * Fonte da licença: a tabela `licenses` (instalada pela administração) tem precedência;
 * LICENSE_FILE (Self-hosted) só vale enquanto o banco não tiver licença do cliente.
 */
export class LicenseService {
  private readonly cache = new Map<string, { at: number; value: LicenseEvaluation }>();
  private readonly publicKey: KeyObject;

  constructor(
    private readonly db: Db,
    private readonly config: LicenseConfig,
    private readonly now: () => number = Date.now,
  ) {
    this.publicKey = parsePublicKey(config.LICENSE_PUBLIC_KEY ?? VENDOR_PUBLIC_KEY);
  }

  invalidate(tenantId?: string): void {
    if (tenantId) this.cache.delete(tenantId);
    else this.cache.clear();
  }

  /** Estado da licença do cliente, em cache por alguns segundos. */
  async evaluate(tenantId: string): Promise<LicenseEvaluation> {
    const cached = this.cache.get(tenantId);
    if (cached && this.now() - cached.at < CACHE_MS) return cached.value;
    const value = await this.load(tenantId);
    this.cache.set(tenantId, { at: this.now(), value });
    return value;
  }

  /** O que a tela de administração mostra: estado + usuários em uso + avisos. */
  async status(tenantId: string): Promise<LicenseStatus> {
    const evaluation = await this.evaluate(tenantId);
    const usedSeats = await this.usedSeats(tenantId);
    const warnings = [...evaluation.warnings];
    const { maxNamedUsers } = evaluation;
    if (maxNamedUsers > 0 && usedSeats / maxNamedUsers >= SEAT_WARNING_RATIO) {
      warnings.push(`${usedSeats} de ${maxNamedUsers} licenças de usuário em uso`);
    }
    const p = evaluation.payload;
    return {
      state: evaluation.state,
      licenseId: p?.licenseId ?? null,
      customer: p?.customer ?? null,
      edition: p?.edition ?? null,
      maxNamedUsers,
      usedSeats,
      expiresAt: p?.expiresAt ?? null,
      features: p?.features ?? [],
      warnings,
    };
  }

  /** Aviso para mostrar ao usuário no app (carência) ou ao administrador (licença sem efeito). */
  async notice(tenantId: string, role: "user" | "admin"): Promise<string | undefined> {
    const evaluation = await this.evaluate(tenantId);
    if (evaluation.state === "grace") return evaluation.warnings[0];
    if (role === "admin" && (evaluation.state === "expired" || evaluation.state === "invalid")) {
      return evaluation.warnings[0];
    }
    return undefined;
  }

  /** Valida e grava a licença do cliente. Licença inválida é recusada (400); vencida é aceita e mostra o estado. */
  async install(tenantId: string, text: string, installedBy: string): Promise<LicenseStatus> {
    const evaluation = this.evaluateText(tenantId, text);
    if (evaluation.state === "invalid") {
      throw new AppError(400, "INVALID_PARAMS", evaluation.warnings[0] ?? "Licença inválida");
    }
    const normalized = text.replace(/\s+/g, "");
    await this.db
      .insert(licenses)
      .values({ tenantId, license: normalized, installedBy, installedAt: new Date() })
      .onConflictDoUpdate({
        target: licenses.tenantId,
        set: { license: normalized, installedBy, installedAt: new Date() },
      });
    this.invalidate(tenantId);
    return this.status(tenantId);
  }

  async usedSeats(tenantId: string): Promise<number> {
    const [row] = await this.db
      .select({ n: count() })
      .from(users)
      .where(and(eq(users.tenantId, tenantId), isNotNull(users.seatAssignedAt)));
    return row?.n ?? 0;
  }

  /**
   * Ocupa uma licença para o usuário, sem passar do limite mesmo com logins simultâneos:
   * a contagem e a atribuição acontecem numa transação que trava a linha do cliente.
   * Devolve false quando o limite foi atingido.
   */
  async claimSeat(tenantId: string, sapUser: string): Promise<boolean> {
    const { maxNamedUsers } = await this.evaluate(tenantId);
    return this.db.transaction(async (tx) => {
      await tx.select({ id: tenants.id }).from(tenants).where(eq(tenants.id, tenantId)).for("update");
      const [user] = await tx
        .select({ seatAssignedAt: users.seatAssignedAt })
        .from(users)
        .where(and(eq(users.tenantId, tenantId), eq(users.sapUser, sapUser)))
        .limit(1);
      if (!user) throw new AppError(404, "ROUTE_NOT_FOUND", `Usuário ${sapUser} não encontrado`);
      if (user.seatAssignedAt) return true;
      const [used] = await tx
        .select({ n: count() })
        .from(users)
        .where(and(eq(users.tenantId, tenantId), isNotNull(users.seatAssignedAt)));
      if ((used?.n ?? 0) >= maxNamedUsers) return false;
      await tx
        .update(users)
        .set({ seatAssignedAt: new Date() })
        .where(and(eq(users.tenantId, tenantId), eq(users.sapUser, sapUser), sql`${users.seatAssignedAt} is null`));
      return true;
    });
  }

  async releaseSeat(tenantId: string, sapUser: string): Promise<void> {
    await this.db
      .update(users)
      .set({ seatAssignedAt: null })
      .where(and(eq(users.tenantId, tenantId), eq(users.sapUser, sapUser)));
  }

  private async load(tenantId: string): Promise<LicenseEvaluation> {
    const [row] = await this.db.select().from(licenses).where(eq(licenses.tenantId, tenantId)).limit(1);
    if (row) return { ...this.evaluateText(tenantId, row.license), source: "database" };
    if (this.config.LICENSE_FILE) {
      let text: string;
      try {
        text = readFileSync(this.config.LICENSE_FILE, "utf8");
      } catch {
        return this.invalid(`Arquivo de licença ilegível: ${this.config.LICENSE_FILE}`, "file");
      }
      return { ...this.evaluateText(tenantId, text), source: "file" };
    }
    return {
      state: "evaluation",
      maxNamedUsers: EVALUATION_MAX_USERS,
      warnings: [`Sem licença instalada: modo de avaliação (até ${EVALUATION_MAX_USERS} usuários)`],
      source: "none",
    };
  }

  private invalid(reason: string, source: LicenseEvaluation["source"], payload?: LicensePayload): LicenseEvaluation {
    return { state: "invalid", payload, maxNamedUsers: 0, warnings: [reason], source };
  }

  /** Estado de um texto de licença (assinatura, modo de implantação, cliente e validade). */
  evaluateText(tenantId: string, text: string): LicenseEvaluation {
    let parsed: ParsedLicense;
    try {
      parsed = parseLicense(text);
    } catch (err) {
      return this.invalid(err instanceof LicenseFormatError ? err.message : "Licença ilegível", "database");
    }
    if (!verifySignature(parsed, this.publicKey)) {
      return this.invalid("Assinatura da licença inválida", "database");
    }
    const p = parsed.payload;
    if (p.deployment !== "any" && p.deployment !== this.config.DEPLOYMENT_MODE) {
      const reason = `Licença emitida para implantação ${p.deployment}, mas este servidor é ${this.config.DEPLOYMENT_MODE}`;
      return this.invalid(reason, "database", p);
    }
    if (p.tenantId && p.tenantId !== tenantId) {
      return this.invalid("Licença emitida para outro cliente", "database", p);
    }
    const now = this.now();
    const expires = expiryInstant(p.expiresAt).getTime();
    const base = { payload: p, maxNamedUsers: p.maxNamedUsers, source: "database" as const };
    if (now <= expires) {
      const days = Math.ceil((expires - now) / DAY_MS);
      const warnings = days <= EXPIRY_WARNING_DAYS ? [`A licença vence em ${plural(days, "dia", "dias")}`] : [];
      return { ...base, state: "valid", warnings };
    }
    const graceEnd = expires + GRACE_DAYS * DAY_MS;
    if (now <= graceEnd) {
      const left = Math.ceil((graceEnd - now) / DAY_MS);
      const warning = `Licença vencida em ${p.expiresAt}. O acesso será bloqueado em ${plural(left, "dia", "dias")}; instale a nova licença`;
      return { ...base, state: "grace", warnings: [warning] };
    }
    return { ...base, state: "expired", warnings: [`Licença vencida em ${p.expiresAt}. Instale uma nova licença`] };
  }
}
