import { Readable } from "node:stream";
import {
  type AdminSystem,
  AdminSystemInput,
  type AdminUser,
  AdminUserUpdate,
  type AuditEventDto,
  type AuditPage,
  LicenseInstall,
  type LicenseStatus,
  type SystemTestResult,
  type UsageReport,
} from "@raiox/contracts";
import { and, count, desc, eq, inArray, sql } from "drizzle-orm";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { type AppContext, type Auth, requireAdmin } from "../context";
import { auditEvents } from "../db/schema";
import { AppError } from "../errors";
import type { SapSystem } from "../repos/systems";
import type { UserRow } from "../repos/users";

const CSV_MAX_ROWS = 50_000;
const CSV_CHUNK = 1_000;
const AUDIT_PAGE_MAX = 500;

const AuditFilters = z.object({
  user: z
    .string()
    .trim()
    .min(1)
    .max(40)
    .transform((u) => u.toUpperCase())
    .optional(),
  action: z.string().trim().min(1).max(60).optional(),
  from: z.string().pipe(z.coerce.date()).optional(),
  to: z.string().pipe(z.coerce.date()).optional(),
  before: z.coerce.number().int().positive().optional(),
});
const AuditPageQuery = AuditFilters.extend({ limit: z.coerce.number().int().min(1).max(AUDIT_PAGE_MAX).default(100) });
const UsageQuery = z.object({ days: z.coerce.number().int().min(1).max(365).default(30) });

const DAY_MS = 24 * 60 * 60 * 1000;

