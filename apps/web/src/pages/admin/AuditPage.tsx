import type { AuditEventDto } from "@raiox/contracts";
import { ChevronRight, Download, Filter, Loader2, ScrollText, X } from "lucide-react";
import { type FormEvent, useMemo, useState } from "react";
import { Badge } from "../../components/ui/badge";
import { Button, buttonClasses } from "../../components/ui/button";
import { Card } from "../../components/ui/card";
import { inputClass, tableHeadClass, tdClass, thClass } from "../../components/ui/form";
import { EmptyState, ErrorState, Skeleton } from "../../components/ui/misc";
import { PageHeader } from "../../components/ui/page";
import {
  type AuditFilters,
  auditCsvUrl,
  EMPTY_AUDIT_FILTERS,
  formatDateTime,
  formatMs,
  hasAuditFilters,
  outcomeLabel,
  outcomeTone,
} from "../../lib/admin";
import { useAdminAudit } from "../../lib/admin-queries";
import { cn } from "../../lib/utils";

function Details({ event }: { event: AuditEventDto }) {
  const params = event.details && Object.keys(event.details).length > 0 ? event.details : undefined;
  return (
    <div className="grid gap-4 bg-zinc-50/70 px-5 py-4 text-sm sm:grid-cols-[1fr_1.4fr] dark:bg-zinc-950/40">
      <dl className="grid grid-cols-2 gap-x-4 gap-y-2.5 self-start">
        {(
          [
            ["Evento", `#${event.id}`],
            ["Sistema SAP", event.sapSystemId ?? "—"],
            ["Alvo", event.target ?? "—"],
            ["Status HTTP", event.httpStatus ?? "—"],
            ["Duração", event.durationMs !== null ? formatMs(event.durationMs) : "—"],
            ["IP", event.ip ?? "—"],
          ] as const
        ).map(([k, v]) => (
          <div key={k} className="min-w-0">
            <dt className="text-xs text-zinc-500">{k}</dt>
            <dd className="truncate font-mono text-[0.8125rem]" title={String(v)}>
              {v}
            </dd>
          </div>
        ))}
      </dl>
      <div className="min-w-0">
        <p className="text-xs text-zinc-500">Parâmetros</p>
        {params ? (
          <pre className="mt-1 max-h-56 overflow-auto rounded-lg border border-zinc-200 bg-white p-3 font-mono text-xs leading-relaxed dark:border-zinc-800 dark:bg-zinc-900">
            {JSON.stringify(params, null, 2)}
          </pre>
        ) : (
          <p className="mt-1 text-zinc-500">Sem parâmetros registrados.</p>
        )}
      </div>
    </div>
  );
}

