import type { Fact } from "@raiox/contracts";
import { localizeDates } from "../../lib/utils";

export function FactList({ facts }: { facts: Fact[] }) {
  return (
    <dl className="divide-y divide-zinc-100 dark:divide-zinc-800">
      {facts.map((f) => (
        <div key={f.id} className="flex items-start justify-between gap-4 px-5 py-2.5 text-sm">
          <dt className="shrink-0 text-zinc-500 dark:text-zinc-400">{f.label}</dt>
          <dd className="text-right font-medium text-zinc-900 dark:text-zinc-100">{localizeDates(f.value)}</dd>
        </div>
      ))}
    </dl>
  );
}
