import { randomBytes } from "node:crypto";
import postgres from "postgres";
import { type Database, openDatabase } from "../src/db/client";

let shared: Promise<Database> | undefined;

/**
 * Um banco por arquivo de teste. As apps do arquivo compartilham o banco; cada teste usa dados próprios
 * (usuários e conversas distintos).
 *
 * - Padrão: PGlite em memória (subir o WASM e migrar leva ~1 s).
 * - Com TEST_DATABASE_URL=postgres://… (CI): PostgreSQL de verdade, num banco novo com nome aleatório criado
 *   pela conexão administrativa e removido ao final. O usuário precisa da permissão CREATEDB.
 */
export function testDatabase(): Promise<Database> {
  if (!shared) {
    const url = process.env.TEST_DATABASE_URL;
    shared = url ? openPostgresDatabase(url) : openDatabase("pglite:memory");
  }
  return shared;
}

/** Fecha (e, no PostgreSQL, apaga) o banco do arquivo de teste. Chamado por test/setup.ts depois de cada arquivo. */
export async function closeTestDatabase(): Promise<void> {
  const database = await shared;
  shared = undefined;
  await database?.close();
}

async function openPostgresDatabase(adminUrl: string): Promise<Database> {
  const name = `raiox_test_${randomBytes(6).toString("hex")}`;
  const admin = postgres(adminUrl, { max: 1, onnotice: () => {} });
  await admin.unsafe(`create database ${name}`);
  const url = new URL(adminUrl);
  url.pathname = `/${name}`;
  const database = await openDatabase(url.toString());
  return {
    ...database,
    close: async () => {
      await database.close();
      // force: derruba conexões que sobraram (apps de teste que não fecharam o banco).
      await admin.unsafe(`drop database if exists ${name} with (force)`);
      await admin.end({ timeout: 5 });
    },
  };
}
