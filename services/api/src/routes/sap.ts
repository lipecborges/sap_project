import { findDiagnostic, type OverviewResponse, type OverviewSection, validateParams } from "@raiox/contracts";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { type AppContext, authenticate } from "../context";
import { AppError } from "../errors";
import { runDiagnostic } from "../run";

const RunBody = z.object({ params: z.record(z.string(), z.string().max(200)).default({}) });

export function sapRoutes(app: FastifyInstance, ctx: AppContext): void {
  app.get("/api/v1/sap/health", async (request) => {
    const auth = await authenticate(ctx, request);
    return auth.sap.health(auth.credentials);
  });

  app.get("/api/v1/diagnostics", async (request) => {
    const auth = await authenticate(ctx, request);
    return auth.sap.diagnostics(auth.credentials);
  });

  app.post<{ Params: { id: string } }>("/api/v1/diagnostics/:id", async (request) => {
    const auth = await authenticate(ctx, request);
    const { params } = RunBody.parse(request.body ?? {});
    // Validação antecipada com o catálogo local; o add-on valida de novo (fonte da verdade).
    const meta = findDiagnostic(request.params.id);
    if (meta) {
      const errors = validateParams(meta, params);
      if (Object.keys(errors).length > 0) throw new AppError(400, "INVALID_PARAMS", "Parâmetros inválidos", errors);
    }
    return runDiagnostic(ctx, auth, request, request.params.id, params);
  });

  /** Painel inicial: produção, vendas e compras em paralelo; cada parte pode falhar sozinha. */
  app.get<{ Querystring: { plant?: string } }>("/api/v1/overview", async (request): Promise<OverviewResponse> => {
    const auth = await authenticate(ctx, request);
    const plant = request.query.plant?.trim().slice(0, 4) || ctx.config.DEFAULT_PLANT;
    const section = async (id: string, params: Record<string, string>): Promise<OverviewSection> => {
      try {
        return { result: await runDiagnostic(ctx, auth, request, id, params, "overview") };
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
}
