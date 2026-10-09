import { afterAll } from "vitest";
import { type Database, openDatabase } from "../src/db/client";

let shared: Promise<Database> | undefined;

/**
 * Um PGlite em memória por arquivo de teste (subir o WASM e migrar leva ~1 s).
 * As apps do arquivo compartilham o banco; cada teste usa dados próprios (usuários e conversas distintos).
 */
export function testDatabase(): Promise<Database> {
  if (!shared) {
    shared = openDatabase("pglite:memory");
    afterAll(async () => (await shared)?.close());
  }
  return shared;
}
