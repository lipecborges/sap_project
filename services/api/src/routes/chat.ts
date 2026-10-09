import { ChatRequest, type ConversationDetail, type ConversationList } from "@raiox/contracts";
import type { FastifyInstance } from "fastify";
import { runChat } from "../ai/agent";
import { type AppContext, authenticate } from "../context";
import { AppError } from "../errors";
import { runDiagnostic } from "../run";

export function chatRoutes(app: FastifyInstance, ctx: AppContext): void {
  /** Assistente: resposta em Server-Sent Events (texto em streaming + consultas ao SAP). */
  app.post("/api/v1/chat", async (request, reply) => {
    const auth = await authenticate(ctx, request);
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
    const started = performance.now();
    const owner = { tenantId: auth.tenantId, sapUser: auth.sapUser };
    let outcome = "ok";
    let turn: { conversationId: string; toolCalls: number } | undefined;
    try {
      turn = await runChat(
        {
          sap: auth.sap,
          credentials: auth.credentials,
          owner,
          provider: ctx.provider,
          conversations: ctx.conversations,
          run: (id, params) => runDiagnostic(ctx, auth, request, id, params, "chat"),
        },
        body,
        emit,
        abort.signal,
      );
    } catch (err) {
      const error = err instanceof AppError ? err : new AppError(500, "INTERNAL", "Erro interno");
      if (!(err instanceof AppError)) ctx.log.error(err);
      outcome = abort.signal.aborted ? "ABORTED" : error.code;
      emit({ type: "error", code: error.code, message: error.message });
    } finally {
      reply.raw.end();
      await ctx.audit.record({
        tenantId: auth.tenantId,
        sapUser: auth.sapUser,
        sapSystemId: auth.system.id,
        action: "CHAT_TURN",
        target: turn?.conversationId ?? body.conversationId,
        details: { provider: ctx.provider.name, toolCalls: turn?.toolCalls ?? 0 },
        outcome,
        durationMs: Math.round(performance.now() - started),
        ip: request.ip,
        requestId: request.id,
      });
    }
  });

  app.get("/api/v1/conversations", async (request): Promise<ConversationList> => {
    const auth = await authenticate(ctx, request);
    return { conversations: await ctx.conversations.list({ tenantId: auth.tenantId, sapUser: auth.sapUser }) };
  });

  app.get<{ Params: { id: string } }>("/api/v1/conversations/:id", async (request): Promise<ConversationDetail> => {
    const auth = await authenticate(ctx, request);
    const detail = await ctx.conversations.turns({ tenantId: auth.tenantId, sapUser: auth.sapUser }, request.params.id);
    if (!detail) throw new AppError(404, "ROUTE_NOT_FOUND", "Conversa não encontrada");
    return detail;
  });

  app.delete<{ Params: { id: string } }>("/api/v1/conversations/:id", async (request) => {
    const auth = await authenticate(ctx, request);
    const removed = await ctx.conversations.delete(
      { tenantId: auth.tenantId, sapUser: auth.sapUser },
      request.params.id,
    );
    if (!removed) throw new AppError(404, "ROUTE_NOT_FOUND", "Conversa não encontrada");
    return { ok: true };
  });
}
