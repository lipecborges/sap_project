import { SD_STAGE_LABELS } from "@raiox/contracts";
import { Link, useNavigate } from "@tanstack/react-router";
import { Check, ChevronRight, Sparkles, X } from "lucide-react";
import { useState } from "react";
import { FactList } from "../components/domain/facts";
import { FilterBar } from "../components/domain/filters";
import { FindingList } from "../components/domain/findings";
import { OBJECT_LABEL } from "../components/domain/objects";
import { ResultStatusBadge, StageBadge } from "../components/domain/status";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardHeader } from "../components/ui/card";
import { EmptyState, ErrorState, Skeleton } from "../components/ui/misc";
import { PageHeader } from "../components/ui/page";
import { useDiagnostic } from "../lib/queries";
import { countsOf, factOf, rowsOf, tableOf } from "../lib/table";
import { cn, daysFromToday, relativeDays } from "../lib/utils";

export function SalesListPage({ filter = "ALL" }: { filter?: string }) {
  const navigate = useNavigate();
  const { data, isLoading, error, refetch } = useDiagnostic("SD-10", { maxRows: "500" });
  const [search, setSearch] = useState("");
  const rows = rowsOf(tableOf(data, "salesOrders"));
  const stages = countsOf(data, "stage");
  const chips = [
    { key: "ALL", label: "Todos", count: rows.length },
    ...Object.entries(SD_STAGE_LABELS)
      .filter(([k]) => stages[k])
      .map(([k, label]) => ({ key: k, label, count: stages[k] })),
  ];
  const term = search.trim().toLowerCase();
  const visible = rows
    .filter((r) => filter === "ALL" || r.stageCode === filter)
    .filter((r) => !term || `${r.salesOrder} ${r.customer}`.toLowerCase().includes(term));

  return (
    <>
      <PageHeader
        title="Pedidos de venda travados"
        description={`${factOf(data, "total") ?? "…"} pedidos parados antes do faturamento · ${factOf(data, "totalValue") ?? ""}`}
        actions={
          <Button
            variant="outline"
            onClick={() => navigate({ to: "/assistente", search: { q: "Quais pedidos estão travados e por quê?" } })}
          >
            <Sparkles /> Analisar com IA
          </Button>
        }
      />
      <Card>
        <FilterBar
          chips={chips}
          active={filter}
          onChange={(k) => navigate({ to: "/vendas", search: k === "ALL" ? {} : { filtro: k }, replace: true })}
          search={search}
          onSearch={setSearch}
          placeholder="Pedido, cliente…"
        />
        {isLoading ? (
          <div className="space-y-2 p-4">
            {[0, 1, 2, 3].map((i) => (
              <Skeleton key={i} className="h-11" />
            ))}
          </div>
        ) : error ? (
          <ErrorState error={error} onRetry={() => refetch()} />
        ) : visible.length === 0 ? (
          <EmptyState title="Nenhum pedido neste filtro" />
        ) : (
          <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
            {visible.map((r) => {
              const due = daysFromToday(r.requestedDate ?? "");
              return (
                <li key={r.salesOrder}>
                  <Link
                    to="/vendas/pedidos/$salesOrder"
                    params={{ salesOrder: r.salesOrder ?? "" }}
                    className="grid grid-cols-[1fr_auto] items-center gap-x-4 gap-y-1 px-5 py-3.5 transition hover:bg-zinc-50 md:grid-cols-[7rem_1fr_9rem_9rem_8rem_auto] dark:hover:bg-zinc-800/40"
                  >
                    <span className="font-mono text-[0.8125rem] font-medium">{r.salesOrder}</span>
                    <span className="col-span-2 min-w-0 md:col-span-1">
                      <span className="block truncate text-sm font-medium">{r.customer}</span>
                      <span className="block truncate text-xs text-zinc-500">{r.reason}</span>
                    </span>
                    <span>
                      <StageBadge code={r.stageCode ?? ""} />
                    </span>
                    <span className="text-sm tabular-nums">{r.netValue}</span>
                    <span
                      className={cn(
                        "text-xs",
                        due !== undefined && due < 0 ? "font-medium text-red-600 dark:text-red-400" : "text-zinc-500",
                      )}
                    >
                      {due !== undefined && due < 0
                        ? `Atrasado ${relativeDays(due)}`
                        : `Entrega ${relativeDays(due ?? 0)}`}
                    </span>
                    <ChevronRight className="hidden size-4 text-zinc-300 md:block" />
                  </Link>
                </li>
              );
            })}
          </ul>
        )}
      </Card>
    </>
  );
}

const PIPELINE = [
  { key: "ORDER", label: "Pedido" },
  { key: "CREDIT", label: SD_STAGE_LABELS.CREDIT },
  { key: "DELIVERY", label: SD_STAGE_LABELS.DELIVERY },
  { key: "GOODS_ISSUE", label: SD_STAGE_LABELS.GOODS_ISSUE },
  { key: "BILLING", label: SD_STAGE_LABELS.BILLING },
];

