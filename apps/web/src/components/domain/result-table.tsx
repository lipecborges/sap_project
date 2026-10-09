import type { ResultTable } from "@raiox/contracts";
import { EmptyState } from "../ui/misc";

/** Colunas técnicas (códigos) ficam fora da exibição genérica. */
const hidden = (key: string) => key.endsWith("Code") || key.endsWith("Codes");

export function ResultTableView({ table, onRowClick }: { table: ResultTable; onRowClick?: (row: string[]) => void }) {
  const visible = table.keys
    .map((k, i) => ({ key: k, label: table.columns[i] ?? k, index: i }))
    .filter((c) => !hidden(c.key));
  if (table.rows.length === 0) return <EmptyState title="Nenhum registro" />;
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-sm">
        <thead>
          <tr className="border-b border-zinc-200 text-xs text-zinc-500 dark:border-zinc-800 dark:text-zinc-400">
            {visible.map((c) => (
              <th key={c.key} scope="col" className="whitespace-nowrap px-4 py-2.5 font-medium first:pl-5">
                {c.label}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-zinc-100 dark:divide-zinc-800/70">
          {table.rows.map((row, i) => (
            <tr
              // biome-ignore lint/suspicious/noArrayIndexKey: linhas sem id próprio
              key={i}
              onClick={onRowClick ? () => onRowClick(row) : undefined}
              className={onRowClick ? "cursor-pointer hover:bg-zinc-50 dark:hover:bg-zinc-800/50" : undefined}
            >
              {visible.map((c) => (
                <td key={c.key} className="whitespace-nowrap px-4 py-2.5 first:pl-5">
                  {row[c.index]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {table.truncated && <p className="px-5 py-2 text-xs text-zinc-500">Há mais registros: refine os filtros.</p>}
    </div>
  );
}
