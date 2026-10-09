import type { ReactNode, SelectHTMLAttributes } from "react";
import { cn } from "../../lib/utils";

export const inputClass =
  "block h-10 w-full rounded-lg border border-zinc-300 bg-white px-3 text-sm shadow-xs outline-none transition placeholder:text-zinc-400 focus:border-brand-500 focus:ring-4 focus:ring-brand-500/15 disabled:opacity-60 aria-[invalid=true]:border-red-400 dark:border-zinc-700 dark:bg-zinc-900";

/** Seta do seletor (o navegador não desenha a seta com appearance-none). */
export const SELECT_ARROW =
  "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%2371717a' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpath d='m6 9 6 6 6-6'/%3E%3C/svg%3E\")";

export function Select({ className, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      className={cn(
        inputClass,
        "appearance-none bg-[length:1rem] bg-[right_0.75rem_center] bg-no-repeat pr-9",
        className,
      )}
      style={{ backgroundImage: SELECT_ARROW }}
      {...props}
    />
  );
}

export function Field({
  label,
  hint,
  error,
  children,
  className,
}: {
  label: string;
  hint?: ReactNode;
  error?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    // biome-ignore lint/a11y/noLabelWithoutControl: o controle é passado como children
    <label className={cn("block text-sm font-medium", className)}>
      {label}
      <span className="mt-1.5 block font-normal">{children}</span>
      {error ? (
        <span role="alert" className="mt-1 block text-xs font-normal text-red-600 dark:text-red-400">
          {error}
        </span>
      ) : hint ? (
        <span className="mt-1 block text-xs font-normal text-zinc-500 dark:text-zinc-400">{hint}</span>
      ) : null}
    </label>
  );
}

/** Aviso inline (erro, atenção ou informação) para formulários e páginas. */
export function Callout({
  tone = "info",
  children,
  className,
}: {
  tone?: "info" | "warning" | "critical" | "good";
  children: ReactNode;
  className?: string;
}) {
  const tones = {
    info: "border-sky-200 bg-sky-50 text-sky-800 dark:border-sky-900 dark:bg-sky-950/40 dark:text-sky-200",
    warning:
      "border-amber-200 bg-amber-50 text-amber-900 dark:border-amber-900 dark:bg-amber-950/40 dark:text-amber-200",
    critical: "border-red-200 bg-red-50 text-red-700 dark:border-red-900 dark:bg-red-950/40 dark:text-red-300",
    good: "border-emerald-200 bg-emerald-50 text-emerald-800 dark:border-emerald-900 dark:bg-emerald-950/40 dark:text-emerald-200",
  };
  return (
    <div
      role={tone === "critical" ? "alert" : "status"}
      className={cn("rounded-lg border px-3 py-2 text-sm", tones[tone], className)}
    >
      {children}
    </div>
  );
}

/** Controle segmentado (2–3 opções) para alternar visões. */
export function Segmented<T extends string>({
  value,
  onChange,
  options,
  ariaLabel,
}: {
  value: T;
  onChange: (value: T) => void;
  options: { value: T; label: string }[];
  ariaLabel: string;
}) {
  return (
    <fieldset className="m-0 inline-flex min-w-0 rounded-lg border-0 bg-zinc-100 p-0.5 text-xs font-medium dark:bg-zinc-800">
      <legend className="sr-only">{ariaLabel}</legend>
      {options.map((o) => (
        <button
          key={o.value}
          type="button"
          aria-pressed={value === o.value}
          onClick={() => onChange(o.value)}
          className={cn(
            "rounded-md px-2.5 py-1 transition",
            value === o.value
              ? "bg-white text-zinc-900 shadow-xs dark:bg-zinc-700 dark:text-white"
              : "text-zinc-500 hover:text-zinc-800 dark:text-zinc-400 dark:hover:text-zinc-200",
          )}
        >
          {o.label}
        </button>
      ))}
    </fieldset>
  );
}

export const tableHeadClass =
  "border-b border-zinc-200 text-left text-xs text-zinc-500 dark:border-zinc-800 dark:text-zinc-400";
export const thClass = "whitespace-nowrap px-4 py-2.5 font-medium first:pl-5 last:pr-5";
export const tdClass = "px-4 py-3 align-middle first:pl-5 last:pr-5";
export const tbodyClass = "divide-y divide-zinc-100 dark:divide-zinc-800/70";
