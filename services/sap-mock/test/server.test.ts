import { ApiError, DiagnosticResult, DiagnosticsResponse, HealthResponse, MeResponse } from "@raiox/contracts";
import { afterAll, describe, expect, it } from "vitest";
import { buildServer, ICF_BASE_PATH } from "../src/server";

const app = buildServer({ release: "ECC", today: new Date("2026-10-09T12:00:00Z") });
afterAll(() => app.close());

const basic = (user: string, password: string) => `Basic ${Buffer.from(`${user}:${password}`).toString("base64")}`;
const DEMO = basic("demo", "demo");

async function run(id: string, params: Record<string, string>, authorization = DEMO) {
  return app.inject({
    method: "POST",
    url: `${ICF_BASE_PATH}/diagnostics/${id}?sap-client=100`,
    headers: { authorization, "content-type": "application/x-www-form-urlencoded" },
    payload: new URLSearchParams(params).toString(),
  });
}

describe("autenticação e rotas", () => {
  it("rejeita sem credencial com 401 e WWW-Authenticate", async () => {
    const res = await app.inject({ method: "GET", url: `${ICF_BASE_PATH}/me` });
    expect(res.statusCode).toBe(401);
    expect(res.headers["www-authenticate"]).toContain("Basic");
    expect(ApiError.parse(res.json()).error.code).toBe("UNAUTHENTICATED");
  });

  it("rejeita senha errada", async () => {
    const res = await app.inject({
      method: "GET",
      url: `${ICF_BASE_PATH}/me`,
      headers: { authorization: basic("DEMO", "x") },
    });
    expect(res.statusCode).toBe(401);
  });

  it("health, me e catálogo seguem o contrato", async () => {
    const headers = { authorization: DEMO };
    const health = HealthResponse.parse((await app.inject({ url: `${ICF_BASE_PATH}/health`, headers })).json());
    expect(health.system.release).toBe("ECC");
    const me = MeResponse.parse((await app.inject({ url: `${ICF_BASE_PATH}/me`, headers })).json());
    expect(me.user).toBe("DEMO");
    const catalog = DiagnosticsResponse.parse(
      (await app.inject({ url: `${ICF_BASE_PATH}/diagnostics`, headers })).json(),
    );
    expect(catalog.diagnostics.map((d) => d.id)).toEqual([
      "SD-01",
      "SD-10",
      "MM-02",
      "MM-10",
      "PP-01",
      "PP-03",
      "PP-04",
    ]);
  });

  it("nega diagnóstico sem autorização (ZRX_DIAG)", async () => {
    const res = await run("PP-01", { productionOrder: "1000001" }, basic("VENDAS", "vendas"));
    expect(res.statusCode).toBe(403);
    expect(ApiError.parse(res.json()).error.code).toBe("NOT_AUTHORIZED");
  });

  it("valida parâmetros", async () => {
    const res = await run("MM-02", { invoiceDocument: "abc" });
    expect(res.statusCode).toBe(400);
    const body = ApiError.parse(res.json());
    expect(body.error.params).toEqual({ invoiceDocument: "Use apenas números", fiscalYear: "Obrigatório" });
  });

  it("diagnóstico desconhecido dá 404", async () => {
    const res = await run("XX-99", {});
    expect(res.statusCode).toBe(404);
    expect(ApiError.parse(res.json()).error.code).toBe("UNKNOWN_DIAGNOSTIC");
  });
});

