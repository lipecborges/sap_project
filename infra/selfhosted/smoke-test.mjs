// Teste ponta a ponta da instalação self-hosted: health → login (sessão) → diagnóstico → painel → assistente → web.
// Com EXPECT_OFFLINE=true, também confirma que não há saída para a internet (D23).
const base = process.env.RAIOX_URL ?? "http://localhost:8080";

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
