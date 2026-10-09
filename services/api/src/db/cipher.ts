import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from "node:crypto";

/**
 * Cifra dados sensíveis guardados no banco (ex.: a senha SAP da sessão, D32) com AES-256-GCM.
 * A chave vem de SESSION_SECRET e nunca é gravada no banco: um dump sozinho não revela nada.
 * Formato: v1.<iv>.<tag>.<texto cifrado>, em base64url.
 */
export class Cipher {
  private readonly key: Buffer;

  constructor(secret: string) {
    const material = decodeSecret(secret);
    if (material.length < 32) throw new Error("SESSION_SECRET precisa ter pelo menos 32 bytes (base64 ou hex)");
    this.key = Buffer.from(hkdfSync("sha256", material, Buffer.alloc(0), "raiox-session-v1", 32));
  }

  static random(): Cipher {
    return new Cipher(randomBytes(32).toString("base64"));
  }

  seal(value: unknown): string {
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", this.key, iv);
    const data = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
    return ["v1", iv, cipher.getAuthTag(), data]
      .map((p) => (typeof p === "string" ? p : p.toString("base64url")))
      .join(".");
  }

  /** Devolve undefined se o texto foi adulterado ou cifrado com outra chave. */
  open<T>(sealed: string): T | undefined {
    const [version, iv, tag, data] = sealed.split(".");
    if (version !== "v1" || !iv || !tag || data === undefined) return undefined;
    try {
      const decipher = createDecipheriv("aes-256-gcm", this.key, Buffer.from(iv, "base64url"));
      decipher.setAuthTag(Buffer.from(tag, "base64url"));
      const text = Buffer.concat([decipher.update(Buffer.from(data, "base64url")), decipher.final()]).toString("utf8");
      return JSON.parse(text) as T;
    } catch {
      return undefined;
    }
  }
}

function decodeSecret(secret: string): Buffer {
  const trimmed = secret.trim();
  if (/^[0-9a-f]+$/i.test(trimmed) && trimmed.length % 2 === 0) return Buffer.from(trimmed, "hex");
  return Buffer.from(trimmed, "base64");
}
