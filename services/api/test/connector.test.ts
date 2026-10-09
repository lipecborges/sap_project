import { ConnectorClient, type ConnectorClientOptions, checkPath } from "@raiox/connector";
import { AdminConnectorCreated, AdminConnectorList, ApiError, DiagnosticResult } from "@raiox/contracts";
import { buildServer } from "@raiox/sap-mock";
import type { FastifyInstance } from "fastify";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { WebSocket } from "ws";
import { createApp } from "../src/app";
import { loadConfig } from "../src/config";
import type { GatewayOptions } from "../src/connector/hub";
import { ConnectorRepository } from "../src/connector/repository";
import { auditEvents } from "../src/db/schema";
import { testDatabase } from "./helpers";

const basic = (user: string, password: string) => `Basic ${Buffer.from(`${user}:${password}`).toString("base64")}`;
const DEMO = basic("DEMO", "demo");
const SAP_API_PATH = "/sap/bc/zrx/api/v1";

let mock: FastifyInstance;
let mockUrl: string;
const cleanups: Array<() => Promise<void>> = [];

beforeAll(async () => {
  mock = buildServer({ release: "S4" });
  mockUrl = await mock.listen({ port: 0, host: "127.0.0.1" });
});

afterEach(async () => {
  for (const cleanup of cleanups.splice(0).reverse()) await cleanup();
});

afterAll(async () => {
  await mock.close();
});

interface Harness {
  api: FastifyInstance;
  port: number;
  connectorId: string;
  token: string;
  /** Reabre a API na mesma porta (simula reinício do servidor). */
  restart(): Promise<void>;
}

/** API real (Cloud, transporte conector) escutando numa porta, com um conector já cadastrado. */
async function startApi(env: Record<string, string> = {}, gateway: GatewayOptions = {}): Promise<Harness> {
  const database = await testDatabase();
  const { connector, token } = await new ConnectorRepository(database.db).create("default", "Conector de teste");
  const config = loadConfig({
    DEPLOYMENT_MODE: "cloud",
    SAP_CONNECTOR_ID: connector.id,
    ADMIN_USERS: "DEMO",
    LOG_LEVEL: "silent",
    ...env,
  });
  const harness: Harness = {
    api: await createApp(config, { database, gateway: { graceMs: 0, ...gateway } }),
    port: 0,
    connectorId: connector.id,
    token,
    restart: async () => {
      await harness.api.close();
      harness.api = await createApp(config, { database, gateway: { graceMs: 0, ...gateway } });
      await harness.api.listen({ port: harness.port, host: "127.0.0.1" });
    },
  };
  await harness.api.listen({ port: 0, host: "127.0.0.1" });
  harness.port = (harness.api.server.address() as { port: number }).port;
  cleanups.push(() => harness.api.close());
  return harness;
}

/** Conector real (o mesmo código do serviço) apontado para o mock do SAP. */
function startConnector(h: Harness, options: ConnectorClientOptions = {}, token = h.token): ConnectorClient {
  const client = new ConnectorClient(
    {
      raioxUrl: `ws://127.0.0.1:${h.port}`,
      token,
      sapBaseUrl: mockUrl,
      sapApiPath: SAP_API_PATH,
      sapTimeoutMs: 5000,
      logLevel: "silent",
    },
    { baseDelayMs: 20, maxDelayMs: 100, shutdownGraceMs: 200, ...options },
  );
  client.start();
  cleanups.push(() => client.stop());
  return client;
}

interface FakeConnector {
  ws: WebSocket;
  requests: Array<{ id: string; method: string; path: string; timeoutMs: number }>;
  closed: Promise<number>;
}

/** Conector de mentira: cumprimenta e registra as requisições, mas só responde se o teste mandar. */
async function fakeConnector(h: Harness, options: { autoPong?: boolean } = {}): Promise<FakeConnector> {
  const ws = new WebSocket(`ws://127.0.0.1:${h.port}/connector/v1/ws`, {
    headers: { authorization: `Bearer ${h.token}` },
    autoPong: options.autoPong ?? true,
  });
  const fake: FakeConnector = {
    ws,
    requests: [],
    closed: new Promise((resolve) => ws.on("close", (code) => resolve(code))),
  };
  ws.on("message", (data) => {
    const frame = JSON.parse(data.toString());
    if (frame.type === "request") fake.requests.push(frame);
  });
  ws.on("error", () => {});
  await new Promise<void>((resolve, reject) => {
    ws.once("open", resolve);
    ws.once("error", reject);
  });
  ws.send(JSON.stringify({ type: "hello", v: 1, version: "test" }));
  await new Promise<void>((resolve) => ws.once("message", () => resolve()));
  cleanups.push(async () => ws.terminate());
  return fake;
}

