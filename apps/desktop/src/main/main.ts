import {
  app,
  BrowserWindow,
  ipcMain,
  shell,
  WebContentsView,
} from "electron";
import * as path from "node:path";
import * as fs from "node:fs";
import * as os from "node:os";
import type { CompanionConfig, LoginCode, OnboardingScreen } from "../shared/types";
import { DEFAULT_CONFIG, VAULT_BAR_HEIGHT } from "../shared/types";
import {
  initVault,
  login,
  startDaemon,
  vaultState,
  type DaemonHandle,
} from "./agentio/commands";
import { cliStatus, detectCli, installCli } from "./agentio/install";
import { cliLocation } from "./agentio/process";

const APP_NAME = "AgentIO Companion";
const isDev = !app.isPackaged;
const RENDERER_PORT = process.env.RENDERER_PORT || "5174";

let onboardingWin: BrowserWindow | null = null;
/** The hub's page, shown inside the app window below the app's bar. */
let vaultView: WebContentsView | null = null;
/** The local vault's daemon, when this app started it. */
let daemon: DaemonHandle | null = null;
/** Cancels the running `agentio login`, if any. */
let loginAbort: AbortController | null = null;
/** The code the running `agentio login` waits on, once it has printed it. */
let loginCode: LoginCode | null = null;

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

