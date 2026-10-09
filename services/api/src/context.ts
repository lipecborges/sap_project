import type { FastifyBaseLogger, FastifyRequest } from "fastify";
import type { AccessPolicy, Role } from "./access";
import type { LlmProvider } from "./ai/provider";
import type { Config } from "./config";
import type { Database } from "./db/client";
import { AppError } from "./errors";
import type { Metrics } from "./plugins/metrics";
import type { AuditLog } from "./repos/audit";
import type { ConversationRepository } from "./repos/conversations";
import type { SessionRepository } from "./repos/sessions";
import { DEFAULT_TENANT, type SapSystem, type SystemRegistry } from "./repos/systems";
import type { UserRepository } from "./repos/users";
import type { SapClient } from "./sap/client";
import type { ConnectorHub, SapCredentials } from "./sap/transport";

export const SESSION_COOKIE = "raiox_session";
/** Integrações com Basic auth escolhem o sistema SAP por este cabeçalho (padrão: o sistema padrão). */
export const SYSTEM_HEADER = "x-raiox-system";

/** Tudo que as rotas usam. Montado uma vez em createApp. */
export interface AppContext {
  config: Config;
  log: FastifyBaseLogger;
  database: Database;
  sessions: SessionRepository;
  conversations: ConversationRepository;
  users: UserRepository;
  audit: AuditLog;
  systems: SystemRegistry;
  access: AccessPolicy;
  hub: ConnectorHub;
  provider: LlmProvider;
  /** Métricas Prometheus (definido por registerObservability). */
  metrics?: Metrics;
}

/** Usuário autenticado na requisição. */
export interface Auth {
  tenantId: string;
  system: SapSystem;
  sapUser: string;
  role: Role;
  credentials: SapCredentials;
  sap: SapClient;
  via: "session" | "basic";
}

/**
 * Cliente (tenant) da requisição. Self-hosted: sempre "default".
 * Cloud: subdomínio de CLOUD_BASE_DOMAIN (acme.raiox.app → acme); sem ele, "default".
 */
export function resolveTenant(config: Config, request: FastifyRequest): string {
  if (config.DEPLOYMENT_MODE === "selfhosted" || !config.CLOUD_BASE_DOMAIN) return DEFAULT_TENANT;
  const host = (request.hostname ?? "").toLowerCase().split(":")[0] ?? "";
  const suffix = `.${config.CLOUD_BASE_DOMAIN.toLowerCase()}`;
  if (!host.endsWith(suffix)) throw new AppError(404, "ROUTE_NOT_FOUND", "Cliente não identificado pelo endereço");
  const tenant = host.slice(0, -suffix.length);
  if (!/^[a-z0-9-]{1,40}$/.test(tenant)) throw new AppError(404, "ROUTE_NOT_FOUND", "Cliente não identificado");
  return tenant;
}

/** Credencial Basic (integrações e testes); o navegador usa o cookie de sessão. */
export function basicCredentials(request: FastifyRequest): SapCredentials | undefined {
  const header = request.headers.authorization;
  if (header?.startsWith("Basic ")) {
    const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
    const sep = decoded.indexOf(":");
    if (sep > 0) return { user: decoded.slice(0, sep).toUpperCase(), password: decoded.slice(sep + 1) };
  }
  return undefined;
}

/** Autentica a requisição pela sessão (cookie) ou por Basic. Lança 401 sem credencial. */
export async function authenticate(ctx: AppContext, request: FastifyRequest): Promise<Auth> {
  const session = await ctx.sessions.get(request.cookies[SESSION_COOKIE]);
  if (session) {
    const system = await ctx.systems.get(session.tenantId, session.sapSystemId);
    if (!system) {
      await ctx.sessions.delete(request.cookies[SESSION_COOKIE]);
      throw new AppError(401, "UNAUTHENTICATED", "O sistema SAP desta sessão foi removido. Entre novamente.");
    }
    const { role } = await ctx.access.assertActive(session.tenantId, session.sapUser);
    return {
      tenantId: session.tenantId,
      system,
      sapUser: session.sapUser,
      role,
      credentials: session.credentials,
      sap: ctx.systems.client(system),
      via: "session",
    };
  }
  const basic = basicCredentials(request);
  if (basic) {
    const tenantId = resolveTenant(ctx.config, request);
    const header = request.headers[SYSTEM_HEADER];
    const system = await ctx.systems.resolve(tenantId, typeof header === "string" ? header : undefined);
    const { role } = await ctx.access.assertActive(tenantId, basic.user);
    return {
      tenantId,
      system,
      sapUser: basic.user,
      role,
      credentials: basic,
      sap: ctx.systems.client(system),
      via: "basic",
    };
  }
  throw new AppError(401, "UNAUTHENTICATED", "Sessão expirada. Entre novamente.");
}

export async function requireAdmin(ctx: AppContext, request: FastifyRequest): Promise<Auth> {
  const auth = await authenticate(ctx, request);
  if (auth.role !== "admin") throw new AppError(403, "FORBIDDEN", "Acesso restrito a administradores do Raio-X");
  return auth;
}
