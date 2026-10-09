import type { DiagnosticResult } from "@raiox/contracts";
import type { FastifyRequest } from "fastify";
import type { AppContext, Auth } from "./context";
import { AppError } from "./errors";

/** Executa um diagnóstico no SAP e registra na auditoria (sucesso ou erro). */
export async function runDiagnostic(
  ctx: AppContext,
  auth: Auth,
  request: FastifyRequest,
  diagnosticId: string,
  params: Record<string, string>,
  via: "direct" | "chat" | "overview" = "direct",
): Promise<DiagnosticResult> {
  const started = performance.now();
  const base = {
    tenantId: auth.tenantId,
    action: "DIAGNOSTIC_RUN",
    sapUser: auth.sapUser,
    sapSystemId: auth.system.id,
    target: diagnosticId,
    ip: request.ip,
    requestId: request.id,
  };
  try {
    const result = await auth.sap.run(auth.credentials, diagnosticId, params);
    await ctx.audit.record({
      ...base,
      details: { params, via, status: result.status, findings: result.findings.map((f) => f.code) },
      outcome: "ok",
      httpStatus: 200,
      durationMs: Math.round(performance.now() - started),
    });
    return result;
  } catch (err) {
    await ctx.audit.record({
      ...base,
      details: { params, via },
      outcome: err instanceof AppError ? err.code : "INTERNAL",
      httpStatus: err instanceof AppError ? err.statusCode : 500,
      durationMs: Math.round(performance.now() - started),
    });
    throw err;
  }
}
