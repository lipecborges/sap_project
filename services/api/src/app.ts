import { existsSync } from "node:fs";
import { resolve } from "node:path";
import fastifyCookie from "@fastify/cookie";
import fastifyStatic from "@fastify/static";
import Fastify, { type FastifyInstance } from "fastify";
import { z } from "zod";
import { type AccessPolicy, LicensedAccessPolicy } from "./access";
import { AnthropicProvider } from "./ai/anthropic-provider";
import { DemoProvider } from "./ai/demo-provider";
import type { LlmProvider } from "./ai/provider";
import type { Config } from "./config";
import { GatewayHub, type GatewayOptions } from "./connector/hub";
import { ConnectorRepository } from "./connector/repository";
import { connectorRoutes } from "./connector/routes";
import type { AppContext } from "./context";
import { Cipher } from "./db/cipher";
import { type Database, openDatabase } from "./db/client";
import { AppError } from "./errors";
import { LicenseService } from "./license/service";
import { registerObservability } from "./plugins/metrics";
import { registerSecurity, serverOptions } from "./plugins/security";
import { AuditLog } from "./repos/audit";
import { ConversationRepository } from "./repos/conversations";
import { SessionRepository } from "./repos/sessions";
import { SystemRegistry } from "./repos/systems";
import { UserRepository } from "./repos/users";
import { adminRoutes } from "./routes/admin";
import { authRoutes } from "./routes/auth";
import { chatRoutes } from "./routes/chat";
import { healthRoutes } from "./routes/health";
import { sapRoutes } from "./routes/sap";
import { type ConnectorHub, offlineConnectorHub, type SapTransport } from "./sap/transport";

export { SESSION_COOKIE } from "./context";
export { API_VERSION } from "./version";

export function createProvider(config: Config): LlmProvider {
  if (config.AI_PROVIDER === "anthropic") {
    return new AnthropicProvider({ model: config.AI_MODEL, effort: config.AI_EFFORT, fallbacks: config.AI_FALLBACKS });
  }
  return new DemoProvider();
}

export interface AppOptions {
  /** Testes: um único transporte para todos os sistemas SAP. */
  transport?: SapTransport;
  provider?: LlmProvider;
  /** Banco já aberto (testes); por padrão abre DATABASE_URL. */
  database?: Database;
  hub?: ConnectorHub;
  /** Ajustes do gateway de conectores (testes: prazos curtos). Ignorado quando `hub` é informado. */
  gateway?: GatewayOptions;
  access?: AccessPolicy;
}

/** Intervalo da limpeza de sessões vencidas e da retenção (conversas e auditoria). */
const MAINTENANCE_INTERVAL_MS = 60 * 60 * 1000;

/** Monta a API: abre o banco (aplicando as migrações), prepara os serviços e registra as rotas. */
export async function createApp(config: Config, options: AppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify(serverOptions(config));

  const database = options.database ?? (await openDatabase(config.DATABASE_URL));
  if (!options.database) app.addHook("onClose", () => database.close());
  if (config.DATABASE_URL_DEFAULTED && !options.database) {
    app.log.warn("DATABASE_URL não definido: usando banco em memória (dados somem ao reiniciar)");
  }
  let cipher: Cipher;
  if (config.SESSION_SECRET) {
    cipher = new Cipher(config.SESSION_SECRET);
  } else {
    app.log.warn("SESSION_SECRET não definido: chave temporária (as sessões caem ao reiniciar)");
    cipher = Cipher.random();
  }

  const gateway = options.hub
    ? undefined
    : new GatewayHub(new ConnectorRepository(database.db), app.log, options.gateway);
  const hub = options.hub ?? gateway ?? offlineConnectorHub;
  const users = new UserRepository(database.db);
  const systems = new SystemRegistry(database.db, config, hub, options.transport);
  await systems.bootstrap();

  const license = new LicenseService(database.db, config);
  const ctx: AppContext = {
    config,
    log: app.log,
    database,
    sessions: new SessionRepository(database.db, cipher, config.SESSION_IDLE_MINUTES * 60 * 1000),
    conversations: new ConversationRepository(database.db),
    users,
    audit: new AuditLog(database.db, app.log),
    systems,
    access: options.access ?? new LicensedAccessPolicy(users, license, config.ADMIN_USERS),
    license,
    hub,
    provider: options.provider ?? createProvider(config),
  };
  app.decorate("ctx", ctx);

  const maintenance = async () => {
    try {
      const sessions = await ctx.sessions.purgeExpired();
      const conversations = await ctx.conversations.purgeOlderThan(config.CONVERSATION_RETENTION_DAYS);
      const audit = await ctx.audit.purgeOlderThan(config.AUDIT_RETENTION_DAYS);
      if (sessions + conversations + audit > 0) app.log.info({ sessions, conversations, audit }, "limpeza periódica");
    } catch (err) {
      app.log.error({ err }, "falha na limpeza periódica");
    }
  };
  const timer = setInterval(maintenance, MAINTENANCE_INTERVAL_MS);
  timer.unref();
  app.addHook("onClose", async () => clearInterval(timer));

  app.register(fastifyCookie);
  await registerSecurity(app, ctx);
  registerObservability(app, ctx);

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof AppError) return reply.status(error.statusCode).send(error.toBody());
    if (error instanceof z.ZodError) {
      return reply
        .status(400)
        .send(new AppError(400, "INVALID_PARAMS", error.issues[0]?.message ?? "Requisição inválida").toBody());
    }
    const status = (error as { statusCode?: number }).statusCode;
    if (status && status >= 400 && status < 500) {
      return reply.status(status).send(new AppError(status, "INVALID_PARAMS", "Requisição inválida").toBody());
    }
    app.log.error(error);
    return reply.status(500).send(new AppError(500, "INTERNAL", "Erro interno").toBody());
  });

  healthRoutes(app, ctx);
  authRoutes(app, ctx);
  sapRoutes(app, ctx);
  chatRoutes(app, ctx);
  adminRoutes(app, ctx);
  if (gateway) connectorRoutes(app, ctx, gateway);

  const notFound = (url: string, method: string) =>
    new AppError(404, "ROUTE_NOT_FOUND", `Rota ${method} ${url} não existe`).toBody();
  if (config.WEB_DIST_DIR) {
    const root = resolve(config.WEB_DIST_DIR);
    if (!existsSync(resolve(root, "index.html"))) throw new Error(`WEB_DIST_DIR sem index.html: ${root}`);
    app.register(fastifyStatic, { root, wildcard: false });
    // SPA: qualquer rota fora de /api devolve o index.html.
    app.setNotFoundHandler((request, reply) => {
      if (request.url.startsWith("/api/")) return reply.status(404).send(notFound(request.url, request.method));
      return reply.sendFile("index.html");
    });
  } else {
    app.setNotFoundHandler((request, reply) => reply.status(404).send(notFound(request.url, request.method)));
  }

  return app;
}

declare module "fastify" {
  interface FastifyInstance {
    ctx: AppContext;
  }
}
