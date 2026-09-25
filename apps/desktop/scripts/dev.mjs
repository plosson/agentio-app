import { spawn } from "node:child_process";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const desktopRoot = path.resolve(__dirname, "..");
const require = createRequire(import.meta.url);

const RENDERER_PORT = process.env.RENDERER_PORT || "5174";
const rendererUrl = `http://localhost:${RENDERER_PORT}`;

function run(command, args, opts = {}) {
  return spawn(command, args, {
    stdio: "inherit",
    shell: process.platform === "win32",
    env: { ...process.env, RENDERER_PORT, FORCE_COLOR: "1" },
    ...opts,
  });
}

async function waitOnUrl(url, timeoutMs = 60_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(url, { method: "GET" });
      if (res.ok || res.status === 404) return;
    } catch {
      // keep waiting
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error(`Timed out waiting for ${url}`);
}

const children = [];

function shutdown(code = 0) {
  for (const child of children) {
    if (!child.killed) child.kill("SIGTERM");
  }
  process.exit(code);
}

process.on("SIGINT", () => shutdown(0));
process.on("SIGTERM", () => shutdown(0));

console.log(`[desktop] starting Vite renderer on ${rendererUrl}…`);
const vite = run("pnpm", ["exec", "vite", "--config", "vite.config.ts"], {
  cwd: desktopRoot,
});
children.push(vite);

try {
  await waitOnUrl(rendererUrl);
} catch (err) {
  console.error(err);
  shutdown(1);
}

console.log("[desktop] Vite ready — launching Electron…");

let electronBin;
try {
  electronBin = require("electron");
} catch {
  electronBin = path.join(desktopRoot, "node_modules", ".bin", "electron");
}

const electron = run(electronBin, ["."], { cwd: desktopRoot });
children.push(electron);

electron.on("exit", (code) => shutdown(code ?? 0));
vite.on("exit", (code) => {
  if (code && code !== 0) shutdown(code);
});