const SCENARIOS: Array<[string, Record<string, string>, DiagnosticResult["status"], string[]]> = [
  ["SD-01", { salesOrder: "0004500001" }, "PROBLEM_FOUND", ["SD01.CREDIT_BLOCK"]],
  ["SD-01", { salesOrder: "4500002" }, "PROBLEM_FOUND", ["SD01.DELIVERY_BLOCK_HEADER", "SD01.INCOMPLETE"]],
  ["SD-01", { salesOrder: "4500003" }, "PROBLEM_FOUND", ["SD01.GOODS_ISSUE_PENDING"]],
  ["SD-01", { salesOrder: "4500004" }, "OK", ["SD01.ALREADY_BILLED"]],
  ["SD-01", { salesOrder: "4500005" }, "PROBLEM_FOUND", ["SD01.BILLING_BLOCK", "SD01.ITEM_REJECTED"]],
  ["SD-01", { salesOrder: "4500006" }, "PROBLEM_FOUND", ["SD01.CREDIT_BLOCK"]],
  ["SD-01", { salesOrder: "4500007" }, "PROBLEM_FOUND", ["SD01.INCOMPLETE"]],
  ["SD-01", { salesOrder: "9999999" }, "NOT_FOUND", ["SD01.NOT_FOUND"]],
  ["SD-10", {}, "PROBLEM_FOUND", ["SD10.PAST_REQUESTED_DATE"]],
  ["MM-10", {}, "PROBLEM_FOUND", ["MM10.OVERDUE"]],
  [
    "MM-02",
    { invoiceDocument: "5105600005", fiscalYear: "2026" },
    "PROBLEM_FOUND",
    ["MM02.PAYMENT_BLOCK", "MM02.BLOCK_DATE"],
  ],
  [
    "MM-02",
    { invoiceDocument: "5105600001", fiscalYear: "2026" },
    "PROBLEM_FOUND",
    ["MM02.PAYMENT_BLOCK", "MM02.BLOCK_PRICE", "MM02.PRICE_DIFF", "MM02.TOLERANCE_INFO"],
  ],
  [
    "MM-02",
    { invoiceDocument: "5105600002", fiscalYear: "2026" },
    "PROBLEM_FOUND",
    ["MM02.BLOCK_QUANTITY", "MM02.GR_MISSING"],
  ],
  ["MM-02", { invoiceDocument: "5105600003", fiscalYear: "2026" }, "OK", ["MM02.NOT_BLOCKED"]],
  ["MM-02", { invoiceDocument: "5105600004", fiscalYear: "2026" }, "PROBLEM_FOUND", ["MM02.PARKED"]],
  ["PP-01", { productionOrder: "1000001" }, "PROBLEM_FOUND", ["PP01.NOT_RELEASED", "PP01.MISSING_PARTS"]],
  ["PP-01", { productionOrder: "1000002" }, "PROBLEM_FOUND", ["PP01.NOT_RELEASED", "PP01.USER_STATUS_BLOCK"]],
  ["PP-01", { productionOrder: "1000003" }, "OK", ["PP01.RELEASED"]],
  ["PP-01", { productionOrder: "1000004" }, "PROBLEM_FOUND", ["PP01.LOCKED"]],
  ["PP-01", { productionOrder: "1000005" }, "OK", ["PP01.TECO"]],
  ["PP-01", { productionOrder: "1000006" }, "PROBLEM_FOUND", ["PP01.NOT_RELEASED", "PP01.MANUAL_RELEASE"]],
  [
    "PP-03",
    { productionOrder: "1000010" },
    "PROBLEM_FOUND",
    ["PP03.LATE_FINISH", "PP03.OPERATION_LATE", "PP03.MISSING_PARTS", "PP03.SALES_ORDER_AT_RISK"],
  ],
  ["PP-03", { productionOrder: "1000011" }, "OK", []],
  ["PP-03", { productionOrder: "1000012" }, "PROBLEM_FOUND", ["PP03.LATE_FINISH", "PP03.CONFIRMED_NOT_RECEIVED"]],
  ["PP-03", { productionOrder: "1000013" }, "OK", ["PP03.REVERSED_CONFIRMATION"]],
  ["PP-03", { productionOrder: "1000001" }, "PROBLEM_FOUND", ["PP03.LATE_START", "PP03.MISSING_PARTS"]],
  ["PP-03", { productionOrder: "1" }, "NOT_FOUND", ["PP03.NOT_FOUND"]],
  ["PP-04", { plant: "1000" }, "PROBLEM_FOUND", ["PP04.LATE_ORDERS", "PP04.MISSING_PARTS"]],
  ["PP-04", { plant: "9999" }, "NOT_FOUND", ["PP04.NO_ORDERS"]],
];

describe.each(SCENARIOS)("%s %o", (id, params, status, codes) => {
  it(`retorna ${status} com ${codes.join(", ") || "nenhum achado"}`, async () => {
    const res = await run(id, params);
    expect(res.statusCode).toBe(200);
    const result = DiagnosticResult.parse(res.json());
    expect(result.status).toBe(status);
    expect(result.findings.map((f) => f.code)).toEqual(codes);
  });
});

