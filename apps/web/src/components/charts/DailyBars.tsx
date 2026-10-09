import { useState } from "react";
import { shortDay } from "../../lib/admin";

export interface DayDatum {
  date: string;
  value: number;
}

/**
 * Colunas diárias de série única (um só tom, como o BarList): a altura é o valor do dia.
 * Passar o mouse, tocar ou focar uma coluna mostra o valor; a tabela oculta serve a leitores de tela.
 */
export function DailyBars({ data, unit, ariaLabel }: { data: DayDatum[]; unit: [string, string]; ariaLabel: string }) {
  const [active, setActive] = useState<number>();
  const peak = Math.max(0, ...data.map((d) => d.value));
  const max = Math.max(1, peak);
  const shown = active !== undefined ? data[active] : undefined;
  const ticks = data.length > 1 ? [0, Math.floor((data.length - 1) / 2), data.length - 1] : [0];
  const label = (v: number) => `${v} ${v === 1 ? unit[0] : unit[1]}`;

  return (
    <figure>
      <div className="mb-2 h-5 text-sm text-zinc-500 tabular-nums dark:text-zinc-400" aria-hidden>
        {shown ? (
          <>
            <span className="font-medium text-zinc-900 dark:text-zinc-100">{label(shown.value)}</span> ·{" "}
            {shortDay(shown.date)}
          </>
        ) : (
          <>Máximo no período: {label(peak)}</>
        )}
      </div>
      <div
        role="img"
        aria-label={ariaLabel}
        className="flex h-40 items-end gap-[3px] border-b border-zinc-200 dark:border-zinc-800"
        onMouseLeave={() => setActive(undefined)}
      >
        {data.map((d, i) => (
          <button
            key={d.date}
            type="button"
            tabIndex={-1}
            aria-hidden
            onMouseEnter={() => setActive(i)}
            onClick={() => setActive(i)}
            className="group flex h-full min-w-0 flex-1 items-end"
          >
            <span
              className="block w-full rounded-t-[3px] transition-opacity"
              style={{
                height: d.value === 0 ? "2px" : `${Math.max(3, (d.value / max) * 100)}%`,
                background: "var(--chart-series-1)",
                opacity: d.value === 0 ? 0.3 : active !== undefined && active !== i ? 0.45 : 1,
              }}
            />
          </button>
        ))}
      </div>
      <div className="relative mt-1.5 flex h-4 justify-between text-xs text-zinc-400 tabular-nums" aria-hidden>
        {ticks.map((i) => (
          <span key={i}>{data[i] ? shortDay(data[i].date) : ""}</span>
        ))}
      </div>
      <table className="sr-only">
        <caption>{ariaLabel}</caption>
        <tbody>
          {data.map((d) => (
            <tr key={d.date}>
              <th scope="row">{shortDay(d.date)}</th>
              <td>{label(d.value)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </figure>
  );
}
