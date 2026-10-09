import type { DiagnosticResult, ResultTable } from "@raiox/contracts";

export type Row = Record<string, string>;

/** Linhas da tabela como objetos, pelas chaves estáveis (`keys`). */
export function rowsOf(table: ResultTable | undefined): Row[] {
  if (!table) return [];
  return table.rows.map((row) => Object.fromEntries(table.keys.map((key, i) => [key, row[i] ?? ""])));
}

export function tableOf(result: DiagnosticResult | undefined, id: string): ResultTable | undefined {
  return result?.tables.find((t) => t.id === id);
}

export function factOf(result: DiagnosticResult | undefined, id: string): string | undefined {
  return result?.facts.find((f) => f.id === id)?.value;
}

/** Totais com id "prefixo:CODIGO" (ex.: situation:RELEASED) → { RELEASED: 3 }. */
export function countsOf(result: DiagnosticResult | undefined, prefix: string): Record<string, number> {
  const out: Record<string, number> = {};
  for (const f of result?.facts ?? []) {
    if (f.id.startsWith(`${prefix}:`)) out[f.id.slice(prefix.length + 1)] = Number(f.value);
  }
  return out;
}
