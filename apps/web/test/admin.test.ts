import type { AdminUser } from "@raiox/contracts";
import { describe, expect, it } from "vitest";
import { ADMIN_NAV, isActivePath, navSections } from "../src/layouts/nav";
import {
  auditCsvUrl,
  auditQuery,
  connectorSnippet,
  dayBoundary,
  EMPTY_AUDIT_FILTERS,
  filterUsers,
  formatMs,
  hasAuditFilters,
  outcomeTone,
  seatPercent,
  timeAgo,
} from "../src/lib/admin";
import { RequestError } from "../src/lib/api";
import { loginErrorMessage, pickSystem } from "../src/lib/login";

describe("consulta de auditoria", () => {
  it("monta só os filtros preenchidos, com usuário em maiúsculas", () => {
    const q = new URLSearchParams(auditQuery({ ...EMPTY_AUDIT_FILTERS, user: " demo ", action: "LOGIN" }));
    expect(Object.fromEntries(q)).toEqual({ user: "DEMO", action: "LOGIN" });
  });

  it("converte o período para ISO (início e fim do dia local) e inclui paginação", () => {
    const q = new URLSearchParams(
      auditQuery({ user: "", action: "", from: "2026-10-01", to: "2026-10-09" }, { before: 120, limit: 50 }),
    );
    expect(q.get("from")).toBe(new Date(2026, 9, 1, 0, 0, 0, 0).toISOString());
    expect(q.get("to")).toBe(new Date(2026, 9, 9, 23, 59, 59, 999).toISOString());
    expect(q.get("before")).toBe("120");
    expect(q.get("limit")).toBe("50");
    expect(q.has("user")).toBe(false);
  });

  it("ignora datas inválidas", () => {
    expect(dayBoundary("09/10/2026", "start")).toBeUndefined();
    expect(auditQuery({ ...EMPTY_AUDIT_FILTERS, from: "ontem" })).toBe("");
  });

  it("gera o link do CSV com os mesmos filtros (e sem '?' quando não há filtro)", () => {
    expect(auditCsvUrl(EMPTY_AUDIT_FILTERS)).toBe("/api/v1/admin/audit.csv");
    const url = auditCsvUrl({ ...EMPTY_AUDIT_FILTERS, user: "ana", action: "ADMIN_USER_UPDATE" });
    expect(url).toBe("/api/v1/admin/audit.csv?user=ANA&action=ADMIN_USER_UPDATE");
    // O CSV não pagina: nunca leva before/limit.
    expect(url).not.toContain("before");
  });

  it("detecta se há filtros ativos", () => {
    expect(hasAuditFilters(EMPTY_AUDIT_FILTERS)).toBe(false);
    expect(hasAuditFilters({ ...EMPTY_AUDIT_FILTERS, action: "LOGIN" })).toBe(true);
  });
});

describe("visibilidade do menu por papel", () => {
  const diagnostics = ["PP-04", "SD-10"];

  it("administrador vê a administração; usuário comum não", () => {
    expect(navSections({ diagnostics, role: "admin" }).admin.map((n) => n.to)).toEqual(ADMIN_NAV.map((n) => n.to));
    expect(navSections({ diagnostics, role: "user" }).admin).toEqual([]);
  });

  it("continua filtrando os processos pelas autorizações SAP", () => {
    const nav = navSections({ diagnostics, role: "admin" });
    expect(nav.process.map((n) => n.to)).toEqual(["/producao", "/vendas"]);
    expect(nav.main.map((n) => n.to)).toEqual(["/", "/assistente"]);
  });

  it("marca a rota ativa sem confundir prefixos", () => {
    expect(isActivePath("/admin/usuarios", "/admin/usuarios")).toBe(true);
    expect(isActivePath("/admin/usuarios", "/admin")).toBe(true);
    expect(isActivePath("/administracao", "/admin")).toBe(false);
    expect(isActivePath("/producao/ordens/1", "/producao")).toBe(true);
    expect(isActivePath("/vendas", "/")).toBe(false);
  });
});

describe("login", () => {
  const err = (code: string, message = "msg do servidor") => new RequestError(403, code, message);

  it("traduz os códigos específicos de login", () => {
    expect(loginErrorMessage(err("LICENSE_REQUIRED"))).toMatch(/licença/i);
    expect(loginErrorMessage(err("FORBIDDEN"))).toMatch(/bloqueado/i);
    expect(loginErrorMessage(err("RATE_LIMITED"))).toMatch(/tentativas/i);
  });

  it("usa a mensagem do servidor nos demais casos", () => {
    expect(loginErrorMessage(err("UNAUTHENTICATED", "Usuário ou senha inválidos"))).toBe("Usuário ou senha inválidos");
    expect(loginErrorMessage(new Error("x"))).toBe("Não foi possível entrar");
  });

  it("escolhe o sistema: lembrado, senão padrão, senão o primeiro", () => {
    const systems = [
      { id: "prd", isDefault: false },
      { id: "qas", isDefault: true },
    ];
    expect(pickSystem(systems, "prd")).toBe("prd");
    expect(pickSystem(systems, "sumiu")).toBe("qas");
    expect(pickSystem([{ id: "a", isDefault: false }])).toBe("a");
    expect(pickSystem([])).toBeUndefined();
  });
});

describe("conector e formatos", () => {
  it("monta o comando docker com o token e a URL websocket do próprio servidor", () => {
    const snippet = connectorSnippet("tok_123", "https://raiox.exemplo.com.br");
    expect(snippet).toContain("-e RAIOX_URL=wss://raiox.exemplo.com.br/connector/v1/ws");
    expect(snippet).toContain("-e RAIOX_CONNECTOR_TOKEN=tok_123");
    expect(snippet).toContain("-e SAP_BASE_URL=http://<sap-host>:<porta>");
    expect(snippet).toContain("raiox/connector");
    expect(connectorSnippet("t", "http://localhost:5173")).toContain("ws://localhost:5173/connector/v1/ws");
  });

  it("calcula o uso de licenças e o tom do resultado", () => {
    expect(seatPercent(9, 10)).toBe(90);
    expect(seatPercent(1, 0)).toBe(0);
    expect(outcomeTone("ok")).toBe("good");
    expect(outcomeTone("RATE_LIMITED")).toBe("warning");
    expect(outcomeTone("SAP_UNAVAILABLE")).toBe("critical");
  });

  it("formata tempos", () => {
    const now = new Date("2026-10-09T12:00:00Z");
    expect(timeAgo(null, now)).toBe("nunca");
    expect(timeAgo("2026-10-09T11:55:00Z", now)).toBe("há 5 min");
    expect(timeAgo("2026-10-09T09:00:00Z", now)).toBe("há 3 h");
    expect(timeAgo("2026-10-07T12:00:00Z", now)).toBe("há 2 dias");
    expect(formatMs(850)).toBe("850 ms");
    expect(formatMs(1520)).toBe("1,5 s");
  });

  it("filtra usuários por usuário SAP ou nome, ignorando acentos", () => {
    const user = (sapUser: string, displayName: string | null): AdminUser => ({
      sapUser,
      displayName,
      role: "user",
      hasSeat: true,
      blocked: false,
      firstLoginAt: "2026-01-01T00:00:00Z",
      lastLoginAt: null,
      activeSessions: 0,
    });
    const users = [user("DEMO", "José da Silva"), user("ANA", null)];
    expect(filterUsers(users, "jose").map((u) => u.sapUser)).toEqual(["DEMO"]);
    expect(filterUsers(users, " an ").map((u) => u.sapUser)).toEqual(["ANA"]);
    expect(filterUsers(users, "")).toHaveLength(2);
  });
});
