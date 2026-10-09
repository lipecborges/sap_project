import { z } from "zod";

export const DiagnosticId = z.enum(["SD-01", "MM-02", "PP-01", "PP-03", "PP-04"]);
export type DiagnosticId = z.infer<typeof DiagnosticId>;

export const ParamType = z.enum(["DOCUMENT", "STRING", "INTEGER", "DATE", "ENUM"]);
export type ParamType = z.infer<typeof ParamType>;

export const ParamMeta = z.object({
  name: z.string().min(1),
  label: z.string(),
  dataType: ParamType,
  required: z.boolean(),
  /** Valores aceitos quando dataType = ENUM (vazio nos demais). */
  options: z.array(z.string()),
});
export type ParamMeta = z.infer<typeof ParamMeta>;

/** OBJECT = diagnóstico de um documento; LIST = consulta de vários objetos. */
export const DiagnosticKind = z.enum(["OBJECT", "LIST"]);
export const SapModule = z.enum(["SD", "MM", "PP", "GE"]);

export const DiagnosticMeta = z.object({
  id: z.string().min(1),
  version: z.string(),
  module: SapModule,
  kind: DiagnosticKind,
  title: z.string(),
  params: z.array(ParamMeta),
});
export type DiagnosticMeta = z.infer<typeof DiagnosticMeta>;

/** Situação principal da ordem de produção (catálogo, PP-03). */
export const PpSituation = z.enum([
  "DELETED",
  "CLOSED",
  "TECHNICALLY_COMPLETED",
  "DELIVERED",
  "PARTIALLY_DELIVERED",
  "CONFIRMED",
  "IN_PRODUCTION",
  "RELEASED",
  "APPROVED",
  "CREATED",
]);
export type PpSituation = z.infer<typeof PpSituation>;

/** Sinalizadores adicionais da ordem (catálogo, PP-03). */
export const PpFlag = z.enum([
  "LATE_START",
  "LATE_FINISH",
  "OPERATION_LATE",
  "MISSING_PARTS",
  "LOCKED",
  "CONFIRMED_NOT_RECEIVED",
  "SALES_ORDER_AT_RISK",
  "REVERSED_CONFIRMATION",
]);
export type PpFlag = z.infer<typeof PpFlag>;

const doc = (name: string, label: string): ParamMeta => ({
  name,
  label,
  dataType: "DOCUMENT",
  required: true,
  options: [],
});

const optional = (name: string, label: string, dataType: ParamType, options: string[] = []): ParamMeta => ({
  name,
  label,
  dataType,
  required: false,
  options,
});

/**
 * Catálogo dos diagnósticos do MVP. É a referência para o sap-mock, a API e a web;
 * o add-on ABAP devolve os mesmos metadados em GET /v1/diagnostics.
 */
export const DIAGNOSTICS: readonly DiagnosticMeta[] = [
  {
    id: "SD-01",
    version: "1.0",
    module: "SD",
    kind: "OBJECT",
    title: "Pedido de venda não faturado",
    params: [doc("salesOrder", "Pedido de venda")],
  },
  {
    id: "MM-02",
    version: "1.0",
    module: "MM",
    kind: "OBJECT",
    title: "Fatura de fornecedor bloqueada para pagamento",
    params: [
      doc("invoiceDocument", "Documento de faturamento (MIRO)"),
      { name: "fiscalYear", label: "Exercício", dataType: "INTEGER", required: true, options: [] },
    ],
  },
  {
    id: "PP-01",
    version: "1.0",
    module: "PP",
    kind: "OBJECT",
    title: "Ordem de produção não liberada / falta de componentes",
    params: [doc("productionOrder", "Ordem de produção")],
  },
  {
    id: "PP-03",
    version: "1.0",
    module: "PP",
    kind: "OBJECT",
    title: "Situação da ordem de produção",
    params: [doc("productionOrder", "Ordem de produção")],
  },
  {
    id: "PP-04",
    version: "1.0",
    module: "PP",
    kind: "LIST",
    title: "Ordens de produção por situação",
    params: [
      { name: "plant", label: "Centro", dataType: "STRING", required: true, options: [] },
      optional("situation", "Situação", "ENUM", [...PpSituation.options, ...PpFlag.options]),
      optional("mrpController", "Planejador MRP", "STRING"),
      optional("orderType", "Tipo de ordem", "STRING"),
      optional("material", "Material", "STRING"),
      optional("dateFrom", "Fim programado de", "DATE"),
      optional("dateTo", "Fim programado até", "DATE"),
      optional("maxRows", "Linhas por página", "INTEGER"),
      optional("page", "Página", "INTEGER"),
    ],
  },
];

export function findDiagnostic(id: string): DiagnosticMeta | undefined {
  return DIAGNOSTICS.find((d) => d.id === id);
}

export type ParamErrors = Record<string, string>;

/**
 * Valida parâmetros planos (como chegam do form/query string) contra os metadados.
 * Mesma regra aplicada pelo ABAP: obrigatórios, inteiros, datas AAAA-MM-DD e enums.
 */
export function validateParams(meta: DiagnosticMeta, params: Record<string, string | undefined>): ParamErrors {
  const errors: ParamErrors = {};
  for (const p of meta.params) {
    const value = params[p.name]?.trim() ?? "";
    if (value === "") {
      if (p.required) errors[p.name] = "Obrigatório";
      continue;
    }
    if ((p.dataType === "INTEGER" || p.dataType === "DOCUMENT") && !/^\d+$/.test(value)) {
      errors[p.name] = "Use apenas números";
    } else if (p.dataType === "DATE" && !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      errors[p.name] = "Use o formato AAAA-MM-DD";
    } else if (p.dataType === "ENUM" && !p.options.includes(value)) {
      errors[p.name] = `Valor inválido. Opções: ${p.options.join(", ")}`;
    }
  }
  return errors;
}

/** Equivalente à conversão ALPHA de saída: "0004500123" → "4500123". */
export function stripLeadingZeros(value: string): string {
  const stripped = value.replace(/^0+/, "");
  return stripped === "" ? "0" : stripped;
}

export const PP_SITUATION_LABELS: Record<PpSituation, string> = {
  DELETED: "Eliminada",
  CLOSED: "Fechada",
  TECHNICALLY_COMPLETED: "Encerrada tecnicamente",
  DELIVERED: "Entregue",
  PARTIALLY_DELIVERED: "Entregue parcialmente",
  CONFIRMED: "Produzida (confirmada)",
  IN_PRODUCTION: "Em produção",
  RELEASED: "Liberada",
  APPROVED: "Aprovada",
  CREATED: "Criada",
};

export const PP_FLAG_LABELS: Record<PpFlag, string> = {
  LATE_START: "Atrasada no início",
  LATE_FINISH: "Atrasada no fim",
  OPERATION_LATE: "Operação atrasada",
  MISSING_PARTS: "Falta de material",
  LOCKED: "Bloqueada",
  CONFIRMED_NOT_RECEIVED: "Confirmada sem entrada",
  SALES_ORDER_AT_RISK: "Risco para o pedido do cliente",
  REVERSED_CONFIRMATION: "Apontamento estornado",
};
