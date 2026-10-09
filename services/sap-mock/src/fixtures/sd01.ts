import { type DiagnosticResult, type Evidence, type Finding, stripLeadingZeros } from "@raiox/contracts";
import { emptyResult, type MockContext, settleStatus } from "../context";

/**
 * SD-01: Pedido de venda não faturado.
 * Cenários (pedido → situação):
 *   4500001 bloqueio de crédito
 *   4500002 bloqueio de remessa + incompletude
 *   4500003 remessa criada, sem saída de mercadoria
 *   4500004 já faturado
 *   4500005 bloqueio de faturamento + item recusado
 */

/** No S/4 os status do documento SD saíram da VBUK e foram para a VBAK/LIKP. */
function headerStatus(ctx: MockContext, field: string, value: string, label: string): Evidence {
  return { source: ctx.release === "ECC" ? "VBUK" : "VBAK", field, value, label };
}

function deliveryStatus(ctx: MockContext, field: string, value: string, label: string): Evidence {
  return { source: ctx.release === "ECC" ? "VBUK" : "LIKP", field, value, label };
}

const scenarios: Record<string, (ctx: MockContext, r: DiagnosticResult) => void> = {
  "4500001": (ctx, r) => {
    r.findings.push({
      code: "SD01.CREDIT_BLOCK",
      severity: "BLOCKING",
      title: "Pedido bloqueado por crédito",
      detail: "A verificação de crédito não aprovou o pedido: o cliente 100234 excedeu o limite em R$ 18.450,00.",
      evidence: [headerStatus(ctx, "CMGST", "B", "Status de crédito: não aprovado")],
      suggestedAction:
        ctx.release === "ECC"
          ? { tcode: "VKM3", description: "Solicitar a liberação ao responsável de crédito" }
          : { tcode: "UKM_MY_DCDS", description: "Solicitar a decisão de crédito ao responsável (FSCM)" },
    });
    r.facts.push(
      { id: "customer", label: "Cliente", value: "100234 · Comercial Andrade Ltda." },
      { id: "netValue", label: "Valor líquido", value: "R$ 48.450,00" },
      { id: "salesOrg", label: "Org. de vendas", value: "1000" },
    );
  },
  "4500002": (ctx, r) => {
    r.findings.push(
      {
        code: "SD01.DELIVERY_BLOCK_HEADER",
        severity: "BLOCKING",
        title: "Bloqueio de remessa no cabeçalho",
        detail: "O pedido está com o bloqueio de remessa 01 (Bloqueio geral).",
        evidence: [{ source: "VBAK", field: "LIFSK", value: "01", label: "Bloqueio de remessa: Bloqueio geral" }],
        suggestedAction: { tcode: "VA02", description: "Remover o bloqueio de remessa, se autorizado" },
      },
      {
        code: "SD01.INCOMPLETE",
        severity: "BLOCKING",
        title: "Pedido incompleto",
        detail: "Faltam dados obrigatórios para remessa e faturamento: condições de pagamento e incoterms.",
        evidence: [
          { source: "VBUV", field: "FDNAM", value: "ZTERM", label: "Campo faltante: condições de pagamento" },
          { source: "VBUV", field: "FDNAM", value: "INCO1", label: "Campo faltante: incoterms" },
          headerStatus(ctx, "UVALL", "A", "Status de incompletude: incompleto"),
        ],
        suggestedAction: { tcode: "VA02", description: "Completar os dados pelo log de incompletude" },
      },
    );
  },
  "4500003": (ctx, r) => {
    r.findings.push({
      code: "SD01.GOODS_ISSUE_PENDING",
      severity: "BLOCKING",
      title: "Remessa sem saída de mercadoria",
      detail:
        "A remessa 80000123 foi criada, mas a saída de mercadoria não foi lançada. O faturamento depende dela. Rode o diagnóstico SD-02 para a remessa.",
      evidence: [
        { source: "VBFA", field: "VBTYP_N", value: "J", label: "Documento subsequente: remessa 80000123" },
        deliveryStatus(ctx, "WBSTK", "A", "Status de saída de mercadoria: não processado"),
      ],
      suggestedAction: { tcode: "VL02N", description: "Lançar a saída de mercadoria da remessa 80000123" },
    });
    r.related.push({ kind: "DELIVERY", id: "80000123" });
  },
  "4500004": (_ctx, r) => {
    r.findings.push({
      code: "SD01.ALREADY_BILLED",
      severity: "INFO",
      title: "Pedido já faturado",
      detail: "O pedido foi faturado pela fatura 90000456, a partir da remessa 80000124.",
      evidence: [{ source: "VBFA", field: "VBTYP_N", value: "M", label: "Documento subsequente: fatura 90000456" }],
      suggestedAction: { tcode: "VF03", description: "Exibir a fatura 90000456" },
    });
    r.related.push({ kind: "DELIVERY", id: "80000124" }, { kind: "BILLING_DOCUMENT", id: "90000456" });
  },
  "4500005": (_ctx, r) => {
    r.findings.push(
      {
        code: "SD01.BILLING_BLOCK",
        severity: "BLOCKING",
        title: "Bloqueio de faturamento",
        detail: "O pedido está com o bloqueio de faturamento 02 (Verificar preço).",
        evidence: [{ source: "VBAK", field: "FAKSK", value: "02", label: "Bloqueio de faturamento: Verificar preço" }],
        suggestedAction: { tcode: "VA02", description: "Conferir o preço e remover o bloqueio de faturamento" },
      },
      {
        code: "SD01.ITEM_REJECTED",
        severity: "INFO",
        title: "Item 20 recusado",
        detail: "O item 20 foi recusado (motivo 01: Prazo de entrega inaceitável) e não será faturado.",
        evidence: [{ source: "VBAP", field: "ABGRU", value: "01", label: "Motivo de recusa do item 20" }],
      },
    );
    r.related.push({ kind: "DELIVERY", id: "80000125" });
  },
};

export function sd01(ctx: MockContext, params: Record<string, string>): DiagnosticResult {
  const salesOrder = stripLeadingZeros(params.salesOrder ?? "");
  const scenario = scenarios[salesOrder];
  const result = emptyResult(ctx, "SD-01", { kind: "SALES_ORDER", id: salesOrder });
  if (!scenario) {
    result.status = "NOT_FOUND";
    result.findings.push(notFound(salesOrder));
    return result;
  }
  scenario(ctx, result);
  return settleStatus(result);
}

function notFound(salesOrder: string): Finding {
  return {
    code: "SD01.NOT_FOUND",
    severity: "INFO",
    title: "Pedido não encontrado",
    detail: `O pedido de venda ${salesOrder} não existe neste sistema/mandante.`,
    evidence: [{ source: "VBAK", field: "VBELN", value: salesOrder, label: "Pedido de venda" }],
  };
}
