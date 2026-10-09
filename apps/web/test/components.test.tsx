import type { Finding, ResultTable } from "@raiox/contracts";
import { render, screen, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { BarList } from "../src/components/charts/BarList";
import { FindingList } from "../src/components/domain/findings";
import { ResultTableView } from "../src/components/domain/result-table";

const findings: Finding[] = [
  { code: "PP03.REVERSED_CONFIRMATION", severity: "INFO", title: "Apontamento estornado", detail: "", evidence: [] },
  {
    code: "PP03.LATE_FINISH",
    severity: "BLOCKING",
    title: "Fim atrasado em 3 dia(s)",
    detail: "O fim programado era 2026-10-06.",
    evidence: [{ source: "AFKO", field: "GLTRS", value: "2026-10-06", label: "Fim programado" }],
    suggestedAction: { tcode: "COOIS", description: "Ver as operações pendentes" },
  },
];

describe("FindingList", () => {
  it("mostra bloqueios primeiro, com evidência e transação", () => {
    render(<FindingList findings={findings} />);
    const titles = screen.getAllByRole("heading", { level: 3 }).map((h) => h.textContent);
    expect(titles).toEqual(["Fim atrasado em 3 dia(s)", "Apontamento estornado"]);
    expect(screen.getByRole("button", { name: /COOIS/ })).toBeInTheDocument();
    expect(screen.getByText(/AFKO-GLTRS/)).toBeInTheDocument();
  });
});

describe("ResultTableView", () => {
  it("esconde colunas técnicas de código", () => {
    const table: ResultTable = {
      id: "orders",
      title: "Ordens",
      keys: ["order", "situation", "situationCode"],
      columns: ["Ordem", "Situação", "Código da situação"],
      rows: [["1000010", "Em produção", "IN_PRODUCTION"]],
      truncated: false,
    };
    render(<ResultTableView table={table} />);
    const grid = screen.getByRole("table");
    expect(within(grid).getByText("Em produção")).toBeInTheDocument();
    expect(within(grid).queryByText("IN_PRODUCTION")).not.toBeInTheDocument();
  });
});

describe("BarList", () => {
  it("rotula cada barra e oferece tabela acessível", () => {
    render(
      <BarList
        ariaLabel="Ordens por situação"
        unit={["ordem", "ordens"]}
        data={[
          { key: "RELEASED", label: "Liberada", value: 3 },
          { key: "CREATED", label: "Criada", value: 1 },
        ]}
      />,
    );
    expect(screen.getAllByText("Liberada")).toHaveLength(2);
    expect(screen.getByText("3 ordens")).toBeInTheDocument();
    expect(screen.getByText("1 ordem")).toBeInTheDocument();
  });
});
