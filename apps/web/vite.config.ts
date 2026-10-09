import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    // Em desenvolvimento a API roda separada; em produção ela serve este build (WEB_DIST_DIR).
    proxy: {
      "/api": "http://localhost:3000",
      // WebSocket do conector on-premise (D35), para testar o conector contra o pnpm dev.
      "/connector": { target: "http://localhost:3000", ws: true },
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./test/setup.ts"],
  },
});
