import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { ApiError, LicenseStatus, SessionInfo } from "@raiox/contracts";
import { buildServer } from "@raiox/sap-mock";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { LicensedAccessPolicy } from "../src/access";
import { DemoProvider } from "../src/ai/demo-provider";
import { createApp } from "../src/app";
import { type Config, loadConfig } from "../src/config";
import { licenses, sessions, tenants, users } from "../src/db/schema";
import { parseLicense, parsePublicKey, VENDOR_PUBLIC_KEY, verifySignature } from "../src/license/format";
import { LicenseService } from "../src/license/service";
import { UserRepository } from "../src/repos/users";
import { testDatabase } from "./helpers";
import { inDays, testVendor } from "./licenses";

const vendor = testVendor();
let mock: FastifyInstance;
let config: Config;

beforeAll(async () => {
  mock = buildServer({ release: "ECC" });
  const address = await mock.listen({ port: 0, host: "127.0.0.1" });
  config = loadConfig({
    SAP_BASE_URL: address,
    SAP_SYSTEM_NAME: "PRD",
    LOG_LEVEL: "silent",
    SESSION_SECRET: Buffer.alloc(32, 7).toString("base64"),
    LICENSE_PUBLIC_KEY: vendor.publicPem,
  });
});
afterAll(() => mock.close());

beforeEach(async () => {
  const { db } = await testDatabase();
  await db.insert(tenants).values({ id: "default", name: "Padrão" }).onConflictDoNothing();
  await db.delete(sessions);
  await db.delete(users);
  await db.delete(licenses);
});

const app = async (overrides: Partial<Config> = {}) =>
  createApp({ ...config, ...overrides }, { database: await testDatabase(), provider: new DemoProvider(0) });

const login = (api: FastifyInstance, user = "demo", password = "demo") =>
  api.inject({ method: "POST", url: "/api/v1/auth/login", payload: { user, password } });

async function install(license: string) {
  const { db } = await testDatabase();
  await db.insert(licenses).values({ tenantId: "default", license });
}

describe("formato e assinatura", () => {
  it("aceita a assinatura correta", () => {
    const parsed = parseLicense(vendor.sign({ maxNamedUsers: 7 }));
    expect(parsed.payload.maxNamedUsers).toBe(7);
    expect(verifySignature(parsed, parsePublicKey(vendor.publicPem))).toBe(true);
  });

  it("aceita a chave pública em base64 (SPKI)", () => {
    const der = parsePublicKey(vendor.publicPem).export({ type: "spki", format: "der" }).toString("base64");
    expect(verifySignature(parseLicense(vendor.sign()), parsePublicKey(der))).toBe(true);
  });

  it("rejeita payload adulterado e chave de outro fornecedor", () => {
    const [prefix, body, signature] = vendor.sign({ maxNamedUsers: 5 }).split(".");
    const forged = Buffer.from(
      JSON.stringify({ ...parseLicense(vendor.sign({ maxNamedUsers: 5 })).payload, maxNamedUsers: 500 }),
    );
    const tampered = parseLicense(`${prefix}.${forged.toString("base64url")}.${signature}`);
    expect(verifySignature(tampered, parsePublicKey(vendor.publicPem))).toBe(false);
    expect(body).toBeTruthy();

    const other = testVendor();
    expect(verifySignature(parseLicense(other.sign()), parsePublicKey(vendor.publicPem))).toBe(false);
    // A chave embutida no código também não aceita licenças assinadas por quem não é o fornecedor.
    expect(verifySignature(parseLicense(vendor.sign()), parsePublicKey(VENDOR_PUBLIC_KEY))).toBe(false);
  });

  it("a licença emitida pela CLI do fornecedor é aceita pela API", () => {
    const cli = new URL("../../../tools/license/license.mjs", import.meta.url).pathname;
    const dir = mkdtempSync(join(tmpdir(), "raiox-cli-"));
    const run = (...args: string[]) => execFileSync("node", [cli, ...args], { encoding: "utf8" }).trim();
    run("keygen", "--out", dir);
    const text = run(
      ...["sign", "--key", join(dir, "raiox-license-private.pem"), "--customer", "ACME", "--max-users", "10"],
      ...["--expires", inDays(90), "--deployment", "selfhosted", "--feature", "chat"],
    );
    const parsed = parseLicense(text);
    expect(parsed.payload).toMatchObject({
      customer: "ACME",
      maxNamedUsers: 10,
      deployment: "selfhosted",
      features: ["chat"],
    });
    const publicPem = readFileSync(join(dir, "raiox-license-public.pem"), "utf8");
    expect(verifySignature(parsed, parsePublicKey(publicPem))).toBe(true);
    expect(run("inspect", text, "--pub", join(dir, "raiox-license-public.pem"))).toContain("VÁLIDA");
  });

  it("rejeita texto fora do formato", () => {
    expect(() => parseLicense("qualquer coisa")).toThrow(/Formato/);
    expect(() => parseLicense("RXL1.e30.AAAA")).toThrow(/inválido/);
  });

  it("LICENSE_PUBLIC_KEY não é aceita em produção", () => {
    expect(() =>
      loadConfig({
        SAP_BASE_URL: "http://sap:8000",
        NODE_ENV: "production",
        DATABASE_URL: "pglite:memory",
        LICENSE_PUBLIC_KEY: vendor.publicPem,
      }),
    ).toThrow(/LICENSE_PUBLIC_KEY/);
  });
});

