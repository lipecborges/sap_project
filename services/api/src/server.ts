import { existsSync } from "node:fs";
import { resolve } from "node:path";
import fastifyStatic from "@fastify/static";
import { findDiagnostic, validateParams } from "@raiox/contracts";
import Fastify, { type FastifyInstance, type FastifyRequest } from "fastify";
import { z } from "zod";
import type { Config } from "./config";
import { AppError } from "./errors";
import { SapClient } from "./sap/client";
import { createTransport, type SapCredentials, type SapTransport } from "./sap/transport";

export const API_VERSION = "0.1.0";

const LoginBody = z.object({ user: z.string().trim().min(1), password: z.string().min(1) });
const RunBody = z.object({ params: z.record(z.string(), z.string()).default({}) });

/**
 * Fase 0: as credenciais SAP chegam em cada chamada (Authorization: Basic) e são
 * repassadas ao SAP, sem ser armazenadas. Na Fase 2 isso vira sessão com token.
 */
function credentialsFrom(request: FastifyRequest): SapCredentials {
  const header = request.headers.authorization;
  if (header?.startsWith("Basic ")) {
    const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
    const sep = decoded.indexOf(":");
    if (sep > 0) return { user: decoded.slice(0, sep), password: decoded.slice(sep + 1) };
  }
  throw new AppError(401, "UNAUTHENTICATED", "Informe usuário e senha SAP");
}

export function buildApi(config: Config, transport: SapTransport = createTransport(config)): FastifyInstance {
  const app = Fastify({ logger: config.LOG_LEVEL === "silent" ? false : { level: config.LOG_LEVEL } });
  const sap = new SapClient(transport);

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

  app.get("/api/health", async () => ({
    status: "ok",
    version: API_VERSION,
    deploymentMode: config.DEPLOYMENT_MODE,
    sapTransport: transport.kind,
  }));

  app.post("/api/v1/auth/check", async (request) => {
    const body = LoginBody.parse(request.body);
    return sap.me({ user: body.user, password: body.password });
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
