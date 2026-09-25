import "./styles.css";
import type {
  CliStatus,
  CompanionConfig,
  LoginCode,
  OnboardingScreen,
  VaultState,
} from "../shared/types";
import { VAULT_BAR_HEIGHT } from "../shared/types";

const app = document.querySelector<HTMLDivElement>("#app")!;

let screen: OnboardingScreen = "S1";
let config: CompanionConfig = {
  vaultUrl: "",
  rememberUrl: true,
  cliVersion: null,
  cliPath: null,
};
/** Null until the first check finishes. */
let cliState: CliStatus | null = null;
/** Null while the vault state is being read. */
let vault: VaultState | null = null;
let loginCode: LoginCode | null = null;
/** Shown instead of the actions while a long step runs. */
let busy = "";
let cliPercent = 0;
let cliLabel = "";
let error = "";

function chrome(): string {
  return `<div class="chrome">AgentIO Companion</div>`;
}

function renderS1(): string {
  return `
    ${chrome()}
    <h1>Welcome to AgentIO Companion</h1>
    <p>
      To add services to a remote vault, this app needs the AgentIO CLI.
      It installs its own copy, separate from any agentio you installed yourself.
    </p>
    <div class="status">${renderCliStatus()}</div>
    ${error ? `<div class="error">${escapeHtml(error)}</div>` : ""}
    <div class="actions">${renderCliActions()}</div>
  `;
}

function mono(s: string): string {
  return `<span class="mono">${escapeHtml(s)}</span>`;
}

function renderCliStatus(): string {
  if (!cliState) return "Status: checking the AgentIO CLI…";
  const { cli, required, upToDate } = cliState;
  if (!cli) return `Status: not installed yet`;
  const installed = `CLI ${mono(`v${cli.version}`)} installed`;
  if (upToDate) return `Status: ${installed} · up to date`;
  return `Status: ${installed} · this app needs ${mono(`v${required}`)}`;
}

function renderCliActions(): string {
  if (!cliState) return "";
  const { cli, required, upToDate } = cliState;
  const button = (action: string, label: string, cls = "") =>
    `<button type="button"${cls ? ` class="${cls}"` : ""} data-action="${action}">${escapeHtml(label)}</button>`;
  if (!cli) return button("install", `Install AgentIO v${required}`);
  if (upToDate) return button("continue-cli", "Continue");
  return button("update", `Install v${required}`);
}

function renderS2(): string {
  return `
    ${chrome()}
    <h1>Setting up AgentIO CLI</h1>
    <p class="mono">${escapeHtml(cliLabel || "Starting…")}</p>
    <div class="progress" aria-valuenow="${cliPercent}" aria-valuemin="0" aria-valuemax="100">
      <span style="width:${cliPercent}%"></span>
    </div>
    <p class="mono">${cliPercent}%</p>
    <div class="actions">
      <button type="button" class="secondary" data-action="noop" disabled>Cancel</button>
    </div>
  `;
}

function renderS3(): string {
  return `
    ${chrome()}
    <h1>AgentIO CLI is ready</h1>
    <div class="status">
      <div>Installed: <span class="mono">${escapeHtml(config.cliVersion ?? "unknown")}</span></div>
      <div>Location: <span class="mono">${escapeHtml(config.cliPath ?? "unknown")}</span></div>
    </div>
    <div class="actions">
      <button type="button" data-action="continue-url">Continue</button>
    </div>
  `;
}

function errorBox(): string {
  return error ? `<div class="error">${escapeHtml(error)}</div>` : "";
}

function actionsOrBusy(actions: string): string {
  return busy
    ? `<p class="mono">${escapeHtml(busy)}</p>`
    : `<div class="actions">${actions}</div>`;
}

function renderMode(): string {
  if (!vault) {
    return `${chrome()}<h1>Choose a vault</h1><p>Checking this app’s vault…</p>`;
  }
  if (vault.mode === "remote") {
    const scope = vault.canManageProfiles
      ? ""
      : `<p class="error">This key cannot add services from this computer. Ask the hub owner for a key that can manage profiles.</p>`;
    return `
      ${chrome()}
      <h1>Your vault</h1>
      <div class="status">Signed in to ${mono(vault.hub)}</div>
      ${scope}
      ${errorBox()}
      ${actionsOrBusy(`
        <button type="button" data-action="open-remote">Open vault</button>
        <button type="button" class="secondary" data-action="go-remote">Sign in to a different hub</button>
      `)}
    `;
  }
  if (vault.mode === "local") {
    return `
      ${chrome()}
      <h1>Your vault</h1>
      <div class="status">A local vault is set up on this computer.</div>
      ${errorBox()}
      ${actionsOrBusy(`
        <button type="button" data-action="open-local">Open local vault</button>
        <button type="button" class="secondary" data-action="go-remote">Connect to a remote vault instead</button>
      `)}
      <p class="mono">Signing in to a hub makes this app use the hub instead of the local vault.</p>
    `;
  }
  return `
    ${chrome()}
    <h1>Choose a vault</h1>
    <p>
      A local vault keeps your credentials on this computer.
      A remote vault is a hub that you or your team already runs.
    </p>
    ${errorBox()}
    ${actionsOrBusy(`
      <button type="button" data-action="go-local">Create a local vault</button>
      <button type="button" class="secondary" data-action="go-remote">Connect to a remote vault</button>
    `)}
  `;
}

