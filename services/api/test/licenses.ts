import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { signLicense } from "../src/license/format";

export interface TestVendor {
  publicPem: string;
  privateKey: KeyObject;
  sign(overrides?: Record<string, unknown>): string;
}

/** Fornecedor de mentira: par de chaves gerado no teste (a chave real nunca está no repositório). */
export function testVendor(): TestVendor {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const publicPem = publicKey.export({ type: "spki", format: "pem" }).toString();
  return {
    publicPem,
    privateKey,
    sign: (overrides = {}) => signLicense(payload(overrides) as never, privateKey),
  };
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** Data ISO (yyyy-mm-dd) daqui a `days` dias (negativo = no passado). */
export const inDays = (days: number) => new Date(Date.now() + days * DAY_MS).toISOString().slice(0, 10);

export function payload(overrides: Record<string, unknown> = {}) {
  return {
    v: 1,
    licenseId: "LIC-TESTE-1",
    customer: "Cliente Teste",
    edition: "standard",
    maxNamedUsers: 10,
    issuedAt: inDays(-30),
    expiresAt: inDays(365),
    deployment: "any",
    features: ["chat"],
    ...overrides,
  };
}
