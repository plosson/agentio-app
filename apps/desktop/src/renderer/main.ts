import "./styles.css";
import type { CompanionConfig, OnboardingScreen } from "../shared/types";

const app = document.querySelector<HTMLDivElement>("#app")!;

let screen: OnboardingScreen = "S1";
let config: CompanionConfig = {
  vaultUrl: "",
  rememberUrl: true,
  cliVersion: null,
};
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
      To add services to a remote vault, this machine needs the AgentIO CLI.
      We’ll install (or update) the latest release. Nothing is bundled inside this app.
    </p>
    <div class="status">
      Status: CLI not found <span class="mono">(skeleton — detection stubbed)</span>
    </div>
    <div class="actions">
      <button type="button" data-action="install">Install latest AgentIO</button>
      <button type="button" class="secondary" data-action="update">Update to latest</button>
      <button type="button" class="linkish" data-action="use-path">Advanced: use existing CLI on PATH…</button>
    </div>
  `;
}

function renderS2(): string {
  return `
    ${chrome()}
    <h1>Setting up AgentIO CLI</h1>
    <p>${cliLabel || "Starting…"}</p>
    <div class="progress" aria-valuenow="${cliPercent}" aria-valuemin="0" aria-valuemax="100">
      <span style="width:${cliPercent}%"></span>
    </div>
    <p class="mono">${cliPercent}% · stub download (no real release fetch yet)</p>
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
      <div>Location: <span class="mono">(stub — not written to disk)</span></div>
    </div>
    <div class="actions">
      <button type="button" data-action="continue-url">Continue</button>
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
    ${error ? `<div class="error">${escapeHtml(error)}</div>` : ""}
    <div class="actions">
      <button type="button" data-action="continue-passphrase">Continue</button>
      <button type="button" class="linkish" data-action="open-marketing">Need a hosted vault? agentio.com</button>
    </div>
  `;
}

function renderS5(): string {
  return `
    ${chrome()}
    <h1>Unlock vault</h1>
    <p class="mono">${escapeHtml(config.vaultUrl || "(no URL)")}</p>
    <label for="passphrase">Passphrase</label>
    <input id="passphrase" type="password" autocomplete="current-password" />
    <p class="mono">Skeleton: unlock does not call the hub yet.</p>
    ${error ? `<div class="error">${escapeHtml(error)}</div>` : ""}
    <div class="actions">
      <button type="button" data-action="unlock">Unlock</button>
      <button type="button" class="linkish" data-action="change-url">Change vault URL</button>
    </div>
  `;
}

function renderS6(): string {
  return `
    ${chrome()}
    <h1>Vault UI</h1>
    <p>
      Opening remote hub UI at
      <span class="mono">${escapeHtml(config.vaultUrl)}/ui</span>
    </p>
    <p class="ok">
      If the hub is reachable, a vault window should appear with
      <span class="mono">window.agentioCompanion</span> available to page scripts.
    </p>
    <div class="actions">
      <button type="button" data-action="reopen-vault">Open / focus vault window</button>
      <button type="button" class="secondary" data-action="change-url">Change vault URL</button>
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
  const body =
    screen === "S1"
      ? renderS1()
      : screen === "S2"
        ? renderS2()
        : screen === "S3"
          ? renderS3()
          : screen === "S4"
            ? renderS4()
            : screen === "S5"
              ? renderS5()
              : renderS6();
  app.innerHTML = `<div class="shell" data-screen="${screen}">${body}</div>`;
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
        await window.agentioOnboarding.startCliInstall();
      } else if (action === "use-path") {
        await window.agentioOnboarding.skipCliUsePath();
        await refreshConfig();
        render();
      } else if (action === "continue-url") {
        screen = "S4";
        render();
      } else if (action === "continue-passphrase") {
        const url = (
          document.querySelector<HTMLInputElement>("#vault-url")?.value || ""
        ).trim();
        const remember =
          document.querySelector<HTMLInputElement>("#remember")?.checked ?? true;
        await window.agentioOnboarding.setVaultUrl(url, remember);
        await refreshConfig();
      } else if (action === "unlock") {
        const passphrase =
          document.querySelector<HTMLInputElement>("#passphrase")?.value || "";
        const result = await window.agentioOnboarding.unlockStub(passphrase);
        if (!result.ok) {
          error = result.error || "Unlock failed";
          render();
          return;
        }
        await window.agentioOnboarding.openVault();
        await refreshConfig();
        screen = "S6";
        render();
      } else if (action === "change-url") {
        screen = "S4";
        render();
      } else if (action === "reopen-vault") {
        await window.agentioOnboarding.openVault();
      } else if (action === "open-marketing") {
        // Best-effort; main may not expose this in skeleton
        window.open("https://agentio.com", "_blank");
      }
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
      render();
    }
  });
}

async function boot(): Promise<void> {
  wire();
  if (!window.agentioOnboarding) {
    app.innerHTML = `<div class="shell"><h1>AgentIO Companion</h1><p class="error">Preload bridge missing — open this UI inside Electron.</p></div>`;
    return;
  }
  await refreshConfig();
  window.agentioOnboarding.onNavigate((next) => {
    screen = next;
    void refreshConfig().then(render);
  });
  window.agentioOnboarding.onCliProgress((payload) => {
    cliPercent = payload.percent;
    cliLabel = payload.label;
    if (screen === "S2") render();
  });
  render();
}

void boot();
