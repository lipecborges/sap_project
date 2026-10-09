import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { ChevronDown, Info, Laptop, LogOut, Menu, Moon, Search, Server, ShieldCheck, Sun, X } from "lucide-react";
import { Dialog, DropdownMenu } from "radix-ui";
import { useState } from "react";
import { Kbd } from "../components/ui/misc";
import { useAuth, useSession } from "../lib/auth";
import { useOverview } from "../lib/queries";
import { countsOf, factOf } from "../lib/table";
import { useTheme } from "../lib/theme";
import { cn } from "../lib/utils";
import { CommandPalette, useCommandPalette } from "./CommandPalette";
import { ADMIN_ROOT, isActivePath, type NavItem, navSections } from "./nav";

function useNavBadges(): Record<string, number | undefined> {
  const { data } = useOverview();
  const flags = countsOf(data?.production.result, "flag");
  const late = (flags.LATE_FINISH ?? 0) + (flags.LATE_START ?? 0);
  return {
    "/producao": late || undefined,
    "/vendas": Number(factOf(data?.sales.result, "total")) || undefined,
    "/compras": Number(factOf(data?.purchasing.result, "total")) || undefined,
  };
}

function NavLink({ item, badge, onNavigate }: { item: NavItem; badge?: number; onNavigate?: () => void }) {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const active = isActivePath(pathname, item.to);
  return (
    <Link
      to={item.to}
      onClick={onNavigate}
      className={cn(
        "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
        active
          ? "bg-white text-zinc-950 shadow-xs ring-1 ring-zinc-200 dark:bg-zinc-800 dark:text-white dark:ring-zinc-700"
          : "text-zinc-600 hover:bg-zinc-200/60 hover:text-zinc-950 dark:text-zinc-400 dark:hover:bg-zinc-800/60 dark:hover:text-white",
      )}
    >
      <item.icon
        className={cn(
          "size-4",
          active ? "text-brand-600 dark:text-brand-400" : "text-zinc-400 group-hover:text-zinc-600",
        )}
      />
      <span className="flex-1">{item.label}</span>
      {item.to === "/assistente" && (
        <span className="rounded bg-brand-600 px-1.5 py-px text-[0.625rem] font-semibold tracking-wide text-white">
          IA
        </span>
      )}
      {badge !== undefined && (
        <span className="min-w-5 rounded-full bg-zinc-200 px-1.5 text-center text-xs font-semibold text-zinc-700 tabular-nums dark:bg-zinc-700 dark:text-zinc-200">
          {badge}
        </span>
      )}
    </Link>
  );
}

/** "Administração" com as subpáginas, que se expandem quando a área está aberta. */
function AdminNav({ items, onNavigate }: { items: NavItem[]; onNavigate?: () => void }) {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const inAdmin = isActivePath(pathname, ADMIN_ROOT.to);
  return (
    <nav className="space-y-1" aria-label="Administração">
      <p className="px-3 pb-1 text-xs font-medium text-zinc-400">Gestão</p>
      <Link
        to={items[0]?.to ?? ADMIN_ROOT.to}
        onClick={onNavigate}
        className={cn(
          "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium transition-colors",
          inAdmin
            ? "text-zinc-950 dark:text-white"
            : "text-zinc-600 hover:bg-zinc-200/60 hover:text-zinc-950 dark:text-zinc-400 dark:hover:bg-zinc-800/60 dark:hover:text-white",
        )}
      >
        <ADMIN_ROOT.icon
          className={cn(
            "size-4",
            inAdmin ? "text-brand-600 dark:text-brand-400" : "text-zinc-400 group-hover:text-zinc-600",
          )}
        />
        <span className="flex-1">{ADMIN_ROOT.label}</span>
        <ChevronDown className={cn("size-3.5 text-zinc-400 transition", !inAdmin && "-rotate-90")} />
      </Link>
      {inAdmin && (
        <div className="ml-5 space-y-0.5 border-l border-zinc-200 pl-2 dark:border-zinc-800">
          {items.map((n) => {
            const active = isActivePath(pathname, n.to);
            return (
              <Link
                key={n.to}
                to={n.to}
                onClick={onNavigate}
                aria-current={active ? "page" : undefined}
                className={cn(
                  "flex items-center gap-2.5 rounded-md px-2.5 py-1.5 text-sm transition-colors",
                  active
                    ? "bg-white font-medium text-zinc-950 shadow-xs ring-1 ring-zinc-200 dark:bg-zinc-800 dark:text-white dark:ring-zinc-700"
                    : "text-zinc-600 hover:bg-zinc-200/60 dark:text-zinc-400 dark:hover:bg-zinc-800/60",
                )}
              >
                <n.icon className="size-3.5 text-zinc-400" />
                {n.label}
              </Link>
            );
          })}
        </div>
      )}
    </nav>
  );
}