export function adminRoutes(app: FastifyInstance, ctx: AppContext): void {
  /** Toda alteração da administração fica na auditoria (nunca com segredos). */
  const audit = (
    auth: Auth,
    request: FastifyRequest,
    action: string,
    target: string,
    details: Record<string, unknown>,
  ) =>
    ctx.audit.record({
      tenantId: auth.tenantId,
      action,
      sapUser: auth.sapUser,
      sapSystemId: auth.system.id,
      target,
      details,
      outcome: "ok",
      httpStatus: 200,
      ip: request.ip,
      requestId: request.id,
    });

  const toAdminUser = (row: UserRow, sessions: Map<string, number>): AdminUser => ({
    sapUser: row.sapUser,
    displayName: row.displayName,
    role: ctx.config.ADMIN_USERS.includes(row.sapUser) ? "admin" : row.role,
    hasSeat: row.seatAssignedAt !== null,
    blocked: row.blocked,
    firstLoginAt: row.firstLoginAt.toISOString(),
    lastLoginAt: row.lastLoginAt?.toISOString() ?? null,
    activeSessions: sessions.get(row.sapUser) ?? 0,
  });

  const toAdminSystem = (s: SapSystem): AdminSystem => ({
    id: s.id,
    name: s.name,
    transport: s.transport,
    baseUrl: s.baseUrl,
    sapClient: s.sapClient,
    connectorId: s.connectorId,
    isDefault: s.isDefault,
    managedByEnv: ctx.systems.isManagedByEnv(s),
  });

  // ── Usuários e licença ────────────────────────────────────────────────────

  app.get("/api/v1/admin/users", async (request) => {
    const auth = await requireAdmin(ctx, request);
    const [rows, sessions] = await Promise.all([
      ctx.users.list(auth.tenantId),
      ctx.sessions.activeCounts(auth.tenantId),
    ]);
    return { users: rows.map((r) => toAdminUser(r, sessions)) };
  });

  app.patch<{ Params: { sapUser: string } }>("/api/v1/admin/users/:sapUser", async (request) => {
    const auth = await requireAdmin(ctx, request);
    const sapUser = request.params.sapUser.trim().toUpperCase();
    const patch = AdminUserUpdate.parse(request.body ?? {});
    const current = await ctx.users.get(auth.tenantId, sapUser);
    if (!current) throw new AppError(404, "ROUTE_NOT_FOUND", `Usuário ${sapUser} não encontrado`);
    if (sapUser === auth.sapUser && (patch.blocked === true || patch.role === "user" || patch.seat === false)) {
      throw new AppError(400, "INVALID_PARAMS", "Você não pode bloquear, rebaixar nem tirar a licença de si mesmo");
    }

    const before = { role: current.role, blocked: current.blocked, seat: current.seatAssignedAt !== null };
    if (patch.seat === true && !before.seat && !(await ctx.license.claimSeat(auth.tenantId, sapUser))) {
      const { maxNamedUsers } = await ctx.license.evaluate(auth.tenantId);
      throw new AppError(
        409,
        "LICENSE_REQUIRED",
        `Limite de ${maxNamedUsers} usuários do Raio-X atingido. Libere a licença de outro usuário antes.`,
      );
    }
    if (patch.seat === false) await ctx.license.releaseSeat(auth.tenantId, sapUser);
    await ctx.users.update(auth.tenantId, sapUser, { role: patch.role, blocked: patch.blocked });

    ctx.access.invalidate?.(auth.tenantId, sapUser);
    // Quem foi bloqueado ou perdeu a licença sai agora, não só quando a sessão vencer.
    const revoked = patch.blocked === true || patch.seat === false;
    const closedSessions = revoked ? await ctx.sessions.deleteForUser(auth.tenantId, sapUser) : 0;

    const updated = await ctx.users.get(auth.tenantId, sapUser);
    if (!updated) throw new AppError(404, "ROUTE_NOT_FOUND", `Usuário ${sapUser} não encontrado`);
    await audit(auth, request, "ADMIN_USER_UPDATE", sapUser, {
      before,
      after: { role: updated.role, blocked: updated.blocked, seat: updated.seatAssignedAt !== null },
      closedSessions,
    });
    return toAdminUser(updated, await ctx.sessions.activeCounts(auth.tenantId));
  });

  app.get("/api/v1/admin/license", async (request): Promise<LicenseStatus> => {
    const auth = await requireAdmin(ctx, request);
    return ctx.license.status(auth.tenantId);
  });

  app.put("/api/v1/admin/license", async (request): Promise<LicenseStatus> => {
    const auth = await requireAdmin(ctx, request);
    const { license } = LicenseInstall.parse(request.body ?? {});
    const status = await ctx.license.install(auth.tenantId, license, auth.sapUser);
    ctx.access.invalidate?.(auth.tenantId);
    await audit(auth, request, "ADMIN_LICENSE_INSTALL", status.licenseId ?? "-", {
      licenseId: status.licenseId,
      customer: status.customer,
      edition: status.edition,
      maxNamedUsers: status.maxNamedUsers,
      expiresAt: status.expiresAt,
      state: status.state,
    });
    return status;
  });

  // ── Sistemas SAP ──────────────────────────────────────────────────────────

  app.get("/api/v1/admin/systems", async (request) => {
    const auth = await requireAdmin(ctx, request);
    return { systems: (await ctx.systems.list(auth.tenantId)).map(toAdminSystem) };
  });

  app.post("/api/v1/admin/systems", async (request, reply) => {
    const auth = await requireAdmin(ctx, request);
    const body = AdminSystemInput.parse(request.body ?? {});
    if (!body.id) throw new AppError(400, "INVALID_PARAMS", "Informe o id do sistema");
    if (!body.name) throw new AppError(400, "INVALID_PARAMS", "Informe o nome do sistema");
    const { id, ...fields } = body;
    const created = await ctx.systems.create(auth.tenantId, id, fields);
    await audit(auth, request, "ADMIN_SYSTEM_CREATE", created.id, { system: toAdminSystem(created) });
    return reply.status(201).send(toAdminSystem(created));
  });

  app.patch<{ Params: { id: string } }>("/api/v1/admin/systems/:id", async (request) => {
    const auth = await requireAdmin(ctx, request);
    const { id: _ignored, ...patch } = AdminSystemInput.parse(request.body ?? {});
    const before = await ctx.systems.get(auth.tenantId, request.params.id);
    const updated = await ctx.systems.update(auth.tenantId, request.params.id, patch);
    await audit(auth, request, "ADMIN_SYSTEM_UPDATE", updated.id, {
      before: before ? toAdminSystem(before) : null,
      after: toAdminSystem(updated),
    });
    return toAdminSystem(updated);
  });

  app.delete<{ Params: { id: string } }>("/api/v1/admin/systems/:id", async (request) => {
    const auth = await requireAdmin(ctx, request);
    const { removed, promoted } = await ctx.systems.remove(auth.tenantId, request.params.id);
    const closedSessions = await ctx.sessions.deleteForSystem(auth.tenantId, removed.id);
    await audit(auth, request, "ADMIN_SYSTEM_DELETE", removed.id, {
      system: toAdminSystem(removed),
      closedSessions,
      newDefault: promoted ?? null,
    });
    return { ok: true };
  });

  /** Chama /health do add-on com a credencial do administrador logado e mede o tempo de resposta. */
  app.post<{ Params: { id: string } }>("/api/v1/admin/systems/:id/test", async (request): Promise<SystemTestResult> => {
    const auth = await requireAdmin(ctx, request);
    const system = await ctx.systems.get(auth.tenantId, request.params.id);
    if (!system) throw new AppError(404, "ROUTE_NOT_FOUND", `Sistema ${request.params.id} não encontrado`);
    const started = performance.now();
    try {
      const health = await ctx.systems.client(system).health(auth.credentials);
      return { ok: true, latencyMs: Math.round(performance.now() - started), health };
    } catch (err) {
      const e = err instanceof AppError ? err : new AppError(500, "INTERNAL", "Falha inesperada no teste");
      return {
        ok: false,
        latencyMs: Math.round(performance.now() - started),
        error: { code: e.code, message: e.message },
      };
    }
  });

  // ── Auditoria e uso ───────────────────────────────────────────────────────

  const toAuditDto = (r: typeof auditEvents.$inferSelect): AuditEventDto => ({
    id: r.id,
    at: r.at.toISOString(),
    sapUser: r.sapUser,
    sapSystemId: r.sapSystemId,
    action: r.action,
    target: r.target,
    details: (r.details as Record<string, unknown> | null) ?? null,
    outcome: r.outcome,
    httpStatus: r.httpStatus,
    durationMs: r.durationMs,
    ip: r.ip,
  });

  app.get("/api/v1/admin/audit", async (request): Promise<AuditPage> => {
    const auth = await requireAdmin(ctx, request);
    const { user, limit, ...filters } = AuditPageQuery.parse(request.query);
    // Uma linha a mais diz se existe próxima página.
    const rows = await ctx.audit.query({ tenantId: auth.tenantId, sapUser: user, ...filters, limit: limit + 1 });
    const page = rows.slice(0, limit);
    return { events: page.map(toAuditDto), nextBefore: rows.length > limit ? (page.at(-1)?.id ?? null) : null };
  });

  app.get("/api/v1/admin/audit.csv", async (request, reply) => {
    const auth = await requireAdmin(ctx, request);
    const { user, ...filters } = AuditFilters.parse(request.query);
    const base = { tenantId: auth.tenantId, sapUser: user, ...filters };
    async function* lines(): AsyncGenerator<string> {
      yield csvLine(CSV_HEADER);
      let before = base.before;
      let sent = 0;
      while (sent < CSV_MAX_ROWS) {
        const rows = await ctx.audit.query({ ...base, before, limit: Math.min(CSV_CHUNK, CSV_MAX_ROWS - sent) });
        for (const r of rows) yield csvLine(toCsvRow(toAuditDto(r)));
        sent += rows.length;
        if (rows.length < CSV_CHUNK) return;
        before = rows.at(-1)?.id;
      }
    }
    return reply
      .header("content-type", "text/csv; charset=utf-8")
      .header("content-disposition", 'attachment; filename="auditoria-raiox.csv"')
      .send(Readable.from(lines()));
  });

  app.get("/api/v1/admin/usage", async (request): Promise<UsageReport> => {
    const auth = await requireAdmin(ctx, request);
    const { days } = UsageQuery.parse(request.query);
    const today = new Date();
    const since = new Date(
      Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()) - (days - 1) * DAY_MS,
    );
    return usageReport(ctx, auth.tenantId, since, days);
  });
}

