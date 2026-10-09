import { Factory, type LucideIcon, Receipt, ShoppingCart, Stethoscope } from "lucide-react";

export const MODULE_META: Record<string, { label: string; icon: LucideIcon; color: string }> = {
  PP: {
    label: "Produção",
    icon: Factory,
    color: "text-violet-600 bg-violet-50 dark:bg-violet-950/50 dark:text-violet-300",
  },
  SD: { label: "Vendas", icon: ShoppingCart, color: "text-sky-600 bg-sky-50 dark:bg-sky-950/50 dark:text-sky-300" },
  MM: {
    label: "Compras",
    icon: Receipt,
    color: "text-emerald-600 bg-emerald-50 dark:bg-emerald-950/50 dark:text-emerald-300",
  },
  GE: { label: "Geral", icon: Stethoscope, color: "text-zinc-600 bg-zinc-100 dark:bg-zinc-800 dark:text-zinc-300" },
};

export const OBJECT_LABEL: Record<string, string> = {
  SALES_ORDER: "Pedido de venda",
  DELIVERY: "Remessa",
  BILLING_DOCUMENT: "Fatura",
  SUPPLIER_INVOICE: "Fatura de fornecedor",
  PURCHASE_ORDER: "Pedido de compra",
  PRODUCTION_ORDER: "Ordem de produção",
  PLANT: "Centro",
};

/** Rota da página de detalhe de um documento, quando existe. */
export function objectRoute(kind: string, id: string): string | undefined {
  switch (kind) {
    case "PRODUCTION_ORDER":
      return `/producao/ordens/${id}`;
    case "SALES_ORDER":
      return `/vendas/pedidos/${id}`;
    case "SUPPLIER_INVOICE": {
      const [doc, year] = id.split("/");
      return year ? `/compras/faturas/${doc}/${year}` : undefined;
    }
    default:
      return undefined;
  }
}
