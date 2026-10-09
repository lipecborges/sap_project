import { useState } from "react";
import { cn } from "../../lib/utils";

export interface BarDatum {
  key: string;
  label: string;
  value: number;
}

/**
 * Barras horizontais de série única (magnitude por categoria): um só tom, rótulo e
 * valor diretos em cada linha, então não há legenda. Hover destaca a linha e mostra o percentual.
 */
export function BarList({
  data,
  unit,
  onSelect,
  ariaLabel,
}: {
  data: BarDatum[];
  unit: [string, string];
  onSelect?: (key: string) => void;
  ariaLabel: string;
}) {
  const [hover, setHover] = useState<string>();
  const max = Math.max(1, ...data.map((d) => d.value));
  const total = data.reduce((s, d) => s + d.value, 0);
  return (
    <div>
      <ul className="space-y-1" aria-label={ariaLabel}>
        {data.map((d) => {
          const pct = total ? Math.round((d.value / total) * 100) : 0;
          const Tag = onSelect ? "button" : "div";
          return (
            <li key={d.key}>
              <Tag
                {...(onSelect ? { type: "button" as const, onClick: () => onSelect(d.key) } : {})}
                onMouseEnter={() => setHover(d.key)}
                onMouseLeave={() => setHover(undefined)}
                onFocus={() => setHover(d.key)}
                onBlur={() => setHover(undefined)}
                className={cn(
                  "grid w-full grid-cols-[minmax(5rem,9rem)_minmax(3rem,1fr)_2.5rem] items-center gap-3 rounded-md px-2 py-1.5 text-left text-sm",
                  onSelect && "hover:bg-zinc-50 dark:hover:bg-zinc-800/50",
                )}
              >
                <span className="truncate text-zinc-600 dark:text-zinc-400">{d.label}</span>
                <span className="relative h-2 rounded-full" style={{ background: "var(--chart-track)" }}>
                  <span
                    className="absolute inset-y-0 left-0 rounded-full transition-[width,opacity]"
                    style={{
                      width: `${(d.value / max) * 100}%`,
                      background: "var(--chart-series-1)",
                      opacity: hover && hover !== d.key ? 0.45 : 1,
                    }}
                  />
                </span>
                <span className="text-right font-medium tabular-nums text-zinc-900 dark:text-zinc-100">
                  {hover === d.key ? `${pct}%` : d.value}
                </span>
              </Tag>
            </li>
          );
        })}
      </ul>
      <table className="sr-only">
        <caption>{ariaLabel}</caption>
        <tbody>
          {data.map((d) => (
            <tr key={d.key}>
              <th scope="row">{d.label}</th>
              <td>
                {d.value} {d.value === 1 ? unit[0] : unit[1]}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
