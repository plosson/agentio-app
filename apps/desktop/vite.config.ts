import { defineConfig } from "vite";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.dirname(fileURLToPath(import.meta.url));

export default defineConfig({
  root: path.join(rootDir, "src/renderer"),
  base: "./",
  build: {
    outDir: path.join(rootDir, "dist/renderer"),
    emptyOutDir: true,
  },
  server: {
    port: Number(process.env.RENDERER_PORT || 5174),
    strictPort: true,
  },
});
