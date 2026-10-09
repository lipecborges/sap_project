import { createPublicKey, type KeyObject, sign, verify } from "node:crypto";
import { z } from "zod";

/**
 * Chave pública do fornecedor (Ed25519, SPKI). O par é gerado pelo dono do produto com `tools/license` (keygen);
 * a chave privada nunca entra no repositório. ATENÇÃO: esta constante deve ser substituída pela chave real
 * antes de emitir licenças a clientes.
 */
export const VENDOR_PUBLIC_KEY = `-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEA2zvn/vHUbfMZQT8i4FZh/xwrCum17M4tB2OLrd8E3Q0=
-----END PUBLIC KEY-----`;

export const LICENSE_PREFIX = "RXL1";

const DateText = z.union([z.iso.date(), z.iso.datetime({ offset: true })]);

/** Conteúdo assinado da licença (D34). */
export const LicensePayload = z.object({
  v: z.literal(1),
  licenseId: z.string().min(1).max(80),
  customer: z.string().min(1).max(200),
  /** Se informado, a licença só vale para este cliente (tenant). */
  tenantId: z.string().min(1).max(60).optional(),
  edition: z.enum(["standard", "enterprise"]),
  maxNamedUsers: z.number().int().positive().max(1_000_000),
  issuedAt: DateText,
  expiresAt: DateText,
  deployment: z.enum(["cloud", "selfhosted", "any"]),
  features: z.array(z.string().max(60)).max(100),
});
export type LicensePayload = z.infer<typeof LicensePayload>;

export interface ParsedLicense {
  payload: LicensePayload;
  payloadBytes: Buffer;
  signature: Buffer;
}

/** Erro de formato; a mensagem é mostrada ao administrador. */
export class LicenseFormatError extends Error {}

/** Aceita PEM ou SPKI DER em base64 (LICENSE_PUBLIC_KEY). */
export function parsePublicKey(value: string): KeyObject {
  const text = value.trim();
  try {
    if (text.includes("BEGIN")) return createPublicKey(text);
    return createPublicKey({ key: Buffer.from(text, "base64"), format: "der", type: "spki" });
  } catch {
    throw new Error("Chave pública de licença inválida (use PEM ou SPKI em base64)");
  }
}

/** Decodifica o texto `RXL1.<payload>.<assinatura>` sem verificar a assinatura. */
export function parseLicense(text: string): ParsedLicense {
  const parts = text.replace(/\s+/g, "").split(".");
  if (parts.length !== 3 || parts[0] !== LICENSE_PREFIX) {
    throw new LicenseFormatError("Formato de licença inválido (esperado RXL1.<dados>.<assinatura>)");
  }
  const payloadBytes = Buffer.from(parts[1]!, "base64url");
  const signature = Buffer.from(parts[2]!, "base64url");
  let json: unknown;
  try {
    json = JSON.parse(payloadBytes.toString("utf8"));
  } catch {
    throw new LicenseFormatError("Conteúdo da licença ilegível");
  }
  const parsed = LicensePayload.safeParse(json);
  if (!parsed.success) {
    throw new LicenseFormatError(`Conteúdo da licença inválido: ${parsed.error.issues[0]?.message ?? "formato"}`);
  }
  return { payload: parsed.data, payloadBytes, signature };
}

export function verifySignature(license: ParsedLicense, publicKey: KeyObject): boolean {
  try {
    return verify(null, license.payloadBytes, publicKey, license.signature);
  } catch {
    return false;
  }
}

/** Assina um payload (usado nos testes; a emissão real é feita por tools/license). */
export function signLicense(payload: LicensePayload, privateKey: KeyObject | string): string {
  const bytes = Buffer.from(JSON.stringify(payload), "utf8");
  const signature = sign(null, bytes, privateKey);
  return `${LICENSE_PREFIX}.${bytes.toString("base64url")}.${signature.toString("base64url")}`;
}

/** Fim da validade: data sem hora vale até o fim do dia (UTC). */
export function expiryInstant(expiresAt: string): Date {
  return new Date(/^\d{4}-\d{2}-\d{2}$/.test(expiresAt) ? `${expiresAt}T23:59:59.999Z` : expiresAt);
}
