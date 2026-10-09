import { PP_SITUATION_LABELS, type PpSituation, SD_STAGE_LABELS } from "@raiox/contracts";
import { Link, useNavigate } from "@tanstack/react-router";
import {
  AlertOctagon,
  ArrowRight,
  ArrowUp,
  ChevronRight,
  Clock,
  Factory,
  type LucideIcon,
  PackageX,
  Receipt,
  ShoppingCart,
  Sparkles,
} from "lucide-react";
import { type FormEvent, useState } from "react";
import { BarList } from "../components/charts/BarList";
import { MODULE_META } from "../components/domain/objects";
import { Badge, type Tone } from "../components/ui/badge";
import { Card, CardHeader } from "../components/ui/card";
import { EmptyState, ErrorState, Skeleton } from "../components/ui/misc";
import { useSession } from "../lib/auth";
import { useOverview } from "../lib/queries";
import { countsOf, factOf, rowsOf, tableOf } from "../lib/table";
import { cn, formatDate, greeting, relativeDays } from "../lib/utils";

const SUGGESTIONS = [
  "Me dá um panorama de hoje",
  "Quais ordens estão atrasadas?",
  "Por que o pedido 4500001 não faturou?",
  "Quais faturas estão bloqueadas?",
];

function AskBox() {
  const navigate = useNavigate();
  const [text, setText] = useState("");
  const ask = (q: string) => q.trim() && navigate({ to: "/assistente", search: { q: q.trim() } });
  const submit = (e: FormEvent) => {
    e.preventDefault();
    ask(text);
  };
  return (
    <div className="rounded-2xl border border-zinc-200 bg-white p-2 shadow-sm dark:border-zinc-800 dark:bg-zinc-900">
      <form onSubmit={submit} className="flex items-center gap-2">
        <Sparkles className="ml-2 size-5 shrink-0 text-brand-500" />
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Pergunte ao Raio-X sobre pedidos, ordens ou faturas…"
          className="h-11 min-w-0 flex-1 bg-transparent text-[0.9375rem] outline-none placeholder:text-zinc-400"
        />
        <button
          type="submit"
          aria-label="Perguntar"
          disabled={!text.trim()}
          className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-brand-600 text-white transition hover:bg-brand-700 disabled:bg-zinc-200 disabled:text-zinc-400 dark:disabled:bg-zinc-800"
        >
          <ArrowUp className="size-4" />
        </button>
      </form>
      <div className="flex flex-wrap gap-1.5 px-2 pt-1 pb-1.5">
        {SUGGESTIONS.map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => ask(s)}
            className="rounded-full border border-zinc-200 px-3 py-1 text-xs text-zinc-600 transition hover:border-brand-300 hover:bg-brand-50 hover:text-brand-700 dark:border-zinc-700 dark:text-zinc-400 dark:hover:border-brand-700 dark:hover:bg-brand-900/30 dark:hover:text-brand-200"
          >
            {s}
          </button>
        ))}
      </div>
    </div>
  );
}

const TONE_STYLE: Record<"critical" | "serious" | "warning" | "brand", string> = {
  critical: "bg-red-50 text-red-600 dark:bg-red-950/60 dark:text-red-400",
  serious: "bg-orange-50 text-orange-600 dark:bg-orange-950/60 dark:text-orange-400",
  warning: "bg-amber-50 text-amber-600 dark:bg-amber-950/60 dark:text-amber-400",
  brand: "bg-brand-50 text-brand-600 dark:bg-brand-900/40 dark:text-brand-300",
};

