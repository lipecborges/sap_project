import { ConnectorClient } from "./client";
import { loadConfig } from "./config";
import { createLogger } from "./logger";

let config: ReturnType<typeof loadConfig>;
try {
  config = loadConfig();
} catch (err) {
  console.error(JSON.stringify({ level: "error", msg: err instanceof Error ? err.message : String(err) }));
  process.exit(1);
}

const log = createLogger(config.logLevel);
const client = new ConnectorClient(config, { logger: log });

client.onFatal(() => process.exit(1));
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.once(signal, () => {
    log.info({ signal }, "sinal recebido: encerrando");
    client.stop().finally(() => process.exit(0));
  });
}

log.info({ sapHost: new URL(config.sapBaseUrl).host, apiPath: config.sapApiPath }, "conector Raio-X iniciando");
client.start();
