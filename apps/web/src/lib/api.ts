import {
  AdminConnectorCreated,
  AdminConnectorList,
  type AdminSystemInput,
  AdminSystemList,
  AdminUserList,
  type AdminUserUpdate,
  ApiError,
  AppInfo,
  AuditPage,
  ChatEvent,
  type ChatRequest,
  ConversationDetail,
  ConversationList,
  type DiagnosticMeta,
  DiagnosticResult,
  DiagnosticsResponse,
  HealthResponse,
  LicenseStatus,
  OverviewResponse,
  SessionInfo,
  SystemsResponse,
  SystemTestResult,
  UsageReport,
} from "@raiox/contracts";
import { z } from "zod";
import { type AuditFilters, auditQuery } from "./admin";

export interface Credentials {
  user: string;
  password: string;
  /** Sistema SAP escolhido na tela de login (quando há mais de um). */
  system?: string;
}

/** Disparado quando a sessão expira, para o app voltar ao login. */
export const UNAUTHORIZED_EVENT = "raiox:unauthorized";

export class RequestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly params?: Record<string, string>,
  ) {
    super(message);
  }
}

/** A sessão é um cookie httpOnly emitido pela API no login: a senha não fica no navegador. */
async function request<T extends z.ZodType>(path: string, schema: T, init: RequestInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("accept", "application/json");
  let res: Response;
  try {
    res = await fetch(path, { ...init, headers, credentials: "same-origin" });
  } catch {
    throw new RequestError(0, "NETWORK", "Sem conexão com o servidor Raio-X");
  }
  const body: unknown = await res.json().catch(() => undefined);
  if (!res.ok) {
    if (res.status === 401 && !path.startsWith("/api/v1/auth/")) window.dispatchEvent(new Event(UNAUTHORIZED_EVENT));
    const err = ApiError.safeParse(body);
    if (err.success)
      throw new RequestError(res.status, err.data.error.code, err.data.error.message, err.data.error.params);
    throw new RequestError(res.status, "HTTP", `Erro HTTP ${res.status}`);
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) throw new RequestError(res.status, "BAD_RESPONSE", "Resposta inesperada do servidor");
  return parsed.data as z.infer<T>;
}

const json = (body: unknown, method = "POST"): RequestInit => ({
  method,
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

const anything = z.unknown();
const enc = encodeURIComponent;

export const api = {
  info: () => request("/api/health", AppInfo),
  systems: () => request("/api/v1/auth/systems", SystemsResponse),
  login: (creds: Credentials) => request("/api/v1/auth/login", SessionInfo, json(creds)),
  session: () => request("/api/v1/auth/session", SessionInfo),
  logout: () => fetch("/api/v1/auth/logout", { method: "POST", credentials: "same-origin" }).catch(() => undefined),
  sapHealth: () => request("/api/v1/sap/health", HealthResponse),
  diagnostics: async (): Promise<DiagnosticMeta[]> =>
    (await request("/api/v1/diagnostics", DiagnosticsResponse)).diagnostics,
  overview: (plant?: string) =>
    request(`/api/v1/overview${plant ? `?plant=${encodeURIComponent(plant)}` : ""}`, OverviewResponse),
  run: (id: string, params: Record<string, string>) =>
    request(`/api/v1/diagnostics/${encodeURIComponent(id)}`, DiagnosticResult, json({ params })),

  conversations: async () => (await request("/api/v1/conversations", ConversationList)).conversations,
  conversation: (id: string) => request(`/api/v1/conversations/${enc(id)}`, ConversationDetail),
  deleteConversation: (id: string) => request(`/api/v1/conversations/${enc(id)}`, anything, { method: "DELETE" }),

  admin: {
    users: async () => (await request("/api/v1/admin/users", AdminUserList)).users,
    updateUser: (sapUser: string, patch: AdminUserUpdate) =>
      request(`/api/v1/admin/users/${enc(sapUser)}`, anything, json(patch, "PATCH")),
    license: () => request("/api/v1/admin/license", LicenseStatus),
    installLicense: (license: string) => request("/api/v1/admin/license", LicenseStatus, json({ license }, "PUT")),
    systems: async () => (await request("/api/v1/admin/systems", AdminSystemList)).systems,
    createSystem: (input: AdminSystemInput) => request("/api/v1/admin/systems", anything, json(input)),
    updateSystem: (id: string, input: AdminSystemInput) =>
      request(`/api/v1/admin/systems/${enc(id)}`, anything, json(input, "PATCH")),
    deleteSystem: (id: string) => request(`/api/v1/admin/systems/${enc(id)}`, anything, { method: "DELETE" }),
    testSystem: (id: string) => request(`/api/v1/admin/systems/${enc(id)}/test`, SystemTestResult, { method: "POST" }),
    connectors: async () => (await request("/api/v1/admin/connectors", AdminConnectorList)).connectors,
    createConnector: (name: string) => request("/api/v1/admin/connectors", AdminConnectorCreated, json({ name })),
    revokeConnector: (id: string) => request(`/api/v1/admin/connectors/${enc(id)}`, anything, { method: "DELETE" }),
    audit: (filters: AuditFilters, before?: number) =>
      request(`/api/v1/admin/audit?${auditQuery(filters, { before, limit: 50 })}`, AuditPage),
    usage: (days = 30) => request(`/api/v1/admin/usage?days=${days}`, UsageReport),
  },

  /** Conversa com o assistente: lê o stream SSE e repassa cada evento. */
  async chat(body: ChatRequest, onEvent: (event: ChatEvent) => void, signal?: AbortSignal) {
    let res: Response;
    try {
      res = await fetch("/api/v1/chat", {
        method: "POST",
        credentials: "same-origin",
        headers: { "content-type": "application/json", accept: "text/event-stream" },
        body: JSON.stringify(body),
        signal,
      });
    } catch (err) {
      if (signal?.aborted) return;
      throw new RequestError(0, "NETWORK", err instanceof Error ? err.message : "Sem conexão");
    }
    if (!res.ok || !res.body) {
      if (res.status === 401) window.dispatchEvent(new Event(UNAUTHORIZED_EVENT));
      const err = ApiError.safeParse(await res.json().catch(() => undefined));
      throw new RequestError(
        res.status,
        err.success ? err.data.error.code : "HTTP",
        err.success ? err.data.error.message : `Erro HTTP ${res.status}`,
      );
    }
    const reader = res.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let sep = buffer.indexOf("\n\n");
      while (sep >= 0) {
        const chunk = buffer.slice(0, sep);
        buffer = buffer.slice(sep + 2);
        if (chunk.startsWith("data: ")) {
          const parsed = ChatEvent.safeParse(JSON.parse(chunk.slice(6)));
          if (parsed.success) onEvent(parsed.data);
        }
        sep = buffer.indexOf("\n\n");
      }
    }
  },
};