describe("listas", () => {
  it("SD-10 lista os pedidos travados com etapa e totais", async () => {
    const result = DiagnosticResult.parse((await run("SD-10", {})).json());
    const table = result.tables[0]!;
    expect(table.rows.map((row) => row[0])).toEqual(["4500003", "4500001", "4500002", "4500005", "4500006", "4500007"]);
    expect(result.facts.find((f) => f.id === "stage:CREDIT")?.value).toBe("2");
    const onlyCredit = DiagnosticResult.parse((await run("SD-10", { stage: "CREDIT" })).json());
    expect(onlyCredit.tables[0]!.rows).toHaveLength(2);
  });

  it("MM-10 lista as faturas pendentes por vencimento", async () => {
    const result = DiagnosticResult.parse((await run("MM-10", {})).json());
    expect(result.tables[0]!.rows.map((row) => row[0])).toEqual([
      "5105600002",
      "5105600001",
      "5105600005",
      "5105600004",
    ]);
    expect(result.facts.find((f) => f.id === "state:PARKED")?.value).toBe("1");
  });

  it("toda linha de lista tem um diagnóstico de detalhe com resultado", async () => {
    const sd = DiagnosticResult.parse((await run("SD-10", {})).json());
    for (const row of sd.tables[0]!.rows) {
      const detail = DiagnosticResult.parse((await run("SD-01", { salesOrder: row[0]! })).json());
      expect(detail.status).not.toBe("NOT_FOUND");
    }
    const mm = DiagnosticResult.parse((await run("MM-10", {})).json());
    for (const row of mm.tables[0]!.rows) {
      const detail = DiagnosticResult.parse(
        (await run("MM-02", { invoiceDocument: row[0]!, fiscalYear: row[1]! })).json(),
      );
      expect(detail.status).not.toBe("NOT_FOUND");
    }
  });
});

describe("PP-04", () => {
  it("expõe totais por código de situação e sinalizador", async () => {
    const result = DiagnosticResult.parse((await run("PP-04", { plant: "1000" })).json());
    expect(result.facts.find((f) => f.id === "flag:LATE_FINISH")?.value).toBe("2");
    const keys = result.tables[0]!.keys;
    const row = result.tables[0]!.rows.find((r) => r[0] === "1000010")!;
    expect(row[keys.indexOf("situationCode")]).toBe("IN_PRODUCTION");
    expect(row[keys.indexOf("progress")]).toBe("60");
  });

  it("filtra por situação e sinalizador e ordena por atraso", async () => {
    const late = DiagnosticResult.parse((await run("PP-04", { plant: "1000", situation: "LATE_FINISH" })).json());
    const orders = late.tables[0]!.rows.map((row) => row[0]);
    expect(orders).toEqual(["1000010", "1000012"]);

    const approved = DiagnosticResult.parse((await run("PP-04", { plant: "1000", situation: "APPROVED" })).json());
    expect(approved.tables[0]!.rows.map((row) => row[0])).toEqual(["1000006"]);
  });

  it("pagina e marca truncated", async () => {
    const page1 = DiagnosticResult.parse((await run("PP-04", { plant: "1000", maxRows: "3" })).json());
    expect(page1.tables[0]!.rows).toHaveLength(3);
    expect(page1.tables[0]!.truncated).toBe(true);
  });

  it("rejeita situação inválida", async () => {
    const res = await run("PP-04", { plant: "1000", situation: "QUALQUER" });
    expect(res.statusCode).toBe(400);
  });
});

describe("release S/4", () => {
  it("usa VBAK como fonte do status de crédito", async () => {
    const s4 = buildServer({ release: "S4" });
    const res = await s4.inject({
      method: "POST",
      url: `${ICF_BASE_PATH}/diagnostics/SD-01`,
      headers: { authorization: DEMO },
      query: { salesOrder: "4500001" },
    });
    const result = DiagnosticResult.parse(res.json());
    expect(result.findings[0]!.evidence[0]!.source).toBe("VBAK");
    expect(result.findings[0]!.suggestedAction?.tcode).toBe("UKM_MY_DCDS");
    await s4.close();
  });
});