function KpiTile({
  label,
  value,
  hint,
  icon: Icon,
  tone,
  to,
  search,
  loading,
}: {
  label: string;
  value?: number;
  hint?: string;
  icon: LucideIcon;
  tone: keyof typeof TONE_STYLE;
  to: string;
  search?: Record<string, string>;
  loading: boolean;
}) {
  return (
    <Link
      to={to}
      search={search as never}
      className="group rounded-xl border border-zinc-200/80 bg-white p-4 shadow-xs transition hover:border-zinc-300 hover:shadow-sm dark:border-zinc-800 dark:bg-zinc-900 dark:hover:border-zinc-700"
    >
      <div className="flex items-center justify-between">
        <span className="text-sm text-zinc-500 dark:text-zinc-400">{label}</span>
        <span className={cn("flex size-8 items-center justify-center rounded-lg", TONE_STYLE[tone])}>
          <Icon className="size-4" />
        </span>
      </div>
      {loading ? (
        <Skeleton className="mt-3 h-8 w-16" />
      ) : (
        <p className="mt-2 text-3xl font-semibold tracking-tight tabular-nums">{value ?? "—"}</p>
      )}
      <p className="mt-1 flex items-center gap-1 text-xs text-zinc-500 dark:text-zinc-400">
        {hint}
        <ChevronRight className="ml-auto size-3.5 opacity-0 transition group-hover:opacity-100" />
      </p>
    </Link>
  );
}

interface AttentionItem {
  key: string;
  module: "PP" | "SD" | "MM";
  title: string;
  subtitle: string;
  badge: { label: string; tone: Tone };
  to: string;
  weight: number;
}

