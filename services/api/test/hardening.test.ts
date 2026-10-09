import { buildServer } from "@raiox/sap-mock";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createApp } from "../src/app";
import { loadConfig } from "../src/config";
import { testDatabase } from "./helpers";

let mock: FastifyInstance;
let sapUrl: string;
const open: FastifyInstance[] = [];

beforeAll(async () => {
  mock = buildServer({ release: "S4" });
  sapUrl = await mock.listen({ port: 0, host: "127.0.0.1" });
});

afterAll(async () => {
  for (const app of open) await app.close();
  await mock.close();
});

async function appWith(env: Record<string, string> = {}): Promise<FastifyInstance> {
  const config = loadConfig({
    DEPLOYMENT_MODE: "selfhosted",
    SAP_BASE_URL: sapUrl,
    SAP_CLIENT: "100",
    LOG_LEVEL: "silent",
    ...env,
  });
  const app = await createApp(config, { database: await testDatabase() });
  open.push(app);
  return app;
}

const login = (app: FastifyInstance, user: string, password = "demo", ip?: string) =>
  app.inject({
    method: "POST",
    url: "/api/v1/auth/login",
    payload: { user, password },
    ...(ip ? { remoteAddress: ip } : {}),
  });

describe("cabeçalhos de segurança", () => {
  it("envia CSP restritiva sem origens externas e sem HSTS em HTTP", async () => {
    const app = await appWith();
    const res = await app.inject({ method: "GET", url: "/api/health" });
    const csp = String(res.headers["content-security-policy"]);
    expect(csp).toContain("default-src 'self'");
    expect(csp).toContain("img-src 'self' data:");
    expect(csp).toContain("connect-src 'self'");
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).not.toMatch(/https?:\/\//);
    expect(csp).not.toContain("upgrade-insecure-requests");
    expect(res.headers["x-content-type-options"]).toBe("nosniff");
    expect(res.headers["strict-transport-security"]).toBeUndefined();
  });

  it("liga o HSTS com COOKIE_SECURE=true", async () => {
    const app = await appWith({ COOKIE_SECURE: "true" });
    const res = await app.inject({ method: "GET", url: "/api/health" });
    expect(String(res.headers["strict-transport-security"])).toContain("max-age=");
  });
});

describe("id da requisição", () => {
  it("devolve o x-request-id recebido", async () => {
    const app = await appWith();
    const res = await app.inject({ method: "GET", url: "/api/health", headers: { "x-request-id": "proxy-123" } });
    expect(res.headers["x-request-id"]).toBe("proxy-123");
  });

  it("gera um id quando não vem, e descarta ids suspeitos", async () => {
    const app = await appWith();
    const generated = await app.inject({ method: "GET", url: "/api/health" });
    expect(String(generated.headers["x-request-id"])).toMatch(/^[0-9a-f-]{36}$/);
    const bad = await app.inject({ method: "GET", url: "/api/health", headers: { "x-request-id": 'a b"c' } });
    expect(bad.headers["x-request-id"]).not.toBe('a b"c');
  });

  it("devolve o id também nas respostas de erro", async () => {
    const app = await appWith();
    const res = await app.inject({ method: "GET", url: "/api/v1/nao-existe", headers: { "x-request-id": "abc" } });
    expect(res.statusCode).toBe(404);
    expect(res.headers["x-request-id"]).toBe("abc");
  });
});

