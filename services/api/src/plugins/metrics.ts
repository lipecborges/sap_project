import { createHash, timingSafeEqual } from "node:crypto";
import { findDiagnostic } from "@raiox/contracts";
import type { FastifyInstance } from "fastify";
import { collectDefaultMetrics, Histogram, Registry } from "prom-client";
import type { AppContext } from "../context";
import { AppError } from "../errors";

/** Métricas de uma instância da API (registro próprio: vários apps no mesmo processo, como nos testes). */
export class Metrics {
  readonly registry = new Registry();
  private readonly httpDuration = new Histogram({
    name: "http_request_duration_seconds",
    help: "Duração das requisições HTTP",
    labelNames: ["method", "route", "status_code"],
    buckets: [0.005, 0.025, 0.1, 0.5, 1, 2.5, 5, 10, 30],
    registers: [this.registry],
  });
  private readonly diagnosticDuration = new Histogram({
    name: "raiox_diagnostic_duration_seconds",
    help: "Duração dos diagnósticos executados no SAP",
    labelNames: ["diagnostic", "outcome"],
    buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60],
    registers: [this.registry],
  });

  constructor() {
    collectDefaultMetrics({ register: this.registry });
  }

  observeHttp(method: string, route: string, status: number, seconds: number): void {
    this.httpDuration.observe({ method, route, status_code: String(status) }, seconds);
  }

  /** `outcome`: "ok" ou o código do erro. Ids fora do catálogo viram "unknown" (evita cardinalidade ilimitada). */
  observeDiagnostic(diagnosticId: string, outcome: string, seconds: number): void {
    const diagnostic = findDiagnostic(diagnosticId) ? diagnosticId : "unknown";
    this.diagnosticDuration.observe({ diagnostic, outcome }, seconds);
  }
}

const digest = (value: string) => createHash("sha256").update(value).digest();

/** Registra a coleta de métricas HTTP e o GET /metrics (Prometheus), protegido por METRICS_TOKEN. */
export function registerObservability(app: FastifyInstance, ctx: AppContext): void {
  const metrics = new Metrics();
  ctx.metrics = metrics;
  const token = ctx.config.METRICS_TOKEN;

  app.addHook("onResponse", async (request, reply) => {
    // Rotas inexistentes viram "unmatched": o caminho bruto geraria cardinalidade ilimitada.
    const route = request.routeOptions.url ?? "unmatched";
    metrics.observeHttp(request.method, route, reply.statusCode, reply.elapsedTime / 1000);
  });

  app.get("/metrics", { config: { rateLimit: false } }, async (request, reply) => {
    // Desligado sem token: responde como se a rota não existisse (também quando a web está embutida).
    if (!token) throw new AppError(404, "ROUTE_NOT_FOUND", `Rota ${request.method} ${request.url} não existe`);
    const header = request.headers.authorization ?? "";
    const given = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!timingSafeEqual(digest(given), digest(token))) {
      reply.header("www-authenticate", "Bearer");
      throw new AppError(401, "UNAUTHENTICATED", "Token de métricas inválido");
    }
    return reply.header("content-type", metrics.registry.contentType).send(await metrics.registry.metrics());
  });
}
