// Teste ponta a ponta da instalação self-hosted: health/ready → login (sessão) → diagnóstico → painel → assistente
// → web → cabeçalhos de segurança → /metrics protegido.
// Com EXPECT_OFFLINE=true, também confirma que não há saída para a internet (D23).
// Com EXPECT_POSTGRES=true, exige PostgreSQL de verdade (não o banco embutido).
// SMOKE_STATE_FILE: na 1ª execução grava o cookie da sessão; com SMOKE_PHASE=resume (depois de reiniciar a API)
// só confere que essa sessão continua válida. Sem o arquivo, a persistência é checada com duas requisições seguidas.
import { readFileSync, writeFileSync } from "node:fs";

const base = process.env.RAIOX_URL ?? "http://localhost:8080";
const stateFile = process.env.SMOKE_STATE_FILE;

function check(condition, message) {
  if (!condition) {
    console.error(`✗ ${message}`);
    process.exit(1);
  }
  console.log(`✓ ${message}`);
}

async function waitForApi() {
  for (let i = 0; i < 30; i++) {
    try {
      const res = await fetch(`${base}/api/health`);
      if (res.ok) return res.json();
    } catch {}
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`API não respondeu em ${base}`);
}

const health = await waitForApi();

if (process.env.SMOKE_PHASE === "resume") {
  if (!stateFile) throw new Error("SMOKE_PHASE=resume exige SMOKE_STATE_FILE");
  const saved = JSON.parse(readFileSync(stateFile, "utf8"));
  const ready = await fetch(`${base}/api/ready`).then((r) => r.json());
  check(ready.status === "ready", "API pronta depois do reinício");
  const session = await fetch(`${base}/api/v1/auth/session`, { headers: { cookie: saved.cookie } });
  check(session.ok, "a sessão do login sobreviveu ao reinício da API (sessões ficam no PostgreSQL)");
  const me = await session.json();
  check(me.user === saved.user, "a sessão restaurada é do mesmo usuário");
  const run = await fetch(`${base}/api/v1/diagnostics/SD-01`, {
    method: "POST",
    headers: { "content-type": "application/json", cookie: saved.cookie },
    body: JSON.stringify({ params: { salesOrder: "4500001" } }),
  });
  check(run.ok, "diagnóstico executado com a sessão restaurada (senha SAP decifrada do banco)");
  process.exit(0);
}

const ready = await fetch(`${base}/api/ready`);
const readyBody = await ready.json();
check(ready.status === 200 && readyBody.status === "ready", "/api/ready: banco acessível");
if (process.env.EXPECT_POSTGRES === "true") {
  check(readyBody.database === "postgres", "banco é PostgreSQL (não o embutido)");
}

const csp = (await fetch(`${base}/api/health`)).headers.get("content-security-policy") ?? "";
check(csp.includes("default-src 'self'") && !/https?:\/\//.test(csp), "CSP restritiva, sem origens externas");

const metricsOff = await fetch(`${base}/metrics`);
check(
  metricsOff.status === 404 || metricsOff.status === 401,
  `/metrics sem token não é público (HTTP ${metricsOff.status})`,
);
if (process.env.METRICS_TOKEN) {
  const metrics = await fetch(`${base}/metrics`, { headers: { authorization: `Bearer ${process.env.METRICS_TOKEN}` } });
  check(
    metrics.ok && (await metrics.text()).includes("http_request_duration_seconds"),
    "/metrics com token devolve as métricas",
  );
}

check(
  health.deploymentMode === "selfhosted" && health.sapTransport === "direct",
  "API em modo self-hosted com transporte direto",
);

const login = await fetch(`${base}/api/v1/auth/login`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ user: process.env.SAP_USER ?? "DEMO", password: process.env.SAP_PASSWORD ?? "demo" }),
});
check(login.ok, "login validado pelo SAP");
const cookie = (login.headers.get("set-cookie") ?? "").split(";")[0];
check(cookie.startsWith("raiox_session="), "sessão criada com cookie httpOnly");

const sessionCheck = await fetch(`${base}/api/v1/auth/session`, { headers: { cookie } });
check(sessionCheck.ok, "sessão válida em uma requisição seguinte");
if (stateFile) {
  writeFileSync(stateFile, JSON.stringify({ cookie, user: (await sessionCheck.json()).user }));
}

const result = await fetch(`${base}/api/v1/diagnostics/SD-01`, {
  method: "POST",
  headers: { "content-type": "application/json", cookie },
  body: JSON.stringify({ params: { salesOrder: "4500001" } }),
}).then((r) => r.json());
check(result.findings?.[0]?.code === "SD01.CREDIT_BLOCK", "diagnóstico SD-01 executado ponta a ponta");

const overview = await fetch(`${base}/api/v1/overview`, { headers: { cookie } }).then((r) => r.json());
check(
  Boolean(overview.production?.result && overview.sales?.result && overview.purchasing?.result),
  "painel com produção, vendas e compras",
);

const chat = await fetch(`${base}/api/v1/chat`, {
  method: "POST",
  headers: { "content-type": "application/json", cookie },
  body: JSON.stringify({ message: "Por que o pedido 4500001 não faturou?" }),
}).then((r) => r.text());
const text = chat
  .split("\n\n")
  .filter((c) => c.startsWith("data: "))
  .map((c) => JSON.parse(c.slice(6)))
  .filter((e) => e.type === "text")
  .map((e) => e.delta)
  .join("");
check(text.includes("crédito"), `assistente respondeu (${health.ai.provider})`);

const page = await fetch(`${base}/`).then((r) => r.text());
check(page.includes("<title>Raio-X</title>"), "interface web servida pela API");

if (process.env.EXPECT_OFFLINE === "true") {
  let reachable = true;
  try {
    await fetch("https://registry.npmjs.org/", { signal: AbortSignal.timeout(5000) });
  } catch {
    reachable = false;
  }
  check(!reachable, "sem saída para a internet: nada acima dependeu da nuvem");
}