function renderLocal(): string {
  return `
    ${chrome()}
    <h1>Create a local vault</h1>
    <p>
      Choose a passphrase of at least 8 characters. You need it each time
      you unlock the vault. It cannot be recovered if you lose it.
    </p>
    <label for="passphrase">Passphrase</label>
    <input id="passphrase" type="password" autocomplete="new-password" />
    <label for="passphrase-again">Passphrase again</label>
    <input id="passphrase-again" type="password" autocomplete="new-password" />
    ${errorBox()}
    ${actionsOrBusy(`
      <button type="button" data-action="create-local">Create vault</button>
      <button type="button" class="linkish" data-action="go-mode">Back</button>
    `)}
  `;
}

function renderLogin(): string {
  if (!loginCode) {
    return `
      ${chrome()}
      <h1>Sign in to your vault</h1>
      <p>Asking ${mono(config.vaultUrl)} for a sign-in code…</p>
      <div class="actions">
        <button type="button" class="secondary" data-action="cancel-login">Cancel</button>
      </div>
    `;
  }
  return `
    ${chrome()}
    <h1>Sign in to your vault</h1>
    <p>The hub’s owner must approve this computer with this code:</p>
    <div class="status"><div class="mono login-code">${escapeHtml(loginCode.userCode)}</div></div>
    <p>
      If you own the hub, open its approval page here. It asks for the hub’s
      passphrase, the one set on the hub itself. Then choose what this computer
      may use; to add services from here, allow it to manage profiles.
    </p>
    <p>
      Otherwise, send the owner this link and wait:
      ${mono(loginCode.verifyUrl)}
    </p>
    <div class="actions">
      <button type="button" data-action="open-approval">Open approval page</button>
      <button type="button" class="secondary" data-action="cancel-login">Cancel</button>
    </div>
  `;
}

/** The bar above the hub's page ("approving" and S6). */
function renderVaultBar(): string {
  const host = config.vaultUrl ? new URL(config.vaultUrl).host : "";
  if (screen === "approving") {
    return `
      <div class="vault-bar">
        <span>Approve code ${mono(loginCode?.userCode ?? "")} below · waiting for approval…</span>
        <button type="button" class="secondary" data-action="cancel-login">Cancel</button>
      </div>
    `;
  }
  return `
    <div class="vault-bar">
      <span>AgentIO Companion · ${mono(host)}</span>
      <button type="button" class="secondary" data-action="switch-vault">Switch vault</button>
    </div>
  `;
}

function renderS4(): string {
  return `
    ${chrome()}
    <h1>Connect to your vault</h1>
    <p>
      Enter the HTTPS URL of your AgentIO vault hub.
      Self-hosted or commercially hosted — same step.
    </p>
    <label for="vault-url">Vault URL</label>
    <input id="vault-url" type="url" placeholder="https://vault.example.com" value="${escapeAttr(config.vaultUrl)}" />
    <div class="row">
      <input id="remember" type="checkbox" ${config.rememberUrl ? "checked" : ""} />
      <label for="remember" style="margin:0">Remember this URL</label>
    </div>
    ${errorBox()}
    <div class="actions">
      <button type="button" data-action="sign-in">Sign in</button>
      <button type="button" class="linkish" data-action="go-mode">Back</button>
      <button type="button" class="linkish" data-action="open-marketing">Need a hosted vault? agentio.com</button>
    </div>
  `;
}

function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function escapeAttr(s: string): string {
  return escapeHtml(s);
}

function render(): void {
  // A hub page fills the window below the bar; the main process places it.
  const bar = screen === "approving" || screen === "S6";
  document.body.classList.toggle("with-vault", bar);
  if (screen === "approving" || screen === "S6") {
    app.innerHTML = renderVaultBar();
    return;
  }
  const screens: Record<Exclude<OnboardingScreen, "approving" | "S6">, () => string> = {
    S1: renderS1,
    S2: renderS2,
    S3: renderS3,
    mode: renderMode,
    S4: renderS4,
    login: renderLogin,
    local: renderLocal,
  };
  const body = screens[screen]();
  app.innerHTML = `<div class="shell" data-screen="${screen}">${body}</div>`;
}

