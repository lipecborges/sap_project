import { ConversationDetail, ConversationList, SessionInfo, SystemsResponse } from "@raiox/contracts";
import { buildServer } from "@raiox/sap-mock";
import { eq } from "drizzle-orm";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { DemoProvider } from "../src/ai/demo-provider";
import { createApp } from "../src/app";
import { type Config, loadConfig } from "../src/config";
import { Cipher } from "../src/db/cipher";
import { auditEvents, sessions, users } from "../src/db/schema";
import { testDatabase } from "./helpers";

const SECRET = Buffer.alloc(32, 7).toString("base64");
let mock: FastifyInstance;
let config: Config;

beforeAll(async () => {
  mock = buildServer({ release: "ECC" });
  const address = await mock.listen({ port: 0, host: "127.0.0.1" });
  config = loadConfig({ SAP_BASE_URL: address, SAP_SYSTEM_NAME: "PRD", LOG_LEVEL: "silent", SESSION_SECRET: SECRET });
});
afterAll(() => mock.close());

const app = async (overrides: Partial<Config> = {}) =>
  createApp({ ...config, ...overrides }, { database: await testDatabase(), provider: new DemoProvider(0) });

async function login(api: FastifyInstance, user = "demo", password = "demo") {
  const res = await api.inject({ method: "POST", url: "/api/v1/auth/login", payload: { user, password } });
  return { res, cookie: String(res.headers["set-cookie"]).split(";")[0]! };
}

describe("cifra das sessões", () => {
  it("abre o que selou e rejeita adulteração ou outra chave", () => {
    const cipher = new Cipher(SECRET);
    const sealed = cipher.seal({ user: "DEMO", password: "segredo" });
    expect(sealed).not.toContain("segredo");
    expect(cipher.open(sealed)).toEqual({ user: "DEMO", password: "segredo" });
    expect(cipher.open(`${sealed.slice(0, -2)}xx`)).toBeUndefined();
    expect(Cipher.random().open(sealed)).toBeUndefined();
  });

  it("exige chave de 32 bytes", () => {
    expect(() => new Cipher("curta")).toThrow(/32 bytes/);
  });
});

describe("sessão no banco", () => {
  it("sobrevive ao reinício da API e guarda só o hash do id e a senha cifrada", async () => {
    const first = await app();
    const { res, cookie } = await login(first);
    const info = SessionInfo.parse(res.json());
    expect(info).toMatchObject({ user: "DEMO", role: "user", system: { id: "default", name: "PRD" } });
    await first.close();

    const second = await app();
    const again = await second.inject({ url: "/api/v1/auth/session", headers: { cookie } });
    expect(again.statusCode).toBe(200);

    const rows = await (await testDatabase()).db.select().from(sessions);
    const id = cookie.split("=")[1]!;
    expect(rows.some((r) => r.idHash === id)).toBe(false);
    expect(JSON.stringify(rows)).not.toContain('"demo"');
    await second.close();
  });

  it("com outra SESSION_SECRET, as sessões antigas deixam de valer", async () => {
    const first = await app();
    const { cookie } = await login(first);
    await first.close();
    const rotated = await app({ SESSION_SECRET: Buffer.alloc(32, 9).toString("base64") });
    expect((await rotated.inject({ url: "/api/v1/auth/session", headers: { cookie } })).statusCode).toBe(401);
    await rotated.close();
  });

  it("usuário bloqueado perde o acesso na hora", async () => {
    const api = await app();
    const { cookie } = await login(api, "vendas", "vendas");
    const db = (await testDatabase()).db;
    await db.update(users).set({ blocked: true }).where(eq(users.sapUser, "VENDAS"));
    const res = await api.inject({ url: "/api/v1/diagnostics", headers: { cookie } });
    expect(res.statusCode).toBe(403);
    expect((await login(api, "vendas", "vendas")).res.statusCode).toBe(403);
    await db.update(users).set({ blocked: false }).where(eq(users.sapUser, "VENDAS"));
    await api.close();
  });

  it("ADMIN_USERS define o papel de administrador", async () => {
    const api = await app({ ADMIN_USERS: ["DEMO"] });
    expect(SessionInfo.parse((await login(api)).res.json()).role).toBe("admin");
    await api.close();
  });

  it("lista os sistemas SAP sem expor endereços", async () => {
    const api = await app();
    const res = await api.inject({ url: "/api/v1/auth/systems" });
    const body = SystemsResponse.parse(res.json());
    expect(body.systems).toEqual([{ id: "default", name: "PRD", isDefault: true }]);
    expect(res.body).not.toContain("127.0.0.1");
    await api.close();
  });
});