/** Etapa travada a partir dos achados do SD-01. */
function blockedStage(codes: string[]): string | undefined {
  if (codes.includes("SD01.ALREADY_BILLED")) return "DONE";
  if (codes.includes("SD01.CREDIT_BLOCK")) return "CREDIT";
  if (codes.some((c) => c.startsWith("SD01.DELIVERY_BLOCK") || c === "SD01.INCOMPLETE" || c === "SD01.NOT_DELIVERED"))
    return "DELIVERY";
  if (codes.includes("SD01.GOODS_ISSUE_PENDING")) return "GOODS_ISSUE";
  if (codes.includes("SD01.BILLING_BLOCK") || codes.includes("SD01.BILLING_DUE")) return "BILLING";
  return undefined;
}

function Pipeline({ blocked }: { blocked?: string }) {
  const blockedIndex = blocked === "DONE" ? PIPELINE.length : PIPELINE.findIndex((s) => s.key === blocked);
  return (
    <ol className="flex items-center overflow-x-auto px-5 py-5">
      {PIPELINE.map((s, i) => {
        const state =
          blockedIndex < 0 ? "pending" : i < blockedIndex ? "done" : i === blockedIndex ? "blocked" : "pending";
        return (
          <li key={s.key} className="flex flex-1 items-center last:flex-none">
            <div className="flex flex-col items-center gap-1.5">
              <span
                className={cn(
                  "flex size-8 items-center justify-center rounded-full border-2 text-xs font-semibold",
                  state === "done" && "border-emerald-500 bg-emerald-500 text-white",
                  state === "blocked" && "border-red-500 bg-red-50 text-red-600 dark:bg-red-950/50",
                  state === "pending" && "border-zinc-200 text-zinc-400 dark:border-zinc-700",
                )}
              >
                {state === "done" ? (
                  <Check className="size-4" />
                ) : state === "blocked" ? (
                  <X className="size-4" />
                ) : (
                  i + 1
                )}
              </span>
              <span
                className={cn(
                  "whitespace-nowrap text-xs",
                  state === "blocked" ? "font-semibold text-red-600 dark:text-red-400" : "text-zinc-500",
                )}
              >
                {s.label}
              </span>
            </div>
            {i < PIPELINE.length - 1 && (
              <span
                className={cn(
                  "mx-2 mb-5 h-0.5 min-w-6 flex-1 rounded",
                  i < blockedIndex ? "bg-emerald-500" : "bg-zinc-200 dark:bg-zinc-800",
                )}
              />
            )}
          </li>
        );
      })}
    </ol>
  );
}

export function SalesOrderPage({ salesOrder }: { salesOrder: string }) {
  const navigate = useNavigate();
  const { data: r, isLoading, error, refetch } = useDiagnostic("SD-01", { salesOrder });
  if (isLoading) return <Skeleton className="h-96" />;
  if (error || !r)
    return (
      <Card>
        <ErrorState error={error} onRetry={() => refetch()} />
      </Card>
    );
  const notFound = r.status === "NOT_FOUND";
  const blocked = blockedStage(r.findings.map((f) => f.code));

  return (
    <>
      <PageHeader
        back={{ to: "/vendas", label: "Pedidos de venda" }}
        eyebrow={<ResultStatusBadge status={r.status} />}
        title={
          <span>
            Pedido <span className="font-mono">{salesOrder}</span>
          </span>
        }
        description={factOf(r, "customer")}
        actions={
          !notFound && (
            <Button
              onClick={() =>
                navigate({ to: "/assistente", search: { q: `Por que o pedido ${salesOrder} não faturou?` } })
              }
            >
              <Sparkles /> Perguntar à IA
            </Button>
          )
        }
      />
      {notFound ? (
        <Card>
          <EmptyState title="Pedido não encontrado" description={r.findings[0]?.detail} />
        </Card>
      ) : (
        <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
          <div className="min-w-0 space-y-6">
            <Card>
              <CardHeader
                title="Fluxo do pedido"
                description={
                  blocked && blocked !== "DONE" ? "Etapa em vermelho é onde o pedido está parado" : "Pedido concluído"
                }
              />
              <Pipeline blocked={blocked} />
            </Card>
            <Card>
              <CardHeader title="Diagnóstico" description="Causa, evidência no SAP e transação para resolver" />
              <div className="px-5 pb-5">
                <FindingList findings={r.findings} />
              </div>
            </Card>
          </div>
          <div className="space-y-6">
            <Card>
              <CardHeader title="Detalhes" />
              <FactList facts={r.facts} />
            </Card>
            {r.related.length > 0 && (
              <Card>
                <CardHeader title="Documentos relacionados" />
                <ul className="space-y-2 px-5 pb-4">
                  {r.related.map((d) => (
                    <li key={`${d.kind}-${d.id}`} className="flex items-center justify-between text-sm">
                      <span className="text-zinc-500">{OBJECT_LABEL[d.kind] ?? d.kind}</span>
                      <Badge tone="neutral" className="font-mono">
                        {d.id}
                      </Badge>
                    </li>
                  ))}
                </ul>
              </Card>
            )}
          </div>
        </div>
      )}
    </>
  );
}