// ── CSV ─────────────────────────────────────────────────────────────────────

const CSV_HEADER = [
  "id",
  "data",
  "usuario",
  "sistema",
  "acao",
  "alvo",
  "resultado",
  "http",
  "duracao_ms",
  "ip",
  "detalhes",
];

function toCsvRow(e: AuditEventDto): (string | number | null)[] {
  return [
    e.id,
    e.at,
    e.sapUser,
    e.sapSystemId,
    e.action,
    e.target,
    e.outcome,
    e.httpStatus,
    e.durationMs,
    e.ip,
    e.details ? JSON.stringify(e.details) : null,
  ];
}

/** Aspas quando há vírgula, aspas ou quebra de linha; células de texto que começam com = + - @ ganham um apóstrofo (injeção de fórmula). */
function csvCell(value: string | number | null): string {
  if (value === null) return "";
  let text = String(value);
  if (typeof value === "string" && /^[=+\-@\t\r]/.test(text)) text = `'${text}`;
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

const csvLine = (cells: (string | number | null)[]) => `${cells.map(csvCell).join(",")}\r\n`;

// ── Uso ─────────────────────────────────────────────────────────────────────

async function usageReport(ctx: AppContext, tenantId: string, since: Date, days: number): Promise<UsageReport> {
  const { db } = ctx.database;
  const e = auditEvents;
  const inPeriod = and(eq(e.tenantId, tenantId), sql`${e.at} >= ${since}`);
  const isRun = sql`${e.action} = 'DIAGNOSTIC_RUN'`;
  const isChat = sql`${e.action} = 'CHAT_TURN'`;
  const num = (expr: ReturnType<typeof sql>) => sql<number>`${expr}`.mapWith(Number);

  const day = sql<string>`to_char(${e.at} at time zone 'UTC', 'YYYY-MM-DD')`;
  const perDay = await db
    .select({
      date: day,
      runs: num(sql`count(*) filter (where ${isRun})`),
      chatTurns: num(sql`count(*) filter (where ${isChat})`),
      activeUsers: num(
        sql`count(distinct ${e.sapUser}) filter (where ${inArray(e.action, ["LOGIN", "DIAGNOSTIC_RUN", "CHAT_TURN"])})`,
      ),
    })
    .from(e)
    .where(inPeriod)
    .groupBy(day);
  const byDate = new Map(perDay.map((r) => [r.date, r]));
  const series: UsageReport["days"] = [];
  for (let i = 0; i < days; i++) {
    const date = new Date(since.getTime() + i * DAY_MS).toISOString().slice(0, 10);
    const row = byDate.get(date);
    series.push({ date, runs: row?.runs ?? 0, chatTurns: row?.chatTurns ?? 0, activeUsers: row?.activeUsers ?? 0 });
  }

  const topDiagnostics = await db
    .select({ id: sql<string>`${e.target}`, runs: num(sql`count(*)`) })
    .from(e)
    .where(and(inPeriod, eq(e.action, "DIAGNOSTIC_RUN"), sql`${e.target} is not null`))
    .groupBy(e.target)
    .orderBy(desc(count()), e.target)
    .limit(10);

  const topUsers = await db
    .select({
      sapUser: sql<string>`${e.sapUser}`,
      runs: num(sql`count(*) filter (where ${isRun})`),
      chatTurns: num(sql`count(*) filter (where ${isChat})`),
    })
    .from(e)
    .where(and(inPeriod, inArray(e.action, ["DIAGNOSTIC_RUN", "CHAT_TURN"]), sql`${e.sapUser} is not null`))
    .groupBy(e.sapUser)
    .orderBy(desc(count()), e.sapUser)
    .limit(10);

  const latency = await db
    .select({
      id: sql<string>`${e.target}`,
      avgMs: num(sql`avg(${e.durationMs})`),
      p95Ms: num(sql`percentile_cont(0.95) within group (order by ${e.durationMs})`),
    })
    .from(e)
    .where(
      and(
        inPeriod,
        eq(e.action, "DIAGNOSTIC_RUN"),
        eq(e.outcome, "ok"),
        sql`${e.target} is not null`,
        sql`${e.durationMs} is not null`,
      ),
    )
    .groupBy(e.target)
    .orderBy(e.target);

  return { days: series, topDiagnostics, topUsers, latency };
}
