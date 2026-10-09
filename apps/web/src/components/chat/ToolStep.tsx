import { findDiagnostic } from "@raiox/contracts";
import { Link } from "@tanstack/react-router";
import { AlertCircle, ArrowUpRight, Check, ChevronDown, Loader2 } from "lucide-react";
import { useState } from "react";
import type { ToolCall } from "../../lib/chat";
import { cn } from "../../lib/utils";
import { FindingList } from "../domain/findings";
import { MODULE_META, OBJECT_LABEL, objectRoute } from "../domain/objects";
import { ResultTableView } from "../domain/result-table";
import { ResultStatusBadge } from "../domain/status";

function describeParams(params: Record<string, string>): string {
  return Object.values(params).filter(Boolean).join(" · ");
}

/** Uma consulta ao SAP feita pelo assistente, com o resultado expansível. */
export function ToolStep({ call }: { call: ToolCall }) {
  const [open, setOpen] = useState(false);
  const meta = findDiagnostic(call.diagnosticId);
  const module = MODULE_META[meta?.module ?? "GE"]!;
  const result = call.result;
  const route = result && meta?.kind === "OBJECT" ? objectRoute(result.object.kind, result.object.id) : undefined;
  const listRoute = { "PP-04": "/producao", "SD-10": "/vendas", "MM-10": "/compras" }[call.diagnosticId];

  return (
    <div className="overflow-hidden rounded-lg border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900">
      <button
        type="button"
        onClick={() => result && setOpen((o) => !o)}
        className={cn(
          "flex w-full items-center gap-3 px-3 py-2 text-left text-sm",
          result && "hover:bg-zinc-50 dark:hover:bg-zinc-800/50",
        )}
      >
        <span className={cn("flex size-7 shrink-0 items-center justify-center rounded-md", module.color)}>
          <module.icon className="size-3.5" />
        </span>
        <span className="min-w-0 flex-1">
          <span className="block truncate font-medium">{call.title}</span>
          <span className="block truncate text-xs text-zinc-500">
            {call.diagnosticId} {describeParams(call.params) && `· ${describeParams(call.params)}`}
          </span>
        </span>
        {call.status === "running" && (
          <span className="flex items-center gap-1.5 text-xs text-zinc-500">
            <Loader2 className="size-3.5 animate-spin" /> Consultando SAP
          </span>
        )}
        {call.status === "error" && (
          <span className="flex items-center gap-1.5 text-xs text-red-600" title={call.error}>
            <AlertCircle className="size-3.5" /> {call.error}
          </span>
        )}
        {call.status === "ok" && result && (
          <>
            <span className="hidden sm:block">
              <ResultStatusBadge status={result.status} />
            </span>
            <Check className="size-4 text-emerald-500 sm:hidden" />
            <ChevronDown className={cn("size-4 text-zinc-400 transition", open && "rotate-180")} />
          </>
        )}
      </button>
      {open && result && (
        <div className="animate-fade-in space-y-3 border-t border-zinc-100 bg-zinc-50/60 p-3 dark:border-zinc-800 dark:bg-zinc-950/40">
          {result.findings.length > 0 && <FindingList findings={result.findings} compact />}
          {meta?.kind === "LIST" && result.tables[0] && (
            <div className="rounded-lg border border-zinc-200 bg-white dark:border-zinc-800 dark:bg-zinc-900">
              <ResultTableView table={{ ...result.tables[0], rows: result.tables[0].rows.slice(0, 6) }} />
            </div>
          )}
          <div className="flex flex-wrap gap-2 text-xs">
            {route && (
              <Link
                to={route}
                className="inline-flex items-center gap-1 font-medium text-brand-600 hover:underline dark:text-brand-400"
              >
                Abrir {OBJECT_LABEL[result.object.kind]?.toLowerCase()} {result.object.id}{" "}
                <ArrowUpRight className="size-3.5" />
              </Link>
            )}
            {listRoute && (
              <Link
                to={listRoute}
                className="inline-flex items-center gap-1 font-medium text-brand-600 hover:underline dark:text-brand-400"
              >
                Ver lista completa <ArrowUpRight className="size-3.5" />
              </Link>
            )}
            <span className="ml-auto text-zinc-400">
              {result.system.sid}/{result.system.client} · {result.durationMs} ms
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
