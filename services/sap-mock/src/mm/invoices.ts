/** Faturas de fornecedor do simulador (usadas por MM-02 e MM-10). Datas relativas a hoje. */
export type InvoiceState = "BLOCKED" | "PARKED" | "RELEASED";

export interface SupplierInvoice {
  belnr: string;
  gjahr: string;
  vendor: string;
  companyCode: string;
  grossAmount: number;
  postingDate: number;
  dueDate: number;
  purchaseOrder: string;
  state: InvoiceState;
  reason: string;
}

export const STATE_LABELS: Record<InvoiceState, string> = {
  BLOCKED: "Bloqueada",
  PARKED: "Estacionada",
  RELEASED: "Liberada",
};

export const INVOICES: SupplierInvoice[] = [
  {
    belnr: "5105600001",
    gjahr: "2026",
    vendor: "200310 · Metalúrgica Silva S.A.",
    companyCode: "1000",
    grossAmount: 1150,
    postingDate: -5,
    dueDate: 2,
    purchaseOrder: "4500017788",
    state: "BLOCKED",
    reason: "Divergência de preço (+15%)",
  },
  {
    belnr: "5105600002",
    gjahr: "2026",
    vendor: "200455 · Plásticos Vale Ltda.",
    companyCode: "1000",
    grossAmount: 8400,
    postingDate: -8,
    dueDate: -1,
    purchaseOrder: "4500017790",
    state: "BLOCKED",
    reason: "Quantidade faturada maior que a recebida",
  },
  {
    belnr: "5105600003",
    gjahr: "2026",
    vendor: "200310 · Metalúrgica Silva S.A.",
    companyCode: "1000",
    grossAmount: 22350,
    postingDate: -10,
    dueDate: 20,
    purchaseOrder: "4500017701",
    state: "RELEASED",
    reason: "Sem bloqueio",
  },
  {
    belnr: "5105600004",
    gjahr: "2026",
    vendor: "200612 · Transportes Rápido Sul",
    companyCode: "1000",
    grossAmount: 3980,
    postingDate: -2,
    dueDate: 13,
    purchaseOrder: "4500017812",
    state: "PARKED",
    reason: "Estacionada, não lançada",
  },
  {
    belnr: "5105600005",
    gjahr: "2026",
    vendor: "200455 · Plásticos Vale Ltda.",
    companyCode: "1000",
    grossAmount: 15720,
    postingDate: -3,
    dueDate: 4,
    purchaseOrder: "4500017795",
    state: "BLOCKED",
    reason: "Entrega antes da data do pedido",
  },
];

export function findInvoice(belnr: string, gjahr: string): SupplierInvoice | undefined {
  return INVOICES.find((i) => i.belnr === belnr && i.gjahr === gjahr);
}
