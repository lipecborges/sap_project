#!/usr/bin/env node
// Ferramenta do fornecedor para gerar o par de chaves, assinar e inspecionar licenças do Raio-X (D34).
// Formato: RXL1.<base64url(payload JSON)>.<base64url(assinatura Ed25519 sobre os bytes do payload)>
import { createPrivateKey, createPublicKey, generateKeyPairSync, sign, verify } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseArgs } from "node:util";

const USAGE = `Uso:
  node license.mjs keygen --out <pasta>
  node license.mjs sign --key <private.pem> --customer <nome> --max-users <n> --expires <AAAA-MM-DD>
                        [--edition standard|enterprise] [--deployment cloud|selfhosted|any]
                        [--tenant <id>] [--feature <nome> ...] [--license-id <id>] [--issued <AAAA-MM-DD>]
  node license.mjs inspect <licença ou arquivo> [--pub <public.pem>]
`;

function fail(message) {
  console.error(`Erro: ${message}\n\n${USAGE}`);
  process.exit(1);
}

const [command, ...rest] = process.argv.slice(2);

function keygen(args) {
  const { values } = parseArgs({ args, options: { out: { type: "string" } } });
  if (!values.out) fail("informe --out <pasta>");
  const dir = resolve(values.out);
  mkdirSync(dir, { recursive: true });
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const privatePath = resolve(dir, "raiox-license-private.pem");
  const publicPath = resolve(dir, "raiox-license-public.pem");
  writeFileSync(privatePath, privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600, flag: "wx" });
  writeFileSync(publicPath, publicKey.export({ type: "spki", format: "pem" }), { flag: "wx" });
  console.log(`Chave privada (GUARDE EM COFRE, nunca no repositório): ${privatePath}`);
  console.log(`Chave pública (cole em VENDOR_PUBLIC_KEY, services/api/src/license/format.ts): ${publicPath}`);
}

function signCommand(args) {
  const { values } = parseArgs({
    args,
    options: {
      key: { type: "string" },
      customer: { type: "string" },
      "max-users": { type: "string" },
      expires: { type: "string" },
      edition: { type: "string", default: "standard" },
      deployment: { type: "string", default: "any" },
      tenant: { type: "string" },
      feature: { type: "string", multiple: true, default: [] },
      "license-id": { type: "string" },
      issued: { type: "string" },
    },
  });
  for (const required of ["key", "customer", "max-users", "expires"]) {
    if (!values[required]) fail(`informe --${required}`);
  }
  const maxNamedUsers = Number(values["max-users"]);
  if (!Number.isInteger(maxNamedUsers) || maxNamedUsers < 1) fail("--max-users deve ser um inteiro positivo");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(values.expires) || Number.isNaN(Date.parse(values.expires))) {
    fail("--expires deve ser uma data AAAA-MM-DD");
  }
  if (!["standard", "enterprise"].includes(values.edition)) fail("--edition: standard ou enterprise");
  if (!["cloud", "selfhosted", "any"].includes(values.deployment)) fail("--deployment: cloud, selfhosted ou any");
  const today = new Date().toISOString().slice(0, 10);
  const payload = {
    v: 1,
    licenseId:
      values["license-id"] ??
      `LIC-${today.replaceAll("-", "")}-${Math.random().toString(36).slice(2, 6).toUpperCase()}`,
    customer: values.customer,
    ...(values.tenant ? { tenantId: values.tenant } : {}),
    edition: values.edition,
    maxNamedUsers,
    issuedAt: values.issued ?? today,
    expiresAt: values.expires,
    deployment: values.deployment,
    features: values.feature,
  };
  const bytes = Buffer.from(JSON.stringify(payload), "utf8");
  const signature = sign(null, bytes, createPrivateKey(readFileSync(resolve(values.key))));
  console.log(`RXL1.${bytes.toString("base64url")}.${signature.toString("base64url")}`);
}

function inspect(args) {
  const { values, positionals } = parseArgs({ args, options: { pub: { type: "string" } }, allowPositionals: true });
  const input = positionals[0];
  if (!input) fail("informe a licença (texto ou arquivo)");
  const text = (input.startsWith("RXL1.") ? input : readFileSync(resolve(input), "utf8")).replace(/\s+/g, "");
  const parts = text.split(".");
  if (parts.length !== 3 || parts[0] !== "RXL1") fail("formato inválido (esperado RXL1.<dados>.<assinatura>)");
  const bytes = Buffer.from(parts[1], "base64url");
  console.log(JSON.stringify(JSON.parse(bytes.toString("utf8")), null, 2));
  if (values.pub) {
    const ok = verify(
      null,
      bytes,
      createPublicKey(readFileSync(resolve(values.pub))),
      Buffer.from(parts[2], "base64url"),
    );
    console.log(ok ? "Assinatura: VÁLIDA" : "Assinatura: INVÁLIDA");
    process.exit(ok ? 0 : 2);
  }
  console.log("Assinatura: não verificada (use --pub <public.pem>)");
}

switch (command) {
  case "keygen":
    keygen(rest);
    break;
  case "sign":
    signCommand(rest);
    break;
  case "inspect":
    inspect(rest);
    break;
  default:
    fail(command ? `comando desconhecido: ${command}` : "informe um comando");
}
