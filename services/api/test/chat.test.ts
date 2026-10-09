import type Anthropic from "@anthropic-ai/sdk";
import { ChatEvent, OverviewResponse } from "@raiox/contracts";
import { buildServer } from "@raiox/sap-mock";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { AnthropicProvider } from "../src/ai/anthropic-provider";
import { DemoProvider, planFor } from "../src/ai/demo-provider";
import type { LlmProvider } from "../src/ai/provider";
import { createApp } from "../src/app";
import { type Config, loadConfig } from "../src/config";
import { testDatabase } from "./helpers";

let mock: FastifyInstance;
let config: Config;
const DEMO = `Basic ${Buffer.from("DEMO:demo").toString("base64")}`;

beforeAll(async () => {
  mock = buildServer({ release: "ECC" });
  const address = await mock.listen({ port: 0, host: "127.0.0.1" });
  config = loadConfig({ SAP_BASE_URL: address, LOG_LEVEL: "silent" });
});
afterAll(() => mock.close());

function parseSse(body: string): ChatEvent[] {
  return body
    .split("\n\n")
    .filter((chunk) => chunk.startsWith("data: "))
    .map((chunk) => ChatEvent.parse(JSON.parse(chunk.slice(6))));
}

async function chat(api: FastifyInstance, message: string, conversationId?: string, authorization = DEMO) {
  const res = await api.inject({
    method: "POST",
    url: "/api/v1/chat",
    headers: { authorization },
    payload: { message, ...(conversationId ? { conversationId } : {}) },
  });
  return { status: res.statusCode, events: parseSse(res.body) };
}

const text = (events: ChatEvent[]) =>
  events
    .filter((e): e is Extract<ChatEvent, { type: "text" }> => e.type === "text")
    .map((e) => e.delta)
    .join("");

describe("modo demonstração", () => {
  it("entende a pergunta, consulta o SAP e explica com a transação", async () => {
    const api = await createApp(config, { database: await testDatabase(), provider: new DemoProvider(0) });
    const { status, events } = await chat(api, "Por que o pedido 4500001 não faturou?");
    expect(status).toBe(200);
    expect(events[0]).toMatchObject({ type: "start", provider: "demo" });
    const toolResult = events.find((e) => e.type === "tool_result");
    expect(toolResult).toMatchObject({ diagnosticId: "SD-01" });
    expect(text(events)).toContain("bloqueado por crédito");
    expect(text(events)).toContain("`VKM3`");
    expect(events.at(-2)?.type).toBe("suggestions");
    expect(events.at(-1)?.type).toBe("done");
    await api.close();
  });

  it("aprofunda na falta de material (PP-03 → PP-01)", async () => {
    const api = await createApp(config, { database: await testDatabase(), provider: new DemoProvider(0) });
    const { events } = await chat(api, "Como está a ordem 1000010?");
    const tools = events
      .filter((e) => e.type === "tool_start")
      .map((e) => (e as { diagnosticId: string }).diagnosticId);
    expect(tools).toEqual(["PP-03", "PP-01"]);
    await api.close();
  });

  it("respeita a autorização do usuário", async () => {
    const api = await createApp(config, { database: await testDatabase(), provider: new DemoProvider(0) });
    const vendas = `Basic ${Buffer.from("VENDAS:vendas").toString("base64")}`;
    const { events } = await chat(api, "Como está a ordem 1000010?", undefined, vendas);
    expect(events.some((e) => e.type === "tool_start")).toBe(false);
    expect(text(events)).toContain("não tem autorização");
    await api.close();
  });

  it.each([
    ["Por que a fatura 5105600001 está bloqueada?", "MM-02"],
    ["quais ordens estão atrasadas no centro 1000", "PP-04"],
    ["Quais pedidos estão travados por crédito?", "SD-10"],
    ["faturas bloqueadas", "MM-10"],
    ["a ordem 1000001 não liberou, falta componente?", "PP-01"],
  ])("planFor(%s) → %s", (message, id) => {
    expect(planFor(message)[0]?.id).toBe(id);
  });
});

describe("painel", () => {
  it("devolve produção, vendas e compras; falta de autorização vira erro da seção", async () => {
    const api = await createApp(config, { database: await testDatabase(), provider: new DemoProvider(0) });
    const res = await api.inject({ url: "/api/v1/overview", headers: { authorization: DEMO } });
    const body = OverviewResponse.parse(res.json());
    expect(body.production.result?.diagnosticId).toBe("PP-04");
    expect(body.sales.result?.diagnosticId).toBe("SD-10");
    expect(body.purchasing.result?.diagnosticId).toBe("MM-10");

    const vendas = `Basic ${Buffer.from("VENDAS:vendas").toString("base64")}`;
    const limited = OverviewResponse.parse(
      (await api.inject({ url: "/api/v1/overview", headers: { authorization: vendas } })).json(),
    );
    expect(limited.sales.result).toBeDefined();
    expect(limited.production.error?.code).toBe("NOT_AUTHORIZED");
    await api.close();
  });
});

