import { existsSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";
import { sql } from "drizzle-orm";
import type { PgDatabase, PgQueryResultHKT } from "drizzle-orm/pg-core";
import { drizzle as drizzlePglite } from "drizzle-orm/pglite";
import { migrate as migratePglite } from "drizzle-orm/pglite/migrator";
import { drizzle as drizzlePostgres } from "drizzle-orm/postgres-js";
import { migrate as migratePostgres } from "drizzle-orm/postgres-js/migrator";
import postgres from "postgres";
import * as schema from "./schema";

/** Banco usado pela API: o mesmo tipo para PostgreSQL de verdade e para o PGlite embutido. */
export type Db = PgDatabase<PgQueryResultHKT, typeof schema>;

export interface Database {
  db: Db;
  /** postgres: servidor PostgreSQL. pglite: PostgreSQL embutido (desenvolvimento e testes). */
  kind: "postgres" | "pglite";
  /** Testa a conexão (prontidão). */
  ping(): Promise<void>;
  close(): Promise<void>;
}

/** Trava de migração: várias réplicas da API sobem ao mesmo tempo sem migrar duas vezes. */
const MIGRATION_LOCK = 72_011_001;

/**
 * DATABASE_URL:
 *   postgres://usuario:senha@host:5432/raiox   PostgreSQL (produção, Cloud e Self-hosted)
 *   pglite:memory                               em memória (testes)
 *   pglite:./.data/pglite                       arquivo local (desenvolvimento, sem Docker)
 */
export async function openDatabase(url: string, options: { migrationsDir?: string } = {}): Promise<Database> {
  const migrationsFolder = options.migrationsDir ?? findMigrationsDir();

  if (url.startsWith("pglite:")) {
    const target = url.slice("pglite:".length);
    let client: PGlite;
    if (target === "memory" || target === "") {
      client = new PGlite();
    } else {
      mkdirSync(resolve(target), { recursive: true });
      client = new PGlite(resolve(target));
    }
    const db = drizzlePglite(client, { schema });
    await migratePglite(db, { migrationsFolder });
    return {
      db: db as unknown as Db,
      kind: "pglite",
      ping: async () => {
        await client.query("select 1");
      },
      close: () => client.close(),
    };
  }

  const client = postgres(url, { max: 10, idle_timeout: 30, connect_timeout: 10, onnotice: () => {} });
  const db = drizzlePostgres(client, { schema });
  await client.begin(async (tx) => {
    await tx`select pg_advisory_xact_lock(${MIGRATION_LOCK})`;
    await migratePostgres(drizzlePostgres(tx as unknown as postgres.Sql, { schema }), { migrationsFolder });
  });
  return {
    db: db as unknown as Db,
    kind: "postgres",
    ping: async () => {
      await db.execute(sql`select 1`);
    },
    close: () => client.end({ timeout: 5 }),
  };
}

/** Pasta das migrações SQL: ao lado do código-fonte (tsx) ou do bundle (dist/ e na imagem Docker). */
function findMigrationsDir(): string {
  const here = dirname(fileURLToPath(import.meta.url));
  for (const candidate of [resolve(here, "../drizzle"), resolve(here, "../../drizzle")]) {
    if (existsSync(resolve(candidate, "meta/_journal.json"))) return candidate;
  }
  throw new Error(`Pasta de migrações (drizzle/) não encontrada a partir de ${here}`);
}