function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const session = useSession();
  const badges = useNavBadges();
  const nav = navSections(session.me);
  const { sap } = session;
  return (
    <div className="flex h-full flex-col gap-6 px-3 py-4">
      <Link to="/" onClick={onNavigate} className="flex items-center gap-2.5 px-2">
        <div className="flex size-8 items-center justify-center rounded-lg bg-gradient-to-br from-brand-500 to-brand-700 text-sm font-bold text-white shadow-sm">
          RX
        </div>
        <div className="leading-tight">
          <div className="text-sm font-semibold">Raio-X</div>
          <div className="text-xs text-zinc-500">Diagnóstico SAP</div>
        </div>
      </Link>

      <nav className="space-y-1">
        {nav.main.map((n) => (
          <NavLink key={n.to} item={n} onNavigate={onNavigate} />
        ))}
      </nav>
      <nav className="space-y-1">
        <p className="px-3 pb-1 text-xs font-medium text-zinc-400">Processos</p>
        {nav.process.map((n) => (
          <NavLink key={n.to} item={n} badge={badges[n.to]} onNavigate={onNavigate} />
        ))}
      </nav>
      <nav className="space-y-1">
        <p className="px-3 pb-1 text-xs font-medium text-zinc-400">Ferramentas</p>
        {nav.tools.map((n) => (
          <NavLink key={n.to} item={n} onNavigate={onNavigate} />
        ))}
      </nav>
      {nav.admin.length > 0 && <AdminNav items={nav.admin} onNavigate={onNavigate} />}

      <div className="mt-auto rounded-lg border border-zinc-200 bg-white p-3 text-xs dark:border-zinc-800 dark:bg-zinc-900">
        <p className="mb-1.5 flex items-center gap-1.5 truncate text-zinc-500" title="Sistema SAP desta sessão">
          <Server className="size-3.5 shrink-0" />
          <span className="truncate">{session.me.system.name}</span>
        </p>
        <div className="flex items-center gap-2">
          <span className="size-2 rounded-full bg-emerald-500 shadow-[0_0_0_3px] shadow-emerald-500/20" />
          <span className="font-medium text-zinc-800 dark:text-zinc-200">
            {sap.system.sid}/{sap.system.client}
          </span>
          <span className="text-zinc-400">{sap.system.release}</span>
        </div>
        <p className="mt-1 text-zinc-500">
          Add-on {sap.addonVersion} · {session.app.deploymentMode === "cloud" ? "Cloud" : "Self-hosted"}
        </p>
      </div>
    </div>
  );
}

