import type { MeResponse, SessionInfo, SystemsResponse } from "@raiox/contracts";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { type AppContext, authenticate, resolveTenant, SESSION_COOKIE } from "../context";
import { AppError } from "../errors";
import type { SapSystem } from "../repos/systems";

const LoginBody = z.object({
  user: z.string().trim().min(1).max(12),
  password: z.string().min(1).max(256),
  /** Sistema SAP (quando o cliente tem mais de um). Padrão: o sistema padrão. */
  system: z.string().max(40).optional(),
});

export function authRoutes(app: FastifyInstance, ctx: AppContext): void {
  const cookieOptions = {
    path: "/",
    httpOnly: true,
    sameSite: "strict" as const,
    secure: ctx.config.COOKIE_SECURE,
  };
  const info = async (
    tenantId: string,
    me: MeResponse,
    role: "user" | "admin",
    system: SapSystem,
  ): Promise<SessionInfo> => {
    const notice = await ctx.access.notice?.(tenantId, role);
    return { ...me, role, system: { id: system.id, name: system.name }, ...(notice ? { notice } : {}) };
  };

  /** Sistemas para a tela de login: só id e nome, nunca endereços. */
  app.get("/api/v1/auth/systems", async (request): Promise<SystemsResponse> => {
    const systems = await ctx.systems.list(resolveTenant(ctx.config, request));
    return { systems: systems.map((s) => ({ id: s.id, name: s.name, isDefault: s.isDefault })) };
  });

  app.post("/api/v1/auth/check", async (request) => {
    const body = LoginBody.parse(request.body);
    const system = await ctx.systems.resolve(resolveTenant(ctx.config, request), body.system);
    return ctx.systems.client(system).me({ user: body.user.toUpperCase(), password: body.password });
  });

  /** Login do navegador: o SAP valida a senha; a sessão vai para o banco e o navegador recebe um cookie httpOnly. */
  app.post("/api/v1/auth/login", async (request: FastifyRequest, reply: FastifyReply): Promise<SessionInfo> => {
    const body = LoginBody.parse(request.body);
    const tenantId = resolveTenant(ctx.config, request);
    const system = await ctx.systems.resolve(tenantId, body.system);
    const credentials = { user: body.user.toUpperCase(), password: body.password };
    const audit = {
      tenantId,
      sapUser: credentials.user,
      sapSystemId: system.id,
      ip: request.ip,
      requestId: request.id,
    };
    let me: MeResponse;
    let role: "user" | "admin";
    try {
      me = await ctx.systems.client(system).me(credentials);
      ({ role } = await ctx.access.admitLogin({ tenantId, sapUser: credentials.user, me }));
    } catch (err) {
      const code = err instanceof AppError ? err.code : "INTERNAL";
      await ctx.audit.record({ ...audit, action: "LOGIN_FAILED", outcome: code });
      throw err;
    }
    await ctx.sessions.delete(request.cookies[SESSION_COOKIE]);
    const id = await ctx.sessions.create({
      tenantId,
      sapSystemId: system.id,
      credentials,
      me,
      ip: request.ip,
      userAgent: request.headers["user-agent"],
    });
    await ctx.audit.record({ ...audit, action: "LOGIN", outcome: "ok" });
    reply.setCookie(SESSION_COOKIE, id, cookieOptions);
    return info(tenantId, me, role, system);
  });

  app.get("/api/v1/auth/session", async (request): Promise<SessionInfo> => {
    const session = await ctx.sessions.get(request.cookies[SESSION_COOKIE]);
    if (!session) throw new AppError(401, "UNAUTHENTICATED", "Sem sessão ativa");
    const auth = await authenticate(ctx, request);
    return info(auth.tenantId, session.me, auth.role, auth.system);
  });

  app.post("/api/v1/auth/logout", async (request, reply) => {
    const session = await ctx.sessions.get(request.cookies[SESSION_COOKIE]);
    if (session) {
      await ctx.audit.record({
        tenantId: session.tenantId,
        sapUser: session.sapUser,
        sapSystemId: session.sapSystemId,
        action: "LOGOUT",
        outcome: "ok",
        ip: request.ip,
        requestId: request.id,
      });
    }
    await ctx.sessions.delete(request.cookies[SESSION_COOKIE]);
    reply.clearCookie(SESSION_COOKIE, cookieOptions);
    return { ok: true };
  });
}
