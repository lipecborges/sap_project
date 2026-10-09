import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ApiError, DiagnosticResult, MeResponse } from "@raiox/contracts";
import { buildServer } from "@raiox/sap-mock";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp } from "../src/app";
import { type Config, loadConfig } from "../src/config";
import { testDatabase } from "./helpers";

let mock: FastifyInstance;
let api: FastifyInstance;
let config: Config;
const DEMO = `Basic ${Buffer.from("DEMO:demo").toString("base64")}`;

beforeAll(async () => {
  mock = buildServer({ release: "S4" });
  const address = await mock.listen({ port: 0, host: "127.0.0.1" });
  config = loadConfig({ DEPLOYMENT_MODE: "selfhosted", SAP_BASE_URL: address, SAP_CLIENT: "100", LOG_LEVEL: "silent" });
  api = await createApp(config, { database: await testDatabase() });
});

afterAll(async () => {
  await api.close();
  await mock.close();
});

describe("configuração", () => {
  it("self-hosted usa transporte direto e exige SAP_BASE_URL", () => {
    expect(() => loadConfig({ DEPLOYMENT_MODE: "selfhosted" })).toThrow(/SAP_BASE_URL/);
    expect(loadConfig({ SAP_BASE_URL: "http://sap:8000" }).SAP_TRANSPORT).toBe("direct");
  });

  it("cloud usa conector por padrão", () => {
    expect(loadConfig({ DEPLOYMENT_MODE: "cloud" }).SAP_TRANSPORT).toBe("connector");
  });

  it("valida o mandante", () => {
    expect(() => loadConfig({ SAP_BASE_URL: "http://sap:8000", SAP_CLIENT: "1" })).toThrow(/Mandante/);
  });
});

describe("API → transporte direto → sap-mock", () => {
  it("health informa o modo e o transporte", async () => {
    const res = await api.inject({ url: "/api/health" });
    expect(res.json()).toMatchObject({ status: "ok", deploymentMode: "selfhosted", sapTransport: "direct" });
  });

  it("valida o login no SAP", async () => {
    const ok = await api.inject({
      method: "POST",
      url: "/api/v1/auth/check",
      payload: { user: "demo", password: "demo" },
    });
    expect(MeResponse.parse(ok.json()).user).toBe("DEMO");

    const bad = await api.inject({
      method: "POST",
      url: "/api/v1/auth/check",
      payload: { user: "demo", password: "x" },
    });
    expect(bad.statusCode).toBe(401);
    expect(ApiError.parse(bad.json()).error.code).toBe("UNAUTHENTICATED");
  });

  it("executa um diagnóstico e devolve o resultado validado", async () => {
    const res = await api.inject({
      method: "POST",
      url: "/api/v1/diagnostics/SD-01",
      headers: { authorization: DEMO },
      payload: { params: { salesOrder: "4500001" } },
    });
    expect(res.statusCode).toBe(200);
    const result = DiagnosticResult.parse(res.json());
    expect(result.system.release).toBe("S4");
    expect(result.findings[0]?.code).toBe("SD01.CREDIT_BLOCK");
  });

  it("valida parâmetros antes de ir ao SAP", async () => {
    const res = await api.inject({
      method: "POST",
      url: "/api/v1/diagnostics/PP-04",
      headers: { authorization: DEMO },
      payload: { params: {} },
    });
    expect(res.statusCode).toBe(400);
    expect(ApiError.parse(res.json()).error.params).toEqual({ plant: "Obrigatório" });
  });

  it("repassa a falta de autorização do SAP", async () => {
    const res = await api.inject({
      method: "POST",
      url: "/api/v1/diagnostics/PP-03",
      headers: { authorization: `Basic ${Buffer.from("VENDAS:vendas").toString("base64")}` },
      payload: { params: { productionOrder: "1000010" } },
    });
    expect(res.statusCode).toBe(403);
    expect(ApiError.parse(res.json()).error.code).toBe("NOT_AUTHORIZED");
  });

  it("exige credenciais", async () => {
    const res = await api.inject({ url: "/api/v1/diagnostics" });
    expect(res.statusCode).toBe(401);
  });

  it("SAP fora do ar vira SAP_UNAVAILABLE", async () => {
    const offline = await createApp(
      loadConfig({ SAP_BASE_URL: "http://127.0.0.1:1", LOG_LEVEL: "silent", SAP_TIMEOUT_MS: "2000" }),
    );
    const res = await offline.inject({ url: "/api/v1/diagnostics", headers: { authorization: DEMO } });
    expect(res.statusCode).toBe(503);
    expect(ApiError.parse(res.json()).error.code).toBe("SAP_UNAVAILABLE");
    await offline.close();
  });

  it("modo cloud com o conector offline responde SAP_UNAVAILABLE", async () => {
    const cloud = await createApp(
      loadConfig({ DEPLOYMENT_MODE: "cloud", SAP_CONNECTOR_ID: "c1", LOG_LEVEL: "silent" }),
    );
    const res = await cloud.inject({ url: "/api/v1/diagnostics", headers: { authorization: DEMO } });
    expect(res.statusCode).toBe(503);
    expect(ApiError.parse(res.json()).error.code).toBe("SAP_UNAVAILABLE");
    await cloud.close();
  });
});

describe("web embutida", () => {
  it("serve o index.html para rotas da SPA e mantém 404 em /api", async () => {
    const dir = mkdtempSync(join(tmpdir(), "raiox-web-"));
    writeFileSync(join(dir, "index.html"), "<!doctype html><title>Raio-X</title>");
    const withWeb = await createApp({ ...config, WEB_DIST_DIR: dir }, { database: await testDatabase() });
    const page = await withWeb.inject({ url: "/diagnosticos/SD-01" });
    expect(page.statusCode).toBe(200);
    expect(page.body).toContain("Raio-X");
    const missing = await withWeb.inject({ url: "/api/nada" });
    expect(missing.statusCode).toBe(404);
    await withWeb.close();
  });
});

describe("sessão do navegador", () => {
  it("login cria cookie httpOnly; a sessão vale nas chamadas seguintes; logout encerra", async () => {
    const login = await api.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { user: "demo", password: "demo" },
    });
    expect(login.statusCode).toBe(200);
    const setCookie = String(login.headers["set-cookie"]);
    expect(setCookie).toMatch(/raiox_session=.+; Path=\/; HttpOnly; SameSite=Strict/);
    const cookie = setCookie.split(";")[0]!;

    expect(MeResponse.parse((await api.inject({ url: "/api/v1/auth/session", headers: { cookie } })).json()).user).toBe(
      "DEMO",
    );
    const run = await api.inject({
      method: "POST",
      url: "/api/v1/diagnostics/SD-01",
      headers: { cookie },
      payload: { params: { salesOrder: "4500001" } },
    });
    expect(run.statusCode).toBe(200);

    await api.inject({ method: "POST", url: "/api/v1/auth/logout", headers: { cookie } });
    expect((await api.inject({ url: "/api/v1/auth/session", headers: { cookie } })).statusCode).toBe(401);
  });

  it("login com senha errada não cria sessão", async () => {
    const res = await api.inject({
      method: "POST",
      url: "/api/v1/auth/login",
      payload: { user: "demo", password: "x" },
    });
    expect(res.statusCode).toBe(401);
    expect(res.headers["set-cookie"]).toBeUndefined();
  });

  it("cookie inválido não autentica", async () => {
    const res = await api.inject({ url: "/api/v1/diagnostics", headers: { cookie: "raiox_session=falso" } });
    expect(res.statusCode).toBe(401);
  });
});
