import { z } from "zod";

/** Versão atual do protocolo conector ↔ gateway (docs/conector-protocolo.md). */
export const PROTOCOL_VERSION = 1;

/** Caminho do WebSocket na API. */
export const CONNECTOR_WS_PATH = "/connector/v1/ws";

/** Tamanho máximo de um quadro (texto JSON), nos dois sentidos. */
export const MAX_FRAME_BYTES = 5 * 1024 * 1024;

/** Conector → gateway. */
export const HelloFrame = z.object({
  type: z.literal("hello"),
  v: z.literal(PROTOCOL_VERSION),
  version: z.string().max(40),
  sapBaseUrlHost: z.string().max(200).optional(),
});
export type HelloFrame = z.infer<typeof HelloFrame>;

export const ResponseFrame = z.object({
  type: z.literal("response"),
  id: z.string(),
  status: z.number().int().min(100).max(599),
  contentType: z.string().optional(),
  body: z.string(),
});
export type ResponseFrame = z.infer<typeof ResponseFrame>;

export const ErrorFrame = z.object({
  type: z.literal("error"),
  id: z.string(),
  code: z.string().max(60),
  message: z.string().max(500),
});
export type ErrorFrame = z.infer<typeof ErrorFrame>;

export const ConnectorFrame = z.discriminatedUnion("type", [HelloFrame, ResponseFrame, ErrorFrame]);
export type ConnectorFrame = z.infer<typeof ConnectorFrame>;

/** Gateway → conector. */
export interface WelcomeFrame {
  type: "welcome";
  v: typeof PROTOCOL_VERSION;
  connectorId: string;
}

export interface RequestFrame {
  type: "request";
  id: string;
  method: "GET" | "POST";
  path: string;
  headers: Record<string, string>;
  body?: string;
  timeoutMs: number;
}