/** Show the mode screen and read the vault state for it. */
async function enterMode(): Promise<void> {
  screen = "mode";
  vault = null;
  render();
  if (!window.agentioOnboarding) return;
  try {
    vault = await window.agentioOnboarding.vaultState();
  } catch (e) {
    vault = { mode: "none" };
    error = errorText(e);
  }
  if (screen === "mode") render();
}

/** Electron prefixes errors from the main process; show only the message. */
function errorText(e: unknown): string {
  return (e instanceof Error ? e.message : String(e)).replace(
    /^Error invoking remote method '[^']+': (?:[A-Za-z]*Error: )?/,
    "",
  );
}

async function refreshConfig(): Promise<void> {
  if (window.agentioOnboarding) {
    config = await window.agentioOnboarding.getConfig();
  }
}

function wire(): void {
  app.addEventListener("click", async (ev) => {
    const t = (ev.target as HTMLElement).closest<HTMLElement>("[data-action]");
    if (!t || !window.agentioOnboarding) return;
    const action = t.dataset.action;
    error = "";

    try {
      if (action === "install" || action === "update") {
        cliPercent = 0;
        cliLabel = "";
        const onboarding = window.agentioOnboarding;
        await onboarding.startCliInstall().catch(async (e) => {
          // A failed run may still have changed what is installed.
          cliState = await onboarding.cliStatus();
          throw e;
        });
      } else if (action === "continue-cli") {
        await window.agentioOnboarding.continueWithCli();
      } else if (action === "continue-url" || action === "go-mode") {
        await enterMode();
      } else if (action === "go-remote") {
        screen = "S4";
        render();
      } else if (action === "go-local") {
        screen = "local";
        render();
      } else if (action === "sign-in") {
        const url = (
          document.querySelector<HTMLInputElement>("#vault-url")?.value || ""
        ).trim();
        const remember =
          document.querySelector<HTMLInputElement>("#remember")?.checked ?? true;
        loginCode = null;
        await window.agentioOnboarding.setVaultUrl(url, remember);
        await refreshConfig();
        await window.agentioOnboarding.startLogin();
      } else if (action === "open-approval") {
        await window.agentioOnboarding.openApproval();
      } else if (action === "cancel-login") {
        await window.agentioOnboarding.cancelLogin();
      } else if (action === "switch-vault") {
        await window.agentioOnboarding.closeVault();
        await enterMode();
      } else if (action === "create-local") {
        const passphrase =
          document.querySelector<HTMLInputElement>("#passphrase")?.value || "";
        const again =
          document.querySelector<HTMLInputElement>("#passphrase-again")?.value || "";
        if (passphrase.length < 8) throw new Error("The passphrase needs at least 8 characters");
        if (passphrase !== again) throw new Error("The two passphrases are different");
        busy = "Creating the vault and starting it…";
        render();
        await window.agentioOnboarding.createLocalVault(passphrase);
      } else if (action === "open-local") {
        busy = "Starting the local vault…";
        render();
        await window.agentioOnboarding.openLocalVault();
      } else if (action === "open-remote") {
        await window.agentioOnboarding.openRemoteVault();
      } else if (action === "open-marketing") {
        // Best-effort; main may not expose this in skeleton
        window.open("https://agentio.com", "_blank");
      }
    } catch (e) {
      busy = "";
      error = errorText(e);
      // A failed or cancelled sign-in goes back to the hub URL.
      if (screen === "login" || screen === "approving") screen = "S4";
      render();
    }
    busy = "";
  });
}

async function boot(): Promise<void> {
  document.documentElement.style.setProperty("--vault-bar-height", `${VAULT_BAR_HEIGHT}px`);
  wire();
  if (!window.agentioOnboarding) {
    app.innerHTML = `<div class="shell"><h1>AgentIO Companion</h1><p class="error">Preload bridge missing — open this UI inside Electron.</p></div>`;
    return;
  }
  await refreshConfig();
  window.agentioOnboarding.onNavigate((next) => {
    if (next === "mode") {
      void refreshConfig().then(enterMode);
      return;
    }
    screen = next;
    void refreshConfig().then(render);
  });
  window.agentioOnboarding.onLoginCode((code) => {
    loginCode = code;
    if (screen === "login") render();
  });
  window.agentioOnboarding.onCliProgress((payload) => {
    cliPercent = payload.percent;
    cliLabel = payload.label;
    if (screen === "S2") render();
  });
  render();
  cliState = await window.agentioOnboarding.cliStatus();
  if (screen === "S1") render();
}

void boot();
