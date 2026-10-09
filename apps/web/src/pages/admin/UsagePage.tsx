import { findDiagnostic, type UsageReport } from "@raiox/contracts";
import { BarChart3, type LucideIcon, MessagesSquare, Search, Users } from "lucide-react";
import { useState } from "react";
import { BarList } from "../../components/charts/BarList";
import { DailyBars } from "../../components/charts/DailyBars";
import { Card, CardHeader } from "../../components/ui/card";
import { Segmented } from "../../components/ui/form";
import { EmptyState, ErrorState, Skeleton } from "../../components/ui/misc";
import { PageHeader } from "../../components/ui/page";
import { formatMs } from "../../lib/admin";
import { useAdminUsage } from "../../lib/admin-queries";

function Kpi({ label, value, hint, icon: Icon }: { label: string; value: string; hint: string; icon: LucideIcon }) {
  return (
    <Card className="p-4">
      <div className="flex items-center justify-between">
        <span className="text-sm text-zinc-500 dark:text-zinc-400">{label}</span>
        <span className="flex size-8 items-center justify-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-900/40 dark:text-brand-300">
          <Icon className="size-4" />
        </span>
      </div>
      <p className="mt-2 text-3xl font-semibold tracking-tight tabular-nums">{value}</p>
      <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">{hint}</p>
    </Card>
  );
}

const number = new Intl.NumberFormat("pt-BR");

function Latency({ rows }: { rows: UsageReport["latency"] }) {
  const max = Math.max(1, ...rows.map((r) => r.p95Ms));
  if (rows.length === 0) return <EmptyState title="Sem medições no período" />;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-zinc-200 text-xs text-zinc-500 dark:border-zinc-800 dark:text-zinc-400">
            <th scope="col" className="px-5 py-2.5 font-medium">
              Diagnóstico
            </th>
            <th scope="col" className="px-4 py-2.5 text-right font-medium">
              Média
            </th>
            <th scope="col" className="px-4 py-2.5 text-right font-medium">
              p95
            </th>
            <th scope="col" className="hidden w-1/3 px-5 py-2.5 font-medium sm:table-cell">
              <span className="sr-only">Proporção do p95</span>
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800/70">
          {rows.map((r) => (
            <tr key={r.id}>
              <td className="px-5 py-2.5">
                <span className="font-mono text-[0.8125rem]">{r.id}</span>
                <span className="block max-w-72 truncate text-xs text-zinc-500">{findDiagnostic(r.id)?.title}</span>
              </td>
              <td className="px-4 py-2.5 text-right tabular-nums">{formatMs(r.avgMs)}</td>
              <td className="px-4 py-2.5 text-right font-medium tabular-nums">{formatMs(r.p95Ms)}</td>
              <td className="hidden px-5 py-2.5 sm:table-cell" aria-hidden>
                <span className="relative block h-2 rounded-full" style={{ background: "var(--chart-track)" }}>
                  <span
                    className="absolute inset-y-0 left-0 rounded-full"
                    style={{ width: `${(r.p95Ms / max) * 100}%`, background: "var(--chart-series-1)" }}
                  />
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function UsagePage() {
  const { data, isLoading, error, refetch } = useAdminUsage(30);
  const [metric, setMetric] = useState<"runs" | "chatTurns">("runs");

  const totals = data && {
    runs: data.days.reduce((s, d) => s + d.runs, 0),
    chat: data.days.reduce((s, d) => s + d.chatTurns, 0),
    peakUsers: Math.max(0, ...data.days.map((d) => d.activeUsers)),
  };
  const empty = data && totals && totals.runs + totals.chat === 0;

  return (
    <>
      <PageHeader title="Uso" description="Atividade dos últimos 30 dias neste cliente." />

      {isLoading ? (
        <div className="space-y-6" role="status" aria-busy="true" aria-label="Carregando uso">
          <div className="grid gap-4 sm:grid-cols-3">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-28 rounded-xl" />
            ))}
          </div>
          <Skeleton className="h-64 rounded-xl" />
        </div>
      ) : error ? (
        <Card>
          <ErrorState error={error} onRetry={() => refetch()} />
        </Card>
      ) : data && totals ? (
        <div className="space-y-6">
          <div className="grid gap-4 sm:grid-cols-3">
            <Kpi
              label="Consultas ao SAP"
              value={number.format(totals.runs)}
              hint="Diagnósticos executados"
              icon={Search}
            />
            <Kpi
              label="Mensagens no assistente"
              value={number.format(totals.chat)}
              hint="Perguntas feitas à IA"
              icon={MessagesSquare}
            />
            <Kpi label="Usuários ativos" value={String(totals.peakUsers)} hint="Pico em um único dia" icon={Users} />
          </div>

          <Card>
            <CardHeader
              title="Atividade por dia"
              icon={<BarChart3 />}
              action={
                <Segmented
                  ariaLabel="Métrica do gráfico"
                  value={metric}
                  onChange={setMetric}
                  options={[
                    { value: "runs", label: "Consultas" },
                    { value: "chatTurns", label: "Assistente" },
                  ]}
                />
              }
            />
            <div className="px-5 pb-5">
              {empty ? (
                <EmptyState title="Sem atividade no período" description="Os números aparecem assim que houver uso." />
              ) : (
                <DailyBars
                  data={data.days.map((d) => ({ date: d.date, value: d[metric] }))}
                  unit={metric === "runs" ? ["consulta", "consultas"] : ["mensagem", "mensagens"]}
                  ariaLabel={`${metric === "runs" ? "Consultas" : "Mensagens do assistente"} por dia, últimos 30 dias`}
                />
              )}
            </div>
          </Card>

          <div className="grid gap-6 lg:grid-cols-2">
            <Card>
              <CardHeader title="Diagnósticos mais usados" description="Execuções no período" />
              <div className="px-3 pb-4">
                {data.topDiagnostics.length === 0 ? (
                  <EmptyState title="Nenhuma execução" />
                ) : (
                  <BarList
                    ariaLabel="Diagnósticos mais executados"
                    unit={["execução", "execuções"]}
                    data={data.topDiagnostics.map((d) => ({ key: d.id, label: d.id, value: d.runs }))}
                  />
                )}
              </div>
            </Card>
            <Card>
              <CardHeader title="Usuários mais ativos" description="Consultas e mensagens no período" />
              <div className="px-3 pb-4">
                {data.topUsers.length === 0 ? (
                  <EmptyState title="Nenhum usuário ativo" />
                ) : (
                  <BarList
                    ariaLabel="Usuários mais ativos"
                    unit={["interação", "interações"]}
                    data={data.topUsers.map((u) => ({ key: u.sapUser, label: u.sapUser, value: u.runs + u.chatTurns }))}
                  />
                )}
              </div>
            </Card>
          </div>

          <Card>
            <CardHeader
              title="Tempo de resposta do SAP"
              description="Média e percentil 95 por diagnóstico: o p95 é o tempo que 95% das consultas não ultrapassam"
            />
            <Latency rows={data.latency} />
          </Card>
        </div>
      ) : null}
    </>
  );
}