async function eventually(check: () => boolean | Promise<boolean>, timeoutMs = 3000): Promise<void> {
  const limit = Date.now() + timeoutMs;
  while (!(await check())) {
    if (Date.now() > limit) throw new Error("condição não atendida a tempo");
    await new Promise((r) => setTimeout(r, 10));
  }
}

const runDiagnostic = (api: FastifyInstance) =>
  api.inject({
    method: "POST",
    url: "/api/v1/diagnostics/SD-01",
    headers: { authorization: DEMO },
    payload: { params: { salesOrder: "4500001" } },
  });

describe("gateway de conectores", () => {
  it("entrega o diagnóstico pelo conector com o mesmo resultado do transporte direto", async () => {
    const database = await testDatabase();
    const direct = await createApp(
      loadConfig({ DEPLOYMENT_MODE: "selfhosted", SAP_BASE_URL: mockUrl, LOG_LEVEL: "silent" }),
      { database },
    );
    const expected = await runDiagnostic(direct);
    await direct.close();
    expect(expected.statusCode).toBe(200);

    const h = await startApi();
    const client = startConnector(h);
    await client.waitFor("online");
    const res = await runDiagnostic(h.api);
    expect(res.statusCode).toBe(200);
    const result = DiagnosticResult.parse(res.json());
    const reference = DiagnosticResult.parse(expected.json());
    expect(result.findings).toEqual(reference.findings);
    expect(result.system.release).toBe("S4");
    expect(result.findings[0]?.code).toBe("SD01.CREDIT_BLOCK");
  });

  it("repassa erros do SAP (credencial inválida) como no transporte direto", async () => {
    const h = await startApi();
    await startConnector(h).waitFor("online");
    const res = await h.api.inject({
      method: "POST",
      url: "/api/v1/diagnostics/SD-01",
      headers: { authorization: basic("DEMO", "errada") },
      payload: { params: { salesOrder: "4500001" } },
    });
    expect(res.statusCode).toBe(401);
    expect(ApiError.parse(res.json()).error.code).toBe("UNAUTHENTICATED");
  });

  it("conector offline responde 503 SAP_UNAVAILABLE", async () => {
    const h = await startApi();
    const res = await runDiagnostic(h.api);
    expect(res.statusCode).toBe(503);
    const error = ApiError.parse(res.json()).error;
    expect(error.code).toBe("SAP_UNAVAILABLE");
    expect(error.message).toMatch(/offline/);
  });

  it("rejeita token inválido antes do upgrade e o cliente para de tentar", async () => {
    const h = await startApi();
    const status = await new Promise<number>((resolve) => {
      const ws = new WebSocket(`ws://127.0.0.1:${h.port}/connector/v1/ws`, {
        headers: { authorization: "Bearer nope" },
      });
      ws.on("unexpected-response", (_req, res) => resolve(res.statusCode ?? 0));
      ws.on("error", () => {});
    });
    expect(status).toBe(401);

    const client = startConnector(h, {}, "token-invalido");
    const fatal = new Promise<string>((resolve) => client.onFatal(resolve));
    expect(await fatal).toMatch(/inválido ou revogado/);
    expect(client.state).toBe("stopped");
  });

  it("revogar pelo admin derruba o conector conectado", async () => {
    const h = await startApi();
    const client = startConnector(h);
    const fatal = new Promise<string>((resolve) => client.onFatal(resolve));
    await client.waitFor("online");
    expect(h.api.ctx.hub.isOnline(h.connectorId)).toBe(true);

    const res = await h.api.inject({
      method: "DELETE",
      url: `/api/v1/admin/connectors/${h.connectorId}`,
      headers: { authorization: DEMO },
    });
    expect(res.statusCode).toBe(204);
    expect(h.api.ctx.hub.isOnline(h.connectorId)).toBe(false);
    // O cliente tenta reconectar, recebe 401 e para.
    await fatal;
    expect((await runDiagnostic(h.api)).statusCode).toBe(503);
  });

  it("expira a requisição quando o conector não responde", async () => {
    const h = await startApi({ SAP_TIMEOUT_MS: "300" });
    const fake = await fakeConnector(h);
    const started = Date.now();
    const res = await h.api.inject({ url: "/api/v1/sap/health", headers: { authorization: DEMO } });
    expect(res.statusCode).toBe(503);
    expect(ApiError.parse(res.json()).error.code).toBe("SAP_UNAVAILABLE");
    expect(res.json().error.message).toMatch(/não respondeu/);
    expect(Date.now() - started).toBeLessThan(2000);
    expect(fake.requests).toHaveLength(1);
    expect(fake.requests[0]?.path).toContain(`${SAP_API_PATH}/health`);
  });

  it("rejeita as requisições pendentes quando o socket fecha", async () => {
    const h = await startApi();
    const fake = await fakeConnector(h);
    const pending = h.api.inject({ url: "/api/v1/sap/health", headers: { authorization: DEMO } });
    await eventually(() => fake.requests.length === 1);
    fake.ws.close();
    const res = await pending;
    expect(res.statusCode).toBe(503);
    expect(res.json().error.message).toMatch(/desconectou/);
  });

  it("limita as requisições simultâneas por conector", async () => {
    const h = await startApi({}, { maxInFlight: 1 });
    const fake = await fakeConnector(h);
    const first = h.api.inject({ url: "/api/v1/sap/health", headers: { authorization: DEMO } });
    await eventually(() => fake.requests.length === 1);
    const second = await h.api.inject({ url: "/api/v1/sap/health", headers: { authorization: DEMO } });
    expect(second.statusCode).toBe(503);
    expect(second.json().error.message).toMatch(/sobrecarregado/);
    fake.ws.close();
    await first;
  });

  it("uma nova conexão do mesmo conector substitui a anterior", async () => {
    const h = await startApi();
    const first = await fakeConnector(h);
    const second = await fakeConnector(h);
    expect(await first.closed).toBe(4000);
    expect(h.api.ctx.hub.isOnline(h.connectorId)).toBe(true);
    expect(second.ws.readyState).toBe(WebSocket.OPEN);
  });

  it("derruba o conector que não responde aos pings", async () => {
    const h = await startApi({}, { pingIntervalMs: 30, pongTimeoutMs: 100 });
    const fake = await fakeConnector(h, { autoPong: false });
    await fake.closed;
    await eventually(() => !h.api.ctx.hub.isOnline(h.connectorId));
  });

  it("encerra a conexão com quadros inválidos", async () => {
    const h = await startApi();
    const fake = await fakeConnector(h);
    fake.ws.send("isto não é json");
    expect(await fake.closed).toBe(1008);
  });

  it("reconecta sozinho depois que o servidor reinicia", async () => {
    const h = await startApi();
    const client = startConnector(h);
    await client.waitFor("online");
    await h.restart();
    await client.waitFor("reconnecting");
    await client.waitFor("online");
    await eventually(() => h.api.ctx.hub.isOnline(h.connectorId));
    expect(h.api.ctx.hub.isOnline(h.connectorId)).toBe(true);
    expect((await runDiagnostic(h.api)).statusCode).toBe(200);
  });

  it("reconecta quando a conexão cai", async () => {
    const h = await startApi();
    const client = startConnector(h);
    await client.waitFor("online");
    client.dropConnection();
    await client.waitFor("reconnecting");
    await client.waitFor("online");
    expect((await runDiagnostic(h.api)).statusCode).toBe(200);
  });
});

