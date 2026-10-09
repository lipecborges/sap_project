import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    // Em desenvolvimento a API roda separada; em produção ela serve este build (WEB_DIST_DIR).
    proxy: { "/api": "http://localhost:3000" },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./test/setup.ts"],
  },
});
