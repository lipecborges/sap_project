import { Search } from "lucide-react";
import { cn } from "../../lib/utils";

export interface FilterChip {
  key: string;
  label: string;
  count?: number;
}

export function FilterBar({
  chips,
  active,
  onChange,
  search,
  onSearch,
  placeholder,
}: {
  chips: FilterChip[];
  active: string;
  onChange: (key: string) => void;
  search: string;
  onSearch: (value: string) => void;
  placeholder: string;
}) {
  return (
    <div className="flex flex-col gap-3 border-b border-zinc-200 px-4 py-3 md:flex-row md:items-center dark:border-zinc-800">
      <div className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-0.5">
        {chips.map((c) => (
          <button
            key={c.key}
            type="button"
            onClick={() => onChange(c.key)}
            className={cn(
              "flex shrink-0 items-center gap-1.5 rounded-full border px-3 py-1 text-xs font-medium transition",
              active === c.key
                ? "border-zinc-900 bg-zinc-900 text-white dark:border-white dark:bg-white dark:text-zinc-900"
                : "border-zinc-200 text-zinc-600 hover:border-zinc-300 dark:border-zinc-700 dark:text-zinc-400",
            )}
          >
            {c.label}
            {c.count !== undefined && (
              <span className={cn("tabular-nums", active === c.key ? "opacity-70" : "text-zinc-400")}>{c.count}</span>
            )}
          </button>
        ))}
      </div>
      <label className="relative md:ml-auto md:w-64">
        <span className="sr-only">Buscar</span>
        <Search className="pointer-events-none absolute top-1/2 left-2.5 size-4 -translate-y-1/2 text-zinc-400" />
        <input
          value={search}
          onChange={(e) => onSearch(e.target.value)}
          placeholder={placeholder}
          className="h-8 w-full rounded-lg border border-zinc-200 bg-white pr-3 pl-8 text-sm outline-none focus:border-brand-400 dark:border-zinc-700 dark:bg-zinc-900"
        />
      </label>
    </div>
  );
}