describe("estados da licença", () => {
  const service = async (overrides: Partial<Config> = {}) =>
    new LicenseService((await testDatabase()).db, { ...config, ...overrides });

  it("sem licença: avaliação com 5 usuários e aviso", async () => {
    const status = await (await service()).status("default");
    expect(LicenseStatus.parse(status)).toMatchObject({ state: "evaluation", maxNamedUsers: 5, licenseId: null });
    expect(status.warnings[0]).toMatch(/avaliação/);
  });

  it("licença válida longe do vencimento não tem avisos", async () => {
    const s = await service();
    const status = s.evaluateText("default", vendor.sign({ maxNamedUsers: 10 }));
    expect(status).toMatchObject({ state: "valid", maxNamedUsers: 10, warnings: [] });
  });

  it("avisa quando vence em até 30 dias e quando 90% dos usuários estão em uso", async () => {
    await install(vendor.sign({ expiresAt: inDays(10), maxNamedUsers: 1 }));
    const { db } = await testDatabase();
    await db.insert(users).values({ tenantId: "default", sapUser: "A", seatAssignedAt: new Date() });
    const status = await (await service()).status("default");
    expect(status.state).toBe("valid");
    expect(status.usedSeats).toBe(1);
    expect(status.warnings).toEqual([expect.stringMatching(/vence em/), expect.stringMatching(/1 de 1/)]);
  });

  it("vencida há menos de 15 dias: carência; depois: expirada", async () => {
    const s = await service();
    const grace = s.evaluateText("default", vendor.sign({ expiresAt: inDays(-5) }));
    expect(grace.state).toBe("grace");
    expect(grace.warnings[0]).toMatch(/bloqueado em/);
    expect(s.evaluateText("default", vendor.sign({ expiresAt: inDays(-16) })).state).toBe("expired");
  });

  it("assinatura inválida, modo de implantação e cliente errados: inválida", async () => {
    const s = await service();
    expect(s.evaluateText("default", testVendor().sign()).state).toBe("invalid");
    expect(s.evaluateText("default", "lixo")).toMatchObject({ state: "invalid", maxNamedUsers: 0 });
    // Este servidor é selfhosted.
    const cloud = s.evaluateText("default", vendor.sign({ deployment: "cloud" }));
    expect(cloud.state).toBe("invalid");
    expect(cloud.warnings[0]).toMatch(/cloud/);
    expect(s.evaluateText("default", vendor.sign({ deployment: "selfhosted" })).state).toBe("valid");
    expect(s.evaluateText("default", vendor.sign({ tenantId: "acme" })).state).toBe("invalid");
    expect(s.evaluateText("acme", vendor.sign({ tenantId: "acme" })).state).toBe("valid");
  });

  it("LICENSE_FILE vale só enquanto o banco não tem licença", async () => {
    const file = join(mkdtempSync(join(tmpdir(), "raiox-lic-")), "raiox.lic");
    writeFileSync(file, `${vendor.sign({ licenseId: "DO-ARQUIVO", maxNamedUsers: 3 })}\n`);
    const fromFile = await (await service({ LICENSE_FILE: file })).status("default");
    expect(fromFile).toMatchObject({ state: "valid", licenseId: "DO-ARQUIVO", maxNamedUsers: 3 });

    await install(vendor.sign({ licenseId: "DO-BANCO", maxNamedUsers: 8 }));
    const fromDb = await (await service({ LICENSE_FILE: file })).status("default");
    expect(fromDb).toMatchObject({ licenseId: "DO-BANCO", maxNamedUsers: 8 });

    const { db } = await testDatabase();
    await db.delete(licenses);
    const missing = await (await service({ LICENSE_FILE: join(tmpdir(), "nao-existe.lic") })).status("default");
    expect(missing.state).toBe("invalid");
  });

  it("o estado fica em cache e a instalação o renova", async () => {
    const s = await service();
    expect((await s.status("default")).state).toBe("evaluation");
    await install(vendor.sign());
    expect((await s.status("default")).state).toBe("evaluation");
    const installed = await s.install("default", vendor.sign({ licenseId: "NOVA" }), "ADMIN");
    expect(installed).toMatchObject({ state: "valid", licenseId: "NOVA" });
    await expect(s.install("default", testVendor().sign(), "ADMIN")).rejects.toMatchObject({ statusCode: 400 });
  });
});