export function HomePage() {
  const session = useSession();
  const { data, isLoading, error, refetch } = useOverview();

  const orders = rowsOf(tableOf(data?.production.result, "orders"));
  const sales = rowsOf(tableOf(data?.sales.result, "salesOrders"));
  const invoices = rowsOf(tableOf(data?.purchasing.result, "invoices"));
  const flags = countsOf(data?.production.result, "flag");
  const situations = countsOf(data?.production.result, "situation");
  const stages = countsOf(data?.sales.result, "stage");
  const lateOrders = orders.filter((o) => /LATE_(START|FINISH)/.test(o.flagCodes ?? ""));
  const overdueInvoices = invoices.filter((i) => Number(i.daysToDue) < 0);

  const attention: AttentionItem[] = [
    ...overdueInvoices.map((i) => ({
      key: `mm-${i.invoice}`,
      module: "MM" as const,
      title: `Fatura ${i.invoice} bloqueada e vencida ${relativeDays(Number(i.daysToDue))}`,
      subtitle: `${i.vendor} · ${i.grossAmount} · ${i.reason}`,
      badge: { label: "Vencida", tone: "critical" as Tone },
      to: `/compras/faturas/${i.invoice}/${i.fiscalYear}`,
      weight: 1000 - Number(i.daysToDue),
    })),
    ...lateOrders.map((o) => ({
      key: `pp-${o.order}`,
      module: "PP" as const,
      title: `Ordem ${o.order} ${Number(o.delayDays) > 0 ? `atrasada ${o.delayDays} dia(s)` : "com início atrasado"}`,
      subtitle: `${o.description} · ${o.flags}`,
      badge: { label: "Atrasada", tone: "critical" as Tone },
      to: `/producao/ordens/${o.order}`,
      weight: 500 + Number(o.delayDays),
    })),
    ...sales
      .filter((s) => (s.requestedDate ?? "") < new Date().toISOString().slice(0, 10))
      .map((s) => ({
        key: `sd-${s.salesOrder}`,
        module: "SD" as const,
        title: `Pedido ${s.salesOrder} passou da data pedida pelo cliente`,
        subtitle: `${s.customer} · ${s.netValue} · ${s.reason}`,
        badge: { label: s.stage ?? "", tone: "warning" as Tone },
        to: `/vendas/pedidos/${s.salesOrder}`,
        weight: 400,
      })),
    ...orders
      .filter((o) => (o.flagCodes ?? "").includes("MISSING_PARTS") && !lateOrders.includes(o))
      .map((o) => ({
        key: `pp-mp-${o.order}`,
        module: "PP" as const,
        title: `Ordem ${o.order} com falta de material`,
        subtitle: `${o.description} · fim ${formatDate(o.scheduledFinish ?? "")}`,
        badge: { label: "Falta de material", tone: "serious" as Tone },
        to: `/producao/ordens/${o.order}`,
        weight: 300,
      })),
  ]
    .sort((a, b) => b.weight - a.weight)
    .slice(0, 7);

  const today = new Date().toLocaleDateString("pt-BR", { weekday: "long", day: "numeric", month: "long" });

  return (
    <div className="space-y-8">
      <section className="grid gap-6 lg:grid-cols-[1fr_minmax(0,34rem)] lg:items-end">
        <div className="min-w-0">
          <p className="text-sm text-zinc-500 first-letter:uppercase dark:text-zinc-400">{today}</p>
          <h1 className="mt-1 text-3xl font-semibold tracking-tight">
            {greeting()}, {session.me.user.charAt(0) + session.me.user.slice(1).toLowerCase()}
          </h1>
          <p className="mt-1 text-zinc-500 dark:text-zinc-400">
            {isLoading
              ? "Consultando o SAP…"
              : attention.length > 0
                ? `${attention.length} ${attention.length === 1 ? "item precisa" : "itens precisam"} da sua atenção hoje.`
                : "Nada crítico por aqui hoje."}
          </p>
        </div>
        <AskBox />
      </section>

      {error ? (
        <Card>
          <ErrorState error={error} onRetry={() => refetch()} />
        </Card>
      ) : (
        <>
          <section className="grid grid-cols-2 gap-3 lg:grid-cols-4">
            <KpiTile
              label="Ordens atrasadas"
              value={data?.production.result ? lateOrders.length : undefined}
              hint={data?.production.error ? "Sem autorização" : `Centro ${data?.plant ?? "…"}`}
              icon={Clock}
              tone="critical"
              to="/producao"
              search={{ filtro: "LATE" }}
              loading={isLoading}
            />
            <KpiTile
              label="Falta de material"
              value={data?.production.result ? (flags.MISSING_PARTS ?? 0) : undefined}
              hint="Ordens com componentes faltando"
              icon={PackageX}
              tone="serious"
              to="/producao"
              search={{ filtro: "MISSING_PARTS" }}
              loading={isLoading}
            />
            <KpiTile
              label="Pedidos travados"
              value={data?.sales.result ? Number(factOf(data.sales.result, "total")) : undefined}
              hint={data?.sales.error ? "Sem autorização" : `${factOf(data?.sales.result, "totalValue") ?? ""} parados`}
              icon={ShoppingCart}
              tone="warning"
              to="/vendas"
              loading={isLoading}
            />
            <KpiTile
              label="Faturas bloqueadas"
              value={data?.purchasing.result ? Number(factOf(data.purchasing.result, "total")) : undefined}
              hint={
                data?.purchasing.error
                  ? "Sem autorização"
                  : `${overdueInvoices.length} vencida(s) · ${factOf(data?.purchasing.result, "totalAmount") ?? ""}`
              }
              icon={Receipt}
              tone="brand"
              to="/compras"
              loading={isLoading}
            />
          </section>

          <section className="grid gap-6 xl:grid-cols-[minmax(0,1.5fr)_minmax(22rem,1fr)]">
            <Card className="min-w-0">
              <CardHeader
                icon={<AlertOctagon />}
                title="Precisa de atenção agora"
                description="Ordenado por impacto: vencimentos, atrasos e prazos do cliente"
              />
              {isLoading ? (
                <div className="space-y-3 px-5 pb-5">
                  {[0, 1, 2, 3].map((i) => (
                    <Skeleton key={i} className="h-12" />
                  ))}
                </div>
              ) : attention.length === 0 ? (
                <EmptyState title="Tudo em dia" description="Nenhuma pendência crítica encontrada." />
              ) : (
                <ul className="divide-y divide-zinc-100 pb-2 dark:divide-zinc-800">
                  {attention.map((item) => {
                    const meta = MODULE_META[item.module]!;
                    return (
                      <li key={item.key}>
                        <Link
                          to={item.to}
                          className="flex items-center gap-3 px-5 py-3 transition hover:bg-zinc-50 dark:hover:bg-zinc-800/40"
                        >
                          <span
                            className={cn("flex size-9 shrink-0 items-center justify-center rounded-lg", meta.color)}
                          >
                            <meta.icon className="size-4" />
                          </span>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-sm font-medium">{item.title}</p>
                            <p className="truncate text-xs text-zinc-500 dark:text-zinc-400">{item.subtitle}</p>
                          </div>
                          <Badge tone={item.badge.tone} className="hidden sm:inline-flex">
                            {item.badge.label}
                          </Badge>
                          <ChevronRight className="size-4 text-zinc-300" />
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              )}
            </Card>

            <div className="grid min-w-0 gap-6 md:grid-cols-2 xl:grid-cols-1">
              <Card className="min-w-0">
                <CardHeader
                  icon={<Factory />}
                  title="Ordens por situação"
                  description={`Centro ${data?.plant ?? ""} · ${factOf(data?.production.result, "total") ?? "…"} ordens`}
                  action={
                    <Link
                      to="/producao"
                      className="text-xs font-medium text-brand-600 hover:underline dark:text-brand-400"
                    >
                      Ver todas
                    </Link>
                  }
                />
                <div className="px-3 pb-4">
                  {isLoading ? (
                    <Skeleton className="mx-2 h-32" />
                  ) : data?.production.error ? (
                    <EmptyState title="Sem autorização para produção" />
                  ) : (
                    <BarList
                      ariaLabel="Ordens de produção por situação"
                      unit={["ordem", "ordens"]}
                      data={Object.entries(situations)
                        .sort((a, b) => b[1] - a[1])
                        .map(([k, v]) => ({ key: k, label: PP_SITUATION_LABELS[k as PpSituation] ?? k, value: v }))}
                    />
                  )}
                </div>
              </Card>
              <Card className="min-w-0">
                <CardHeader
                  icon={<ShoppingCart />}
                  title="Pedidos travados por etapa"
                  description={
                    factOf(data?.sales.result, "totalValue")
                      ? `${factOf(data?.sales.result, "totalValue")} parados`
                      : undefined
                  }
                  action={
                    <Link
                      to="/vendas"
                      className="text-xs font-medium text-brand-600 hover:underline dark:text-brand-400"
                    >
                      Ver pedidos
                    </Link>
                  }
                />
                <div className="px-3 pb-4">
                  {isLoading ? (
                    <Skeleton className="mx-2 h-24" />
                  ) : data?.sales.error ? (
                    <EmptyState title="Sem autorização para vendas" />
                  ) : (
                    <BarList
                      ariaLabel="Pedidos de venda travados por etapa"
                      unit={["pedido", "pedidos"]}
                      data={Object.entries(SD_STAGE_LABELS).map(([k, label]) => ({
                        key: k,
                        label,
                        value: stages[k] ?? 0,
                      }))}
                    />
                  )}
                </div>
              </Card>
            </div>
          </section>

          <Link
            to="/assistente"
            className="group flex items-center gap-4 rounded-xl border border-brand-200 bg-gradient-to-r from-brand-50 to-white p-5 transition hover:border-brand-300 dark:border-brand-900 dark:from-brand-950/60 dark:to-zinc-900"
          >
            <span className="flex size-10 items-center justify-center rounded-xl bg-brand-600 text-white">
              <Sparkles className="size-5" />
            </span>
            <div className="flex-1">
              <p className="font-medium">Não achou o que procura?</p>
              <p className="text-sm text-zinc-600 dark:text-zinc-400">
                Pergunte ao assistente. Ele consulta o SAP, cruza os documentos e explica o que fazer.
              </p>
            </div>
            <ArrowRight className="size-5 text-brand-600 transition group-hover:translate-x-0.5" />
          </Link>
        </>
      )}
    </div>
  );
}
