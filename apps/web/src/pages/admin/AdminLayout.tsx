import { Link, Outlet, useRouterState } from "@tanstack/react-router";
import { ADMIN_NAV, isActivePath } from "../../layouts/nav";
import { cn } from "../../lib/utils";

/** Container das páginas de administração. No desktop a navegação fica no menu lateral; no celular, em abas. */
export function AdminLayout() {
  const pathname = useRouterState({ select: (s) => s.location.pathname });
  return (
    <div>
      <nav
        aria-label="Seções da administração"
        className="-mx-4 mb-6 flex gap-1 overflow-x-auto border-b border-zinc-200 px-4 lg:hidden dark:border-zinc-800"
      >
        {ADMIN_NAV.map((n) => {
          const active = isActivePath(pathname, n.to);
          return (
            <Link
              key={n.to}
              to={n.to}
              aria-current={active ? "page" : undefined}
              className={cn(
                "-mb-px flex shrink-0 items-center gap-1.5 border-b-2 px-3 py-2.5 text-sm font-medium",
                active
                  ? "border-brand-600 text-brand-700 dark:border-brand-400 dark:text-brand-300"
                  : "border-transparent text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100",
              )}
            >
              <n.icon className="size-4" />
              {n.label}
            </Link>
          );
        })}
      </nav>
      <Outlet />
    </div>
  );
}