describe("vagas de usuário nomeado", () => {
  it("atribui a vaga no primeiro login e barra o excedente com LICENSE_REQUIRED", async () => {
    await install(vendor.sign({ maxNamedUsers: 1 }));
    const api = await app();
    expect((await login(api)).statusCode).toBe(200);
    const denied = await login(api, "vendas", "vendas");
    expect(denied.statusCode).toBe(403);
    expect(ApiError.parse(denied.json()).error).toEqual({
      code: "LICENSE_REQUIRED",
      message: "Limite de 1 usuários do Raio-X atingido. Fale com o administrador.",
    });
    // Quem já tem vaga continua entrando.
    expect((await login(api)).statusCode).toBe(200);
    const { db } = await testDatabase();
    const rows = await db.select().from(users);
    expect(rows.find((r) => r.sapUser === "DEMO")?.seatAssignedAt).toBeInstanceOf(Date);
    expect(rows.find((r) => r.sapUser === "VENDAS")?.seatAssignedAt).toBeNull();
    await api.close();
  });

  it("logins simultâneos nunca passam do limite", async () => {
    await install(vendor.sign({ maxNamedUsers: 3 }));
    const db = await testDatabase();
    const repo = new UserRepository(db.db);
    const service = new LicenseService(db.db, config);
    const policy = new LicensedAccessPolicy(repo, service, []);
    const names = Array.from({ length: 12 }, (_, i) => `U${i}`);
    const results = await Promise.allSettled(
      names.map((sapUser) => policy.admitLogin({ tenantId: "default", sapUser })),
    );
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(3);
    for (const r of results.filter((x) => x.status === "rejected")) {
      expect((r as PromiseRejectedResult).reason).toMatchObject({ code: "LICENSE_REQUIRED" });
    }
    expect(await service.usedSeats("default")).toBe(3);

    // Dois logins HTTP ao mesmo tempo com uma única vaga livre: só um entra.
    await db.db.delete(users);
    await db.db.delete(licenses);
    await install(vendor.sign({ maxNamedUsers: 1 }));
    const api = await app();
    const codes = (await Promise.all([login(api), login(api, "vendas", "vendas")])).map((r) => r.statusCode).sort();
    expect(codes).toEqual([200, 403]);
    await api.close();
  });

  it("liberar a vaga tira o acesso", async () => {
    await install(vendor.sign({ maxNamedUsers: 1 }));
    const api = await app({ ADMIN_USERS: [] });
    const cookie = String((await login(api)).headers["set-cookie"]).split(";")[0]!;
    expect((await api.inject({ url: "/api/v1/diagnostics", headers: { cookie } })).statusCode).toBe(200);

    const { db } = await testDatabase();
    await db.update(users).set({ seatAssignedAt: null });
    // A leitura do usuário fica em cache por até 10 s; a política é recriada aqui para ver o banco.
    const fresh = await app({ ADMIN_USERS: [] });
    const res = await fresh.inject({ url: "/api/v1/diagnostics", headers: { cookie } });
    expect(res.statusCode).toBe(403);
    expect(ApiError.parse(res.json()).error.code).toBe("LICENSE_REQUIRED");
    await api.close();
    await fresh.close();
  });

  it("invalidate() faz a mudança valer antes do cache de 10 s vencer", async () => {
    await install(vendor.sign({ maxNamedUsers: 2 }));
    const api = await app();
    const cookie = String((await login(api)).headers["set-cookie"]).split(";")[0]!;
    expect((await api.inject({ url: "/api/v1/diagnostics", headers: { cookie } })).statusCode).toBe(200);
    const { db } = await testDatabase();
    await db.update(users).set({ seatAssignedAt: null });
    // Ainda em cache neste processo: continua valendo...
    expect((await api.inject({ url: "/api/v1/diagnostics", headers: { cookie } })).statusCode).toBe(200);
    // ...até a administração invalidar.
    api.ctx.access.invalidate?.("default", "DEMO");
    expect((await api.inject({ url: "/api/v1/diagnostics", headers: { cookie } })).statusCode).toBe(403);
    await api.close();
  });

  it("licença expirada ou inválida barra usuários, mas o administrador entra para instalar outra", async () => {
    await install(vendor.sign({ expiresAt: inDays(-40) }));
    const api = await app({ ADMIN_USERS: ["DEMO"] });
    const denied = await login(api, "vendas", "vendas");
    expect(denied.statusCode).toBe(403);
    expect(ApiError.parse(denied.json()).error.code).toBe("LICENSE_REQUIRED");
    const admin = await login(api);
    expect(admin.statusCode).toBe(200);
    const info = SessionInfo.parse(admin.json());
    expect(info.role).toBe("admin");
    expect(info.notice).toMatch(/vencida/);
    await api.close();

    const { db } = await testDatabase();
    await db.delete(licenses);
    await install(testVendor().sign());
    const invalid = await app();
    expect((await login(invalid, "vendas", "vendas")).statusCode).toBe(403);
    await invalid.close();
  });

  it("em carência todos entram e o SessionInfo traz o aviso", async () => {
    await install(vendor.sign({ expiresAt: inDays(-3) }));
    const api = await app();
    const res = await login(api);
    expect(res.statusCode).toBe(200);
    const info = SessionInfo.parse(res.json());
    expect(info.notice).toMatch(/Licença vencida/);
    const cookie = String(res.headers["set-cookie"]).split(";")[0]!;
    const again = SessionInfo.parse((await api.inject({ url: "/api/v1/auth/session", headers: { cookie } })).json());
    expect(again.notice).toBe(info.notice);
    await api.close();
  });

  it("licença válida não gera aviso e o bloqueio continua valendo", async () => {
    await install(vendor.sign());
    const api = await app();
    const res = await login(api);
    expect(SessionInfo.parse(res.json()).notice).toBeUndefined();
    const { db } = await testDatabase();
    await db.update(users).set({ blocked: true });
    expect((await login(api)).statusCode).toBe(403);
    await api.close();
  });

  it("administrador entra mesmo com o limite atingido", async () => {
    await install(vendor.sign({ maxNamedUsers: 1 }));
    const api = await app({ ADMIN_USERS: ["DEMO"] });
    expect((await login(api, "vendas", "vendas")).statusCode).toBe(200);
    expect((await login(api)).statusCode).toBe(200);
    await api.close();
  });
});
