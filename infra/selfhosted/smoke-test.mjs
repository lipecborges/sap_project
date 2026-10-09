// Teste ponta a ponta da instalação self-hosted: health → login SAP → diagnóstico → interface web.
// Com EXPECT_OFFLINE=true, também confirma que não há saída para a internet (D23).
const base = process.env.RAIOX_URL ?? "http://localhost:8080";
const auth = `Basic ${Buffer.from(`${process.env.SAP_USER ?? "DEMO"}:${process.env.SAP_PASSWORD ?? "demo"}`).toString("base64")}`;

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

const me = await fetch(`${base}/api/v1/auth/check`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ user: process.env.SAP_USER ?? "DEMO", password: process.env.SAP_PASSWORD ?? "demo" }),
});
check(me.ok, "login validado pelo SAP");

const result = await fetch(`${base}/api/v1/diagnostics/SD-01`, {
  method: "POST",
  headers: { "content-type": "application/json", authorization: auth },
  body: JSON.stringify({ params: { salesOrder: "4500001" } }),
}).then((r) => r.json());
check(result.findings?.[0]?.code === "SD01.CREDIT_BLOCK", "diagnóstico SD-01 executado ponta a ponta");

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
