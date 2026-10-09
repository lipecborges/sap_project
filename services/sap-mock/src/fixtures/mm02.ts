import { type DiagnosticResult, stripLeadingZeros } from "@raiox/contracts";
import { emptyResult, type MockContext, settleStatus } from "../context";

/**
 * MM-02: Fatura de fornecedor bloqueada para pagamento.
 * Cenários (documento/exercício → situação):
 *   5105600001/2026 bloqueio por divergência de preço
 *   5105600002/2026 bloqueio por quantidade (entrada de mercadoria faltando)
 *   5105600003/2026 sem bloqueio
 *   5105600004/2026 fatura estacionada (não lançada)
 */

const scenarios: Record<string, (r: DiagnosticResult) => void> = {
  "5105600001/2026": (r) => {
    r.findings.push(
      {
        code: "MM02.PAYMENT_BLOCK",
        severity: "BLOCKING",
        title: "Fatura bloqueada para pagamento",
        detail: "A verificação de faturas bloqueou o pagamento automaticamente (chave R).",
        evidence: [
          { source: "RBKP", field: "ZLSPR", value: "R", label: "Bloqueio de pagamento: verificação de faturas" },
        ],
        suggestedAction: { tcode: "MRBR", description: "Liberar a fatura depois de resolver a divergência" },
      },
      {
        code: "MM02.BLOCK_PRICE",
        severity: "BLOCKING",
        title: "Item 1 bloqueado por preço",
        detail: "O preço faturado do item 1 está acima da tolerância em relação ao pedido 4500017788.",
        evidence: [{ source: "RSEG", field: "SPGRP", value: "X", label: "Motivo de bloqueio: preço" }],
      },
      {
        code: "MM02.PRICE_DIFF",
        severity: "BLOCKING",
        title: "Divergência de preço de 15%",
        detail: "Pedido: R$ 10,00/PC. Fatura: R$ 11,50/PC (+15%), para 100 PC.",
        evidence: [
          { source: "EKPO", field: "NETPR", value: "10,00", label: "Preço do pedido 4500017788/10" },
          { source: "RSEG", field: "WRBTR", value: "1.150,00", label: "Valor faturado do item 1" },
        ],
        suggestedAction: { tcode: "ME23N", description: "Conferir o preço do pedido com o comprador" },
      },
      {
        code: "MM02.TOLERANCE_INFO",
        severity: "INFO",
        title: "Tolerância de preço excedida",
        detail: "A chave de tolerância PP da empresa 1000 permite até 5% acima do preço do pedido.",
        evidence: [{ source: "T169G", field: "PROZ1", value: "5,00", label: "Tolerância PP (limite superior %)" }],
      },
    );
    r.related.push({ kind: "PURCHASE_ORDER", id: "4500017788" });
    r.facts.push(
      { id: "vendor", label: "Fornecedor", value: "200310 · Metalúrgica Silva S.A." },
      { id: "grossAmount", label: "Valor bruto", value: "R$ 1.150,00" },
      { id: "companyCode", label: "Empresa", value: "1000" },
    );
  },
  "5105600002/2026": (r) => {
    r.findings.push(
      {
        code: "MM02.BLOCK_QUANTITY",
        severity: "BLOCKING",
        title: "Item 1 bloqueado por quantidade",
        detail: "A quantidade faturada é maior que a quantidade recebida.",
        evidence: [{ source: "RSEG", field: "SPGRM", value: "X", label: "Motivo de bloqueio: quantidade" }],
        suggestedAction: { tcode: "MRBR", description: "Liberar depois de lançar a entrada de mercadoria" },
      },
      {
        code: "MM02.GR_MISSING",
        severity: "BLOCKING",
        title: "Entrada de mercadoria incompleta",
        detail: "Recebido: 80 PC. Faturado: 100 PC. Faltam 20 PC de entrada de mercadoria no pedido 4500017790/10.",
        evidence: [
          { source: "EKBE", field: "MENGE", value: "80", label: "Entradas de mercadoria (VGABE 1)" },
          { source: "EKBE", field: "MENGE", value: "100", label: "Faturas (VGABE 2)" },
        ],
        suggestedAction: { tcode: "MIGO", description: "Lançar a entrada de mercadoria dos 20 PC restantes" },
      },
    );
    r.related.push({ kind: "PURCHASE_ORDER", id: "4500017790" });
  },
  "5105600003/2026": (r) => {
    r.findings.push({
      code: "MM02.NOT_BLOCKED",
      severity: "INFO",
      title: "Fatura sem bloqueio",
      detail: "A fatura está lançada e liberada para pagamento. Vencimento conforme as condições de pagamento.",
      evidence: [{ source: "RBKP", field: "ZLSPR", value: "", label: "Bloqueio de pagamento: nenhum" }],
      suggestedAction: { tcode: "FBL1N", description: "Acompanhar a partida do fornecedor" },
    });
  },
  "5105600004/2026": (r) => {
    r.findings.push({
      code: "MM02.PARKED",
      severity: "WARNING",
      title: "Fatura estacionada",
      detail: "A fatura foi estacionada e ainda não foi lançada, por isso não entra no pagamento.",
      evidence: [{ source: "RBKP", field: "RBSTAT", value: "A", label: "Status: estacionada" }],
      suggestedAction: { tcode: "MIR4", description: "Completar e lançar a fatura" },
    });
  },
};

export function mm02(ctx: MockContext, params: Record<string, string>): DiagnosticResult {
  const invoice = stripLeadingZeros(params.invoiceDocument ?? "");
  const year = params.fiscalYear ?? "";
  const result = emptyResult(ctx, "MM-02", { kind: "SUPPLIER_INVOICE", id: `${invoice}/${year}` });
  const scenario = scenarios[`${invoice}/${year}`];
  if (!scenario) {
    result.status = "NOT_FOUND";
    result.findings.push({
      code: "MM02.NOT_FOUND",
      severity: "INFO",
      title: "Fatura não encontrada",
      detail: `O documento ${invoice} do exercício ${year} não existe na verificação de faturas (RBKP).`,
      evidence: [{ source: "RBKP", field: "BELNR", value: invoice, label: "Documento de faturamento" }],
    });
    return result;
  }
  scenario(result);
  return settleStatus(result);
}