describe("histórico de conversas", () => {
  it("grava os turnos, lista, reabre com o mesmo contexto e apaga", async () => {
    const api = await app();
    const { cookie } = await login(api);
    const ask = async (message: string, conversationId?: string) => {
      const res = await api.inject({
        method: "POST",
        url: "/api/v1/chat",
        headers: { cookie },
        payload: { message, ...(conversationId ? { conversationId } : {}) },
      });
      const start = res.body.split("\n\n").find((c) => c.includes('"start"'));
      return JSON.parse(start!.slice(6)).conversationId as string;
    };
    const id = await ask("Por que o pedido 4500001 não faturou?");
    expect(await ask("e o pedido 4500002?", id)).toBe(id);

    const list = ConversationList.parse(
      (await api.inject({ url: "/api/v1/conversations", headers: { cookie } })).json(),
    );
    expect(list.conversations[0]).toMatchObject({ id, title: "Por que o pedido 4500001 não faturou?" });

    const detail = ConversationDetail.parse(
      (await api.inject({ url: `/api/v1/conversations/${id}`, headers: { cookie } })).json(),
    );
    expect(detail.turns.map((t) => t.question)).toEqual([
      "Por que o pedido 4500001 não faturou?",
      "e o pedido 4500002?",
    ]);
    expect(detail.turns[0]?.events.some((e) => e.type === "tool_result")).toBe(true);

    // Outro usuário não enxerga a conversa.
    const other = await login(api, "vendas", "vendas");
    expect(
      (await api.inject({ url: `/api/v1/conversations/${id}`, headers: { cookie: other.cookie } })).statusCode,
    ).toBe(404);

    expect(
      (await api.inject({ method: "DELETE", url: `/api/v1/conversations/${id}`, headers: { cookie } })).statusCode,
    ).toBe(200);
    expect((await api.inject({ url: `/api/v1/conversations/${id}`, headers: { cookie } })).statusCode).toBe(404);
    await api.close();
  });
});

describe("auditoria", () => {
  it("registra login, falha de login, diagnóstico e turno do assistente, sem senha", async () => {
    const api = await app();
    await login(api, "demo", "errada");
    const { cookie } = await login(api);
    await api.inject({
      method: "POST",
      url: "/api/v1/diagnostics/SD-01",
      headers: { cookie },
      payload: { params: { salesOrder: "4500001" } },
    });
    await api.inject({
      method: "POST",
      url: "/api/v1/diagnostics/PP-03",
      headers: { cookie: (await login(api, "vendas", "vendas")).cookie },
      payload: { params: { productionOrder: "1000010" } },
    });
    const rows = await (await testDatabase()).db.select().from(auditEvents);
    const actions = rows.map((r) => `${r.action}:${r.sapUser}:${r.target ?? ""}:${r.outcome}`);
    expect(actions).toContain("LOGIN_FAILED:DEMO::UNAUTHENTICATED");
    expect(actions).toContain("LOGIN:DEMO::ok");
    expect(actions).toContain("DIAGNOSTIC_RUN:DEMO:SD-01:ok");
    expect(actions).toContain("DIAGNOSTIC_RUN:VENDAS:PP-03:NOT_AUTHORIZED");
    const run = rows.find((r) => r.target === "SD-01" && (r.details as { via?: string }).via === "direct");
    expect(run?.details).toMatchObject({ params: { salesOrder: "4500001" }, via: "direct" });
    expect(run?.durationMs).toBeGreaterThanOrEqual(0);
    expect(JSON.stringify(rows)).not.toContain("errada");
    await api.close();
  });
});

describe("prontidão", () => {
  it("/api/ready confirma o banco", async () => {
    const api = await app();
    expect((await api.inject({ url: "/api/ready" })).json()).toEqual({
      status: "ready",
      database: process.env.TEST_DATABASE_URL ? "postgres" : "pglite",
    });
    await api.close();
  });
});
