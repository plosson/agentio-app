import {
  app,
  BrowserWindow,
  ipcMain,
  shell,
} from "electron";
import * as path from "node:path";
import * as fs from "node:fs";
import type { CompanionConfig, OnboardingScreen } from "../shared/types";
import { DEFAULT_CONFIG } from "../shared/types";

const APP_NAME = "AgentIO Companion";
const isDev = !app.isPackaged;
const RENDERER_PORT = process.env.RENDERER_PORT || "5174";

let onboardingWin: BrowserWindow | null = null;
let vaultWin: BrowserWindow | null = null;

/** In-memory config for the skeleton (persist later). */
const config: CompanionConfig = { ...DEFAULT_CONFIG };

function onboardingPreloadPath(): string {
  return path.join(__dirname, "../preload/preload.js");
}

function vaultPreloadPath(): string {
  return path.join(__dirname, "../preload/vault-preload.js");
}

function resolveRendererIndex(): string {
  return path.join(__dirname, "../renderer/index.html");
}

function sendNavigate(screen: OnboardingScreen): void {
  onboardingWin?.webContents.send("onboarding:navigate", screen);
}

function createOnboardingWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 720,
    height: 560,
    title: APP_NAME,
    backgroundColor: "#0F172A",
    show: false,
    webPreferences: {
      preload: onboardingPreloadPath(),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  win.once("ready-to-show", () => win.show());

  if (isDev) {
    const url = `http://localhost:${RENDERER_PORT}`;
    void win.loadURL(url);
    if (process.env.AGENTIO_OPEN_DEVTOOLS === "1") {
      win.webContents.openDevTools({ mode: "detach" });
    }
  } else {
    void win.loadFile(resolveRendererIndex());
  }

  win.on("closed", () => {
    if (onboardingWin === win) onboardingWin = null;
  });

  return win;
}

function normalizeHubBase(raw: string): string {
  const trimmed = raw.trim().replace(/\/+$/, "");
  if (!trimmed) throw new Error("Vault URL is empty");
  let url: URL;
  try {
    url = new URL(trimmed);
  } catch {
    throw new Error("Invalid vault URL");
  }
  const isLocal =
    url.hostname === "localhost" || url.hostname === "127.0.0.1";
  if (url.protocol !== "https:" && !(isDev && isLocal && url.protocol === "http:")) {
    throw new Error("Vault URL must be HTTPS (http://localhost allowed in dev)");
  }
  return `${url.protocol}//${url.host}`;
}

function createVaultWindow(hubBase: string): BrowserWindow {
  const win = new BrowserWindow({
    width: 1100,
    height: 760,
    title: `${APP_NAME} — ${new URL(hubBase).host}`,
    backgroundColor: "#0F172A",
    show: false,
    webPreferences: {
      preload: vaultPreloadPath(),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });

  win.once("ready-to-show", () => win.show());

  const uiUrl = `${hubBase}/ui`;
  console.log(`[vault] loadURL ${uiUrl}`);
  void win.loadURL(uiUrl);

  win.on("closed", () => {
    if (vaultWin === win) vaultWin = null;
  });

  return win;
}

function registerIpc(): void {
  ipcMain.handle("onboarding:getConfig", () => ({ ...config }));

  ipcMain.handle(
    "onboarding:setVaultUrl",
    (_e, url: string, remember: boolean) => {
      const base = normalizeHubBase(url);
      config.vaultUrl = base;
      config.rememberUrl = Boolean(remember);
      sendNavigate("S5");
    },
  );

  ipcMain.handle("onboarding:startCliInstall", async (event) => {
    sendNavigate("S2");
    const steps = [
      { percent: 10, label: "Fetching latest release metadata… (stub)" },
      { percent: 35, label: "Downloading agentio (stub — no real download)…" },
      { percent: 70, label: "Verifying checksum… (stub)" },
      { percent: 90, label: "Installing to app support dir… (stub)" },
      { percent: 100, label: "CLI ready (stub v0.0.0-dev)" },
    ];
    for (const step of steps) {
      await new Promise((r) => setTimeout(r, 400));
      event.sender.send("onboarding:cliProgress", step);
    }
    config.cliVersion = "0.0.0-dev (stub)";
    sendNavigate("S3");
  });

  ipcMain.handle("onboarding:skipCliUsePath", () => {
    config.cliVersion = "PATH (stub — not verified)";
    sendNavigate("S3");
  });

  ipcMain.handle("onboarding:unlockStub", (_e, passphrase: string) => {
    if (!passphrase || passphrase.length < 1) {
      return { ok: false, error: "Enter a passphrase" };
    }
    // Skeleton: do not call the hub unlock API yet.
    console.log("[unlock] stub accepted (passphrase not sent to hub)");
    return { ok: true };
  });

  ipcMain.handle("onboarding:openVault", () => {
    if (!config.vaultUrl) {
      throw new Error("Set a vault URL first");
    }
    if (vaultWin && !vaultWin.isDestroyed()) {
      vaultWin.focus();
      return;
    }
    vaultWin = createVaultWindow(config.vaultUrl);
    // Keep onboarding around for Change URL; hide it while vault is open.
    onboardingWin?.hide();
    sendNavigate("S6");
  });

  ipcMain.handle("companion:addProfile", (_e, service: string) => {
    console.log(`[bridge stub] addProfile(${JSON.stringify(service)}) — PTY later`);
  });

  ipcMain.handle(
    "companion:reauth",
    (_e, service: string, name?: string) => {
      console.log(
        `[bridge stub] reauth(${JSON.stringify(service)}, ${JSON.stringify(name)}) — PTY later`,
      );
    },
  );

  ipcMain.handle("companion:openTerminal", () => {
    console.log("[bridge stub] openTerminal() — PTY later");
  });

  ipcMain.handle("shell:openExternal", (_e, url: string) => {
    if (typeof url === "string" && /^https?:\/\//i.test(url)) {
      return shell.openExternal(url);
    }
  });
}

app.whenReady().then(() => {
  registerIpc();
  onboardingWin = createOnboardingWindow();
  sendNavigate("S1");

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      onboardingWin = createOnboardingWindow();
      sendNavigate(config.cliVersion ? (config.vaultUrl ? "S5" : "S4") : "S1");
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

// Ensure dist exists reference for packagers
if (isDev && !fs.existsSync(onboardingPreloadPath())) {
  console.warn("[main] preload.js missing — run build:main first");
}
