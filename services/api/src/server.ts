import { existsSync } from "node:fs";
import { resolve } from "node:path";
import fastifyCookie from "@fastify/cookie";
import fastifyStatic from "@fastify/static";
import {
  type AppInfo,
  ChatRequest,
  findDiagnostic,
  type OverviewResponse,
  type OverviewSection,
  validateParams,
} from "@raiox/contracts";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { z } from "zod";
import { runChat } from "./ai/agent";
import { AnthropicProvider } from "./ai/anthropic-provider";
import { DemoProvider } from "./ai/demo-provider";
import type { LlmProvider } from "./ai/provider";
import { ConversationStore } from "./ai/store";
import type { Config } from "./config";
import { AppError } from "./errors";
import { SapClient } from "./sap/client";
import { createTransport, type SapCredentials, type SapTransport } from "./sap/transport";
import { SessionStore } from "./sessions";

export const API_VERSION = "0.1.0";

const LoginBody = z.object({ user: z.string().trim().min(1), password: z.string().min(1) });
const RunBody = z.object({ params: z.record(z.string(), z.string()).default({}) });

export const SESSION_COOKIE = "raiox_session";

/** Credencial Basic (integrações e testes); o navegador usa o cookie de sessão. */
function basicCredentials(request: FastifyRequest): SapCredentials | undefined {
  const header = request.headers.authorization;
  if (header?.startsWith("Basic ")) {
    const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
    const sep = decoded.indexOf(":");
    if (sep > 0) return { user: decoded.slice(0, sep), password: decoded.slice(sep + 1) };
  }
  return undefined;
}

export function createProvider(config: Config): LlmProvider {
  if (config.AI_PROVIDER === "anthropic") {
    return new AnthropicProvider({ model: config.AI_MODEL, effort: config.AI_EFFORT, fallbacks: config.AI_FALLBACKS });
  }
  return new DemoProvider();
}

export interface ApiOptions {
  transport?: SapTransport;
  provider?: LlmProvider;
}

