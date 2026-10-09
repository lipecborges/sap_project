import formbody from "@fastify/formbody";
import {
  type ApiError,
  DIAGNOSTICS,
  type DiagnosticResult,
  type DiagnosticsResponse,
  type ErrorCode,
  findDiagnostic,
  type HealthResponse,
  type MeResponse,
  type SapRelease,
  validateParams,
} from "@raiox/contracts";
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import { type MockContext, systemInfo } from "./context";
import { mm02 } from "./fixtures/mm02";
import { pp01, pp03, pp04 } from "./fixtures/pp";
import { sd01 } from "./fixtures/sd01";
import { type MockUser, USERS } from "./users";

/** Caminho do serviço ICF do add-on ABAP. */
export const ICF_BASE_PATH = "/sap/bc/zrx/api/v1";
export const ADDON_VERSION = "0.1.0";

type Handler = (ctx: MockContext, params: Record<string, string>) => DiagnosticResult;

const HANDLERS: Record<string, Handler> = {
  "SD-01": sd01,
  "MM-02": mm02,
  "PP-01": pp01,
  "PP-03": pp03,
  "PP-04": pp04,
};

/** Parâmetros técnicos do ICF que não são parâmetros de diagnóstico. */
const ICF_PARAMS = new Set(["sap-client", "sap-language"]);

export interface MockServerOptions {
  release?: SapRelease;
  /** Fixa o "hoje" dos cenários (útil em testes). */
  today?: Date;
  logger?: boolean;
}

declare module "fastify" {
  interface FastifyRequest {
    sapUser?: { name: string } & MockUser;
  }
}

function sendError(
  reply: FastifyReply,
  status: number,
  code: ErrorCode,
  message: string,
  params?: Record<string, string>,
) {
  const body: ApiError = { error: { code, message, ...(params ? { params } : {}) } };
  return reply.status(status).send(body);
}

function authenticate(request: FastifyRequest): ({ name: string } & MockUser) | undefined {
  const header = request.headers.authorization;
  if (!header?.startsWith("Basic ")) return undefined;
  const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
  const sep = decoded.indexOf(":");
  if (sep < 0) return undefined;
  const name = decoded.slice(0, sep).toUpperCase();
  const user = USERS[name];
  return user && user.password === decoded.slice(sep + 1) ? { name, ...user } : undefined;
}

function flatParams(...sources: unknown[]): Record<string, string> {
  const params: Record<string, string> = {};
  for (const source of sources) {
    if (!source || typeof source !== "object") continue;
    for (const [key, value] of Object.entries(source)) {
      if (ICF_PARAMS.has(key) || value === undefined || value === null) continue;
      params[key] = String(Array.isArray(value) ? value[0] : value);
    }
  }
  return params;
}

export function buildServer(options: MockServerOptions = {}): FastifyInstance {
  const app = Fastify({ logger: options.logger ?? false });
  app.register(formbody);
  const context = (): MockContext => ({ release: options.release ?? "ECC", today: options.today ?? new Date() });

  app.addHook("onRequest", async (request, reply) => {
    if (!request.url.startsWith(ICF_BASE_PATH)) return;
    const user = authenticate(request);
    if (!user) {
      reply.header("WWW-Authenticate", 'Basic realm="SAP NetWeaver Application Server [MCK]"');
      return sendError(reply, 401, "UNAUTHENTICATED", "Usuário ou senha SAP inválidos");
    }
    request.sapUser = user;
  });

  app.get(`${ICF_BASE_PATH}/health`, async (): Promise<HealthResponse> => {
    const ctx = context();
    return {
      addonVersion: ADDON_VERSION,
      apiVersion: "v1",
      system: systemInfo(ctx.release),
      diagnostics: DIAGNOSTICS.map((d) => d.id),
    };
  });

  app.get(`${ICF_BASE_PATH}/me`, async (request): Promise<MeResponse> => {
    const user = request.sapUser!;
    return { user: user.name, language: user.language, diagnostics: user.diagnostics };
  });

  app.get(
    `${ICF_BASE_PATH}/diagnostics`,
    async (): Promise<DiagnosticsResponse> => ({ diagnostics: [...DIAGNOSTICS] }),
  );

  app.post<{ Params: { id: string } }>(`${ICF_BASE_PATH}/diagnostics/:id`, async (request, reply) => {
    const { id } = request.params;
    const meta = findDiagnostic(id);
    const handler = HANDLERS[id];
    if (!meta || !handler) return sendError(reply, 404, "UNKNOWN_DIAGNOSTIC", `Diagnóstico ${id} não existe`);
    if (!request.sapUser!.diagnostics.includes(id)) {
      return sendError(reply, 403, "NOT_AUTHORIZED", `Sem autorização para o diagnóstico ${id} (objeto ZRX_DIAG)`);
    }
    const params = flatParams(request.query, request.body);
    const errors = validateParams(meta, params);
    if (Object.keys(errors).length > 0) return sendError(reply, 400, "INVALID_PARAMS", "Parâmetros inválidos", errors);
    return handler(context(), params);
  });

  app.setNotFoundHandler((request, reply) =>
    sendError(reply, 404, "ROUTE_NOT_FOUND", `Rota ${request.method} ${request.url} não existe`),
  );

  return app;
}
