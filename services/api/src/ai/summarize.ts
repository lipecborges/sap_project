import { type DiagnosticResult, findDiagnostic } from "@raiox/contracts";

const STATUS_PHRASE: Record<DiagnosticResult["status"], string> = {
  OK: "Não encontrei impedimentos",
  PROBLEM_FOUND: "Encontrei pontos que precisam de ação",
  NOT_FOUND: "Não encontrei o documento",
  ERROR: "O diagnóstico terminou com erro",
};

const OBJECT_LABELS: Record<string, string> = {
  SALES_ORDER: "o pedido de venda",
  SUPPLIER_INVOICE: "a fatura",
  PRODUCTION_ORDER: "a ordem de produção",
  PLANT: "o centro",
};

const col = (result: DiagnosticResult, key: string) => {
  const table = result.tables[0];
  const index = table?.keys.indexOf(key) ?? -1;
  return (row: string[]) => (index >= 0 ? (row[index] ?? "") : "");
};

/** Texto em markdown a partir de um resultado (usado pelo modo demonstração). */
export function summarize(result: DiagnosticResult, heading?: string): string {
  const meta = findDiagnostic(result.diagnosticId);
  const lines: string[] = [];
  const subject = `${OBJECT_LABELS[result.object.kind] ?? result.object.kind} ${result.object.id}`;

  if (meta?.kind === "LIST") {
    const table = result.tables[0];
    const total = result.facts.find((f) => f.id === "total")?.value ?? String(table?.rows.length ?? 0);
    lines.push(`**${meta.title}:** ${total} encontrado(s).`);
    for (const f of result.findings) lines.push(`- **${f.title}.** ${f.detail}`);
    if (table && table.rows.length > 0) {
      lines.push("", `| ${table.columns.slice(0, 1).join("")} | Detalhe |`, "|---|---|");
      const describe = listDescriber(result);
      for (const row of table.rows.slice(0, 5)) lines.push(`| ${row[0]} | ${describe(row)} |`);
      if (table.rows.length > 5)
        lines.push("", `E mais ${table.rows.length - 5}. Veja a lista completa no cartão ao lado.`);
    }
    return lines.join("\n");
  }

  const main = result.findings.find((f) => f.severity === "BLOCKING") ?? result.findings[0];
  lines.push(
    heading ?? `${STATUS_PHRASE[result.status]} para ${subject}${main ? `: **${main.title.toLowerCase()}**` : ""}.`,
  );
  const causes = result.findings.filter((f) => f.severity !== "INFO" || result.status !== "PROBLEM_FOUND");
  if (causes.length > 0) {
    lines.push("", "**Causa**");
    for (const f of causes) {
      const evidence = f.evidence[0];
      const source = evidence
        ? ` _(${evidence.source}-${evidence.field}${evidence.value ? ` = ${evidence.value}` : ""})_`
        : "";
      lines.push(`- **${f.title}.** ${f.detail}${source}`);
    }
  }
  const actions = result.findings.filter((f) => f.suggestedAction);
  if (actions.length > 0) {
    lines.push("", "**O que fazer**");
    actions.forEach((f, i) => {
      lines.push(`${i + 1}. \`${f.suggestedAction?.tcode}\` ${f.suggestedAction?.description}`);
    });
  }
  return lines.join("\n");
}

function listDescriber(result: DiagnosticResult): (row: string[]) => string {
  switch (result.diagnosticId) {
    case "PP-04": {
      const [desc, sit, flags, delay] = ["description", "situation", "flags", "delayDays"].map((k) => col(result, k));
      return (row) =>
        [desc!(row), sit!(row), flags!(row), Number(delay!(row)) > 0 ? `${delay!(row)} dia(s) de atraso` : ""]
          .filter(Boolean)
          .join(" · ");
    }
    case "SD-10": {
      const [customer, stage, reason] = ["customer", "stage", "reason"].map((k) => col(result, k));
      return (row) => `${customer!(row)} · ${stage!(row)}: ${reason!(row)}`;
    }
    case "MM-10": {
      const [vendor, amount, reason] = ["vendor", "grossAmount", "reason"].map((k) => col(result, k));
      return (row) => `${vendor!(row)} · ${amount!(row)} · ${reason!(row)}`;
    }
    default:
      return (row) => row.slice(1, 4).join(" · ");
  }
}

/** Próximas perguntas sugeridas a partir do que foi consultado. */
export function suggestFollowUps(results: DiagnosticResult[]): string[] {
  const out: string[] = [];
  const codes = (r: DiagnosticResult) => new Set(r.findings.map((f) => f.code));
  for (const r of results) {
    const id = r.object.id;
    switch (r.diagnosticId) {
      case "PP-03":
        if (codes(r).has("PP03.MISSING_PARTS")) out.push(`Quais componentes estão faltando na ordem ${id}?`);
        if (codes(r).has("PP03.SALES_ORDER_AT_RISK")) {
          const so = r.related.find((x) => x.kind === "SALES_ORDER");
          if (so) out.push(`Por que o pedido ${so.id} ainda não faturou?`);
        }
        break;
      case "PP-01":
        out.push(`Como está o andamento da ordem ${id}?`);
        break;
      case "PP-04": {
        const first = r.tables[0]?.rows[0]?.[0];
        if (first) out.push(`Analise a ordem ${first}`);
        out.push("Quais ordens estão com falta de material?");
        break;
      }
      case "SD-10": {
        const first = r.tables[0]?.rows[0]?.[0];
        if (first) out.push(`Por que o pedido ${first} está travado?`);
        break;
      }
      case "MM-10": {
        const first = r.tables[0]?.rows[0]?.[0];
        if (first) out.push(`Por que a fatura ${first} está bloqueada?`);
        break;
      }
      case "SD-01":
        out.push("Quais outros pedidos estão travados?");
        break;
      case "MM-02":
        out.push("Quais faturas estão bloqueadas?");
        break;
    }
  }
  if (out.length === 0)
    out.push("Quais ordens estão atrasadas?", "Quais pedidos estão travados?", "Quais faturas estão bloqueadas?");
  return [...new Set(out)].slice(0, 3);
}
