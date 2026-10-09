import {
  AdminSystem,
  AdminSystemList,
  AdminUser,
  AdminUserList,
  ApiError,
  AuditPage,
  LicenseStatus,
  SystemTestResult,
  UsageReport,
} from "@raiox/contracts";
import { buildServer } from "@raiox/sap-mock";
import { eq } from "drizzle-orm";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { DemoProvider } from "../src/ai/demo-provider";
import { createApp } from "../src/app";
import { type Config, loadConfig } from "../src/config";
import { auditEvents, connectors, licenses, sapSystems, sessions, tenants, users } from "../src/db/schema";
import { testDatabase } from "./helpers";
import { testVendor } from "./licenses";

const vendor = testVendor();
let mock: FastifyInstance;
let mockUrl: string;
let config: Config;
let api: FastifyInstance;
let admin: string;
let vendas: string;

beforeAll(async () => {
  mock = buildServer({ release: "ECC" });
  mockUrl = await mock.listen({ port: 0, host: "127.0.0.1" });
  config = loadConfig({
    SAP_BASE_URL: mockUrl,
    SAP_SYSTEM_NAME: "PRD",
    LOG_LEVEL: "silent",
    SESSION_SECRET: Buffer.alloc(32, 7).toString("base64"),
    LICENSE_PUBLIC_KEY: vendor.publicPem,
    ADMIN_USERS: "DEMO",
  });
});
afterAll(() => mock.close());

beforeEach(async () => {
  const { db } = await testDatabase();
  await db.insert(tenants).values({ id: "default", name: "Padrão" }).onConflictDoNothing();
  await db.delete(sessions);
  await db.delete(users);
  await db.delete(licenses);
  await db.delete(auditEvents);
  await db.delete(connectors);
  await db.delete(sapSystems).where(eq(sapSystems.isDefault, false));
  api = await createApp(config, { database: await testDatabase(), provider: new DemoProvider(0) });
  admin = (await login("demo", "demo")).cookie;
  vendas = (await login("vendas", "vendas")).cookie;
  return () => api.close();
});

async function login(user: string, password: string, system?: string) {
  const res = await api.inject({ method: "POST", url: "/api/v1/auth/login", payload: { user, password, system } });
  return { res, cookie: String(res.headers["set-cookie"]).split(";")[0]! };
}

const call = (method: "GET" | "POST" | "PUT" | "PATCH" | "DELETE", url: string, payload?: unknown, cookie = admin) =>
  api.inject({ method, url: `/api/v1/admin${url}`, headers: { cookie }, payload: payload as object });

const auditActions = async () => {
  const { db } = await testDatabase();
  return db.select().from(auditEvents).where(eq(auditEvents.tenantId, "default"));
};

describe("acesso", () => {
  it("só administradores; sem sessão é 401", async () => {
    const routes: [string, string][] = [
      ["GET", "/users"],
      ["PATCH", "/users/DEMO"],
      ["GET", "/license"],
      ["PUT", "/license"],
      ["GET", "/systems"],
      ["POST", "/systems"],
      ["PATCH", "/systems/qas"],
      ["DELETE", "/systems/qas"],
      ["POST", "/systems/default/test"],
      ["GET", "/audit"],
      ["GET", "/audit.csv"],
      ["GET", "/usage"],
    ];
    for (const [method, url] of routes) {
      const res = await call(method as "GET", url, {}, vendas);
      expect(res.statusCode, `${method} ${url}`).toBe(403);
      expect(ApiError.parse(res.json()).error.code).toBe("FORBIDDEN");
      const anonymous = await api.inject({ method: method as "GET", url: `/api/v1/admin${url}` });
      expect(anonymous.statusCode, `${method} ${url}`).toBe(401);
    }
  });
});