export function AuditPage() {
  const [draft, setDraft] = useState<AuditFilters>(EMPTY_AUDIT_FILTERS);
  const [applied, setApplied] = useState<AuditFilters>(EMPTY_AUDIT_FILTERS);
  const [open, setOpen] = useState<Set<number>>(new Set());
  const query = useAdminAudit(applied);
  const events = useMemo(() => query.data?.pages.flatMap((p) => p.events) ?? [], [query.data]);
  const set = (key: keyof AuditFilters, value: string) => setDraft((d) => ({ ...d, [key]: value }));

  function apply(e: FormEvent) {
    e.preventDefault();
    setOpen(new Set());
    setApplied({ ...draft });
  }
  function clear() {
    setDraft(EMPTY_AUDIT_FILTERS);
    setApplied(EMPTY_AUDIT_FILTERS);
    setOpen(new Set());
  }
  const toggle = (id: number) =>
    setOpen((s) => {
      const next = new Set(s);
      if (!next.delete(id)) next.add(id);
      return next;
    });

  const filtered = hasAuditFilters(applied);

  return (
    <>
      <PageHeader
        title="Auditoria"
        description="Registro de logins, consultas e alterações administrativas."
        actions={
          <a href={auditCsvUrl(applied)} download className={buttonClasses({ variant: "outline" })}>
            <Download /> Exportar CSV
          </a>
        }
      />

      <Card>
        <form
          onSubmit={apply}
          className="grid grid-cols-2 gap-3 border-b border-zinc-100 p-4 lg:grid-cols-[1fr_1fr_9.5rem_9.5rem_auto] dark:border-zinc-800"
        >
          <label className="col-span-2 text-xs font-medium text-zinc-500 sm:col-span-1">
            Usuário
            <input
              className={cn(inputClass, "mt-1 h-9 font-mono uppercase")}
              value={draft.user}
              onChange={(e) => set("user", e.target.value)}
              placeholder="Todos"
              autoCapitalize="characters"
              spellCheck={false}
            />
          </label>
          <label className="col-span-2 text-xs font-medium text-zinc-500 sm:col-span-1">
            Ação
            <input
              className={cn(inputClass, "mt-1 h-9 font-mono")}
              value={draft.action}
              onChange={(e) => set("action", e.target.value)}
              placeholder="Ex.: LOGIN, ADMIN_USER_UPDATE"
              spellCheck={false}
            />
          </label>
          <label className="text-xs font-medium text-zinc-500">
            De
            <input
              type="date"
              className={cn(inputClass, "mt-1 h-9")}
              value={draft.from}
              max={draft.to || undefined}
              onChange={(e) => set("from", e.target.value)}
            />
          </label>
          <label className="text-xs font-medium text-zinc-500">
            Até
            <input
              type="date"
              className={cn(inputClass, "mt-1 h-9")}
              value={draft.to}
              min={draft.from || undefined}
              onChange={(e) => set("to", e.target.value)}
            />
          </label>
          <div className="col-span-2 flex items-end gap-2 lg:col-span-1">
            <Button type="submit" size="md" className="flex-1 lg:flex-none">
              <Filter /> Filtrar
            </Button>
            {(hasAuditFilters(draft) || filtered) && (
              <Button variant="ghost" size="icon" onClick={clear} aria-label="Limpar filtros" type="button">
                <X />
              </Button>
            )}
          </div>
        </form>

        {query.isLoading ? (
          <div className="space-y-3 p-5" role="status" aria-busy="true" aria-label="Carregando auditoria">
            {[0, 1, 2, 3, 4].map((i) => (
              <Skeleton key={i} className="h-9" />
            ))}
          </div>
        ) : query.error ? (
          <ErrorState error={query.error} onRetry={() => query.refetch()} />
        ) : events.length === 0 ? (
          <EmptyState
            icon={<ScrollText />}
            title={filtered ? "Nenhum evento com esses filtros" : "Nenhum evento registrado"}
            description={filtered ? "Ajuste o período, o usuário ou a ação." : undefined}
          />
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead>
                  <tr className={tableHeadClass}>
                    <th scope="col" className={cn(thClass, "w-8 !pr-0")}>
                      <span className="sr-only">Detalhes</span>
                    </th>
                    <th scope="col" className={cn(thClass, "md:hidden")}>
                      Evento
                    </th>
                    <th scope="col" className={cn(thClass, "hidden md:table-cell")}>
                      Quando
                    </th>
                    <th scope="col" className={cn(thClass, "hidden md:table-cell")}>
                      Usuário
                    </th>
                    <th scope="col" className={cn(thClass, "hidden md:table-cell")}>
                      Ação
                    </th>
                    <th scope="col" className={cn(thClass, "hidden lg:table-cell")}>
                      Alvo
                    </th>
                    <th scope="col" className={thClass}>
                      Resultado
                    </th>
                    <th scope="col" className={cn(thClass, "hidden text-right md:table-cell")}>
                      Duração
                    </th>
                  </tr>
                </thead>
                {events.map((ev) => {
                  const expanded = open.has(ev.id);
                  return (
                    <tbody key={ev.id} className="border-b border-zinc-100 last:border-0 dark:border-zinc-800/70">
                      <tr
                        className="cursor-pointer hover:bg-zinc-50/70 dark:hover:bg-zinc-800/30"
                        onClick={() => toggle(ev.id)}
                      >
                        <td className={cn(tdClass, "!pr-0")}>
                          <button
                            type="button"
                            aria-expanded={expanded}
                            aria-label={`${expanded ? "Ocultar" : "Ver"} detalhes do evento ${ev.id}`}
                            onClick={(e) => {
                              e.stopPropagation();
                              toggle(ev.id);
                            }}
                            className="flex size-6 items-center justify-center rounded text-zinc-400 hover:text-zinc-700"
                          >
                            <ChevronRight className={cn("size-4 transition", expanded && "rotate-90")} />
                          </button>
                        </td>
                        <td className={cn(tdClass, "min-w-0 md:hidden")}>
                          <p className="break-all font-mono text-[0.8125rem] font-medium">{ev.action}</p>
                          <p className="mt-0.5 text-xs text-zinc-500">
                            {ev.sapUser ?? "—"} · {formatDateTime(ev.at)}
                          </p>
                        </td>
                        <td
                          className={cn(
                            tdClass,
                            "hidden whitespace-nowrap text-zinc-600 tabular-nums md:table-cell dark:text-zinc-400",
                          )}
                        >
                          {formatDateTime(ev.at)}
                        </td>
                        <td className={cn(tdClass, "hidden font-mono text-[0.8125rem] md:table-cell")}>
                          {ev.sapUser ?? "—"}
                        </td>
                        <td className={cn(tdClass, "hidden font-mono text-[0.8125rem] md:table-cell")}>{ev.action}</td>
                        <td
                          className={cn(tdClass, "hidden max-w-48 truncate text-zinc-500 lg:table-cell")}
                          title={ev.target ?? undefined}
                        >
                          {ev.target ?? "—"}
                        </td>
                        <td className={tdClass}>
                          <Badge tone={outcomeTone(ev.outcome)}>{outcomeLabel(ev.outcome)}</Badge>
                        </td>
                        <td
                          className={cn(
                            tdClass,
                            "hidden text-right whitespace-nowrap tabular-nums text-zinc-500 md:table-cell",
                          )}
                        >
                          {ev.durationMs !== null ? formatMs(ev.durationMs) : "—"}
                        </td>
                      </tr>
                      {expanded && (
                        <tr>
                          <td colSpan={7} className="p-0">
                            <Details event={ev} />
                          </td>
                        </tr>
                      )}
                    </tbody>
                  );
                })}
              </table>
            </div>
            <div className="flex items-center justify-between gap-3 border-t border-zinc-100 px-5 py-3 dark:border-zinc-800">
              <p className="text-xs text-zinc-500">{events.length} eventos carregados</p>
              {query.hasNextPage ? (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => query.fetchNextPage()}
                  disabled={query.isFetchingNextPage}
                >
                  {query.isFetchingNextPage && <Loader2 className="animate-spin" />}
                  Carregar mais
                </Button>
              ) : (
                <p className="text-xs text-zinc-400">Fim do registro</p>
              )}
            </div>
          </>
        )}
      </Card>
    </>
  );
}
