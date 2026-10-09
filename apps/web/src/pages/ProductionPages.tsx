import { type Finding, PP_FLAG_LABELS, type PpFlag } from "@raiox/contracts";
import { Link, useNavigate } from "@tanstack/react-router";
import { CheckCircle2, ChevronRight, CircleDashed, CircleDot, Copy, Loader2, Sparkles, UserRound } from "lucide-react";
import { Tabs } from "radix-ui";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { FactList } from "../components/domain/facts";
import { FilterBar, type FilterChip } from "../components/domain/filters";
import { FindingList } from "../components/domain/findings";
import { FlagBadge, flagCodesFromLabels, SituationBadge, situationCodeFromLabel } from "../components/domain/status";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardHeader } from "../components/ui/card";
import { EmptyState, ErrorState, Progress, Skeleton } from "../components/ui/misc";
import { PageHeader } from "../components/ui/page";
import { useDiagnostic } from "../lib/queries";
import { factOf, type Row, rowsOf, tableOf } from "../lib/table";
import { cn, daysFromToday, formatDate, parseDelay, parsePercent } from "../lib/utils";

const PLANT = "1000";

const CHIP_DEFS: Array<{ key: string; label: string; match: (r: Row) => boolean }> = [
  { key: "ALL", label: "Todas", match: () => true },
  { key: "LATE", label: "Atrasadas", match: (r) => /LATE_(START|FINISH)/.test(r.flagCodes ?? "") },
  { key: "MISSING_PARTS", label: "Falta de material", match: (r) => (r.flagCodes ?? "").includes("MISSING_PARTS") },
  {
    key: "CONFIRMED_NOT_RECEIVED",
    label: "Sem entrada",
    match: (r) => (r.flagCodes ?? "").includes("CONFIRMED_NOT_RECEIVED"),
  },
  { key: "IN_PRODUCTION", label: "Em produção", match: (r) => r.situationCode === "IN_PRODUCTION" },
  { key: "RELEASED", label: "Liberadas", match: (r) => r.situationCode === "RELEASED" },
  { key: "APPROVED", label: "Aprovadas", match: (r) => r.situationCode === "APPROVED" },
  { key: "CREATED", label: "Criadas", match: (r) => r.situationCode === "CREATED" },
];

