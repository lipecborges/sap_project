import { type DiagnosticResult, INVOICE_STATE_LABELS, SD_STAGE_LABELS } from "@raiox/contracts";
import { day, emptyResult, type MockContext, settleStatus } from "../context";
import { INVOICES } from "../mm/invoices";
import { brl, SALES_ORDERS } from "../sd/orders";

const MAX_ROWS = 500;
const DEFAULT_ROWS = 100;

function paginate<T>(items: T[], params: Record<string, string>) {
  const maxRows = Math.min(Number(params.maxRows) || DEFAULT_ROWS, MAX_ROWS);
  const page = Math.max(Number(params.page) || 1, 1);
  return { rows: items.slice((page - 1) * maxRows, page * maxRows), truncated: page * maxRows < items.length };
}

/** SD-10: pedidos de venda parados antes do faturamento, do mais antigo para o mais novo. */
export function sd10(ctx: MockContext, params: Record<string, string>): DiagnosticResult {
  const r = emptyResult(ctx, "SD-10", { kind: "SALES_ORG", id: params.salesOrg || "*" });
  const open = SALES_ORDERS.filter((o) => o.stage !== "COMPLETED")
    .filter((o) => !params.salesOrg || o.salesOrg === params.salesOrg)
    .filter((o) => !params.stage || o.stage === params.stage)
    .sort((a, b) => a.createdOn - b.createdOn);
  const { rows, truncated } = paginate(open, params);

  r.facts.push(
    { id: "total", label: "Pedidos travados", value: String(open.length) },
    { id: "totalValue", label: "Valor parado", value: brl(open.reduce((sum, o) => sum + o.netValue, 0)) },
  );
  for (const stage of Object.keys(SD_STAGE_LABELS) as Array<keyof typeof SD_STAGE_LABELS>) {
    const count = open.filter((o) => o.stage === stage).length;
    if (count > 0) r.facts.push({ id: `stage:${stage}`, label: SD_STAGE_LABELS[stage], value: String(count) });
  }

  r.tables.push({
    id: "salesOrders",
    title: "Pedidos de venda",
    keys: [
      "salesOrder",
      "customer",
      "netValue",
      "createdOn",
      "requestedDate",
      "stage",
      "stageCode",
      "reason",
      "daysOpen",
    ],
    columns: [
      "Pedido",
      "Cliente",
      "Valor líquido",
      "Criado em",
      "Data desejada",
      "Etapa",
      "Código da etapa",
      "Motivo",
      "Dias em aberto",
    ],
    rows: rows.map((o) => [
      o.vbeln,
      o.customer,
      brl(o.netValue),
      day(ctx, o.createdOn),
      day(ctx, o.requestedDate),
      SD_STAGE_LABELS[o.stage as keyof typeof SD_STAGE_LABELS],
      o.stage,
      o.reason,
      String(-o.createdOn),
    ]),
    truncated,
  });

  const late = open.filter((o) => o.requestedDate < 0);
  if (late.length > 0) {
    r.findings.push({
      code: "SD10.PAST_REQUESTED_DATE",
      severity: "WARNING",
      title: `${late.length} pedido(s) já passaram da data desejada pelo cliente`,
      detail: `Pedidos: ${late.map((o) => o.vbeln).join(", ")}. Use o SD-01 para ver a causa de cada um.`,
      evidence: [],
      suggestedAction: { tcode: "VA05", description: "Lista de pedidos de venda" },
    });
  }
  return settleStatus(r);
}

/** MM-10: faturas de fornecedor bloqueadas ou estacionadas, por vencimento. */
export function mm10(ctx: MockContext, params: Record<string, string>): DiagnosticResult {
  const r = emptyResult(ctx, "MM-10", { kind: "COMPANY_CODE", id: params.companyCode || "*" });
  const pending = INVOICES.filter((i) => i.state !== "RELEASED")
    .filter((i) => !params.companyCode || i.companyCode === params.companyCode)
    .filter((i) => !params.state || i.state === params.state)
    .sort((a, b) => a.dueDate - b.dueDate);
  const { rows, truncated } = paginate(pending, params);

  r.facts.push(
    { id: "total", label: "Faturas pendentes", value: String(pending.length) },
    { id: "totalAmount", label: "Valor retido", value: brl(pending.reduce((sum, i) => sum + i.grossAmount, 0)) },
  );
  for (const state of Object.keys(INVOICE_STATE_LABELS) as Array<keyof typeof INVOICE_STATE_LABELS>) {
    const count = pending.filter((i) => i.state === state).length;
    if (count > 0) r.facts.push({ id: `state:${state}`, label: INVOICE_STATE_LABELS[state], value: String(count) });
  }

  r.tables.push({
    id: "invoices",
    title: "Faturas de fornecedor",
    keys: [
      "invoice",
      "fiscalYear",
      "vendor",
      "grossAmount",
      "dueDate",
      "daysToDue",
      "state",
      "stateCode",
      "reason",
      "purchaseOrder",
    ],
    columns: [
      "Fatura",
      "Exercício",
      "Fornecedor",
      "Valor bruto",
      "Vencimento",
      "Dias para vencer",
      "Situação",
      "Código da situação",
      "Motivo",
      "Pedido de compra",
    ],
    rows: rows.map((i) => [
      i.belnr,
      i.gjahr,
      i.vendor,
      brl(i.grossAmount),
      day(ctx, i.dueDate),
      String(i.dueDate),
      INVOICE_STATE_LABELS[i.state as keyof typeof INVOICE_STATE_LABELS],
      i.state,
      i.reason,
      i.purchaseOrder,
    ]),
    truncated,
  });

  const overdue = pending.filter((i) => i.dueDate < 0);
  if (overdue.length > 0) {
    r.findings.push({
      code: "MM10.OVERDUE",
      severity: "BLOCKING",
      title: `${overdue.length} fatura(s) bloqueada(s) já vencida(s)`,
      detail: `Faturas: ${overdue.map((i) => i.belnr).join(", ")}. O fornecedor pode cobrar juros. Use o MM-02 para a causa.`,
      evidence: [],
      suggestedAction: { tcode: "MRBR", description: "Liberar faturas bloqueadas" },
    });
  }
  return settleStatus(r);
}
