import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    // Fecha/apaga o banco de teste ao final de cada arquivo.
    setupFiles: ["./test/setup.ts"],
    // Testes que abrem um banco próprio (PGlite) levam alguns segundos na primeira carga do WASM.
    testTimeout: 20_000,
    hookTimeout: 30_000,
  },
});
