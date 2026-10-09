import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Testes que abrem um banco próprio (PGlite) levam alguns segundos na primeira carga do WASM.
    testTimeout: 20_000,
    hookTimeout: 30_000,
  },
});
