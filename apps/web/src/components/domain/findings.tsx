import type { Finding } from "@raiox/contracts";
import { Copy } from "lucide-react";
import { toast } from "sonner";
import { cn, localizeDates } from "../../lib/utils";
import { SEVERITY, SEVERITY_ORDER } from "./status";

const BORDER: Record<Finding["severity"], string> = {
  BLOCKING: "before:bg-red-500",
  WARNING: "before:bg-amber-400",
  INFO: "before:bg-sky-400",
};

export function TcodeChip({ tcode, description }: { tcode: string; description?: string }) {
  async function copy() {
    try {
      await navigator.clipboard.writeText(tcode);
      toast.success(`Transação ${tcode} copiada`);
    } catch {
      toast(`Transação: ${tcode}`);
    }
  }
  return (
    <div className="flex flex-wrap items-center gap-2 text-sm">
      <button
        type="button"
        onClick={copy}
        title="Copiar transação"
        className="group inline-flex items-center gap-1.5 rounded-md bg-zinc-900 px-2 py-0.5 font-mono text-xs font-semibold text-white hover:bg-zinc-700 dark:bg-zinc-100 dark:text-zinc-900 dark:hover:bg-white"
      >
        {tcode}
        <Copy className="size-3 opacity-60 group-hover:opacity-100" />
      </button>
      {description && <span className="text-zinc-600 dark:text-zinc-400">{description}</span>}
    </div>
  );
}

export function FindingCard({ finding, compact = false }: { finding: Finding; compact?: boolean }) {
  const meta = SEVERITY[finding.severity];
  const Icon = meta.icon;
  return (
    <li
      className={cn(
        "relative overflow-hidden rounded-lg border border-zinc-200 bg-white py-3 pr-4 pl-5 before:absolute before:inset-y-0 before:left-0 before:w-1 dark:border-zinc-800 dark:bg-zinc-900",
        BORDER[finding.severity],
      )}
    >
      <div className="flex items-start gap-2.5">
        <Icon
          className={cn(
            "mt-0.5 size-4 shrink-0",
            finding.severity === "BLOCKING"
              ? "text-red-500"
              : finding.severity === "WARNING"
                ? "text-amber-500"
                : "text-sky-500",
          )}
        />
        <div className="min-w-0 flex-1 space-y-1.5">
          <div className="flex flex-wrap items-baseline justify-between gap-x-3">
            <h3 className="text-sm font-semibold text-zinc-900 dark:text-zinc-100">{localizeDates(finding.title)}</h3>
            <span className="font-mono text-[0.6875rem] text-zinc-400">{finding.code}</span>
          </div>
          {finding.detail && (
            <p className="text-sm text-zinc-600 dark:text-zinc-400">{localizeDates(finding.detail)}</p>
          )}
          {!compact && finding.evidence.length > 0 && (
            <ul className="flex flex-wrap gap-1.5">
              {finding.evidence.map((e, i) => (
                <li
                  // biome-ignore lint/suspicious/noArrayIndexKey: lista estática de evidências
                  key={i}
                  title={e.label}
                  className="rounded border border-zinc-200 bg-zinc-50 px-1.5 py-0.5 font-mono text-[0.6875rem] text-zinc-600 dark:border-zinc-800 dark:bg-zinc-950 dark:text-zinc-400"
                >
                  {e.source}-{e.field}
                  {e.value !== "" && <span className="text-zinc-900 dark:text-zinc-200"> = {e.value}</span>}
                  <span className="ml-1 font-sans text-zinc-400">· {e.label}</span>
                </li>
              ))}
            </ul>
          )}
          {finding.suggestedAction && <TcodeChip {...finding.suggestedAction} />}
        </div>
      </div>
    </li>
  );
}

export function FindingList({ findings, compact }: { findings: Finding[]; compact?: boolean }) {
  const sorted = [...findings].sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity]);
  return (
    <ul className="space-y-2.5">
      {sorted.map((f, i) => (
        // biome-ignore lint/suspicious/noArrayIndexKey: o mesmo código pode repetir (ex.: um achado por item)
        <FindingCard key={`${f.code}-${i}`} finding={f} compact={compact} />
      ))}
    </ul>
  );
}
