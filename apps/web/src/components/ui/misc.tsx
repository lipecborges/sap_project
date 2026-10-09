import { AlertTriangle, Inbox, Lock, RefreshCw } from "lucide-react";
import type { ReactNode } from "react";
import type { RequestError } from "../../lib/api";
import { cn } from "../../lib/utils";
import { Button } from "./button";

export function Skeleton({ className }: { className?: string }) {
  return <div className={cn("animate-pulse rounded-md bg-zinc-200/70 dark:bg-zinc-800", className)} />;
}

export function Kbd({ children }: { children: ReactNode }) {
  return (
    <kbd className="rounded border border-zinc-200 bg-zinc-50 px-1.5 font-mono text-[0.6875rem] text-zinc-500 dark:border-zinc-700 dark:bg-zinc-800 dark:text-zinc-400">
      {children}
    </kbd>
  );
}

export function Progress({
  value,
  tone = "brand",
  className,
}: {
  value: number;
  tone?: "brand" | "good" | "warning" | "critical";
  className?: string;
}) {
  const clamped = Math.max(0, Math.min(100, value));
  const color = { brand: "bg-brand-500", good: "bg-emerald-500", warning: "bg-amber-500", critical: "bg-red-500" }[
    tone
  ];
  return (
    <div
      className={cn("h-1.5 w-full overflow-hidden rounded-full bg-zinc-200/80 dark:bg-zinc-800", className)}
      role="progressbar"
      aria-valuenow={clamped}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div className={cn("h-full rounded-full transition-[width]", color)} style={{ width: `${clamped}%` }} />
    </div>
  );
}

export function EmptyState({ title, description, icon }: { title: string; description?: string; icon?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-12 text-center">
      <div className="mb-3 flex size-10 items-center justify-center rounded-full bg-zinc-100 text-zinc-400 dark:bg-zinc-800 [&_svg]:size-5">
        {icon ?? <Inbox />}
      </div>
      <p className="text-sm font-medium">{title}</p>
      {description && <p className="mt-1 max-w-sm text-sm text-zinc-500 dark:text-zinc-400">{description}</p>}
    </div>
  );
}

export function ErrorState({ error, onRetry }: { error: unknown; onRetry?: () => void }) {
  const err = error as Partial<RequestError> | undefined;
  const forbidden = err?.code === "NOT_AUTHORIZED";
  return (
    <div className="flex flex-col items-center justify-center px-6 py-10 text-center">
      <div
        className={cn(
          "mb-3 flex size-10 items-center justify-center rounded-full [&_svg]:size-5",
          forbidden ? "bg-zinc-100 text-zinc-500 dark:bg-zinc-800" : "bg-red-50 text-red-600 dark:bg-red-950/50",
        )}
      >
        {forbidden ? <Lock /> : <AlertTriangle />}
      </div>
      <p className="text-sm font-medium">{forbidden ? "Sem autorização" : "Não foi possível carregar"}</p>
      <p className="mt-1 max-w-sm text-sm text-zinc-500 dark:text-zinc-400">{err?.message ?? "Erro inesperado"}</p>
      {onRetry && !forbidden && (
        <Button variant="outline" size="sm" className="mt-4" onClick={onRetry}>
          <RefreshCw /> Tentar de novo
        </Button>
      )}
    </div>
  );
}