/** The app's own agentio (binary + separate HOME); the user's install is never used. */
function appCli() {
  return cliLocation(path.join(app.getPath("userData"), "cli"));
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

  win.on("resize", layoutVaultView);
  win.on("closed", () => {
    if (onboardingWin !== win) return;
    vaultView?.webContents.close();
    vaultView = null;
    onboardingWin = null;
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

const VAULT_MIN_WIDTH = 1100;
const VAULT_MIN_HEIGHT = 760;

/** The hub page fills the window below the app's bar. */
function layoutVaultView(): void {
  if (!onboardingWin || !vaultView) return;
  const { width, height } = onboardingWin.getContentBounds();
  vaultView.setBounds({
    x: 0,
    y: VAULT_BAR_HEIGHT,
    width,
    height: Math.max(0, height - VAULT_BAR_HEIGHT),
  });
}

/**
 * Show `url` (a hub page) inside the app window, below the app's bar. It is
 * a separate view with the narrow vault preload: the hub page never gets
 * the onboarding API. Links that open new windows go to the browser.
 */
function showVault(url: string): void {
  const win = onboardingWin;
  if (!win) return;
  if (!vaultView) {
    vaultView = new WebContentsView({
      webPreferences: {
        preload: vaultPreloadPath(),
        contextIsolation: true,
        nodeIntegration: false,
        sandbox: true,
      },
    });
    vaultView.webContents.setWindowOpenHandler(({ url: target }) => {
      if (/^https?:\/\//i.test(target)) void shell.openExternal(target);
      return { action: "deny" };
    });
    win.contentView.addChildView(vaultView);
    const [width, height] = win.getSize();
    if (width < VAULT_MIN_WIDTH || height < VAULT_MIN_HEIGHT) {
      win.setSize(Math.max(width, VAULT_MIN_WIDTH), Math.max(height, VAULT_MIN_HEIGHT));
      win.center();
    }
  }
  layoutVaultView();
  win.setTitle(`${APP_NAME} — ${new URL(url).host}`);
  console.log(`[vault] loadURL ${url}`);
  void vaultView.webContents.loadURL(url);
}

/** Remove the hub page; the app's own screens show again. */
function closeVault(): void {
  if (!vaultView) return;
  onboardingWin?.contentView.removeChildView(vaultView);
  vaultView.webContents.close();
  vaultView = null;
  onboardingWin?.setTitle(APP_NAME);
}

/** Start the local daemon (unless this app already runs it) and open its UI. */
async function openLocalVault(): Promise<void> {
  if (!daemon) {
    const started = await startDaemon(appCli());
    daemon = started;
    void started.exited.then(() => {
      if (daemon === started) daemon = null;
    });
  }
  config.vaultUrl = daemon.url;
  showVault(`${daemon.url}/ui`);
  sendNavigate("S6");
}

function registerIpc(): void {
  ipcMain.handle("onboarding:getConfig", () => ({ ...config }));

  ipcMain.handle(
    "onboarding:setVaultUrl",
    (_e, url: string, remember: boolean) => {
      const base = normalizeHubBase(url);
      config.vaultUrl = base;
      config.rememberUrl = Boolean(remember);
      sendNavigate("login");
    },
  );

  ipcMain.handle("onboarding:cliStatus", () => cliStatus(appCli()));

  // Install and update are the same: rerun the official installer into our dir.
  ipcMain.handle(
    "onboarding:startCliInstall",
    async (event) => {
      sendNavigate("S2");
      // Download percent fills 5–95%; the ends mark start and verification.
      let percent = 5;
      let label = "Starting…";
      const report = (p: { label?: string; percent?: number }) => {
        if (p.percent !== undefined) percent = 5 + Math.round(p.percent * 0.9);
        if (p.label) label = p.label;
        event.sender.send("onboarding:cliProgress", { percent, label });
      };
      report({});
      try {
        const cli = await installCli(appCli(), report);
        config.cliPath = cli.path;
        config.cliVersion = cli.version;
      } catch (err) {
        sendNavigate("S1");
        throw err;
      }
      event.sender.send("onboarding:cliProgress", {
        percent: 100,
        label: `agentio ${config.cliVersion} is ready`,
      });
      sendNavigate("S3");
    },
  );

  ipcMain.handle("onboarding:continueWithCli", async () => {
    const cli = await detectCli(appCli());
    if (!cli) {
      throw new Error("The app's AgentIO CLI is missing or does not run");
    }
    config.cliPath = cli.path;
    config.cliVersion = cli.version;
    sendNavigate("mode");
  });

  ipcMain.handle("onboarding:vaultState", () => vaultState(appCli()));

  // Remote vault: `agentio login`, approved by the hub owner in the vault window.
  ipcMain.handle("onboarding:startLogin", async (event) => {
    if (!config.vaultUrl) {
      throw new Error("Set a vault URL first");
    }
    const hub = config.vaultUrl;
    loginAbort?.abort();
    const abort = new AbortController();
    loginAbort = abort;
    loginCode = null;
    try {
      await login(appCli(), hub, {
        name: `AgentIO Companion on ${os.hostname()}`,
        signal: abort.signal,
        onCode: (code) => {
          loginCode = code;
          event.sender.send("onboarding:loginCode", code);
        },
      });
    } catch (err) {
      // Failed or cancelled: drop the approval page, if it is showing.
      if (loginAbort === abort) closeVault();
      throw err;
    } finally {
      if (loginAbort === abort) {
        loginAbort = null;
        loginCode = null;
      }
    }
    showVault(`${hub}/ui`);
    sendNavigate("S6");
  });

  // The hub owner approves the code on the hub's own page, shown in the app.
  ipcMain.handle("onboarding:openApproval", () => {
    if (!loginCode) {
      throw new Error("There is no sign-in code to approve");
    }
    showVault(loginCode.verifyUrl);
    sendNavigate("approving");
  });

  ipcMain.handle("onboarding:cancelLogin", () => loginAbort?.abort());

  // Already signed in (e.g. after a restart): open the hub the CLI reports.
  ipcMain.handle("onboarding:openRemoteVault", async () => {
    const state = await vaultState(appCli());
    if (state.mode !== "remote") {
      throw new Error("This app is not signed in to a vault hub");
    }
    config.vaultUrl = state.hub;
    showVault(`${state.hub}/ui`);
    sendNavigate("S6");
  });

  // Local vault: create it if needed, then run the daemon and open its UI.
  ipcMain.handle("onboarding:createLocalVault", async (_e, passphrase: string) => {
    if (typeof passphrase !== "string" || !passphrase) {
      throw new Error("Enter a passphrase");
    }
    await initVault(appCli(), passphrase);
    await openLocalVault();
  });

  ipcMain.handle("onboarding:openLocalVault", () => openLocalVault());

  // Back to the app's own screens (the local daemon, if any, keeps running).
  ipcMain.handle("onboarding:closeVault", () => closeVault());

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
      sendNavigate(config.cliVersion ? "mode" : "S1");
    }
  });
});

// Stop the local daemon before quitting, so it does not outlive the app.
let stoppingDaemon = false;
app.on("before-quit", (event) => {
  // A pending sign-in would otherwise keep polling the hub after we quit.
  loginAbort?.abort();
  if (!daemon || stoppingDaemon) return;
  event.preventDefault();
  stoppingDaemon = true;
  void daemon.stop().finally(() => app.quit());
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

// Ensure dist exists reference for packagers
if (isDev && !fs.existsSync(onboardingPreloadPath())) {
  console.warn("[main] preload.js missing — run build:main first");
}
