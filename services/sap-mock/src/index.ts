import { SapRelease } from "@raiox/contracts";
import { buildServer, ICF_BASE_PATH } from "./server";

const port = Number(process.env.PORT ?? 8000);
const host = process.env.HOST ?? "0.0.0.0";
const release = SapRelease.parse(process.env.SAP_MOCK_RELEASE ?? "ECC");

const app = buildServer({ release, logger: true });
app
  .listen({ port, host })
  .then(() =>
    app.log.info(
      `sap-mock (${release}) em http://localhost:${port}${ICF_BASE_PATH} · usuários DEMO/demo e VENDAS/vendas`,
    ),
  )
  .catch((err) => {
    app.log.error(err);
    process.exit(1);
  });
