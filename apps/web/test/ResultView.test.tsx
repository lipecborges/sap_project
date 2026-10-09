import type { DiagnosticResult } from "@raiox/contracts";
import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { ResultView } from "../src/components/ResultView";

const result: DiagnosticResult = {
  diagnosticId: "PP-03",
  version: "1.0",
  object: { kind: "PRODUCTION_ORDER", id: "1000010" },
  system: { sid: "MCK", client: "100", release: "ECC", basisRelease: "700" },
  status: "PROBLEM_FOUND",
  findings: [
    {
      code: "PP03.REVERSED_CONFIRMATION",
      severity: "INFO",
      title: "Apontamento estornado",
      detail: "",
      evidence: [],
    },
    {
      code: "PP03.LATE_FINISH",
      severity: "BLOCKING",
      title: "Fim atrasado em 3 dia(s)",
      detail: "O fim programado era 2026-10-06.",
      evidence: [{ source: "AFKO", field: "GLTRS", value: "2026-10-06", label: "Fim programado" }],
      suggestedAction: { tcode: "COOIS", description: "Ver as operações pendentes" },
    },
  ],
  related: [{ kind: "SALES_ORDER", id: "4500020" }],
  facts: [{ id: "situation", label: "Situação", value: "Em produção" }],
  tables: [
    { id: "operations", title: "Operações", columns: ["Operação", "Status"], rows: [["0010", "CNF"]], truncated: true },
  ],
  executedAt: "2026-10-09T12:00:00Z",
  durationMs: 42,
};

describe("ResultView", () => {
  it("mostra status, achados (bloqueios primeiro), fatos, tabelas e relacionados", () => {
    render(<ResultView result={result} />);
    expect(screen.getByText("Problema encontrado")).toBeInTheDocument();

    const titles = screen.getAllByRole("heading", { level: 3 }).map((h) => h.textContent);
    expect(titles.slice(0, 2)).toEqual(["Fim atrasado em 3 dia(s)", "Apontamento estornado"]);

    expect(screen.getByRole("button", { name: "COOIS" })).toBeInTheDocument();
    expect(screen.getByText("AFKO-GLTRS = 2026-10-06")).toBeInTheDocument();
    expect(screen.getByText("Em produção")).toBeInTheDocument();

    const table = screen.getByRole("table");
    expect(within(table).getByText("0010")).toBeInTheDocument();
    expect(screen.getByText(/Há mais registros/)).toBeInTheDocument();
    expect(screen.getByText("Pedido de venda 4500020")).toBeInTheDocument();
  });
});