describe("segurança do conector", () => {
  it("recusa caminhos fora de SAP_API_PATH e métodos além de GET/POST", async () => {
    const h = await startApi();
    await startConnector(h).waitFor("online");
    const hub = h.api.ctx.hub;
    for (const path of [
      "/sap/bc/outra/coisa",
      `${SAP_API_PATH}/../../../outra`,
      `${SAP_API_PATH}x/health`,
      `//evil.example${SAP_API_PATH}/health`,
      `${SAP_API_PATH}/%2e%2e/x`,
    ]) {
      await expect(hub.forward(h.connectorId, { method: "GET", path, headers: {} }, 2000)).rejects.toThrow(
        /FORBIDDEN_PATH/,
      );
    }
    await expect(
      hub.forward(h.connectorId, { method: "DELETE" as "GET", path: `${SAP_API_PATH}/health`, headers: {} }, 2000),
    ).rejects.toThrow(/FORBIDDEN_METHOD/);
    // Um caminho válido continua passando.
    const ok = await hub.forward(
      h.connectorId,
      { method: "GET", path: `${SAP_API_PATH}/health`, headers: { authorization: DEMO } },
      2000,
    );
    expect(ok.status).toBe(200);
  });

  it("checkPath normaliza antes de comparar", () => {
    expect(checkPath(`${SAP_API_PATH}/me?sap-client=100`, SAP_API_PATH)).toBe(`${SAP_API_PATH}/me?sap-client=100`);
    expect(() => checkPath(`${SAP_API_PATH}/a/../../x`, SAP_API_PATH)).toThrow();
    expect(() => checkPath("health", SAP_API_PATH)).toThrow();
  });
});