export function ProductionListPage({ filter = "ALL" }: { filter?: string }) {
  const navigate = useNavigate();
  const { data, isLoading, error, refetch } = useDiagnostic("PP-04", { plant: PLANT, maxRows: "500" });
  const [search, setSearch] = useState("");
  const rows = rowsOf(tableOf(data, "orders"));

  const chips: FilterChip[] = CHIP_DEFS.map((c) => ({
    key: c.key,
    label: c.label,
    count: rows.filter(c.match).length,
  })).filter((c) => c.key === "ALL" || (c.count ?? 0) > 0);
  const def = CHIP_DEFS.find((c) => c.key === filter) ?? CHIP_DEFS[0]!;
  const term = search.trim().toLowerCase();
  const visible = rows
    .filter(def.match)
    .filter((r) => !term || `${r.order} ${r.material} ${r.description}`.toLowerCase().includes(term));
  const setFilter = (key: string) =>
    navigate({ to: "/producao", search: key === "ALL" ? {} : { filtro: key }, replace: true });

  return (
    <>
      <PageHeader
        title="Ordens de produção"
        description={`Centro ${PLANT} · ${factOf(data, "total") ?? "…"} ordens no período`}
        actions={
          <Button
            variant="outline"
            onClick={() =>
              navigate({ to: "/assistente", search: { q: "Quais ordens estão atrasadas no centro 1000?" } })
            }
          >
            <Sparkles /> Analisar com IA
          </Button>
        }
      />
      <Card>
        <FilterBar
          chips={chips}
          active={def.key}
          onChange={setFilter}
          search={search}
          onSearch={setSearch}
          placeholder="Ordem, material…"
        />
        {isLoading ? (
          <div className="space-y-2 p-4">
            {[0, 1, 2, 3, 4].map((i) => (
              <Skeleton key={i} className="h-11" />
            ))}
          </div>
        ) : error ? (
          <ErrorState error={error} onRetry={() => refetch()} />
        ) : visible.length === 0 ? (
          <EmptyState title="Nenhuma ordem neste filtro" />
        ) : (
          <>
            <table className="hidden w-full text-left text-sm md:table">
              <thead>
                <tr className="border-b border-zinc-200 text-xs text-zinc-500 dark:border-zinc-800 dark:text-zinc-400">
                  <th className="py-2.5 pr-3 pl-5 font-medium">Ordem</th>
                  <th className="px-3 py-2.5 font-medium">Material</th>
                  <th className="px-3 py-2.5 font-medium">Situação</th>
                  <th className="px-3 py-2.5 font-medium">Sinalizadores</th>
                  <th className="w-40 px-3 py-2.5 font-medium">Confirmado</th>
                  <th className="px-3 py-2.5 font-medium">Fim programado</th>
                  <th className="py-2.5 pr-5 pl-3 text-right font-medium">Atraso</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800/70">
                {visible.map((r) => (
                  <tr
                    key={r.order}
                    onClick={() => navigate({ to: "/producao/ordens/$orderId", params: { orderId: r.order ?? "" } })}
                    className="cursor-pointer transition hover:bg-zinc-50 dark:hover:bg-zinc-800/40"
                  >
                    <td className="py-3 pr-3 pl-5 font-mono text-[0.8125rem] font-medium">{r.order}</td>
                    <td className="px-3 py-3">
                      <div className="font-medium">{r.description}</div>
                      <div className="text-xs text-zinc-500">{r.material}</div>
                    </td>
                    <td className="px-3 py-3">
                      <SituationBadge code={r.situationCode ?? ""} />
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex flex-wrap gap-1">
                        {(r.flagCodes ?? "")
                          .split(",")
                          .filter(Boolean)
                          .map((f) => (
                            <FlagBadge key={f} code={f} compact />
                          ))}
                      </div>
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-2">
                        <Progress value={Number(r.progress)} className="w-20" />
                        <span className="text-xs text-zinc-500 tabular-nums">{r.progress}%</span>
                      </div>
                    </td>
                    <td className="px-3 py-3 text-zinc-600 dark:text-zinc-400">
                      {formatDate(r.scheduledFinish ?? "")}
                    </td>
                    <td className="py-3 pr-5 pl-3 text-right">
                      {Number(r.delayDays) > 0 ? (
                        <span className="font-medium text-red-600 tabular-nums dark:text-red-400">{r.delayDays} d</span>
                      ) : (
                        <span className="text-zinc-400">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            <ul className="divide-y divide-zinc-100 md:hidden dark:divide-zinc-800">
              {visible.map((r) => (
                <li key={r.order}>
                  <Link
                    to="/producao/ordens/$orderId"
                    params={{ orderId: r.order ?? "" }}
                    className="flex items-center gap-3 px-4 py-3"
                  >
                    <div className="min-w-0 flex-1 space-y-1.5">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-sm font-medium">{r.order}</span>
                        <SituationBadge code={r.situationCode ?? ""} />
                        {Number(r.delayDays) > 0 && <Badge tone="critical">{r.delayDays} d atraso</Badge>}
                      </div>
                      <p className="truncate text-sm text-zinc-600 dark:text-zinc-400">{r.description}</p>
                      <Progress value={Number(r.progress)} />
                    </div>
                    <ChevronRight className="size-4 text-zinc-300" />
                  </Link>
                </li>
              ))}
            </ul>
          </>
        )}
      </Card>
    </>
  );
}

function Kpi({ label, value, children }: { label: string; value?: string; children?: React.ReactNode }) {
  return (
    <div className="rounded-xl border border-zinc-200/80 bg-white p-4 dark:border-zinc-800 dark:bg-zinc-900">
      <p className="text-xs text-zinc-500 dark:text-zinc-400">{label}</p>
      <p className="mt-1 text-lg font-semibold tracking-tight tabular-nums">{value ?? "—"}</p>
      {children}
    </div>
  );
}

function OperationsTimeline({ rows }: { rows: Row[] }) {
  return (
    <ol className="relative space-y-5 px-5 py-4">
      {rows.map((op, i) => {
        const status = op.status ?? "";
        const done = status.includes("CNF") && !status.includes("PCNF");
        const partial = status.includes("PCNF");
        const late = !done && (daysFromToday(op.scheduledFinish ?? "") ?? 0) < 0;
        const Icon = done ? CheckCircle2 : partial ? CircleDot : CircleDashed;
        return (
          <li key={op.operation} className="relative flex gap-4">
            {i < rows.length - 1 && (
              <span className="absolute top-6 left-[0.6875rem] h-[calc(100%+0.25rem)] w-px bg-zinc-200 dark:bg-zinc-800" />
            )}
            <Icon
              className={cn(
                "relative z-10 size-6 shrink-0 bg-white dark:bg-zinc-900",
                done ? "text-emerald-500" : partial ? "text-brand-500" : "text-zinc-300",
              )}
            />
            <div className="min-w-0 flex-1 pb-1">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-mono text-xs text-zinc-400">{op.operation}</span>
                <span className="text-sm font-medium">{op.description}</span>
                <Badge tone="neutral">{op.workCenter}</Badge>
                {late && <Badge tone="critical">Atrasada</Badge>}
              </div>
              <p className="mt-1 text-xs text-zinc-500 dark:text-zinc-400">
                Fim programado {formatDate(op.scheduledFinish ?? "")}
                {op.actualFinish && op.actualFinish !== "—" ? ` · concluída ${formatDate(op.actualFinish)}` : ""} ·
                confirmado {op.confirmed}
                {op.scrap && !op.scrap.startsWith("0 ") ? ` · refugo ${op.scrap}` : ""}
              </p>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

function SimpleTable({
  rows,
  columns,
}: {
  rows: Row[];
  columns: Array<{ key: string; label: string; className?: string; render?: (r: Row) => React.ReactNode }>;
}) {
  if (rows.length === 0) return <EmptyState title="Nenhum registro" />;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-zinc-200 text-xs text-zinc-500 dark:border-zinc-800 dark:text-zinc-400">
            {columns.map((c) => (
              <th key={c.key} className={cn("whitespace-nowrap px-4 py-2.5 font-medium first:pl-5", c.className)}>
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800/70">
          {rows.map((r, i) => (
            // biome-ignore lint/suspicious/noArrayIndexKey: linhas sem id próprio
            <tr key={i}>
              {columns.map((c) => (
                <td key={c.key} className={cn("whitespace-nowrap px-4 py-2.5 first:pl-5", c.className)}>
                  {c.render ? c.render(r) : r[c.key]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const tabTrigger =
  "relative px-1 pb-3 text-sm font-medium text-zinc-500 transition data-[state=active]:text-zinc-950 data-[state=active]:after:absolute data-[state=active]:after:inset-x-0 data-[state=active]:after:-bottom-px data-[state=active]:after:h-0.5 data-[state=active]:after:bg-brand-600 hover:text-zinc-800 dark:data-[state=active]:text-white";

export function ProductionOrderPage({ orderId }: { orderId: string }) {
  const navigate = useNavigate();
  const status = useDiagnostic("PP-03", { productionOrder: orderId });
  const release = useDiagnostic("PP-01", { productionOrder: orderId });
  const r = status.data;

  // PP-03 (situação) + PP-01 (liberação/componentes); no mesmo assunto, fica o achado mais detalhado.
  const findings = useMemo(() => {
    const byTopic = new Map<string, Finding>();
    const candidates = [
      ...(r?.findings ?? []),
      ...(release.data?.findings ?? []).filter((f) => f.severity !== "INFO" || r?.findings.length === 0),
    ];
    for (const f of candidates) {
      const topic = f.code.split(".")[1] ?? f.code;
      const current = byTopic.get(topic);
      if (!current || f.detail.length + f.evidence.length * 40 > current.detail.length + current.evidence.length * 40)
        byTopic.set(topic, f);
    }
    return [...byTopic.values()];
  }, [r, release.data]);

  if (status.isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-10 w-72" />
        <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
          {[0, 1, 2, 3, 4].map((i) => (
            <Skeleton key={i} className="h-20" />
          ))}
        </div>
        <Skeleton className="h-64" />
      </div>
    );
  }
  if (status.error || !r)
    return (
      <Card>
        <ErrorState error={status.error} onRetry={() => status.refetch()} />
      </Card>
    );
  if (r.status === "NOT_FOUND") {
    return (
      <>
        <PageHeader title={`Ordem ${orderId}`} back={{ to: "/producao", label: "Ordens de produção" }} />
        <Card>
          <EmptyState title="Ordem não encontrada" description={r.findings[0]?.detail} />
        </Card>
      </>
    );
  }

  const situation = situationCodeFromLabel(factOf(r, "situation"));
  const flags = flagCodesFromLabels(factOf(r, "flags"));
  const confirmedPct = parsePercent(factOf(r, "confirmed")) ?? 0;
  const deliveredPct = parsePercent(factOf(r, "delivered")) ?? 0;
  const salesOrder = r.related.find((x) => x.kind === "SALES_ORDER");
  const delay = parseDelay(factOf(r, "delay"));

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(orderId);
      toast.success("Número da ordem copiado");
    } catch {
      toast(orderId);
    }
  };

  return (
    <>
      <PageHeader
        back={{ to: "/producao", label: "Ordens de produção" }}
        eyebrow={
          <div className="flex flex-wrap items-center gap-1.5">
            {situation && <SituationBadge code={situation} />}
            {flags.map((f) => (
              <FlagBadge key={f} code={f} />
            ))}
          </div>
        }
        title={
          <span className="flex items-center gap-2">
            Ordem <span className="font-mono">{orderId}</span>
          </span>
        }
        description={factOf(r, "material")}
        actions={
          <>
            <Button variant="outline" onClick={copy}>
              <Copy /> Copiar nº
            </Button>
            <Button
              onClick={() =>
                navigate({
                  to: "/assistente",
                  search: { q: `Analise a ordem ${orderId}: o que está acontecendo e o que fazer?` },
                })
              }
            >
              <Sparkles /> Perguntar à IA
            </Button>
          </>
        }
      />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
        <Kpi label="Planejada" value={factOf(r, "planned")} />
        <Kpi label="Confirmada" value={factOf(r, "confirmed")?.split(" (")[0]}>
          <Progress value={confirmedPct} className="mt-2" />
        </Kpi>
        <Kpi label="Entregue no estoque" value={factOf(r, "delivered")?.split(" (")[0]}>
          <Progress value={deliveredPct} tone="good" className="mt-2" />
        </Kpi>
        <Kpi label="Refugo" value={factOf(r, "scrap")} />
        <Kpi
          label="Atraso"
          value={
            !delay || (delay.start === 0 && delay.finish === 0)
              ? "No prazo"
              : `${Math.max(delay.start, delay.finish)} dia(s)`
          }
        >
          {delay && (delay.start > 0 || delay.finish > 0) && (
            <p className="mt-1 text-xs text-red-600 dark:text-red-400">
              {delay.finish > 0 ? "no fim programado" : "no início"}
            </p>
          )}
        </Kpi>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_20rem]">
        <div className="min-w-0 space-y-6">
          <Card>
            <CardHeader
              title="Diagnóstico"
              description="O que impede ou atrasa esta ordem, com evidência e transação"
              action={release.isFetching ? <Loader2 className="size-4 animate-spin text-zinc-400" /> : undefined}
            />
            <div className="px-5 pb-5">
              {findings.length === 0 ? (
                <div className="flex items-center gap-2 rounded-lg bg-emerald-50 px-3 py-2.5 text-sm text-emerald-800 dark:bg-emerald-950/40 dark:text-emerald-300">
                  <CheckCircle2 className="size-4" /> Nenhum impedimento encontrado.
                </div>
              ) : (
                <FindingList findings={findings} />
              )}
            </div>
          </Card>

          <Card>
            <Tabs.Root defaultValue="operations">
              <Tabs.List className="flex gap-6 border-b border-zinc-200 px-5 pt-4 dark:border-zinc-800">
                <Tabs.Trigger value="operations" className={tabTrigger}>
                  Operações
                </Tabs.Trigger>
                <Tabs.Trigger value="components" className={tabTrigger}>
                  Componentes
                </Tabs.Trigger>
                <Tabs.Trigger value="confirmations" className={tabTrigger}>
                  Apontamentos
                </Tabs.Trigger>
              </Tabs.List>
              <Tabs.Content value="operations">
                <OperationsTimeline rows={rowsOf(tableOf(r, "operations"))} />
              </Tabs.Content>
              <Tabs.Content value="components">
                <SimpleTable
                  rows={rowsOf(tableOf(r, "components"))}
                  columns={[
                    { key: "material", label: "Material", className: "font-mono text-xs" },
                    { key: "description", label: "Descrição" },
                    { key: "required", label: "Necessário", className: "text-right tabular-nums" },
                    { key: "withdrawn", label: "Retirado", className: "text-right tabular-nums" },
                    { key: "pending", label: "Pendente", className: "text-right tabular-nums" },
                    { key: "stock", label: "Estoque livre", className: "text-right tabular-nums" },
                    {
                      key: "short",
                      label: "",
                      render: (row) =>
                        row.short === "Sim" ? <Badge tone="serious">Falta</Badge> : <Badge tone="good">OK</Badge>,
                    },
                  ]}
                />
              </Tabs.Content>
              <Tabs.Content value="confirmations">
                <SimpleTable
                  rows={rowsOf(tableOf(r, "confirmations"))}
                  columns={[
                    { key: "date", label: "Data", render: (row) => formatDate(row.date ?? "") },
                    { key: "operation", label: "Operação", className: "font-mono text-xs" },
                    { key: "yield", label: "Qtd. boa", className: "text-right tabular-nums" },
                    { key: "scrap", label: "Refugo", className: "text-right tabular-nums" },
                    { key: "user", label: "Usuário" },
                    {
                      key: "reversed",
                      label: "",
                      render: (row) => (row.reversed === "Sim" ? <Badge tone="neutral">Estornado</Badge> : null),
                    },
                  ]}
                />
              </Tabs.Content>
            </Tabs.Root>
          </Card>
        </div>

        <div className="space-y-6">
          {salesOrder && (
            <Card
              className={cn(
                flags.includes("SALES_ORDER_AT_RISK" satisfies PpFlag) && "border-amber-300 dark:border-amber-800",
              )}
            >
              <CardHeader
                icon={<UserRound />}
                title="Pedido do cliente"
                description={flags.includes("SALES_ORDER_AT_RISK") ? PP_FLAG_LABELS.SALES_ORDER_AT_RISK : undefined}
              />
              <div className="px-5 pb-4 text-sm">
                <p className="text-zinc-600 dark:text-zinc-400">{factOf(r, "salesOrder")}</p>
                <Link
                  to="/vendas/pedidos/$salesOrder"
                  params={{ salesOrder: salesOrder.id }}
                  className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-brand-600 hover:underline dark:text-brand-400"
                >
                  Abrir pedido {salesOrder.id} <ChevronRight className="size-4" />
                </Link>
              </div>
            </Card>
          )}
          <Card>
            <CardHeader title="Detalhes" />
            <FactList
              facts={r.facts.filter((f) =>
                [
                  "plant",
                  "mrpController",
                  "systemStatus",
                  "userStatus",
                  "basicDates",
                  "scheduledDates",
                  "actualDates",
                ].includes(f.id),
              )}
            />
          </Card>
          <p className="px-1 text-xs text-zinc-400">
            Fonte: {r.system.sid}/{r.system.client} ({r.system.release}) · PP-03 e PP-01 ·{" "}
            {new Date(r.executedAt).toLocaleTimeString("pt-BR")}
          </p>
        </div>
      </div>
    </>
  );
}
