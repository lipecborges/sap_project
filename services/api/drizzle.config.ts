import { defineConfig } from "drizzle-kit";

/** Gera as migrações SQL a partir de src/db/schema.ts: `pnpm db:generate`. */
export default defineConfig({
  dialect: "postgresql",
  schema: "./src/db/schema.ts",
  out: "./drizzle",
});
