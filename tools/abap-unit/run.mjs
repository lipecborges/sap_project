/**
 * Executa os testes ABAP Unit do add-on (abap/src) sem um sistema SAP:
 * o abaplint transpiler converte o ABAP para JavaScript e o open-abap fornece
 * as classes standard (CL_ABAP_UNIT_ASSERT, RTTI etc.).
 *
 * Não substitui o teste no SAP real (o runtime é outra implementação), mas pega
 * regressões de lógica a cada commit. Tabelas standard usadas ficam em stubs/.
 */
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "../..");
const cache = join(here, ".cache");
const openAbap = join(cache, "open-abap");
const output = join(cache, "output");
// Versão fixa do open-abap para resultados reproduzíveis.
const OPEN_ABAP_COMMIT = "422d1310e583eab372412e9230c6cdc400d38e2a";

function run(cmd, args, options = {}) {
  execFileSync(cmd, args, { stdio: "inherit", ...options });
}

mkdirSync(cache, { recursive: true });
if (!existsSync(join(openAbap, ".git"))) {
  run("git", ["clone", "--quiet", "--filter=blob:none", "https://github.com/open-abap/open-abap", openAbap]);
}
run("git", ["-C", openAbap, "checkout", "--quiet", OPEN_ABAP_COMMIT]);

rmSync(output, { recursive: true, force: true });
const config = join(cache, "abap_transpile.json");
writeFileSync(
  config,
  JSON.stringify(
    {
      input_folder: [join(repoRoot, "abap/src"), join(openAbap, "src"), join(here, "stubs")],
      input_filter: [],
      output_folder: output,
      write_unit_tests: true,
      options: {
        ignoreSyntaxCheck: false,
        addFilenames: true,
        addCommonJS: true,
        setup: { filename: join(here, "setup.mjs"), preFunction: "setup" },
      },
    },
    null,
    2,
  ),
);

run("npx", ["abap_transpile", config], { cwd: here, stdio: ["ignore", "ignore", "inherit"] });
run("node", [join(output, "_unit_open.mjs")], { stdio: ["ignore", "ignore", "inherit"] });

const parsed = JSON.parse(readFileSync(join(output, "output.json"), "utf8"));
const rows = (Array.isArray(parsed) ? parsed : parsed.list).filter((r) => r.class_name.startsWith("ZCL_RX"));
let failed = 0;
for (const r of rows) {
  const ok = r.status === "SUCCESS";
  if (!ok) failed++;
  console.log(
    `${ok ? "✓" : "✗"} ${r.class_name} ${r.testclass_name}->${r.method_name}${ok ? "" : `: ${r.message ?? ""} esperado=${r.expected ?? ""} obtido=${r.actual ?? ""}`}`,
  );
}
console.log(`\n${rows.length - failed}/${rows.length} testes ABAP Unit passaram`);
if (rows.length === 0 || failed > 0) process.exit(1);
