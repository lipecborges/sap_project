import type { DiagnosticResult, ParamMeta } from "@raiox/contracts";
import { useMutation } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { ChevronRight, Loader2, Play } from "lucide-react";
import { type FormEvent, useId, useState } from "react";
import { FactList } from "../components/domain/facts";
import { FindingList } from "../components/domain/findings";
import { enumLabel } from "../components/domain/labels";
import { MODULE_META } from "../components/domain/objects";
import { ResultTableView } from "../components/domain/result-table";
import { ResultStatusBadge } from "../components/domain/status";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardHeader } from "../components/ui/card";
import { EmptyState } from "../components/ui/misc";
import { PageHeader } from "../components/ui/page";
import { api, type RequestError } from "../lib/api";
import { useSession } from "../lib/auth";
import { cn } from "../lib/utils";

export function DiagnosticsPage() {
  const { diagnostics } = useSession();
  const modules = ["SD", "MM", "PP", "GE"].filter((m) => diagnostics.some((d) => d.module === m));
  return (
    <>
      <PageHeader
        title="Diagnósticos"
        description="Execute qualquer diagnóstico diretamente, informando os parâmetros."
      />
      <div className="space-y-8">
        {modules.map((m) => {
          const meta = MODULE_META[m]!;
          return (
            <section key={m}>
              <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-zinc-500">
                <meta.icon className="size-4" /> {meta.label}
              </h2>
              <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
                {diagnostics
                  .filter((d) => d.module === m)
                  .map((d) => (
                    <Link
                      key={d.id}
                      to="/diagnosticos/$diagnosticId"
                      params={{ diagnosticId: d.id }}
                      className="group flex items-start gap-3 rounded-xl border border-zinc-200 bg-white p-4 transition hover:border-zinc-300 hover:shadow-sm dark:border-zinc-800 dark:bg-zinc-900 dark:hover:border-zinc-700"
                    >
                      <span className={cn("flex size-9 shrink-0 items-center justify-center rounded-lg", meta.color)}>
                        <meta.icon className="size-4" />
                      </span>
                      <span className="min-w-0 flex-1">
                        <span className="flex items-center gap-2">
                          <span className="font-mono text-xs text-zinc-400">{d.id}</span>
                          <Badge tone="neutral">{d.kind === "LIST" ? "Lista" : "Documento"}</Badge>
                        </span>
                        <span className="mt-1 block text-sm font-medium">{d.title}</span>
                      </span>
                      <ChevronRight className="size-4 text-zinc-300 transition group-hover:translate-x-0.5" />
                    </Link>
                  ))}
              </div>
            </section>
          );
        })}
      </div>
    </>
  );
}

const inputClass =
  "mt-1.5 block h-9 w-full rounded-lg border border-zinc-300 bg-white px-3 text-sm outline-none focus:border-brand-500 focus:ring-4 focus:ring-brand-500/10 dark:border-zinc-700 dark:bg-zinc-950";

function ParamField({
  param,
  value,
  error,
  onChange,
}: {
  param: ParamMeta;
  value: string;
  error?: string;
  onChange: (v: string) => void;
}) {
  const id = useId();
  return (
    <div className="text-sm">
      <label htmlFor={id} className="font-medium">
        {param.label}
        {param.required && <span className="text-red-500"> *</span>}
      </label>
      {param.dataType === "ENUM" ? (
        <select id={id} className={inputClass} value={value} onChange={(e) => onChange(e.target.value)}>
          <option value="">Todas</option>
          {param.options.map((o) => (
            <option key={o} value={o}>
              {enumLabel(o)}
            </option>
          ))}
        </select>
      ) : (
        <input
          id={id}
          className={inputClass}
          type={param.dataType === "DATE" ? "date" : "text"}
          inputMode={param.dataType === "DOCUMENT" || param.dataType === "INTEGER" ? "numeric" : undefined}
          value={value}
          required={param.required}
          onChange={(e) => onChange(e.target.value)}
        />
      )}
      {error && <span className="mt-1 block text-xs text-red-600">{error}</span>}
    </div>
  );
}

export function DiagnosticRunPage({ diagnosticId }: { diagnosticId: string }) {
  const { diagnostics } = useSession();
  const meta = diagnostics.find((d) => d.id === diagnosticId);
  const [params, setParams] = useState<Record<string, string>>({});
  const run = useMutation<DiagnosticResult, RequestError, Record<string, string>>({
    mutationFn: (p) => api.run(diagnosticId, Object.fromEntries(Object.entries(p).filter(([, v]) => v.trim()))),
  });

  if (!meta) {
    return (
      <Card>
        <EmptyState
          title="Diagnóstico indisponível"
          description="Ele não existe ou o seu usuário não tem autorização (ZRX_DIAG)."
        />
      </Card>
    );
  }
  const submit = (e: FormEvent) => {
    e.preventDefault();
    run.mutate(params);
  };
  const result = run.data;

  return (
    <>
      <PageHeader
        back={{ to: "/diagnosticos", label: "Diagnósticos" }}
        eyebrow={<span className="font-mono text-xs text-zinc-400">{meta.id}</span>}
        title={meta.title}
      />
      <div className="grid gap-6 lg:grid-cols-[20rem_1fr]">
        <Card className="h-fit">
          <form onSubmit={submit} className="space-y-4 p-5">
            {meta.params.map((p) => (
              <ParamField
                key={p.name}
                param={p}
                value={params[p.name] ?? ""}
                error={run.error?.params?.[p.name]}
                onChange={(v) => setParams((prev) => ({ ...prev, [p.name]: v }))}
              />
            ))}
            <Button type="submit" className="w-full" disabled={run.isPending}>
              {run.isPending ? <Loader2 className="animate-spin" /> : <Play />} Executar
            </Button>
            {run.error && !run.error.params && <p className="text-sm text-red-600">{run.error.message}</p>}
          </form>
        </Card>
        <div className="min-w-0 space-y-6">
          {!result ? (
            <Card>
              <EmptyState
                title="Informe os parâmetros e execute"
                description="O resultado aparece aqui, com achados, dados e tabelas."
              />
            </Card>
          ) : (
            <>
              <div className="flex items-center gap-3">
                <ResultStatusBadge status={result.status} />
                <span className="text-xs text-zinc-500">
                  {result.system.sid}/{result.system.client} · {result.durationMs} ms
                </span>
              </div>
              {result.findings.length > 0 && <FindingList findings={result.findings} />}
              {result.facts.length > 0 && (
                <Card>
                  <CardHeader title="Dados" />
                  <FactList facts={result.facts} />
                </Card>
              )}
              {result.tables.map((t) => (
                <Card key={t.id}>
                  <CardHeader title={t.title} />
                  <ResultTableView table={t} />
                </Card>
              ))}
            </>
          )}
        </div>
      </div>
    </>
  );
}