/** Cliente falso da Anthropic: devolve respostas roteirizadas e guarda as requisições. */
function fakeClient(script: Array<Partial<Anthropic.Beta.BetaMessage>>) {
  const requests: Anthropic.Beta.MessageCreateParams[] = [];
  const client = {
    beta: {
      messages: {
        stream(params: Anthropic.Beta.MessageCreateParams) {
          requests.push(structuredClone(params));
          const message = script.shift();
          if (!message) throw new Error("roteiro acabou");
          const listeners: Array<(delta: string) => void> = [];
          return {
            on(_event: "text", fn: (delta: string) => void) {
              listeners.push(fn);
              return this;
            },
            async finalMessage() {
              for (const block of message.content ?? [])
                if (block.type === "text") for (const fn of listeners) fn(block.text);
              return message;
            },
          };
        },
      },
    },
  };
  return { client: client as unknown as Anthropic, requests };
}

describe("provedor Claude (cliente simulado)", () => {
  it("executa a ferramenta pedida, devolve o resultado e grava a conversa só acrescentando", async () => {
    const { client, requests } = fakeClient([
      {
        stop_reason: "tool_use",
        content: [
          { type: "text", text: "Vou consultar a ordem.", citations: null },
          {
            type: "tool_use",
            id: "tu_1",
            name: "diag_pp_03",
            input: { productionOrder: "1000010" },
          } as Anthropic.Beta.BetaToolUseBlock,
        ],
      },
      { stop_reason: "end_turn", content: [{ type: "text", text: " A ordem está atrasada 3 dias.", citations: null }] },
      { stop_reason: "end_turn", content: [{ type: "text", text: "Sim.", citations: null }] },
    ]);
    const provider: LlmProvider = new AnthropicProvider({
      model: "claude-opus-5-5",
      effort: "medium",
      fallbacks: true,
      client,
    });
    const api = await createApp(config, { database: await testDatabase(), provider });

    const first = await chat(api, "Como está a ordem 1000010?");
    expect(first.events.find((e) => e.type === "tool_result")).toMatchObject({ diagnosticId: "PP-03" });
    expect(text(first.events)).toBe("Vou consultar a ordem. A ordem está atrasada 3 dias.");

    // 1ª chamada: ferramentas e parâmetros de modelo
    const firstRequest = requests[0] as Anthropic.Beta.MessageCreateParams & { fallbacks?: unknown };
    expect(firstRequest.model).toBe("claude-opus-5-5");
    expect(firstRequest.fallbacks).toBe("default");
    expect(firstRequest.tools?.map((t) => (t as { name: string }).name)).toContain("diag_pp_03");

    // 2ª chamada: o resultado da ferramenta volta numa mensagem de usuário com tool_result
    const toolTurn = requests[1]!.messages.at(-1)!;
    expect(toolTurn.role).toBe("user");
    expect(JSON.stringify(toolTurn.content)).toContain('"tool_use_id":"tu_1"');

    // 2º turno da conversa: o histórico anterior é reenviado intacto
    const conversationId = (first.events[0] as { conversationId: string }).conversationId;
    await chat(api, "Isso afeta o cliente?", conversationId);
    const history = requests[2]!.messages;
    expect(history).toHaveLength(5);
    expect(history.slice(0, 4)).toEqual(
      requests[1]!.messages.concat([{ role: "assistant", content: history[3]!.content }]),
    );
    await api.close();
  });

  it("não reaproveita conversa de outro usuário", async () => {
    const { client, requests } = fakeClient([
      { stop_reason: "end_turn", content: [{ type: "text", text: "Olá.", citations: null }] },
      { stop_reason: "end_turn", content: [{ type: "text", text: "Olá.", citations: null }] },
    ]);
    const api = await createApp(config, {
      database: await testDatabase(),
      provider: new AnthropicProvider({ model: "m", effort: "low", fallbacks: false, client }),
    });
    const first = await chat(api, "oi");
    const id = (first.events[0] as { conversationId: string }).conversationId;
    const other = `Basic ${Buffer.from("VENDAS:vendas").toString("base64")}`;
    const second = await chat(api, "oi", id, other);
    expect((second.events[0] as { conversationId: string }).conversationId).not.toBe(id);
    expect(requests[1]!.messages).toHaveLength(1);
    await api.close();
  });
});

describe("SSE por HTTP real", () => {
  it("transmite o texto até o fim (não aborta ao terminar de ler a requisição)", async () => {
    const api = await createApp(config, { database: await testDatabase(), provider: new DemoProvider(0) });
    const address = await api.listen({ port: 0, host: "127.0.0.1" });
    const res = await fetch(`${address}/api/v1/chat`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: DEMO },
      body: JSON.stringify({ message: "Por que o pedido 4500001 não faturou?" }),
    });
    const events = parseSse(await res.text());
    expect(text(events)).toContain("bloqueado por crédito");
    await api.close();
  });
});
