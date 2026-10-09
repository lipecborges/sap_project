import fastifyWebsocket from "@fastify/websocket";
import {
  type AdminConnector,
  AdminConnectorCreate,
  type AdminConnectorCreated,
  type AdminConnectorList,
} from "@raiox/contracts";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { type AppContext, requireAdmin } from "../context";
import { AppError } from "../errors";
import type { GatewayHub } from "./hub";
import { CONNECTOR_WS_PATH } from "./protocol";
import type { ConnectorRow } from "./repository";

function toDto(row: ConnectorRow, hub: GatewayHub): AdminConnector {
  return {
    id: row.id,
    name: row.name,
    online: !row.revokedAt && hub.isOnline(row.id),
    version: row.version,
    createdAt: row.createdAt.toISOString(),
    lastSeenAt: row.lastSeenAt?.toISOString() ?? null,
    revoked: row.revokedAt !== null,
  };
}

function bearerToken(request: FastifyRequest): string {
  const header = request.headers.authorization;
  return header?.startsWith("Bearer ") ? header.slice(7).trim() : "";
}

/** WebSocket dos conectores e a administração deles (D35). */
export function connectorRoutes(app: FastifyInstance, ctx: AppContext, hub: GatewayHub): void {
  const authenticated = new WeakMap<FastifyRequest, ConnectorRow>();

  app.addHook("onClose", async () => hub.closeAll());
  app.register(fastifyWebsocket, { options: { maxPayload: hub.maxFrameBytes } });
  app.register(async (scope) => {
    scope.get(
      CONNECTOR_WS_PATH,
      {
        websocket: true,
        // Antes do upgrade: token inválido ou revogado vira 401 HTTP comum.
        preValidation: async (request) => {
          const connector = await hub.repository.verify(bearerToken(request));
          if (!connector) throw new AppError(401, "UNAUTHENTICATED", "Token do conector inválido ou revogado");
          authenticated.set(request, connector);
        },
      },
      (socket, request) => {
        const connector = authenticated.get(request);
        if (!connector) return socket.close(1008, "não autenticado");
        hub.accept(connector, socket);
      },
    );
  });

  app.get("/api/v1/admin/connectors", async (request): Promise<AdminConnectorList> => {
    const auth = await requireAdmin(ctx, request);
    const rows = await hub.repository.list(auth.tenantId);
    return { connectors: rows.map((row) => toDto(row, hub)) };
  });

  app.post("/api/v1/admin/connectors", async (request, reply): Promise<AdminConnectorCreated> => {
    const auth = await requireAdmin(ctx, request);
    const { name } = AdminConnectorCreate.parse(request.body ?? {});
    const { connector, token } = await hub.repository.create(auth.tenantId, name);
    await ctx.audit.record({
      tenantId: auth.tenantId,
      action: "ADMIN_CONNECTOR_CREATE",
      outcome: "ok",
      sapUser: auth.sapUser,
      target: connector.id,
      details: { name },
      ip: request.ip,
      requestId: request.id,
    });
    reply.status(201);
    return { connector: toDto(connector, hub), token };
  });

  app.delete<{ Params: { id: string } }>("/api/v1/admin/connectors/:id", async (request, reply) => {
    const auth = await requireAdmin(ctx, request);
    const row = await hub.repository.revoke(auth.tenantId, request.params.id);
    if (!row) throw new AppError(404, "ROUTE_NOT_FOUND", `Conector ${request.params.id} não existe`);
    hub.disconnect(row.id);
    await ctx.audit.record({
      tenantId: auth.tenantId,
      action: "ADMIN_CONNECTOR_REVOKE",
      outcome: "ok",
      sapUser: auth.sapUser,
      target: row.id,
      details: { name: row.name },
      ip: request.ip,
      requestId: request.id,
    });
    return reply.status(204).send();
  });
}
