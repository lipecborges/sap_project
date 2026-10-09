import {
  ApiError,
  DiagnosticResult,
  DiagnosticsResponse,
  type ErrorCode,
  HealthResponse,
  MeResponse,
} from "@raiox/contracts";
import type { z } from "zod";
import { AppError } from "../errors";
import type { SapCredentials, SapRequest, SapTransport } from "./transport";

const STATUS_TO_CODE: Record<number, ErrorCode> = {
  400: "INVALID_PARAMS",
  401: "UNAUTHENTICATED",
  403: "NOT_AUTHORIZED",
  404: "UNKNOWN_DIAGNOSTIC",
};

/** Cliente tipado da API do add-on: toda resposta é validada contra o contrato. */
export class SapClient {
  constructor(private readonly transport: SapTransport) {}

  health(credentials: SapCredentials) {
    return this.call({ method: "GET", path: "/health", credentials }, HealthResponse);
  }

  me(credentials: SapCredentials) {
    return this.call({ method: "GET", path: "/me", credentials }, MeResponse);
  }

  diagnostics(credentials: SapCredentials) {
    return this.call({ method: "GET", path: "/diagnostics", credentials }, DiagnosticsResponse);
  }

  run(credentials: SapCredentials, id: string, params: Record<string, string>) {
    return this.call(
      { method: "POST", path: `/diagnostics/${encodeURIComponent(id)}`, params, credentials },
      DiagnosticResult,
    );
  }

  private async call<T extends z.ZodType>(request: SapRequest, schema: T): Promise<z.infer<T>> {
    const response = await this.transport.send(request);
    if (response.status === 200) {
      const parsed = schema.safeParse(response.body);
      if (!parsed.success) {
        throw new AppError(
          502,
          "SAP_BAD_RESPONSE",
          `Resposta do SAP fora do contrato: ${parsed.error.issues[0]?.message ?? "inválida"}`,
        );
      }
      return parsed.data;
    }
    const sapError = ApiError.safeParse(response.body);
    const code = sapError.success ? sapError.data.error.code : (STATUS_TO_CODE[response.status] ?? "SAP_BAD_RESPONSE");
    const message = sapError.success ? sapError.data.error.message : `O SAP respondeu HTTP ${response.status}`;
    const status = response.status >= 400 && response.status < 500 ? response.status : 502;
    throw new AppError(status, code, message, sapError.success ? sapError.data.error.params : undefined);
  }
}