describe("usuários", () => {
  it("lista com papel efetivo, vaga e sessões ativas", async () => {
    const body = AdminUserList.parse((await call("GET", "/users")).json());
    expect(body.users.map((u) => u.sapUser)).toEqual(["DEMO", "VENDAS"]);
    expect(body.users[0]).toMatchObject({ role: "admin", hasSeat: true, blocked: false, activeSessions: 1 });
    expect(body.users[1]).toMatchObject({ role: "user", hasSeat: true, activeSessions: 1 });
  });

  it("bloquear remove as sessões e impede novo login; desbloquear libera", async () => {
    const res = await call("PATCH", "/users/vendas", { blocked: true });
    expect(AdminUser.parse(res.json())).toMatchObject({ sapUser: "VENDAS", blocked: true, activeSessions: 0 });
    expect((await api.inject({ url: "/api/v1/auth/session", headers: { cookie: vendas } })).statusCode).toBe(401);
    expect((await login("vendas", "vendas")).res.statusCode).toBe(403);
    await call("PATCH", "/users/VENDAS", { blocked: false });
    expect((await login("vendas", "vendas")).res.statusCode).toBe(200);
  });

  it("liberar a vaga derruba as sessões e tira o acesso; devolver respeita o limite", async () => {
    const { db } = await testDatabase();
    await db.insert(licenses).values({ tenantId: "default", license: vendor.sign({ maxNamedUsers: 1 }) });
    const released = await call("PATCH", "/users/VENDAS", { seat: false });
    expect(AdminUser.parse(released.json())).toMatchObject({ hasSeat: false, activeSessions: 0 });
    expect((await api.inject({ url: "/api/v1/diagnostics", headers: { cookie: vendas } })).statusCode).toBe(401);
    const denied = await login("vendas", "vendas");
    expect(denied.res.statusCode).toBe(403);

    // Com o limite em 1 (ocupado por DEMO), devolver a vaga é recusado até a licença crescer.
    const full = await call("PATCH", "/users/VENDAS", { seat: true });
    expect(full.statusCode).toBe(409);
    expect(ApiError.parse(full.json()).error.code).toBe("LICENSE_REQUIRED");
    await call("PUT", "/license", { license: vendor.sign({ maxNamedUsers: 2 }) });
    const granted = await call("PATCH", "/users/VENDAS", { seat: true });
    expect(AdminUser.parse(granted.json()).hasSeat).toBe(true);
    expect((await login("vendas", "vendas")).res.statusCode).toBe(200);
  });

  it("papel de administrador pode ser concedido", async () => {
    const res = await call("PATCH", "/users/VENDAS", { role: "admin" });
    expect(AdminUser.parse(res.json()).role).toBe("admin");
    expect((await call("GET", "/users", undefined, vendas)).statusCode).toBe(200);
  });

  it("o administrador não bloqueia, rebaixa nem tira a licença de si mesmo", async () => {
    for (const patch of [{ blocked: true }, { role: "user" }, { seat: false }]) {
      const res = await call("PATCH", "/users/DEMO", patch);
      expect(res.statusCode).toBe(400);
      expect(ApiError.parse(res.json()).error.code).toBe("INVALID_PARAMS");
    }
    expect(AdminUser.parse((await call("PATCH", "/users/DEMO", { blocked: false })).json()).blocked).toBe(false);
  });

  it("valida o corpo e o usuário", async () => {
    expect((await call("PATCH", "/users/VENDAS", {})).statusCode).toBe(400);
    expect((await call("PATCH", "/users/NINGUEM", { blocked: true })).statusCode).toBe(404);
  });

  it("audita a alteração com o antes e o depois", async () => {
    await call("PATCH", "/users/VENDAS", { blocked: true });
    const event = (await auditActions()).find((e) => e.action === "ADMIN_USER_UPDATE");
    expect(event).toMatchObject({ sapUser: "DEMO", target: "VENDAS", outcome: "ok" });
    expect(event?.details).toMatchObject({ before: { blocked: false }, after: { blocked: true }, closedSessions: 1 });
  });
});

describe("licença", () => {
  it("mostra a avaliação, instala uma licença assinada e audita sem o texto da licença", async () => {
    const before = LicenseStatus.parse((await call("GET", "/license")).json());
    expect(before).toMatchObject({ state: "evaluation", maxNamedUsers: 5, usedSeats: 2 });

    const text = vendor.sign({ licenseId: "LIC-42", maxNamedUsers: 2, features: ["chat", "export"] });
    const res = await call("PUT", "/license", { license: text });
    expect(res.statusCode).toBe(200);
    const status = LicenseStatus.parse(res.json());
    expect(status).toMatchObject({ state: "valid", licenseId: "LIC-42", maxNamedUsers: 2, usedSeats: 2 });
    expect(status.features).toEqual(["chat", "export"]);
    expect(status.warnings[0]).toMatch(/2 de 2/);
    expect(LicenseStatus.parse((await call("GET", "/license")).json()).licenseId).toBe("LIC-42");

    const event = (await auditActions()).find((e) => e.action === "ADMIN_LICENSE_INSTALL");
    expect(event?.details).toMatchObject({ licenseId: "LIC-42", maxNamedUsers: 2 });
    expect(JSON.stringify(event)).not.toContain(text.slice(10, 60));
  });

  it("recusa licença com assinatura inválida ou fora do formato", async () => {
    const forged = await call("PUT", "/license", { license: testVendor().sign() });
    expect(forged.statusCode).toBe(400);
    expect(ApiError.parse(forged.json()).error.message).toMatch(/Assinatura/);
    expect((await call("PUT", "/license", { license: "isto não é uma licença válida" })).statusCode).toBe(400);
    expect(LicenseStatus.parse((await call("GET", "/license")).json()).state).toBe("evaluation");
  });
});

