import { describe, expect, it } from "vitest";
import { DIAGNOSTICS, DiagnosticMeta, findDiagnostic, ResultTable, stripLeadingZeros, validateParams } from "../src";

describe("catálogo", () => {
  it("todos os diagnósticos seguem o contrato e têm id único", () => {
    for (const d of DIAGNOSTICS) DiagnosticMeta.parse(d);
    expect(new Set(DIAGNOSTICS.map((d) => d.id)).size).toBe(DIAGNOSTICS.length);
  });
});

describe("validateParams", () => {
  const pp04 = findDiagnostic("PP-04")!;

  it("exige obrigatórios", () => {
    expect(validateParams(pp04, {})).toEqual({ plant: "Obrigatório" });
  });

  it("valida data, inteiro e enum", () => {
    expect(validateParams(pp04, { plant: "1000", dateFrom: "09/10/2026", maxRows: "dez", situation: "X" })).toEqual({
      dateFrom: "Use o formato AAAA-MM-DD",
      maxRows: "Use apenas números",
      situation: expect.stringContaining("Valor inválido"),
    });
  });

  it("aceita parâmetros válidos", () => {
    expect(validateParams(pp04, { plant: "1000", situation: "LATE_FINISH", dateTo: "2026-12-31" })).toEqual({});
  });
});

describe("ResultTable", () => {
  it("exige o mesmo número de colunas em cada linha", () => {
    const result = ResultTable.safeParse({ id: "t", title: "", columns: ["a", "b"], rows: [["1"]], truncated: false });
    expect(result.success).toBe(false);
  });
});

describe("stripLeadingZeros", () => {
  it("remove zeros à esquerda como a conversão ALPHA", () => {
    expect(stripLeadingZeros("0004500123")).toBe("4500123");
    expect(stripLeadingZeros("000")).toBe("0");
  });
});
