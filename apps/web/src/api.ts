import {
  ApiError,
  type DiagnosticMeta,
  DiagnosticResult,
  DiagnosticsResponse,
  HealthResponse,
  MeResponse,
} from "@raiox/contracts";
import type { z } from "zod";

export interface Credentials {
  user: string;
  password: string;
}

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

function basicAuth({ user, password }: Credentials): string {
  const bytes = new TextEncoder().encode(`${user}:${password}`);
  return `Basic ${btoa(String.fromCharCode(...bytes))}`;
}

async function request<T extends z.ZodType>(
  path: string,
  schema: T,
  init: RequestInit,
  creds?: Credentials,
): Promise<z.infer<T>> {
  const headers = new Headers(init.headers);
  headers.set("accept", "application/json");
  // Fase 0: credenciais SAP enviadas a cada chamada e mantidas só em memória. Fase 2 troca por sessão.
  if (creds) headers.set("authorization", basicAuth(creds));
  let res: Response;
  try {
    res = await fetch(path, { ...init, headers });
  } catch {
    throw new RequestError(0, "NETWORK", "Não foi possível falar com o servidor Raio-X");
  }
  const body: unknown = await res.json().catch(() => undefined);
  if (!res.ok) {
    const err = ApiError.safeParse(body);
    if (err.success)
      throw new RequestError(res.status, err.data.error.code, err.data.error.message, err.data.error.params);
    throw new RequestError(res.status, "HTTP", `Erro HTTP ${res.status}`);
  }
  return schema.parse(body);
}

const json = (body: unknown): RequestInit => ({
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});

export const api = {
  login: (creds: Credentials) => request("/api/v1/auth/check", MeResponse, json(creds)),
  sapHealth: (creds: Credentials) => request("/api/v1/sap/health", HealthResponse, {}, creds),
  diagnostics: async (creds: Credentials): Promise<DiagnosticMeta[]> =>
    (await request("/api/v1/diagnostics", DiagnosticsResponse, {}, creds)).diagnostics,
  run: (creds: Credentials, id: string, params: Record<string, string>) =>
    request(`/api/v1/diagnostics/${encodeURIComponent(id)}`, DiagnosticResult, json({ params }), creds),
};