describe("sistemas SAP", () => {
  it("lista o sistema das variáveis SAP_* como somente leitura", async () => {
    const body = AdminSystemList.parse((await call("GET", "/systems")).json());
    expect(body.systems).toEqual([
      {
        id: "default",
        name: "PRD",
        transport: "direct",
        baseUrl: mockUrl,
        sapClient: null,
        connectorId: null,
        isDefault: true,
        managedByEnv: true,
      },
    ]);
    const patch = await call("PATCH", "/systems/default", { name: "outro" });
    expect(patch.statusCode).toBe(409);
    expect((await call("DELETE", "/systems/default")).statusCode).toBe(409);
  });

  it("cria, altera e remove; só um padrão por cliente", async () => {
    const created = await call("POST", "/systems", {
      id: "qas",
      name: "QAS",
      transport: "direct",
      baseUrl: mockUrl,
      sapClient: "200",
    });
    expect(created.statusCode).toBe(201);
    expect(AdminSystem.parse(created.json())).toMatchObject({ id: "qas", isDefault: false, managedByEnv: false });

    const dup = await call("POST", "/systems", { id: "qas", name: "Outro", transport: "direct", baseUrl: mockUrl });
    expect(dup.statusCode).toBe(409);
    expect(
      (await call("POST", "/systems", { id: "default", name: "X", transport: "direct", baseUrl: mockUrl })).statusCode,
    ).toBe(409);

    const patched = await call("PATCH", "/systems/qas", { name: "QAS 2", isDefault: true });
    expect(AdminSystem.parse(patched.json())).toMatchObject({ name: "QAS 2", isDefault: true });
    const list = AdminSystemList.parse((await call("GET", "/systems")).json());
    expect(list.systems.filter((s) => s.isDefault).map((s) => s.id)).toEqual(["qas"]);
    expect((await call("PATCH", "/systems/qas", { isDefault: false })).statusCode).toBe(400);
    expect((await call("PATCH", "/systems/nao-existe", { name: "x" })).statusCode).toBe(404);

    expect((await call("DELETE", "/systems/qas")).statusCode).toBe(200);
    expect((await call("DELETE", "/systems/qas")).statusCode).toBe(404);
  });

  it("valida transporte: direct exige baseUrl; connector exige um conector do cliente", async () => {
    const missingUrl = await call("POST", "/systems", { id: "a", name: "A", transport: "direct" });
    expect(missingUrl.statusCode).toBe(400);
    expect(ApiError.parse(missingUrl.json()).error.message).toMatch(/baseUrl/);
    expect((await call("POST", "/systems", { id: "a", name: "A", transport: "connector" })).statusCode).toBe(400);
    expect(
      (await call("POST", "/systems", { id: "a", name: "A", transport: "connector", connectorId: "x" })).statusCode,
    ).toBe(400);
    expect((await call("POST", "/systems", { name: "Sem id", transport: "direct", baseUrl: mockUrl })).statusCode).toBe(
      400,
    );
    expect(
      (await call("POST", "/systems", { id: "Maiúscula", name: "A", transport: "direct", baseUrl: mockUrl }))
        .statusCode,
    ).toBe(400);

    const { db } = await testDatabase();
    await db.insert(connectors).values({ id: "con1", tenantId: "default", name: "Matriz", tokenHash: "hash-1" });
    const ok = await call("POST", "/systems", {
      id: "prd2",
      name: "PRD2",
      transport: "connector",
      connectorId: "con1",
    });
    expect(AdminSystem.parse(ok.json())).toMatchObject({ transport: "connector", connectorId: "con1", baseUrl: null });
    // Trocar para direct exige o endereço e limpa o conector.
    expect((await call("PATCH", "/systems/prd2", { transport: "direct" })).statusCode).toBe(400);
    const back = await call("PATCH", "/systems/prd2", { transport: "direct", baseUrl: mockUrl });
    expect(AdminSystem.parse(back.json())).toMatchObject({ transport: "direct", connectorId: null });
  });

  it("remover um sistema encerra as sessões que entraram por ele", async () => {
    await call("POST", "/systems", { id: "qas", name: "QAS", transport: "direct", baseUrl: mockUrl });
    const viaQas = await login("vendas", "vendas", "qas");
    expect(viaQas.res.statusCode).toBe(200);
    expect((await api.inject({ url: "/api/v1/auth/session", headers: { cookie: viaQas.cookie } })).statusCode).toBe(
      200,
    );
    await call("DELETE", "/systems/qas");
    expect((await api.inject({ url: "/api/v1/auth/session", headers: { cookie: viaQas.cookie } })).statusCode).toBe(
      401,
    );
    // A sessão de outro sistema não é afetada.
    expect((await api.inject({ url: "/api/v1/auth/session", headers: { cookie: vendas } })).statusCode).toBe(200);
  });

  it("testa a conexão com a credencial do administrador e mede a latência", async () => {
    await call("POST", "/systems", { id: "qas", name: "QAS", transport: "direct", baseUrl: mockUrl });
    await call("POST", "/systems", { id: "fora", name: "Fora", transport: "direct", baseUrl: "http://127.0.0.1:1" });

    const ok = SystemTestResult.parse((await call("POST", "/systems/qas/test")).json());
    expect(ok.ok).toBe(true);
    expect(ok.latencyMs).toBeGreaterThanOrEqual(0);
    expect(ok.health?.system).toBeDefined();
    expect(SystemTestResult.parse((await call("POST", "/systems/default/test")).json()).ok).toBe(true);

    const down = SystemTestResult.parse((await call("POST", "/systems/fora/test")).json());
    expect(down).toMatchObject({ ok: false, error: { code: "SAP_UNAVAILABLE" } });
    expect((await call("POST", "/systems/nao-existe/test")).statusCode).toBe(404);
  });

  it("audita criação, alteração e remoção", async () => {
    await call("POST", "/systems", { id: "qas", name: "QAS", transport: "direct", baseUrl: mockUrl });
    await call("PATCH", "/systems/qas", { name: "QAS 2" });
    await call("DELETE", "/systems/qas");
    const events = (await auditActions()).filter((e) => e.action.startsWith("ADMIN_SYSTEM_"));
    expect(events.map((e) => e.action).sort()).toEqual([
      "ADMIN_SYSTEM_CREATE",
      "ADMIN_SYSTEM_DELETE",
      "ADMIN_SYSTEM_UPDATE",
    ]);
    expect(events.every((e) => e.target === "qas" && e.sapUser === "DEMO")).toBe(true);
  });
});

