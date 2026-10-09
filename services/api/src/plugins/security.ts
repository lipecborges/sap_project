import { randomUUID } from "node:crypto";
import fastifyHelmet from "@fastify/helmet";
import fastifyRateLimit from "@fastify/rate-limit";
import type { FastifyInstance, FastifyRequest, FastifyServerOptions } from "fastify";
import type { Config } from "../config";
import type { AppContext } from "../context";
import { AppError } from "../errors";

/** Cabeçalho do identificador da requisição (aceito do proxy e devolvido ao cliente). */
export const REQUEST_ID_HEADER = "x-request-id";

/** Aceita só ids curtos e inofensivos vindos de fora (evita injeção de linhas no log). */
const SAFE_REQUEST_ID = /^[A-Za-z0-9._:-]{1,128}$/;

/** Campos que nunca podem aparecer nos logs. */
const REDACTED_PATHS = [
  "req.headers.authorization",
  "req.headers.cookie",
  'res.headers["set-cookie"]',
  "password",
  "*.password",
  "*.*.password",
];

/** Opções do Fastify de segurança e observabilidade: logger (JSON, com redação), id da requisição e proxy. */
export function serverOptions(config: Config): FastifyServerOptions {
  return {
    // pino escreve JSON (uma linha por evento), formato esperado por coletores de log.
    logger:
      config.LOG_LEVEL === "silent"
        ? false
        : { level: config.LOG_LEVEL, redact: { paths: REDACTED_PATHS, censor: "[REDACTED]" } },
    // Atrás de proxy reverso (nginx, balanceador): IP real do cliente nos logs, no rate limit e na auditoria.
    trustProxy: config.TRUST_PROXY,
    requestIdHeader: false,
    genReqId: (request) => {
      const incoming = request.headers[REQUEST_ID_HEADER];
      return typeof incoming === "string" && SAFE_REQUEST_ID.test(incoming) ? incoming : randomUUID();
    },
    bodyLimit: 256 * 1024,
  };
}

/** Rotas de autenticação que recebem o limite estrito (chave: IP + usuário). */
const LOGIN_ROUTES = new Set(["/api/v1/auth/login", "/api/v1/auth/check"]);

function loginKey(request: FastifyRequest): string {
  const body = request.body as { user?: unknown } | null | undefined;
  const user = typeof body?.user === "string" ? body.user.trim().toUpperCase().slice(0, 40) : "";
  return `${request.ip}|${user}`;
}

/**
 * Cabeçalhos de segurança (helmet), limites de requisições e id da requisição na resposta.
 *
 * O limite usa a memória do processo: vale por réplica. No Cloud com várias réplicas, troque por um
 * armazenamento compartilhado (opção `redis` do @fastify/rate-limit) para o limite ser global.
 */
export async function registerSecurity(app: FastifyInstance, ctx: AppContext): Promise<void> {
  const { config } = ctx;

  await app.register(fastifyHelmet, {
    contentSecurityPolicy: {
      useDefaults: false,
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        // 'unsafe-inline' só em estilos: a interface usa atributos style (larguras de barras, gráficos).
        styleSrc: ["'self'", "'unsafe-inline'"],
        // Fontes embutidas no build da web (@fontsource); nenhuma origem externa.
        fontSrc: ["'self'", "data:"],
        imgSrc: ["'self'", "data:"],
        connectSrc: ["'self'"],
        objectSrc: ["'none'"],
        baseUri: ["'self'"],
        formAction: ["'self'"],
        frameAncestors: ["'none'"],
      },
    },
    // O self-hosted pode rodar em HTTP puro: HSTS só com HTTPS configurado (COOKIE_SECURE=true).
    strictTransportSecurity: config.COOKIE_SECURE ? { maxAge: 15_552_000, includeSubDomains: true } : false,
    crossOriginEmbedderPolicy: false,
  });

  // Registrado antes do rate-limit: dá o limite estrito às rotas de login sem mexer nos arquivos de rotas.
  app.addHook("onRoute", (route) => {
    const urls = Array.isArray(route.url) ? route.url : [route.url];
    if (route.method === "POST" && urls.some((u) => LOGIN_ROUTES.has(u))) {
      route.config = {
        ...route.config,
        rateLimit: {
          max: config.RATE_LIMIT_LOGIN_MAX,
          timeWindow: config.RATE_LIMIT_LOGIN_WINDOW_SECONDS * 1000,
          // O corpo (usuário) só existe depois do parse.
          hook: "preHandler",
          keyGenerator: loginKey,
        },
      };
    }
  });

  // await: o rate-limit só enxerga as rotas definidas depois que o plugin termina de carregar.
  await app.register(fastifyRateLimit, {
    global: true,
    max: config.RATE_LIMIT_MAX,
    timeWindow: config.RATE_LIMIT_WINDOW_SECONDS * 1000,
    errorResponseBuilder: (_request, context) =>
      new AppError(429, "RATE_LIMITED", `Muitas requisições. Tente novamente em ${context.after}.`),
  });

  app.addHook("onSend", async (request, reply) => {
    reply.header(REQUEST_ID_HEADER, request.id);
  });
}