describe("administração de conectores", () => {
  it("cria (token só na resposta), lista com online e revoga, com auditoria", async () => {
    const h = await startApi();

    const created = await h.api.inject({
      method: "POST",
      url: "/api/v1/admin/connectors",
      headers: { authorization: DEMO },
      payload: { name: "Planta São Paulo" },
    });
    expect(created.statusCode).toBe(201);
    const { connector, token } = AdminConnectorCreated.parse(created.json());
    expect(token.length).toBeGreaterThanOrEqual(43);
    expect(connector).toMatchObject({ name: "Planta São Paulo", online: false, revoked: false, version: null });

    // O token do novo conector funciona; a listagem nunca o devolve.
    const client = startConnector(h, {}, token);
    await client.waitFor("online");
    await eventually(() => h.api.ctx.hub.isOnline(connector.id));

    const list = await h.api.inject({ url: "/api/v1/admin/connectors", headers: { authorization: DEMO } });
    const { connectors } = AdminConnectorList.parse(list.json());
    const listed = connectors.find((c) => c.id === connector.id);
    expect(listed).toMatchObject({ online: true, revoked: false });
    await eventually(async () => {
      const again = AdminConnectorList.parse(
        (await h.api.inject({ url: "/api/v1/admin/connectors", headers: { authorization: DEMO } })).json(),
      );
      return again.connectors.find((c) => c.id === connector.id)?.version === "0.1.0";
    });
    expect(list.body).not.toContain(token);

    const revoked = await h.api.inject({
      method: "DELETE",
      url: `/api/v1/admin/connectors/${connector.id}`,
      headers: { authorization: DEMO },
    });
    expect(revoked.statusCode).toBe(204);
    const after = AdminConnectorList.parse(
      (await h.api.inject({ url: "/api/v1/admin/connectors", headers: { authorization: DEMO } })).json(),
    );
    expect(after.connectors.find((c) => c.id === connector.id)).toMatchObject({ online: false, revoked: true });

    const missing = await h.api.inject({
      method: "DELETE",
      url: "/api/v1/admin/connectors/cn_inexistente",
      headers: { authorization: DEMO },
    });
    expect(missing.statusCode).toBe(404);

    const events = await (await testDatabase()).db.select().from(auditEvents);
    const mine = events.filter((e) => e.target === connector.id).map((e) => e.action);
    expect(mine).toEqual(expect.arrayContaining(["ADMIN_CONNECTOR_CREATE", "ADMIN_CONNECTOR_REVOKE"]));
  });

  it("exige papel de administrador e valida o nome", async () => {
    const h = await startApi();
    const user = await h.api.inject({
      url: "/api/v1/admin/connectors",
      headers: { authorization: basic("VENDAS", "vendas") },
    });
    expect(user.statusCode).toBe(403);
    const anonymous = await h.api.inject({ url: "/api/v1/admin/connectors" });
    expect(anonymous.statusCode).toBe(401);
    const invalid = await h.api.inject({
      method: "POST",
      url: "/api/v1/admin/connectors",
      headers: { authorization: DEMO },
      payload: { name: "   " },
    });
    expect(invalid.statusCode).toBe(400);
  });

  it("o repositório guarda só o hash e rejeita tokens revogados", async () => {
    const database = await testDatabase();
    const repo = new ConnectorRepository(database.db);
    const { connector, token } = await repo.create("default", "Repo");
    expect(connector.tokenHash).not.toBe(token);
    expect(connector.tokenHash).toMatch(/^[0-9a-f]{64}$/);
    expect((await repo.verify(token))?.id).toBe(connector.id);
    expect(await repo.verify("outro")).toBeUndefined();
    await repo.revoke("default", connector.id);
    expect(await repo.verify(token)).toBeUndefined();
    expect(await repo.revoke("outro-cliente", connector.id)).toBeUndefined();
  });
});