describe("auditoria", () => {
  async function seed(n: number) {
    const { db } = await testDatabase();
    await db.delete(auditEvents);
    const base = Date.now() - 60_000;
    await db.insert(auditEvents).values(
      Array.from({ length: n }, (_, i) => ({
        tenantId: "default",
        at: new Date(base + i * 1000),
        sapUser: i % 2 === 0 ? "DEMO" : "VENDAS",
        action: "DIAGNOSTIC_RUN",
        target: i === 0 ? '=SOMA(1;1), "x"\nlinha 2' : "SD-01",
        details: { n: i },
        outcome: "ok",
        httpStatus: 200,
        durationMs: 10 + i,
        ip: "10.0.0.1",
      })),
    );
    await db.insert(auditEvents).values({ tenantId: "outro", action: "DIAGNOSTIC_RUN", outcome: "ok" });
  }

  it("pagina do mais recente para o mais antigo, com filtros", async () => {
    await seed(5);
    const first = AuditPage.parse((await call("GET", "/audit?limit=2")).json());
    expect(first.events).toHaveLength(2);
    expect(first.nextBefore).toBe(first.events[1]?.id);
    const second = AuditPage.parse((await call("GET", `/audit?limit=2&before=${first.nextBefore}`)).json());
    expect(second.events.every((e) => e.id < first.nextBefore!)).toBe(true);
    const last = AuditPage.parse((await call("GET", `/audit?limit=2&before=${second.nextBefore}`)).json());
    expect(last.events).toHaveLength(1);
    expect(last.nextBefore).toBeNull();

    const onlyVendas = AuditPage.parse((await call("GET", "/audit?user=vendas&action=DIAGNOSTIC_RUN")).json());
    expect(onlyVendas.events.map((e) => e.sapUser)).toEqual(["VENDAS", "VENDAS"]);
    const future = new Date(Date.now() + 3600_000).toISOString();
    expect(AuditPage.parse((await call("GET", `/audit?from=${future}`)).json()).events).toEqual([]);
    expect((await call("GET", "/audit?limit=9999")).statusCode).toBe(400);
  });

  it("exporta CSV com escape correto e cabeçalho de download", async () => {
    await seed(3);
    const res = await call("GET", "/audit.csv?action=DIAGNOSTIC_RUN");
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toContain("text/csv");
    expect(res.headers["content-disposition"]).toMatch(/^attachment; filename=".+\.csv"$/);
    const [header, ...rows] = res.body.split("\r\n");
    expect(header).toBe("id,data,usuario,sistema,acao,alvo,resultado,http,duracao_ms,ip,detalhes");
    expect(res.body).toContain(`"'=SOMA(1;1), ""x""\nlinha 2"`);
    expect(res.body).toContain('"{""n"":0}"');
    expect(rows.filter(Boolean).length).toBeGreaterThanOrEqual(3);
    expect(res.body).not.toContain("outro");
  });

  it("o CSV vem em blocos e respeita os filtros", async () => {
    await seed(2500);
    const res = await call("GET", "/audit.csv?user=DEMO");
    const lines = res.body.split("\r\n").filter((l) => l && !l.startsWith("id,"));
    expect(lines.length).toBe(1250);
  });
});

