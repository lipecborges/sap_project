import { SQLiteDatabaseClient } from "@abaplint/database-sqlite";

/** Banco SQLite em memória com o mínimo de dados de sistema usados pelo add-on. */
export async function setup(abap, schemas, insert) {
  abap.context.databaseConnections.DEFAULT = new SQLiteDatabaseClient();
  await abap.context.databaseConnections.DEFAULT.connect();
  await abap.context.databaseConnections.DEFAULT.execute(schemas.sqlite);
  await abap.context.databaseConnections.DEFAULT.execute(insert);
  await abap.context.databaseConnections.DEFAULT.execute(
    "INSERT INTO cvers (component, release, extrelease, comp_type) VALUES ('SAP_BASIS', '700', '0030', 'S'), ('SAP_APPL', '600', '0020', 'S');",
  );
}
