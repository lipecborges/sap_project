import { PP_FLAG_LABELS, PP_SITUATION_LABELS, type ResultStatus, type Severity } from "@raiox/contracts";

export const SEVERITY: Record<Severity, { label: string; className: string; dot: string }> = {
  BLOCKING: {
    label: "Bloqueio",
    className: "border-red-200 bg-red-50 dark:border-red-900/60 dark:bg-red-950/40",
    dot: "bg-red-600",
  },
  WARNING: {
    label: "Atenção",
    className: "border-amber-200 bg-amber-50 dark:border-amber-900/60 dark:bg-amber-950/40",
    dot: "bg-amber-500",
  },
  INFO: {
    label: "Informação",
    className: "border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900",
    dot: "bg-sky-600",
  },
};

export const SEVERITY_ORDER: Record<Severity, number> = { BLOCKING: 0, WARNING: 1, INFO: 2 };

export const STATUS: Record<ResultStatus, { label: string; className: string }> = {
  OK: {
    label: "Sem problemas",
    className: "bg-emerald-100 text-emerald-800 dark:bg-emerald-900/50 dark:text-emerald-200",
  },
  PROBLEM_FOUND: {
    label: "Problema encontrado",
    className: "bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200",
  },
  NOT_FOUND: {
    label: "Não encontrado",
    className: "bg-slate-200 text-slate-800 dark:bg-slate-800 dark:text-slate-200",
  },
  ERROR: { label: "Erro", className: "bg-red-100 text-red-800 dark:bg-red-900/50 dark:text-red-200" },
};

export const OBJECT_KIND: Record<string, string> = {
  SALES_ORDER: "Pedido de venda",
  DELIVERY: "Remessa",
  BILLING_DOCUMENT: "Fatura",
  SUPPLIER_INVOICE: "Fatura de fornecedor",
  PURCHASE_ORDER: "Pedido de compra",
  PRODUCTION_ORDER: "Ordem de produção",
  PLANT: "Centro",
};

const ENUM_LABELS: Record<string, string> = { ...PP_SITUATION_LABELS, ...PP_FLAG_LABELS };

export function enumLabel(value: string): string {
  return ENUM_LABELS[value] ?? value;
}

/** Documentos com cenário no sap-mock (sistema MCK), para facilitar demos. */
export const MOCK_EXAMPLES: Record<string, Array<{ label: string; params: Record<string, string> }>> = {
  "SD-01": [
    { label: "4500001 · crédito", params: { salesOrder: "4500001" } },
    { label: "4500002 · bloqueio + incompleto", params: { salesOrder: "4500002" } },
    { label: "4500003 · sem saída de mercadoria", params: { salesOrder: "4500003" } },
    { label: "4500004 · faturado", params: { salesOrder: "4500004" } },
    { label: "4500005 · bloqueio de faturamento", params: { salesOrder: "4500005" } },
  ],
  "MM-02": [
    { label: "5105600001 · preço", params: { invoiceDocument: "5105600001", fiscalYear: "2026" } },
    { label: "5105600002 · quantidade", params: { invoiceDocument: "5105600002", fiscalYear: "2026" } },
    { label: "5105600003 · liberada", params: { invoiceDocument: "5105600003", fiscalYear: "2026" } },
    { label: "5105600004 · estacionada", params: { invoiceDocument: "5105600004", fiscalYear: "2026" } },
  ],
  "PP-01": [
    { label: "1000001 · falta de material", params: { productionOrder: "1000001" } },
    { label: "1000002 · status de usuário", params: { productionOrder: "1000002" } },
    { label: "1000003 · liberada", params: { productionOrder: "1000003" } },
    { label: "1000004 · bloqueada", params: { productionOrder: "1000004" } },
    { label: "1000006 · aprovada", params: { productionOrder: "1000006" } },
  ],
  "PP-03": [
    { label: "1000010 · atrasada", params: { productionOrder: "1000010" } },
    { label: "1000011 · entregue", params: { productionOrder: "1000011" } },
    { label: "1000012 · sem entrada", params: { productionOrder: "1000012" } },
    { label: "1000013 · estorno", params: { productionOrder: "1000013" } },
  ],
  "PP-04": [
    { label: "Centro 1000", params: { plant: "1000" } },
    { label: "Atrasadas no fim", params: { plant: "1000", situation: "LATE_FINISH" } },
    { label: "Aprovadas", params: { plant: "1000", situation: "APPROVED" } },
  ],
};
