/**
 * Cabeçalho dos pedidos de venda do simulador (usado por SD-01 e SD-10).
 * Datas em dias relativos a hoje.
 */
export type SdStage = "CREDIT" | "DELIVERY" | "GOODS_ISSUE" | "BILLING" | "COMPLETED";

export interface SalesOrder {
  vbeln: string;
  customer: string;
  salesOrg: string;
  netValue: number;
  createdOn: number;
  requestedDate: number;
  items: number;
  /** Etapa em que o pedido está parado. */
  stage: SdStage;
  /** Motivo principal, em linguagem de negócio. */
  reason: string;
}

export const STAGE_LABELS: Record<SdStage, string> = {
  CREDIT: "Crédito",
  DELIVERY: "Remessa",
  GOODS_ISSUE: "Saída de mercadoria",
  BILLING: "Faturamento",
  COMPLETED: "Concluído",
};

export const SALES_ORDERS: SalesOrder[] = [
  {
    vbeln: "4500001",
    customer: "100234 · Comercial Andrade Ltda.",
    salesOrg: "1000",
    netValue: 48450,
    createdOn: -6,
    requestedDate: 2,
    items: 3,
    stage: "CREDIT",
    reason: "Bloqueio de crédito",
  },
  {
    vbeln: "4500002",
    customer: "100518 · Distribuidora Paraná S.A.",
    salesOrg: "1000",
    netValue: 12890.5,
    createdOn: -4,
    requestedDate: 5,
    items: 2,
    stage: "DELIVERY",
    reason: "Bloqueio de remessa + pedido incompleto",
  },
  {
    vbeln: "4500003",
    customer: "100777 · Saneamento Litoral S.A.",
    salesOrg: "1000",
    netValue: 96300,
    createdOn: -9,
    requestedDate: -2,
    items: 5,
    stage: "GOODS_ISSUE",
    reason: "Remessa 80000123 sem saída de mercadoria",
  },
  {
    vbeln: "4500004",
    customer: "100234 · Comercial Andrade Ltda.",
    salesOrg: "1000",
    netValue: 7420,
    createdOn: -15,
    requestedDate: -8,
    items: 1,
    stage: "COMPLETED",
    reason: "Faturado",
  },
  {
    vbeln: "4500005",
    customer: "100901 · Agro Serra Verde Ltda.",
    salesOrg: "1000",
    netValue: 31780,
    createdOn: -3,
    requestedDate: 1,
    items: 2,
    stage: "BILLING",
    reason: "Bloqueio de faturamento (verificar preço)",
  },
  {
    vbeln: "4500006",
    customer: "100345 · Hidráulica Central Eireli",
    salesOrg: "1000",
    netValue: 154200,
    createdOn: -2,
    requestedDate: 7,
    items: 8,
    stage: "CREDIT",
    reason: "Bloqueio de crédito",
  },
  {
    vbeln: "4500007",
    customer: "100518 · Distribuidora Paraná S.A.",
    salesOrg: "1000",
    netValue: 5240,
    createdOn: -1,
    requestedDate: 4,
    items: 1,
    stage: "DELIVERY",
    reason: "Pedido incompleto",
  },
];

export function findSalesOrder(vbeln: string): SalesOrder | undefined {
  return SALES_ORDERS.find((o) => o.vbeln === vbeln);
}

export const brl = (value: number) => value.toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
