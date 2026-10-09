import type { ChatEvent, ConversationDetail, ConversationSummary } from "@raiox/contracts";
import { describe, expect, it } from "vitest";
import { applyEvent, emptyAssistant, groupConversations, turnsToItems } from "../src/lib/chat-model";

const NOW = new Date(2026, 9, 9, 15, 0, 0); // 09/10/2026 15:00 (hora local)
const at = (daysAgo: number, hour = 10) => new Date(2026, 9, 9 - daysAgo, hour).toISOString();
const conv = (id: string, updatedAt: string): ConversationSummary => ({
  id,
  title: `Conversa ${id}`,
  createdAt: updatedAt,
  updatedAt,
});

describe("groupConversations", () => {
  it("agrupa em Hoje, Ontem, Últimos 7 dias e Mais antigas, do mais recente ao mais antigo", () => {
    const groups = groupConversations(
      [conv("old", at(30)), conv("week", at(5)), conv("y", at(1, 23)), conv("t1", at(0, 8)), conv("t2", at(0, 14))],
      NOW,
    );
    expect(groups.map((g) => g.label)).toEqual(["Hoje", "Ontem", "Últimos 7 dias", "Mais antigas"]);
    expect(groups[0]?.conversations.map((c) => c.id)).toEqual(["t2", "t1"]);
    expect(groups[1]?.conversations.map((c) => c.id)).toEqual(["y"]);
    expect(groups[2]?.conversations.map((c) => c.id)).toEqual(["week"]);
    expect(groups[3]?.conversations.map((c) => c.id)).toEqual(["old"]);
  });

  it("omite grupos vazios e usa o dia do calendário (não 24 h corridas)", () => {
    const justBeforeMidnight = new Date(2026, 9, 8, 23, 59).toISOString();
    const groups = groupConversations([conv("a", justBeforeMidnight)], NOW);
    expect(groups.map((g) => g.label)).toEqual(["Ontem"]);
  });

  it("coloca exatamente 7 dias atrás em 'Últimos 7 dias' e 8 dias em 'Mais antigas'", () => {
    expect(groupConversations([conv("a", at(7))], NOW)[0]?.label).toBe("Últimos 7 dias");
    expect(groupConversations([conv("a", at(8))], NOW)[0]?.label).toBe("Mais antigas");
  });

  it("devolve lista vazia sem conversas e trata datas inválidas como antigas", () => {
    expect(groupConversations([], NOW)).toEqual([]);
    expect(groupConversations([conv("x", "invalido")], NOW)[0]?.label).toBe("Mais antigas");
  });
});

const toolStart: ChatEvent = {
  type: "tool_start",
  callId: "c1",
  diagnosticId: "SD-01",
  title: "Pedido de venda não faturado",
  params: { salesOrder: "4500001" },
};

describe("applyEvent", () => {
  it("acumula texto, chamadas de ferramenta, sugestões e conclusão", () => {
    let a = emptyAssistant("a");
    for (const e of [
      toolStart,
      { type: "tool_result", callId: "c1", diagnosticId: "SD-01", error: { code: "X", message: "Falhou" } },
      { type: "text", delta: "Olá, " },
      { type: "text", delta: "mundo" },
      { type: "suggestions", items: ["Próxima?"] },
      { type: "done" },
    ] as ChatEvent[])
      a = applyEvent(a, e);
    expect(a.text).toBe("Olá, mundo");
    expect(a.tools).toHaveLength(1);
    expect(a.tools[0]).toMatchObject({ status: "error", error: "Falhou" });
    expect(a.suggestions).toEqual(["Próxima?"]);
    expect(a.status).toBe("done");
  });

  it("ignora eventos que não mudam a mensagem (start)", () => {
    const a = emptyAssistant("a");
    expect(applyEvent(a, { type: "start", conversationId: "x", provider: "demo" })).toBe(a);
  });
});

describe("turnsToItems", () => {
  const turns: ConversationDetail["turns"] = [
    {
      question: "Por que o pedido 4500001 não faturou?",
      createdAt: at(0),
      events: [
        { type: "start", conversationId: "c", provider: "demo" },
        toolStart,
        { type: "tool_result", callId: "c1", diagnosticId: "SD-01", error: { code: "X", message: "sem acesso" } },
        { type: "text", delta: "Está em bloqueio de crédito." },
        { type: "done" },
      ],
    },
    {
      question: "E a remessa?",
      createdAt: at(0),
      // Interrompido: sem "done" e com consulta em andamento.
      events: [toolStart, { type: "text", delta: "Verificando" }],
    },
  ];

  it("transforma cada turno em pergunta + resposta, com os cartões de ferramenta", () => {
    const items = turnsToItems(turns);
    expect(items.map((i) => i.role)).toEqual(["user", "assistant", "user", "assistant"]);
    expect(items[0]).toMatchObject({ role: "user", text: "Por que o pedido 4500001 não faturou?" });
    const first = items[1];
    expect(first?.role === "assistant" && first.text).toBe("Está em bloqueio de crédito.");
    expect(first?.role === "assistant" && first.tools[0]?.diagnosticId).toBe("SD-01");
    expect(first?.role === "assistant" && first.status).toBe("done");
  });

  it("fecha turnos interrompidos sem deixar 'digitando' nem consulta em andamento", () => {
    const last = turnsToItems(turns)[3];
    expect(last?.role === "assistant" && last.status).toBe("done");
    expect(last?.role === "assistant" && last.tools[0]).toMatchObject({
      status: "error",
      error: "Consulta interrompida",
    });
  });

  it("gera ids únicos e estáveis com o prefixo informado", () => {
    const ids = turnsToItems(turns, "p-").map((i) => i.id);
    expect(new Set(ids).size).toBe(4);
    expect(ids[0]).toBe("p-0q");
  });

  it("mantém turno com erro do servidor", () => {
    const items = turnsToItems([
      { question: "x", createdAt: at(0), events: [{ type: "error", code: "INTERNAL", message: "Falha" }] },
    ]);
    const a = items[1];
    expect(a?.role === "assistant" && a.status).toBe("error");
    expect(a?.role === "assistant" && a.error).toBe("Falha");
  });
});
