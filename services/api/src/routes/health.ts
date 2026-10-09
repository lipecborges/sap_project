import type { AppInfo } from "@raiox/contracts";
import type { FastifyInstance } from "fastify";
import type { AppContext } from "../context";
import { API_VERSION } from "../version";

export function healthRoutes(app: FastifyInstance, ctx: AppContext): void {
  /** Vivo (liveness): o processo responde. Não toca no banco nem no SAP. */
  app.get(
    "/api/health",
    async (): Promise<AppInfo> => ({
      status: "ok",
      version: API_VERSION,
      deploymentMode: ctx.config.DEPLOYMENT_MODE,
      sapTransport: ctx.config.SAP_TRANSPORT,
      ai: { provider: ctx.provider.name, ...(ctx.provider.model ? { model: ctx.provider.model } : {}) },
    }),
  );

  /** Pronto (readiness): banco acessível. O balanceador só manda tráfego quando responde 200. */
  app.get("/api/ready", async (_request, reply) => {
    try {
      await ctx.database.ping();
      return { status: "ready", database: ctx.database.kind };
    } catch (err) {
      ctx.log.error({ err }, "banco indisponível");
      return reply.status(503).send({ status: "unavailable", database: ctx.database.kind });
    }
  });
}
