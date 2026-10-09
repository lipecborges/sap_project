import { INVOICE_STATE_LABELS } from "@raiox/contracts";
import { Link, useNavigate } from "@tanstack/react-router";
import { ChevronRight, Sparkles } from "lucide-react";
import { useState } from "react";
import { FactList } from "../components/domain/facts";
import { FilterBar } from "../components/domain/filters";
import { FindingList } from "../components/domain/findings";
import { InvoiceStateBadge, ResultStatusBadge } from "../components/domain/status";
import { Badge } from "../components/ui/badge";
import { Button } from "../components/ui/button";
import { Card, CardHeader } from "../components/ui/card";
import { EmptyState, ErrorState, Skeleton } from "../components/ui/misc";
import { PageHeader } from "../components/ui/page";
import { useDiagnostic } from "../lib/queries";
import { countsOf, factOf, rowsOf, tableOf } from "../lib/table";
import { cn, relativeDays } from "../lib/utils";

export function InvoicesListPage({ filter = "ALL" }: { filter?: string }) {
  const navigate = useNavigate();
  const { data, isLoading, error, refetch } = useDiagnostic("MM-10", { maxRows: "500" });
  const [search, setSearch] = useState("");
  const rows = rowsOf(tableOf(data, "invoices"));
  const states = countsOf(data, "state");
  const overdue = rows.filter((r) => Number(r.daysToDue) < 0).length;
  const chips = [
    { key: "ALL", label: "Todas", count: rows.length },
    ...(overdue ? [{ key: "OVERDUE", label: "Vencidas", count: overdue }] : []),
    ...Object.entries(INVOICE_STATE_LABELS)
      .filter(([k]) => states[k])
      .map(([k, label]) => ({ key: k, label, count: states[k] })),
  ];
  const term = search.trim().toLowerCase();
  const visible = rows
    .filter((r) => filter === "ALL" || (filter === "OVERDUE" ? Number(r.daysToDue) < 0 : r.stateCode === filter))
    .filter((r) => !term || `${r.invoice} ${r.vendor} ${r.purchaseOrder}`.toLowerCase().includes(term));

  return (
    <>
      <PageHeader
        title="Faturas de fornecedor pendentes"
        description={`${factOf(data, "total") ?? "…"} faturas bloqueadas ou estacionadas · ${factOf(data, "totalAmount") ?? ""} retidos`}
        actions={
          <Button
            variant="outline"
            onClick={() =>
              navigate({ to: "/assistente", search: { q: "Quais faturas estão bloqueadas e o que fazer?" } })
            }
          >
            <Sparkles /> Analisar com IA
          </Button>
        }
      />
      <Card>
        <FilterBar
          chips={chips}
          active={filter}
          onChange={(k) => navigate({ to: "/compras", search: k === "ALL" ? {} : { filtro: k }, replace: true })}
          search={search}
          onSearch={setSearch}
          placeholder="Fatura, fornecedor, pedido…"
        />
        {isLoading ? (
          <div className="space-y-2 p-4">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-11" />
            ))}
          </div>
        ) : error ? (
          <ErrorState error={error} onRetry={() => refetch()} />
        ) : visible.length === 0 ? (
          <EmptyState title="Nenhuma fatura neste filtro" />
        ) : (
          <ul className="divide-y divide-zinc-100 dark:divide-zinc-800">
            {visible.map((r) => {
              const days = Number(r.daysToDue);
              return (
                <li key={r.invoice}>
                  <Link
                    to="/compras/faturas/$invoice/$year"
                    params={{ invoice: r.invoice ?? "", year: r.fiscalYear ?? "" }}
                    className="grid grid-cols-[1fr_auto] items-center gap-x-4 gap-y-1 px-5 py-3.5 transition hover:bg-zinc-50 md:grid-cols-[8rem_1fr_8rem_9rem_7rem_auto] dark:hover:bg-zinc-800/40"
                  >
                    <span className="font-mono text-[0.8125rem] font-medium">{r.invoice}</span>
                    <span className="col-span-2 min-w-0 md:col-span-1">
                      <span className="block truncate text-sm font-medium">{r.vendor}</span>
                      <span className="block truncate text-xs text-zinc-500">
                        {r.reason} · pedido {r.purchaseOrder}
                      </span>
                    </span>
                    <span className="text-sm tabular-nums">{r.grossAmount}</span>
                    <span
                      className={cn(
                        "text-xs",
                        days < 0 ? "font-medium text-red-600 dark:text-red-400" : "text-zinc-500",
                      )}
                    >
                      {days < 0 ? `Venceu ${relativeDays(days)}` : `Vence ${relativeDays(days)}`}
                    </span>
                    <span>
                      <InvoiceStateBadge code={r.stateCode ?? ""} />
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

export function InvoicePage({ invoice, year }: { invoice: string; year: string }) {
  const navigate = useNavigate();
  const { data: r, isLoading, error, refetch } = useDiagnostic("MM-02", { invoiceDocument: invoice, fiscalYear: year });
  if (isLoading) return <Skeleton className="h-96" />;
  if (error || !r)
    return (
      <Card>
        <ErrorState error={error} onRetry={() => refetch()} />
      </Card>
    );
  const notFound = r.status === "NOT_FOUND";
  return (
    <>
      <PageHeader
        back={{ to: "/compras", label: "Faturas de fornecedor" }}
        eyebrow={<ResultStatusBadge status={r.status} />}
        title={
          <span>
            Fatura <span className="font-mono">{invoice}</span>
            <span className="ml-2 text-base font-normal text-zinc-400">{year}</span>
          </span>
        }
        description={factOf(r, "vendor")}
        actions={
          !notFound && (
            <Button
              onClick={() =>
                navigate({ to: "/assistente", search: { q: `Por que a fatura ${invoice} de ${year} está bloqueada?` } })
              }
            >
              <Sparkles /> Perguntar à IA
            </Button>
          )
        }
      />
      {notFound ? (
        <Card>
          <EmptyState title="Fatura não encontrada" description={r.findings[0]?.detail} />
        </Card>
      ) : (
        <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
          <Card className="min-w-0">
            <CardHeader title="Diagnóstico" description="Motivos do bloqueio e como liberar" />
            <div className="px-5 pb-5">
              <FindingList findings={r.findings} />
            </div>
          </Card>
          <div className="space-y-6">
            <Card>
              <CardHeader title="Detalhes" />
              <FactList facts={r.facts} />
            </Card>
            {r.related.map((d) => (
              <Badge key={d.id} tone="neutral" className="font-mono">
                Pedido de compra {d.id}
              </Badge>
            ))}
          </div>
        </div>
      )}
    </>
  );
}