export function buildApi(config: Config, options: ApiOptions = {}): FastifyInstance {
  const app = Fastify({ logger: config.LOG_LEVEL === "silent" ? false : { level: config.LOG_LEVEL } });
  const transport = options.transport ?? createTransport(config);
  const sap = new SapClient(transport);
  const provider = options.provider ?? createProvider(config);
  const store = new ConversationStore();
  const sessions = new SessionStore(config.SESSION_IDLE_MINUTES * 60 * 1000);
  app.register(fastifyCookie);

  const credentialsFrom = (request: FastifyRequest): SapCredentials => {
    const session = sessions.get(request.cookies[SESSION_COOKIE]);
    if (session) return session.credentials;
    const basic = basicCredentials(request);
    if (basic) return basic;
    throw new AppError(401, "UNAUTHENTICATED", "Sessão expirada. Entre novamente.");
  };
  const cookieOptions = {
    path: "/",
    httpOnly: true,
    sameSite: "strict" as const,
    secure: config.COOKIE_SECURE,
  };

  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof AppError) return reply.status(error.statusCode).send(error.toBody());
    if (error instanceof z.ZodError) {
      return reply
        .status(400)
        .send(new AppError(400, "INVALID_PARAMS", error.issues[0]?.message ?? "Requisição inválida").toBody());
    }
    app.log.error(error);
    return reply.status(500).send(new AppError(500, "INTERNAL", "Erro interno").toBody());
  });

  app.get(
    "/api/health",
    async (): Promise<AppInfo> => ({
      status: "ok",
      version: API_VERSION,
      deploymentMode: config.DEPLOYMENT_MODE,
      sapTransport: transport.kind,
      ai: { provider: provider.name, ...(provider.model ? { model: provider.model } : {}) },
    }),
  );

  app.post("/api/v1/auth/check", async (request) => {
    const body = LoginBody.parse(request.body);
    return sap.me({ user: body.user, password: body.password });
  });

  /** Login do navegador: o SAP valida; a API guarda a credencial em memória e devolve um cookie httpOnly. */
  app.post("/api/v1/auth/login", async (request, reply) => {
    const body = LoginBody.parse(request.body);
    const credentials = { user: body.user.toUpperCase(), password: body.password };
    const me = await sap.me(credentials);
    sessions.delete(request.cookies[SESSION_COOKIE]);
    reply.setCookie(SESSION_COOKIE, sessions.create(credentials, me), cookieOptions);
    return me;
  });

  app.get("/api/v1/auth/session", async (request) => {
    const session = sessions.get(request.cookies[SESSION_COOKIE]);
    if (!session) throw new AppError(401, "UNAUTHENTICATED", "Sem sessão ativa");
    return session.me;
  });

  app.post("/api/v1/auth/logout", async (request, reply) => {
    sessions.delete(request.cookies[SESSION_COOKIE]);
    reply.clearCookie(SESSION_COOKIE, cookieOptions);
    return { ok: true };
  });

  app.get("/api/v1/sap/health", async (request) => sap.health(credentialsFrom(request)));

  app.get("/api/v1/diagnostics", async (request) => sap.diagnostics(credentialsFrom(request)));

  app.post<{ Params: { id: string } }>("/api/v1/diagnostics/:id", async (request) => {
    const credentials = credentialsFrom(request);
    const { params } = RunBody.parse(request.body ?? {});
    // Validação antecipada com o catálogo local; o add-on valida de novo (fonte da verdade).
    const meta = findDiagnostic(request.params.id);
    if (meta) {
      const errors = validateParams(meta, params);
      if (Object.keys(errors).length > 0) throw new AppError(400, "INVALID_PARAMS", "Parâmetros inválidos", errors);
    }
    return sap.run(credentials, request.params.id, params);
  });

  /** Painel inicial: produção, vendas e compras em paralelo; cada parte pode falhar sozinha. */
  app.get<{ Querystring: { plant?: string } }>("/api/v1/overview", async (request): Promise<OverviewResponse> => {
    const credentials = credentialsFrom(request);
    const plant = request.query.plant?.trim() || config.DEFAULT_PLANT;
    const section = async (id: string, params: Record<string, string>): Promise<OverviewSection> => {
      try {
        return { result: await sap.run(credentials, id, params) };
      } catch (err) {
        if (err instanceof AppError) {
          if (err.code === "UNAUTHENTICATED" || err.code === "SAP_UNAVAILABLE") throw err;
          return { error: { code: err.code, message: err.message } };
        }
        throw err;
      }
    };
    const [production, sales, purchasing] = await Promise.all([
      section("PP-04", { plant }),
      section("SD-10", {}),
      section("MM-10", {}),
    ]);
    return { plant, production, sales, purchasing };
  });

  /** Assistente: resposta em Server-Sent Events (texto em streaming + consultas ao SAP). */
  app.post("/api/v1/chat", async (request, reply) => {
    const credentials = credentialsFrom(request);
    const body = ChatRequest.parse(request.body);
    const abort = new AbortController();
    // "close" da resposta antes do fim = o cliente desconectou (parar). O "close" da requisição
    // dispara assim que o corpo é lido, então não serve para isso.
    reply.raw.on("close", () => {
      if (!reply.raw.writableEnded) abort.abort();
    });

    reply.hijack();
    reply.raw.writeHead(200, {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-store",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    });
    const emit = (event: unknown) => {
      if (!reply.raw.writableEnded) reply.raw.write(`data: ${JSON.stringify(event)}\n\n`);
    };
    try {
      await runChat({ sap, provider, store }, credentials, body, emit, abort.signal);
    } catch (err) {
      const error = err instanceof AppError ? err : new AppError(500, "INTERNAL", "Erro interno");
      if (!(err instanceof AppError)) app.log.error(err);
      emit({ type: "error", code: error.code, message: error.message });
    } finally {
      reply.raw.end();
    }
  });

  if (config.WEB_DIST_DIR) {
    const root = resolve(config.WEB_DIST_DIR);
    if (!existsSync(resolve(root, "index.html"))) throw new Error(`WEB_DIST_DIR sem index.html: ${root}`);
    app.register(fastifyStatic, { root, wildcard: false });
    // SPA: qualquer rota fora de /api devolve o index.html.
    app.setNotFoundHandler((request, reply) => {
      if (request.url.startsWith("/api/")) {
        return reply
          .status(404)
          .send(new AppError(404, "ROUTE_NOT_FOUND", `Rota ${request.method} ${request.url} não existe`).toBody());
      }
      return reply.sendFile("index.html");
    });
  } else {
    app.setNotFoundHandler((request, reply) =>
      reply
        .status(404)
        .send(new AppError(404, "ROUTE_NOT_FOUND", `Rota ${request.method} ${request.url} não existe`).toBody()),
    );
  }

  return app;
}
