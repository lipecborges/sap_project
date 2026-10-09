import { z } from "zod";
import { HealthResponse } from "./api";

/**
 * Administração do Raio-X (/api/v1/admin/*). Só usuários com papel "admin"; tudo é do cliente (tenant)
 * da sessão. Toda alteração gera evento ADMIN_* na auditoria.
 */

// ── Usuários e licenças (D34) ───────────────────────────────────────────────

export const Role = z.enum(["user", "admin"]);
export type Role = z.infer<typeof Role>;

export const AdminUser = z.object({
  sapUser: z.string(),
  displayName: z.string().nullable(),
  role: Role,
  /** Ocupa uma licença de usuário nomeado. */
  hasSeat: z.boolean(),
  blocked: z.boolean(),
  firstLoginAt: z.string(),
  lastLoginAt: z.string().nullable(),
  activeSessions: z.number().int(),
});
export type AdminUser = z.infer<typeof AdminUser>;

export const AdminUserList = z.object({ users: z.array(AdminUser) });
export type AdminUserList = z.infer<typeof AdminUserList>;

/** PATCH /admin/users/:sapUser. seat=false libera a licença (o usuário perde o acesso até ganhar outra). */
export const AdminUserUpdate = z
  .object({ role: Role.optional(), blocked: z.boolean().optional(), seat: z.boolean().optional() })
  .refine((v) => Object.keys(v).length > 0, "Informe ao menos um campo");
export type AdminUserUpdate = z.infer<typeof AdminUserUpdate>;

export const LicenseState = z.enum(["valid", "evaluation", "grace", "expired", "invalid"]);
export type LicenseState = z.infer<typeof LicenseState>;

export const LicenseStatus = z.object({
  /** valid; evaluation (sem licença: limite reduzido); grace (vencida, ainda funcionando); expired; invalid. */
  state: LicenseState,
  licenseId: z.string().nullable(),
  customer: z.string().nullable(),
  edition: z.string().nullable(),
  maxNamedUsers: z.number().int(),
  usedSeats: z.number().int(),
  expiresAt: z.string().nullable(),
  features: z.array(z.string()),
  /** Avisos para o administrador (ex.: "vence em 12 dias", "9 de 10 licenças em uso"). */
  warnings: z.array(z.string()),
});
export type LicenseStatus = z.infer<typeof LicenseStatus>;

/** PUT /admin/license: o texto da licença assinada, como recebido do fornecedor. */
export const LicenseInstall = z.object({ license: z.string().trim().min(20).max(20_000) });
export type LicenseInstall = z.infer<typeof LicenseInstall>;

// ── Sistemas SAP ────────────────────────────────────────────────────────────

export const SapTransportKind = z.enum(["direct", "connector"]);

export const AdminSystem = z.object({
  id: z.string(),
  name: z.string(),
  transport: SapTransportKind,
  baseUrl: z.string().nullable(),
  sapClient: z.string().nullable(),
  connectorId: z.string().nullable(),
  isDefault: z.boolean(),
  /** Definido pelas variáveis SAP_* do servidor: não pode ser alterado nem removido pela tela. */
  managedByEnv: z.boolean(),
});
export type AdminSystem = z.infer<typeof AdminSystem>;

export const AdminSystemList = z.object({ systems: z.array(AdminSystem) });
export type AdminSystemList = z.infer<typeof AdminSystemList>;

/** POST /admin/systems (id obrigatório) e PATCH /admin/systems/:id (todos opcionais). */
export const AdminSystemInput = z.object({
  id: z
    .string()
    .regex(/^[a-z0-9-]{1,20}$/, "Use letras minúsculas, números e hífen (até 20)")
    .optional(),
  name: z.string().trim().min(1).max(40).optional(),
  transport: SapTransportKind.optional(),
  baseUrl: z.url().nullable().optional(),
  sapClient: z
    .string()
    .regex(/^\d{3}$/, "Mandante deve ter 3 dígitos")
    .nullable()
    .optional(),
  connectorId: z.string().nullable().optional(),
  isDefault: z.boolean().optional(),
});
export type AdminSystemInput = z.infer<typeof AdminSystemInput>;

/** POST /admin/systems/:id/test: chama /health do add-on com a credencial do administrador logado. */
export const SystemTestResult = z.object({
  ok: z.boolean(),
  latencyMs: z.number(),
  health: HealthResponse.optional(),
  error: z.object({ code: z.string(), message: z.string() }).optional(),
});
export type SystemTestResult = z.infer<typeof SystemTestResult>;

// ── Conectores on-premise (D35) ─────────────────────────────────────────────

export const AdminConnector = z.object({
  id: z.string(),
  name: z.string(),
  online: z.boolean(),
  version: z.string().nullable(),
  createdAt: z.string(),
  lastSeenAt: z.string().nullable(),
  revoked: z.boolean(),
});
export type AdminConnector = z.infer<typeof AdminConnector>;

export const AdminConnectorList = z.object({ connectors: z.array(AdminConnector) });
export type AdminConnectorList = z.infer<typeof AdminConnectorList>;

export const AdminConnectorCreate = z.object({ name: z.string().trim().min(1).max(60) });
export type AdminConnectorCreate = z.infer<typeof AdminConnectorCreate>;

/** O token aparece só nesta resposta: o servidor guarda apenas o hash. */
export const AdminConnectorCreated = z.object({ connector: AdminConnector, token: z.string() });
export type AdminConnectorCreated = z.infer<typeof AdminConnectorCreated>;

// ── Auditoria e uso (D36) ───────────────────────────────────────────────────

export const AuditEventDto = z.object({
  id: z.number().int(),
  at: z.string(),
  sapUser: z.string().nullable(),
  sapSystemId: z.string().nullable(),
  action: z.string(),
  target: z.string().nullable(),
  details: z.record(z.string(), z.unknown()).nullable(),
  outcome: z.string(),
  httpStatus: z.number().int().nullable(),
  durationMs: z.number().int().nullable(),
  ip: z.string().nullable(),
});
export type AuditEventDto = z.infer<typeof AuditEventDto>;

/**
 * GET /admin/audit?user=&action=&from=&to=&before=&limit= (from/to em ISO; before = id para a próxima página).
 * GET /admin/audit.csv com os mesmos filtros devolve CSV (até 50 000 linhas).
 */
export const AuditPage = z.object({ events: z.array(AuditEventDto), nextBefore: z.number().int().nullable() });
export type AuditPage = z.infer<typeof AuditPage>;

/** GET /admin/usage?days=30 */
export const UsageReport = z.object({
  days: z.array(
    z.object({ date: z.string(), runs: z.number().int(), chatTurns: z.number().int(), activeUsers: z.number().int() }),
  ),
  topDiagnostics: z.array(z.object({ id: z.string(), runs: z.number().int() })),
  topUsers: z.array(z.object({ sapUser: z.string(), runs: z.number().int(), chatTurns: z.number().int() })),
  /** Tempo médio de resposta do SAP por diagnóstico, em ms. */
  latency: z.array(z.object({ id: z.string(), avgMs: z.number(), p95Ms: z.number() })),
});
export type UsageReport = z.infer<typeof UsageReport>;
