import { createApp } from "./app";
import { loadConfig } from "./config";

let config: ReturnType<typeof loadConfig>;
try {
  config = loadConfig();
} catch (err) {
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
}

const app = await createApp(config).catch((err) => {
  console.error("Falha ao iniciar a API:", err instanceof Error ? err.message : err);
  process.exit(1);
});

await app.listen({ host: config.HOST, port: config.PORT }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});
app.log.info(
  `Raio-X API (${config.DEPLOYMENT_MODE}, transporte ${config.SAP_TRANSPORT}) em http://localhost:${config.PORT}`,
);

let closing = false;
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    if (closing) return;
    closing = true;
    // Termina as requisições em andamento e fecha o banco; força a saída se travar.
    setTimeout(() => process.exit(1), 10_000).unref();
    app.close().then(() => process.exit(0));
  });
}
