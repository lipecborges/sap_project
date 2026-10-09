import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  platform: "node",
  target: "node22",
  clean: true,
  // Os pacotes do workspace são TypeScript puro: entram no bundle; o resto vem de node_modules.
  noExternal: [/^@raiox\//],
});
