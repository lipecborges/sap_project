import type { AdminUser, LicenseState } from "@raiox/contracts";
import type { Tone } from "../components/ui/badge";

/** Funções puras da área de administração (filtros, formatos, estados). */

export interface AuditFilters {
  user: string;
  action: string;
  /** Datas "AAAA-MM-DD" dos campos de data; viram intervalo ISO ao consultar. */
  from: string;
  to: string;
}

export const EMPTY_AUDIT_FILTERS: AuditFilters = { user: "", action: "", from: "", to: "" };

const DAY = /^(\d{4})-(\d{2})-(\d{2})$/;

/** Início (ou fim) do dia local de "AAAA-MM-DD" em ISO; undefined se a data for inválida. */
export function dayBoundary(day: string, edge: "start" | "end"): string | undefined {
  const m = DAY.exec(day);
  if (!m) return undefined;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const date = edge === "start" ? new Date(y, mo - 1, d, 0, 0, 0, 0) : new Date(y, mo - 1, d, 23, 59, 59, 999);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
}

/** Querystring de /admin/audit (e .csv): só os filtros preenchidos, usuário em maiúsculas. */
export function auditQuery(filters: AuditFilters, extra: { before?: number; limit?: number } = {}): string {
  const q = new URLSearchParams();
  const user = filters.user.trim().toUpperCase();
  const action = filters.action.trim();
  const from = dayBoundary(filters.from, "start");
  const to = dayBoundary(filters.to, "end");
  if (user) q.set("user", user);
  if (action) q.set("action", action);
  if (from) q.set("from", from);
  if (to) q.set("to", to);
  if (extra.before !== undefined) q.set("before", String(extra.before));
  if (extra.limit !== undefined) q.set("limit", String(extra.limit));
  return q.toString();
}

export function auditCsvUrl(filters: AuditFilters): string {
  const query = auditQuery(filters);
  return `/api/v1/admin/audit.csv${query ? `?${query}` : ""}`;
}

export function hasAuditFilters(filters: AuditFilters): boolean {
  return Object.values(filters).some((v) => v.trim() !== "");
}

export const LICENSE_STATE: Record<LicenseState, { label: string; tone: Tone; hint: string }> = {
  valid: { label: "Válida", tone: "good", hint: "Licença ativa e dentro da validade." },
  evaluation: {
    label: "Avaliação",
    tone: "info",
    hint: "Sem licença instalada: funciona com limite reduzido de usuários.",
  },
  grace: {
    label: "Vencida (carência)",
    tone: "warning",
    hint: "A licença venceu, mas o produto segue funcionando por um período. Instale a renovação.",
  },
  expired: { label: "Vencida", tone: "critical", hint: "A licença venceu: novos acessos podem ser recusados." },
  invalid: { label: "Inválida", tone: "critical", hint: "A licença instalada não pôde ser validada." },
};

/** Percentual de licenças em uso (0–100+); sem limite conhecido retorna 0. */
export function seatPercent(used: number, max: number): number {
  return max > 0 ? Math.round((used / max) * 100) : 0;
}

export function outcomeTone(outcome: string): Tone {
  const o = outcome.toLowerCase();
  if (o === "ok" || o === "success") return "good";
  if (o.includes("rate")) return "warning";
  return "critical";
}

export function outcomeLabel(outcome: string): string {
  return outcome.toLowerCase() === "ok" ? "Sucesso" : outcome;
}

/** Comando para subir o conector on-premise com o token exibido uma única vez. */
export function connectorSnippet(token: string, origin: string): string {
  const url = new URL(origin);
  const wsUrl = `${url.protocol === "https:" ? "wss" : "ws"}://${url.host}/connector/v1/ws`;
  return [
    "docker run -d --name raiox-connector --restart unless-stopped \\",
    `  -e RAIOX_URL=${wsUrl} \\`,
    `  -e RAIOX_CONNECTOR_TOKEN=${token} \\`,
    "  -e SAP_BASE_URL=http://<sap-host>:<porta> \\",
    "  raiox/connector",
  ].join("\n");
}

const dateTime = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short", timeStyle: "short" });
const dateOnly = new Intl.DateTimeFormat("pt-BR", { dateStyle: "short" });

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : dateTime.format(d);
}

export function formatDay(iso: string | null | undefined): string {
  if (!iso) return "—";
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : dateOnly.format(d);
}

/** "agora", "há 5 min", "há 3 h", "há 2 dias"; datas muito antigas voltam ao formato curto. */
export function timeAgo(iso: string | null | undefined, now = new Date()): string {
  if (!iso) return "nunca";
  const then = new Date(iso);
  if (Number.isNaN(then.getTime())) return iso;
  const minutes = Math.floor((now.getTime() - then.getTime()) / 60_000);
  if (minutes < 1) return "agora";
  if (minutes < 60) return `há ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `há ${hours} h`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `há ${days} ${days === 1 ? "dia" : "dias"}`;
  return formatDay(iso);
}

export function formatMs(ms: number): string {
  return ms >= 1000 ? `${(ms / 1000).toFixed(1).replace(".", ",")} s` : `${Math.round(ms)} ms`;
}

/** "2026-10-09" → "09/10" (eixo do gráfico diário). */
export function shortDay(date: string): string {
  const m = DAY.exec(date.slice(0, 10));
  return m ? `${m[3]}/${m[2]}` : date;
}

/** Arquivos de licença aceitos no upload: texto pequeno (.txt, .lic). */
export function isLicenseFile(file: { name: string; size: number }): boolean {
  return /\.(txt|lic|license|pem)$/i.test(file.name) && file.size <= 20_000;
}

/** Busca por usuário SAP ou nome, sem diferenciar maiúsculas e acentos. */
export function filterUsers(users: AdminUser[], query: string): AdminUser[] {
  const norm = (v: string) =>
    v
      .normalize("NFD")
      .replace(/\p{Diacritic}/gu, "")
      .toLowerCase();
  const q = norm(query.trim());
  if (!q) return users;
  return users.filter((u) => norm(u.sapUser).includes(q) || norm(u.displayName ?? "").includes(q));
}
