import type { DiagnosticResult, ObjectRef, SapRelease, SystemInfo } from "@raiox/contracts";

export interface MockContext {
  release: SapRelease;
  /** "Hoje" do simulador: as datas dos cenários são relativas a ele. */
  today: Date;
}

export function systemInfo(release: SapRelease): SystemInfo {
  return {
    sid: "MCK",
    client: "100",
    release,
    basisRelease: release === "ECC" ? "700" : "758",
  };
}

/** Data relativa a "hoje", no formato AAAA-MM-DD (UTC). */
export function day(ctx: MockContext, offsetDays: number): string {
  const d = new Date(Date.UTC(ctx.today.getUTCFullYear(), ctx.today.getUTCMonth(), ctx.today.getUTCDate()));
  d.setUTCDate(d.getUTCDate() + offsetDays);
  return d.toISOString().slice(0, 10);
}

export function emptyResult(
  ctx: MockContext,
  diagnosticId: string,
  object: ObjectRef,
  status: DiagnosticResult["status"] = "OK",
): DiagnosticResult {
  return {
    diagnosticId,
    version: "1.0",
    object,
    system: systemInfo(ctx.release),
    status,
    findings: [],
    related: [],
    facts: [],
    tables: [],
    executedAt: new Date().toISOString(),
    durationMs: 42,
  };
}

/** PROBLEM_FOUND quando há achado BLOCKING ou WARNING; senão mantém o status atual. */
export function settleStatus(result: DiagnosticResult): DiagnosticResult {
  if (result.status !== "OK") return result;
  const problem = result.findings.some((f) => f.severity === "BLOCKING" || f.severity === "WARNING");
  return problem ? { ...result, status: "PROBLEM_FOUND" } : result;
}

export function formatQty(value: number, unit: string): string {
  return `${value.toLocaleString("pt-BR")} ${unit}`;
}