function ThemeMenu() {
  const { choice, setChoice } = useTheme();
  const Icon = choice === "dark" ? Moon : choice === "light" ? Sun : Laptop;
  const options = [
    { value: "light", label: "Claro", icon: Sun },
    { value: "dark", label: "Escuro", icon: Moon },
    { value: "system", label: "Sistema", icon: Laptop },
  ] as const;
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger
        aria-label="Tema"
        className="flex size-9 items-center justify-center rounded-lg text-zinc-500 hover:bg-zinc-100 hover:text-zinc-900 dark:hover:bg-zinc-800 dark:hover:text-zinc-100"
      >
        <Icon className="size-4" />
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          align="end"
          sideOffset={6}
          className="z-50 min-w-36 rounded-lg border border-zinc-200 bg-white p-1 shadow-lg dark:border-zinc-800 dark:bg-zinc-900"
        >
          {options.map((o) => (
            <DropdownMenu.Item
              key={o.value}
              onSelect={() => setChoice(o.value)}
              className={cn(
                "flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm outline-none data-[highlighted]:bg-zinc-100 dark:data-[highlighted]:bg-zinc-800",
                choice === o.value && "font-medium text-brand-600 dark:text-brand-400",
              )}
            >
              <o.icon className="size-4" /> {o.label}
            </DropdownMenu.Item>
          ))}
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

function UserMenu() {
  const { logout } = useAuth();
  const session = useSession();
  const initials = session.me.user.slice(0, 2);
  return (
    <DropdownMenu.Root>
      <DropdownMenu.Trigger className="flex items-center gap-2 rounded-lg p-1 pr-2 hover:bg-zinc-100 dark:hover:bg-zinc-800">
        <span className="flex size-7 items-center justify-center rounded-full bg-zinc-900 text-xs font-semibold text-white dark:bg-zinc-100 dark:text-zinc-900">
          {initials}
        </span>
        <span className="hidden text-sm font-medium sm:block">{session.me.user}</span>
      </DropdownMenu.Trigger>
      <DropdownMenu.Portal>
        <DropdownMenu.Content
          align="end"
          sideOffset={6}
          className="z-50 min-w-56 rounded-lg border border-zinc-200 bg-white p-1 shadow-lg dark:border-zinc-800 dark:bg-zinc-900"
        >
          <div className="px-2 py-2">
            <p className="flex items-center gap-2 text-sm font-medium">
              {session.me.user}
              {session.me.role === "admin" && (
                <span className="inline-flex items-center gap-1 rounded bg-brand-50 px-1.5 py-px text-[0.6875rem] font-semibold text-brand-700 dark:bg-brand-900/40 dark:text-brand-200">
                  <ShieldCheck className="size-3" /> Admin
                </span>
              )}
            </p>
            <p className="mt-0.5 flex items-center gap-1 text-xs text-zinc-500">
              <Server className="size-3" /> {session.me.system.name}
            </p>
            <p className="mt-0.5 text-xs text-zinc-500">
              {session.me.diagnostics.length} diagnósticos liberados · idioma {session.me.language}
            </p>
          </div>
          <DropdownMenu.Separator className="my-1 h-px bg-zinc-200 dark:bg-zinc-800" />
          <DropdownMenu.Item
            onSelect={logout}
            className="flex cursor-pointer items-center gap-2 rounded-md px-2 py-1.5 text-sm outline-none data-[highlighted]:bg-zinc-100 dark:data-[highlighted]:bg-zinc-800"
          >
            <LogOut className="size-4" /> Sair
          </DropdownMenu.Item>
        </DropdownMenu.Content>
      </DropdownMenu.Portal>
    </DropdownMenu.Root>
  );
}

function MobileTabs() {
  const session = useSession();
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  const nav = navSections(session.me);
  const items = [...nav.main, ...nav.process];
  return (
    <nav
      className="fixed inset-x-0 bottom-0 z-30 grid border-t border-zinc-200 bg-white/95 pb-[env(safe-area-inset-bottom)] backdrop-blur lg:hidden dark:border-zinc-800 dark:bg-zinc-900/95"
      style={{ gridTemplateColumns: `repeat(${items.length}, minmax(0, 1fr))` }}
    >
      {items.map((n) => {
        const active = isActivePath(pathname, n.to);
        return (
          <Link
            key={n.to}
            to={n.to}
            className={cn(
              "flex flex-col items-center gap-0.5 py-2 text-[0.6875rem] font-medium",
              active ? "text-brand-600 dark:text-brand-400" : "text-zinc-500",
            )}
          >
            <n.icon className="size-5" />
            {n.label}
          </Link>
        );
      })}
    </nav>
  );
}

export function AppShell() {
  const palette = useCommandPalette();
  const [drawer, setDrawer] = useState(false);
  const { app, me } = useSession();
  const [dismissedNotice, setDismissedNotice] = useState<string>();
  return (
    <div className="flex min-h-full">
      <aside className="sticky top-0 hidden h-screen w-64 shrink-0 border-r border-zinc-200 bg-zinc-100/70 lg:block dark:border-zinc-800 dark:bg-zinc-900/40">
        <Sidebar />
      </aside>

      <Dialog.Root open={drawer} onOpenChange={setDrawer}>
        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-40 bg-zinc-950/40 lg:hidden" />
          <Dialog.Content className="fixed inset-y-0 left-0 z-50 w-72 bg-zinc-50 shadow-xl lg:hidden dark:bg-zinc-950">
            <Dialog.Title className="sr-only">Menu</Dialog.Title>
            <Dialog.Close className="absolute top-4 right-3 rounded-md p-1 text-zinc-500" aria-label="Fechar menu">
              <X className="size-5" />
            </Dialog.Close>
            <Sidebar onNavigate={() => setDrawer(false)} />
          </Dialog.Content>
        </Dialog.Portal>
      </Dialog.Root>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-20 flex h-14 items-center gap-2 border-b border-zinc-200 bg-zinc-50/85 px-4 backdrop-blur lg:px-6 dark:border-zinc-800 dark:bg-zinc-950/85">
          <button
            type="button"
            className="-ml-1 rounded-md p-1.5 text-zinc-600 lg:hidden"
            aria-label="Abrir menu"
            onClick={() => setDrawer(true)}
          >
            <Menu className="size-5" />
          </button>
          <button
            type="button"
            onClick={() => palette.setOpen(true)}
            className="flex h-9 min-w-0 flex-1 items-center gap-2 rounded-lg border border-zinc-200 bg-white px-3 text-sm text-zinc-400 shadow-xs hover:border-zinc-300 dark:border-zinc-800 dark:bg-zinc-900 dark:hover:border-zinc-700"
          >
            <Search className="size-4" />
            <span className="flex-1 truncate text-left">Buscar documento ou perguntar…</span>
            <span className="hidden gap-0.5 sm:flex">
              <Kbd>Ctrl</Kbd>
              <Kbd>K</Kbd>
            </span>
          </button>
          <div className="ml-auto flex items-center gap-1">
            <span
              className="hidden items-center gap-1.5 rounded-full border border-zinc-200 bg-white px-2.5 py-1 text-xs text-zinc-600 md:flex dark:border-zinc-800 dark:bg-zinc-900 dark:text-zinc-400"
              title={
                app.ai.provider === "demo"
                  ? "Sem modelo de IA configurado: respostas por regras locais"
                  : `Modelo ${app.ai.model ?? ""}`
              }
            >
              <span
                className={cn("size-1.5 rounded-full", app.ai.provider === "demo" ? "bg-amber-500" : "bg-emerald-500")}
              />
              IA {app.ai.provider === "demo" ? "demonstração" : "Claude"}
            </span>
            <ThemeMenu />
            <UserMenu />
          </div>
        </header>
        {me.notice && me.notice !== dismissedNotice && (
          <div
            role="status"
            className="flex items-start gap-3 border-b border-amber-200 bg-amber-50 px-4 py-2.5 text-sm text-amber-900 lg:px-6 dark:border-amber-900/60 dark:bg-amber-950/40 dark:text-amber-200"
          >
            <Info className="mt-0.5 size-4 shrink-0" />
            <p className="min-w-0 flex-1">{me.notice}</p>
            <button
              type="button"
              aria-label="Dispensar aviso"
              onClick={() => setDismissedNotice(me.notice)}
              className="-my-0.5 rounded p-1 hover:bg-amber-100 dark:hover:bg-amber-900/40"
            >
              <X className="size-4" />
            </button>
          </div>
        )}
        <main className="mx-auto w-full max-w-7xl flex-1 px-4 pt-6 pb-24 lg:px-8 lg:pb-12">
          <Outlet />
        </main>
      </div>

      <MobileTabs />
      <CommandPalette open={palette.open} onOpenChange={palette.setOpen} />
    </div>
  );
}
