import { describe, expect, it } from "vitest";
import { detectDocuments } from "../src/lib/documents";
import { countsOf, rowsOf } from "../src/lib/table";
import { formatDate, parsePercent } from "../src/lib/utils";

describe("detectDocuments", () => {
  it("reconhece ordem, pedido e fatura pelo formato do número", () => {
    expect(detectDocuments("como está a ordem 1000010?")).toEqual([{ kind: "PRODUCTION_ORDER", id: "1000010" }]);
    expect(detectDocuments("pedido 4500001")).toEqual([{ kind: "SALES_ORDER", id: "4500001" }]);
    expect(detectDocuments("fatura 5105600001 de 2025")).toEqual([
      { kind: "SUPPLIER_INVOICE", id: "5105600001", year: "2025" },
    ]);
    expect(detectDocuments("sem números")).toEqual([]);
  });
});

describe("tabelas e fatos", () => {
  it("converte linhas em objetos pelas chaves", () => {
    expect(
      rowsOf({ id: "t", title: "", keys: ["a", "b"], columns: ["A", "B"], rows: [["1", "2"]], truncated: false }),
    ).toEqual([{ a: "1", b: "2" }]);
  });

  it("lê totais por prefixo", () => {
    const facts = [
      { id: "flag:LATE_FINISH", label: "", value: "2" },
      { id: "situation:RELEASED", label: "", value: "3" },
    ];
    expect(countsOf({ facts } as never, "flag")).toEqual({ LATE_FINISH: 2 });
  });

  it("formata datas e percentuais", () => {
    expect(formatDate("2026-10-09")).toBe("09/10/2026");
    expect(parsePercent("600 PC (60%)")).toBe(60);
  });
});
