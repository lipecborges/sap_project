import type Anthropic from "@anthropic-ai/sdk";
import type { DiagnosticResult } from "@raiox/contracts";
import type { AgentTurn, LlmProvider, ToolOutcome } from "./provider";
import { summarize } from "./summarize";

/**
 * Modo demonstração: entende perguntas comuns por regras simples, chama os mesmos
 * diagnósticos e monta a resposta a partir dos achados. Não usa modelo de IA nem
 * internet, então funciona no self-hosted offline e em demos sem chave de API.
 */
export class DemoProvider implements LlmProvider {
  readonly name = "demo" as const;

  constructor(private readonly typingDelayMs = 12) {}

  async respond(turn: AgentTurn): Promise<Anthropic.Beta.BetaMessageParam[]> {
    const plan = planFor(turn.message);
    const allowed = new Set(turn.diagnostics.map((d) => d.id));
    const parts: string[] = [];

    if (plan.length === 0) {
      parts.push(HELP);
    }
    for (const step of plan) {
      if (!allowed.has(step.id)) {
        parts.push(
          `Você não tem autorização para o diagnóstico ${step.id} (objeto ZRX_DIAG). Fale com o administrador SAP.`,
        );
        continue;
      }
      const outcome: ToolOutcome = await turn.runTool(step.id, step.params);
      if (outcome.error) {
        parts.push(`Não consegui executar o ${step.id}: ${outcome.error.message}`);
        continue;
      }
      const result = outcome.result as DiagnosticResult;
      parts.push(summarize(result));
      // Aprofunda como um analista faria: ordem com falta de material → detalhe dos componentes.
      if (step.id === "PP-03" && allowed.has("PP-01") && result.findings.some((f) => f.code === "PP03.MISSING_PARTS")) {
        const deeper = await turn.runTool("PP-01", { productionOrder: step.params.productionOrder ?? "" });
        if (deeper.result) parts.push(summarize(deeper.result, "**Detalhe da falta de material** (PP-01)"));
      }
    }

    const text = parts.join("\n\n");
    await this.type(text, turn);
    return [
      { role: "user", content: turn.message },
      { role: "assistant", content: [{ type: "text", text }] },
    ];
  }

  private async type(text: string, turn: AgentTurn) {
    const chunks = text.match(/\S+\s*|\s+/g) ?? [text];
    for (const chunk of chunks) {
      if (turn.signal.aborted) return;
      turn.emitText(chunk);
      if (this.typingDelayMs > 0) await new Promise((r) => setTimeout(r, this.typingDelayMs));
    }
  }
}

const HELP = `Sou o assistente do Raio-X em **modo demonstração** (sem modelo de IA configurado). Entendo perguntas como:

- "Por que o pedido 4500001 não faturou?"
- "Como está a ordem 1000010?"
- "Por que a fatura 5105600001 está bloqueada?"
- "Quais ordens estão atrasadas no centro 1000?"
- "Quais pedidos estão travados?" ou "Quais faturas estão bloqueadas?"
- "Me dá um panorama de hoje"

Com um modelo de IA configurado (AI_PROVIDER=anthropic), entendo perguntas livres e combino os diagnósticos sozinho.`;

interface Step {
  id: string;
  params: Record<string, string>;
}

function normalize(text: string): string {
  return text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
}

/** Regras de intenção do modo demonstração. */
export function planFor(message: string): Step[] {
  const text = normalize(message);
  const numbers = message.match(/\b\d{6,10}\b/g) ?? [];
  const year = message.match(/\b(20\d{2})\b/)?.[1] ?? String(new Date().getFullYear());
  const plant = text.match(/centro\s*(\d{4})/)?.[1] ?? "1000";

  for (const n of numbers) {
    if (n.length === 10 && n.startsWith("51"))
      return [{ id: "MM-02", params: { invoiceDocument: n, fiscalYear: year } }];
    if (n.length === 7 && n.startsWith("45")) return [{ id: "SD-01", params: { salesOrder: n } }];
    if (n.length === 7 && /^[12]/.test(n)) {
      const releaseQuestion = /libera|componente|falta/.test(text) && !/situa|andamento|como esta|atras/.test(text);
      return [{ id: releaseQuestion ? "PP-01" : "PP-03", params: { productionOrder: n } }];
    }
  }

  if (/panorama|resumo|visao geral|como estamos|bom dia|o que precisa/.test(text)) {
    return [
      { id: "PP-04", params: { plant, situation: "LATE_FINISH" } },
      { id: "SD-10", params: {} },
      { id: "MM-10", params: {} },
    ];
  }
  if (/fatura/.test(text) && !/faturou|faturad|faturamento/.test(text)) {
    return [{ id: "MM-10", params: /estacionad/.test(text) ? { state: "PARKED" } : {} }];
  }
  if (/pedido/.test(text)) {
    const stage = /credito/.test(text) ? "CREDIT" : /remessa/.test(text) ? "DELIVERY" : undefined;
    return [{ id: "SD-10", params: stage ? { stage } : {} }];
  }
  if (/ordem|ordens|producao|\bops?\b|fabrica/.test(text)) {
    const situation = /falta|componente/.test(text)
      ? "MISSING_PARTS"
      : /aprovad/.test(text)
        ? "APPROVED"
        : /sem entrada/.test(text)
          ? "CONFIRMED_NOT_RECEIVED"
          : /liberad/.test(text)
            ? "RELEASED"
            : /atras/.test(text)
              ? "LATE_FINISH"
              : undefined;
    return [{ id: "PP-04", params: situation ? { plant, situation } : { plant } }];
  }
  return [];
}
