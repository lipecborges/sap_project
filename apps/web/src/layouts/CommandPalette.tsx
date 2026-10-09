import { useNavigate } from "@tanstack/react-router";
import { Command } from "cmdk";
import { ArrowRight, FileSearch, Sparkles } from "lucide-react";
import { Dialog } from "radix-ui";
import { useEffect, useMemo, useState } from "react";
import { MODULE_META, objectRoute } from "../components/domain/objects";
import { useSession } from "../lib/auth";
import { DOCUMENT_LABEL, detectDocuments } from "../lib/documents";
import { MAIN_NAV, PROCESS_NAV, TOOLS_NAV } from "./nav";

export function useCommandPalette() {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setOpen((o) => !o);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);
  return { open, setOpen };
}

const itemClass =
  "flex cursor-pointer items-center gap-3 rounded-lg px-3 py-2 text-sm text-zinc-700 data-[selected=true]:bg-zinc-100 data-[selected=true]:text-zinc-950 dark:text-zinc-300 dark:data-[selected=true]:bg-zinc-800 dark:data-[selected=true]:text-white [&_svg]:size-4 [&_svg]:shrink-0 [&_svg]:text-zinc-400";

export function CommandPalette({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const navigate = useNavigate();
  const session = useSession();
  const [query, setQuery] = useState("");
  const docs = useMemo(() => detectDocuments(query), [query]);

  const go = (to: string, search?: Record<string, string>) => {
    onOpenChange(false);
    setQuery("");
    navigate({ to, search: search as never });
  };

  const nav = [...MAIN_NAV, ...PROCESS_NAV, ...TOOLS_NAV].filter(
    (n) => !n.requires || session.me.diagnostics.includes(n.requires),
  );

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-zinc-950/40 backdrop-blur-[2px]" />
        <Dialog.Content className="fixed top-[12vh] left-1/2 z-50 w-[calc(100%-2rem)] max-w-xl -translate-x-1/2 overflow-hidden rounded-xl border border-zinc-200 bg-white shadow-2xl dark:border-zinc-800 dark:bg-zinc-900">
          <Dialog.Title className="sr-only">Buscar ou perguntar</Dialog.Title>
          <Dialog.Description className="sr-only">
            Digite um número de documento, uma página ou uma pergunta
          </Dialog.Description>
          <Command shouldFilter={docs.length === 0} loop>
            <div className="flex items-center gap-2 border-b border-zinc-200 px-4 dark:border-zinc-800">
              <FileSearch className="size-4 text-zinc-400" />
              <Command.Input
                value={query}
                onValueChange={setQuery}
                placeholder="Nº da ordem, pedido ou fatura… ou pergunte algo"
                className="h-12 w-full bg-transparent text-sm outline-none placeholder:text-zinc-400"
              />
            </div>
            <Command.List className="max-h-[60vh] overflow-y-auto p-2">
              <Command.Empty className="px-3 py-6 text-center text-sm text-zinc-500">Nada encontrado.</Command.Empty>
              {docs.length > 0 && (
                <Command.Group
                  heading="Documentos"
                  className="text-xs text-zinc-500 [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-1.5"
                >
                  {docs.map((d) => {
                    const id = d.kind === "SUPPLIER_INVOICE" ? `${d.id}/${d.year}` : d.id;
                    const route = objectRoute(d.kind, id);
                    const Icon =
                      MODULE_META[d.kind === "PRODUCTION_ORDER" ? "PP" : d.kind === "SALES_ORDER" ? "SD" : "MM"]!.icon;
                    return route ? (
                      <Command.Item
                        key={`${d.kind}-${id}`}
                        value={`doc-${id}`}
                        onSelect={() => go(route)}
                        className={itemClass}
                      >
                        <Icon />
                        <span className="flex-1">
                          Abrir {DOCUMENT_LABEL[d.kind].toLowerCase()} <strong className="font-mono">{id}</strong>
                        </span>
                        <ArrowRight />
                      </Command.Item>
                    ) : null;
                  })}
                </Command.Group>
              )}
              {query.trim().length > 2 && (
                <Command.Group
                  heading="Assistente"
                  className="text-xs text-zinc-500 [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-1.5"
                >
                  <Command.Item
                    value={`ask-${query}`}
                    onSelect={() => go("/assistente", { q: query.trim() })}
                    className={itemClass}
                    forceMount
                  >
                    <Sparkles className="!text-brand-500" />
                    <span className="flex-1 truncate">
                      Perguntar: <span className="text-zinc-500">{query}</span>
                    </span>
                  </Command.Item>
                </Command.Group>
              )}
              <Command.Group
                heading="Ir para"
                className="text-xs text-zinc-500 [&_[cmdk-group-heading]]:px-3 [&_[cmdk-group-heading]]:py-1.5"
              >
                {nav.map((n) => (
                  <Command.Item key={n.to} value={`nav ${n.label}`} onSelect={() => go(n.to)} className={itemClass}>
                    <n.icon />
                    {n.label}
                  </Command.Item>
                ))}
              </Command.Group>
            </Command.List>
          </Command>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