describe("uso", () => {
  it("agrega execuções, conversas, usuários ativos e latência por diagnóstico", async () => {
    const { db } = await testDatabase();
    await db.delete(auditEvents);
    const now = Date.now();
    const at = (daysAgo: number) => new Date(now - daysAgo * 24 * 3600_000);
    const row = (over: Partial<typeof auditEvents.$inferInsert>) => ({
      tenantId: "default",
      action: "DIAGNOSTIC_RUN",
      outcome: "ok",
      at: at(0),
      sapUser: "DEMO",
      target: "SD-01",
      ...over,
    });
    await db
      .insert(auditEvents)
      .values([
        ...[100, 200, 300, 400, 500].map((ms) => row({ durationMs: ms })),
        row({ target: "MM-01", sapUser: "VENDAS", durationMs: 50 }),
        row({ action: "CHAT_TURN", target: null, sapUser: "VENDAS" }),
        row({ action: "CHAT_TURN", target: null, sapUser: "VENDAS", at: at(2) }),
        row({ sapUser: "DEMO", at: at(2), durationMs: 70, outcome: "NOT_AUTHORIZED" }),
        row({ at: at(90), durationMs: 9999 }),
        row({ tenantId: "outro", durationMs: 1 }),
      ]);

    const report = UsageReport.parse((await call("GET", "/usage?days=30")).json());
    expect(report.days).toHaveLength(30);
    const today = report.days.at(-1)!;
    expect(today).toMatchObject({ runs: 6, chatTurns: 1, activeUsers: 2 });
    expect(report.days.at(-3)).toMatchObject({ runs: 1, chatTurns: 1, activeUsers: 2 });
    expect(report.days.slice(0, 20).every((d) => d.runs === 0)).toBe(true);
    expect(report.topDiagnostics).toEqual([
      { id: "SD-01", runs: 6 },
      { id: "MM-01", runs: 1 },
    ]);
    expect(report.topUsers[0]).toEqual({ sapUser: "DEMO", runs: 6, chatTurns: 0 });
    expect(report.topUsers[1]).toEqual({ sapUser: "VENDAS", runs: 1, chatTurns: 2 });
    const sd01 = report.latency.find((l) => l.id === "SD-01")!;
    expect(sd01.avgMs).toBeCloseTo(300);
    expect(sd01.p95Ms).toBeCloseTo(480);

    const wide = UsageReport.parse((await call("GET", "/usage?days=120")).json());
    expect(wide.days).toHaveLength(120);
    expect(wide.topDiagnostics[0]).toEqual({ id: "SD-01", runs: 7 });
    expect((await call("GET", "/usage?days=0")).statusCode).toBe(400);
  });

  it("sem dados devolve a série zerada", async () => {
    const { db } = await testDatabase();
    await db.delete(auditEvents);
    const report = UsageReport.parse((await call("GET", "/usage")).json());
    expect(report.days).toHaveLength(30);
    expect(report).toMatchObject({ topDiagnostics: [], topUsers: [], latency: [] });
  });
});
