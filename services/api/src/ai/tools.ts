import type Anthropic from "@anthropic-ai/sdk";
import type { DiagnosticMeta, DiagnosticResult, ParamMeta } from "@raiox/contracts";

/** Quando a IA deve usar cada diagnóstico (vai na descrição da ferramenta). */
const GUIDANCE: Record<string, string> = {
  "SD-01":
    "Diagnostica por que UM pedido de venda não faturou: crédito, bloqueios de remessa/faturamento, incompletude, saída de mercadoria, status. Use quando o usuário citar um número de pedido de venda (normalmente começa com 45).",
  "SD-10":
    "Lista os pedidos de venda travados antes do faturamento, com a etapa (crédito, remessa, saída de mercadoria, faturamento), motivo e dias em aberto. Use para perguntas gerais sobre pedidos parados ou bloqueados.",
  "MM-02":
    "Diagnostica por que UMA fatura de fornecedor (verificação de faturas/MIRO) está bloqueada para pagamento: preço, quantidade, data, tolerâncias, entrada de mercadoria. Precisa do número do documento (normalmente 10 dígitos começando com 51) e do exercício.",
  "MM-10":
    "Lista as faturas de fornecedor bloqueadas ou estacionadas, por vencimento, com motivo e valor retido. Use para perguntas gerais sobre faturas presas ou pagamentos travados.",
  "PP-01":
    "Diagnostica por que UMA ordem de produção não foi liberada ou está com falta de componentes: status, status de usuário, bloqueio, componentes sem estoque.",
  "PP-03":
    "Visão completa de UMA ordem de produção: situação, sinalizadores (atraso, falta de material, risco para o pedido do cliente), quantidades, datas, operações, componentes e apontamentos. Use para 'como está a ordem X', atraso, andamento.",
  "PP-04":
    "Lista ordens de produção de um centro filtrando por situação ou sinalizador (atrasadas, falta de material, liberadas, aprovadas etc.), ordenadas por atraso. Use para perguntas gerais sobre a produção.",
};

const PARAM_HINTS: Record<ParamMeta["dataType"], string> = {
  DOCUMENT: "Somente dígitos.",
  INTEGER: "Somente dígitos.",
  DATE: "Formato AAAA-MM-DD.",
  STRING: "",
  ENUM: "",
};

export function toolName(id: string): string {
  return `diag_${id.toLowerCase().replace(/-/g, "_")}`;
}

export function toAnthropicTools(diagnostics: DiagnosticMeta[]): Anthropic.Beta.BetaTool[] {
  return diagnostics.map((d) => {
    const properties: Record<string, unknown> = {};
    for (const p of d.params) {
      properties[p.name] = {
        type: "string",
        description: [p.label, PARAM_HINTS[p.dataType]].filter(Boolean).join(". "),
        ...(p.dataType === "ENUM" ? { enum: p.options } : {}),
        ...(p.dataType === "DOCUMENT" || p.dataType === "INTEGER" ? { pattern: "^[0-9]+$" } : {}),
      };
    }
    return {
      name: toolName(d.id),
      description: `${d.title} (${d.id}). ${GUIDANCE[d.id] ?? ""}`.trim(),
      input_schema: {
        type: "object",
        properties,
        required: d.params.filter((p) => p.required).map((p) => p.name),
        additionalProperties: false,
      },
      // Padrão para ferramentas próprias em streaming; a entrada é validada antes de executar.
      eager_input_streaming: true,
    };
  });
}

/**
 * Resultado enviado ao modelo: o contrato inteiro, com tabelas limitadas
 * para não estourar o contexto em listas grandes.
 */
export function resultForModel(result: DiagnosticResult, maxRows = 50): string {
  return JSON.stringify({
    ...result,
    tables: result.tables.map((t) => ({
      ...t,
      rows: t.rows.slice(0, maxRows),
      truncated: t.truncated || t.rows.length > maxRows,
    })),
  });
}