describe("rate limit", () => {
  it("limita o login por IP + usuário com o corpo de erro do contrato", async () => {
    const app = await appWith({ RATE_LIMIT_LOGIN_MAX: "3" });
    for (let i = 0; i < 3; i++) {
      expect((await login(app, "DEMO", "senha-errada", "10.0.0.1")).statusCode).toBe(401);
    }
    const blocked = await login(app, "DEMO", "senha-errada", "10.0.0.1");
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json().error.code).toBe("RATE_LIMITED");
    expect(typeof blocked.json().error.message).toBe("string");
    expect(blocked.headers["retry-after"]).toBeDefined();
    // Outro usuário no mesmo IP e o mesmo usuário em outro IP não são afetados.
    expect((await login(app, "OUTRO", "senha-errada", "10.0.0.1")).statusCode).not.toBe(429);
    expect((await login(app, "DEMO", "senha-errada", "10.0.0.2")).statusCode).not.toBe(429);
  });

  it("aplica o mesmo limite a /auth/check", async () => {
    const app = await appWith({ RATE_LIMIT_LOGIN_MAX: "2" });
    const check = () =>
      app.inject({
        method: "POST",
        url: "/api/v1/auth/check",
        payload: { user: "DEMO", password: "x" },
        remoteAddress: "10.0.1.1",
      });
    await check();
    await check();
    expect((await check()).statusCode).toBe(429);
  });

  it("aplica o limite global por IP", async () => {
    const app = await appWith({ RATE_LIMIT_MAX: "5" });
    const get = () => app.inject({ method: "GET", url: "/api/health", remoteAddress: "10.0.2.1" });
    for (let i = 0; i < 5; i++) expect((await get()).statusCode).toBe(200);
    const blocked = await get();
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json().error.code).toBe("RATE_LIMITED");
  });
});

describe("métricas", () => {
  const TOKEN = "token-de-metricas-com-16+";

  it("fica desligado (404) sem METRICS_TOKEN", async () => {
    const app = await appWith();
    const res = await app.inject({ method: "GET", url: "/metrics", headers: { authorization: `Bearer ${TOKEN}` } });
    expect(res.statusCode).toBe(404);
    expect(res.json().error.code).toBe("ROUTE_NOT_FOUND");
  });

  it("exige o token Bearer correto", async () => {
    const app = await appWith({ METRICS_TOKEN: TOKEN });
    expect((await app.inject({ method: "GET", url: "/metrics" })).statusCode).toBe(401);
    const wrong = await app.inject({ method: "GET", url: "/metrics", headers: { authorization: "Bearer errado" } });
    expect(wrong.statusCode).toBe(401);
    expect(wrong.headers["www-authenticate"]).toBe("Bearer");
  });

  it("expõe métricas HTTP, de processo e de diagnóstico com o token", async () => {
    const app = await appWith({ METRICS_TOKEN: TOKEN });
    const session = await login(app, "DEMO");
    const cookie = String(session.headers["set-cookie"]).split(";")[0] ?? "";
    const run = await app.inject({
      method: "POST",
      url: "/api/v1/diagnostics/SD-01",
      headers: { cookie },
      payload: { params: { salesOrder: "4500001" } },
    });
    expect(run.statusCode).toBe(200);
    const res = await app.inject({ method: "GET", url: "/metrics", headers: { authorization: `Bearer ${TOKEN}` } });
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toContain("text/plain");
    expect(res.body).toContain("http_request_duration_seconds_bucket");
    expect(res.body).toContain('route="/api/v1/diagnostics/:id"');
    expect(res.body).toContain('raiox_diagnostic_duration_seconds_count{diagnostic="SD-01",outcome="ok"} 1');
    expect(res.body).toContain("process_cpu_user_seconds_total");
  });
});

describe("configuração de operação", () => {
  it("aceita METRICS_TOKEN vazio como desligado e rejeita token curto", () => {
    expect(loadConfig({ SAP_BASE_URL: sapUrl, METRICS_TOKEN: "" }).METRICS_TOKEN).toBeUndefined();
    expect(() => loadConfig({ SAP_BASE_URL: sapUrl, METRICS_TOKEN: "curto" })).toThrow(/METRICS_TOKEN/);
  });

  it("TRUST_PROXY é ligado por padrão", () => {
    expect(loadConfig({ SAP_BASE_URL: sapUrl }).TRUST_PROXY).toBe(true);
    expect(loadConfig({ SAP_BASE_URL: sapUrl, TRUST_PROXY: "false" }).TRUST_PROXY).toBe(false);
  });
});
