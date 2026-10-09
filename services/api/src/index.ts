import { loadConfig } from "./config";
import { buildApi } from "./server";

let config: ReturnType<typeof loadConfig>;
try {
  config = loadConfig();
} catch (err) {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
}

const app = buildApi(config);
app
  .listen({ host: config.HOST, port: config.PORT })
  .then(() =>
    app.log.info(
      `Raio-X API (${config.DEPLOYMENT_MODE}, transporte ${config.SAP_TRANSPORT}) em http://localhost:${config.PORT}`,
    ),
  )
  .catch((err) => {
    app.log.error(err);
    process.exit(1);
  });

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    app.close().then(() => process.exit(0));
  });
}
