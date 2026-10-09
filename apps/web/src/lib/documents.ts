/** Reconhece números de documento digitados na busca ou no chat. */
export type DocumentRef =
  | { kind: "PRODUCTION_ORDER"; id: string }
  | { kind: "SALES_ORDER"; id: string }
  | { kind: "SUPPLIER_INVOICE"; id: string; year: string };

export function detectDocuments(text: string): DocumentRef[] {
  const year = text.match(/\b(20\d{2})\b/)?.[1] ?? String(new Date().getFullYear());
  const refs: DocumentRef[] = [];
  for (const n of text.match(/\b\d{6,10}\b/g) ?? []) {
    if (n.length === 10 && n.startsWith("51")) refs.push({ kind: "SUPPLIER_INVOICE", id: n, year });
    else if (n.length === 7 && n.startsWith("45")) refs.push({ kind: "SALES_ORDER", id: n });
    else if (n.length === 7 && /^[12]/.test(n)) refs.push({ kind: "PRODUCTION_ORDER", id: n });
  }
  return refs;
}

export const DOCUMENT_LABEL: Record<DocumentRef["kind"], string> = {
  PRODUCTION_ORDER: "Ordem de produção",
  SALES_ORDER: "Pedido de venda",
  SUPPLIER_INVOICE: "Fatura de fornecedor",
};
