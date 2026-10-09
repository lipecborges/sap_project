import type { DiagnosticResult, Finding, ResultTable } from "@raiox/contracts";
import { useState } from "react";
import { OBJECT_KIND, SEVERITY, SEVERITY_ORDER, STATUS } from "../labels";

export function ResultView({ result }: { result: DiagnosticResult }) {
  const findings = [...result.findings].sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity]);
  const status = STATUS[result.status];

  return (
    <section aria-label="Resultado do diagnóstico" className="space-y-6">
      <header className="flex flex-wrap items-center gap-3">
        <span className={`rounded-full px-3 py-1 text-sm font-medium ${status.className}`}>{status.label}</span>
        <span className="text-sm text-slate-600 dark:text-slate-400">
          {OBJECT_KIND[result.object.kind] ?? result.object.kind} {result.object.id}
        </span>
        <span className="ml-auto text-xs text-slate-500 dark:text-slate-500">
          {result.system.sid}/{result.system.client} · {result.system.release} · {result.durationMs} ms
        </span>
      </header>

      {findings.length > 0 && (
        <ul className="space-y-3">
          {findings.map((f, i) => (
            <FindingCard key={`${f.code}-${i}`} finding={f} />
          ))}
        </ul>
      )}

      {result.facts.length > 0 && (
        <dl className="grid grid-cols-2 overflow-hidden rounded-xl border-t border-l border-slate-200 bg-white lg:grid-cols-3 dark:border-slate-800 dark:bg-slate-900">
          {result.facts.map((fact) => (
            <div key={fact.id} className="border-r border-b border-slate-200 px-4 py-3 dark:border-slate-800">
              <dt className="text-xs text-slate-500 dark:text-slate-400">{fact.label}</dt>
              <dd className="mt-0.5 text-sm font-medium">{fact.value}</dd>
            </div>
          ))}
        </dl>
      )}

      {result.tables.map((table) => (
        <DataTable key={table.id} table={table} />
      ))}

      {result.related.length > 0 && (
        <div className="flex flex-wrap items-center gap-2 text-sm">
          <span className="text-slate-500 dark:text-slate-400">Documentos relacionados:</span>
          {result.related.map((r) => (
            <span
              key={`${r.kind}-${r.id}`}
              className="rounded-md bg-slate-100 px-2 py-0.5 font-mono text-xs dark:bg-slate-800"
            >
              {OBJECT_KIND[r.kind] ?? r.kind} {r.id}
            </span>
          ))}
        </div>
      )}
    </section>
  );
}

function FindingCard({ finding }: { finding: Finding }) {
  const severity = SEVERITY[finding.severity];
  return (
    <li className={`rounded-xl border p-4 ${severity.className}`}>
      <div className="flex items-start gap-3">
        <span className={`mt-1.5 size-2.5 shrink-0 rounded-full ${severity.dot}`} aria-hidden />
        <div className="min-w-0 flex-1 space-y-2">
          <div className="flex flex-wrap items-baseline gap-x-2">
            <h3 className="font-semibold">{finding.title}</h3>
            <span className="text-xs text-slate-500 dark:text-slate-400">
              {severity.label} · <span className="font-mono">{finding.code}</span>
            </span>
          </div>
          {finding.detail && <p className="text-sm text-slate-700 dark:text-slate-300">{finding.detail}</p>}
          {finding.evidence.length > 0 && (
            <ul className="space-y-1 text-xs text-slate-600 dark:text-slate-400">
              {finding.evidence.map((e, i) => (
                <li key={i}>
                  <span className="font-mono">
                    {e.source}-{e.field}
                    {e.value !== "" && ` = ${e.value}`}
                  </span>{" "}
                  · {e.label}
                </li>
              ))}
            </ul>
          )}
          {finding.suggestedAction && <ActionChip {...finding.suggestedAction} />}
        </div>
      </div>
    </li>
  );
}

function ActionChip({ tcode, description }: { tcode: string; description: string }) {
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(tcode);
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    } catch {
      // Área de transferência indisponível (ex.: http sem TLS): apenas ignora.
    }
  }
  return (
    <div className="flex flex-wrap items-center gap-2 text-sm">
      <button
        type="button"
        onClick={copy}
        title="Copiar transação"
        className="rounded-md bg-brand-700 px-2 py-0.5 font-mono text-xs font-semibold text-white hover:bg-brand-800"
      >
        {copied ? "Copiado" : tcode}
      </button>
      <span>{description}</span>
    </div>
  );
}

function DataTable({ table }: { table: ResultTable }) {
  return (
    <div>
      <h3 className="mb-2 text-sm font-semibold">{table.title}</h3>
      {table.rows.length === 0 ? (
        <p className="text-sm text-slate-500 dark:text-slate-400">Nenhum registro.</p>
      ) : (
        <div className="overflow-x-auto rounded-xl border border-slate-200 dark:border-slate-800">
          <table className="w-full text-left text-sm">
            <thead className="bg-slate-100 text-xs text-slate-600 dark:bg-slate-800 dark:text-slate-300">
              <tr>
                {table.columns.map((c) => (
                  <th key={c} scope="col" className="whitespace-nowrap px-3 py-2 font-medium">
                    {c}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200 bg-white dark:divide-slate-800 dark:bg-slate-900">
              {table.rows.map((row, i) => (
                <tr key={i}>
                  {row.map((cell, j) => (
                    <td key={j} className="whitespace-nowrap px-3 py-2">
                      {cell}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {table.truncated && (
        <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">Há mais registros: use a paginação.</p>
      )}
    </div>
  );
}
