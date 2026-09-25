# AgentIO Electron Companion — Project Specification

| Field | Value |
|-------|-------|
| **Product name (working)** | AgentIO Companion |
| **Status** | Specification — do not implement until Pierre says start |
| **Version** | 0.9 |
| **Repo target** | New repo under `plosson` (suggested: `plosson/agentio-companion`) **or** folder inside `plosson/agentio`; decide at kickoff |
| **Related** | `plosson/agentio`; remote vault hub (self-hosted or commercially hosted) |
| **Author** | Claudiu (Grok Bot) for Pierre A. Losson |
| **Date** | 2026-09-25 |

---

## 1. Locked decisions

1. **Remote vault hub.** The vault and admin UI live on a remote hub (Docker AgentIO behind TLS). The hub may be **self-hosted** or **commercially hosted**. The Electron app is a laptop companion: it shows that remote UI and runs **local** OAuth when adding services.
2. **Onboarding (first launch).** Ordered local screens: **(1)** install or update AgentIO CLI to latest → **(2)** ask for **vault URL** → **(3)** ask for **passphrase** → open vault UI. Returning users skip CLI install if already current (optional “update available”); they may land on URL or unlock depending on remembered URL.
3. **Decoupled from commercial site.** No AgentIO account login, billing, provisioning, or vault picker from a control plane in the app. Commercial hosting is optional and only yields a URL to paste in.
4. **Same admin UI.** After unlock, Electron `loadURL`s `https://<hub>/ui`. Same `src/daemon/ui/index.html` as browsers; no companion-only admin fork; HTML is not Electron’s document origin.
5. **Option A (companion vs browser).** Narrow `window.agentioCompanion` preload bridge (`contextIsolation: true`). Shared HTML feature-detects `present` and shows **Add profile** / **Reauth** only then. Clicks → IPC → PTY → stock CLI. Capability = bridge present — not UA or query params.
6. **OAuth via stock CLI.** No new hub OAuth APIs. Localhost **3000–3010**. Remote mode + `--can-manage-profiles` PUTs credentials to the hub.
7. **CLI via setup — not bundled.** Electron package does not embed AgentIO. Onboarding installs or updates to the **latest** release. Runtime opaque.
8. **No local vault daemon** as the default product path.
9. **Shared admin HTML.** One Option A change to `src/daemon/ui/index.html`; hub serve/embed parity stays green.
10. **MVP platform:** macOS first; Windows/Linux later.

---

## 2. Product overview

### 2.1 Journey

```
  Launch Companion
       │
       ▼
  Onboarding — CLI
       install latest  OR  update to latest  OR  already up to date
       │
       ▼
  Onboarding — Vault URL
       │
       ▼
  Unlock — Passphrase
       │
       ▼
  Vault window = same as https://<hub>/ui
       + Add services (Option A → local CLI)
```

### 2.2 Problem

A browser can unlock a remote vault and manage keys/profiles, but cannot complete provider OAuth that must bind localhost. The companion puts the same remote UI in a desktop window and enables in-page Add profile / Reauth only when the local CLI can run.

### 2.3 Goals

- First-launch onboarding: CLI install/update, then vault URL, then passphrase.
- No AgentIO binary inside the Electron package.
- Same remote `/ui` as browsers; companion-only Add profile / Reauth via Option A.
- Vault secrets stay on the hub; laptop holds session cookie + manage-profiles token.

### 2.4 Non-goals (v1)

- Bundling AgentIO in the Electron package.
- Account login / billing / provisioning in the app.
- Local vault daemon as primary store.
- Separate companion-only admin HTML or HTML as document origin.
- New hub OAuth APIs beyond existing remote profile PUT.
- UA/query-param gates; broad preload; mobile; WhatsApp; Hex-Rays work; merging `go-port/*` unasked.

### 2.5 Success criteria (MVP)

1. First launch walks CLI install/update → vault URL → passphrase.
2. Vault window matches hub `/ui` in a browser; browser still has no companion buttons.
3. Add profile OAuth on 3000–3010 works; profile appears on hub after refresh.
4. Package has no AgentIO binary; self-hosted and hosted URLs both work.

---

## 3. Screens (ASCII)

Local chrome = Companion-owned windows/pages. Vault window = remote `loadURL` (hub HTML + Option A when bridge present).

### 3.0 Screen map

```
  [S1 Welcome / CLI]
       │ Install or Update
       ▼
  [S2 CLI progress]
       │ success
       ▼
  [S3 CLI ready] ──Continue──► [S4 Vault URL] ──Continue──► [S5 Passphrase]
                                                                  │
                                                                  ▼
                                                            [S6 Vault UI]
                                                                  │
                                              Add profile ───────► [S7 PTY / OAuth]
```

Settings (later): change vault URL, check CLI updates, open terminal — not required for MVP wireframes below.

---

### S1 — Welcome / AgentIO CLI (first launch)

```
┌─────────────────────────────────────────────────────────────┐
│  AgentIO Companion                                      ● ○ │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│              Welcome to AgentIO Companion                   │
│                                                             │
│   To add services to a remote vault, this Mac needs         │
│   the AgentIO CLI. We’ll install (or update) the            │
│   latest release. Nothing is bundled inside this app.     │
│                                                             │
│   Status:  CLI not found                                    │
│            — or —                                           │
│   Status:  CLI v1.2.3 installed · latest is v1.4.0          │
│                                                             │
│          ┌──────────────────────────┐                       │
│          │  Install latest AgentIO  │                       │
│          └──────────────────────────┘                       │
│          ┌──────────────────────────┐                       │
│          │  Update to latest        │  (if older present)   │
│          └──────────────────────────┘                       │
│                                                             │
│   Advanced: use existing CLI on PATH…                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Returning launch, CLI already latest: skip to S4 (or S5 if URL remembered). Show a quiet “CLI v… · up to date” in settings, not a blocking screen.

---

### S2 — Installing / updating CLI

```
┌─────────────────────────────────────────────────────────────┐
│  AgentIO Companion                                      ● ○ │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│              Setting up AgentIO CLI                         │
│                                                             │
│   Fetching latest release for macOS arm64…                  │
│   ████████████████░░░░░░░░  62%                             │
│                                                             │
│   agentio 1.4.0                                             │
│   From: github.com/plosson/agentio/releases                 │
│                                                             │
│   [ Cancel ]                                                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

On failure: retry + short error (network, checksum, disk). Do not continue to vault URL until CLI is usable.

---

### S3 — CLI ready

```
┌─────────────────────────────────────────────────────────────┐
│  AgentIO Companion                                      ● ○ │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│              AgentIO CLI is ready                           │
│                                                             │
│   Installed:  agentio 1.4.0                                 │
│   Location:   ~/Library/Application Support/…/agentio       │
│               (or chosen install path)                      │
│                                                             │
│          ┌──────────────────────────┐                       │
│          │       Continue           │                       │
│          └──────────────────────────┘                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### S4 — Vault URL

```
┌─────────────────────────────────────────────────────────────┐
│  AgentIO Companion                                      ● ○ │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│              Connect to your vault                          │
│                                                             │
│   Enter the HTTPS URL of your AgentIO vault hub.            │
│   Self-hosted or commercially hosted — same step.           │
│                                                             │
│   Vault URL                                                 │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ https://vault.example.com                           │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   □ Remember this URL                                       │
│                                                             │
│          ┌──────────────────────────┐                       │
│          │       Continue           │                       │
│          └──────────────────────────┘                       │
│                                                             │
│   Need a hosted vault?  agentio.com  (opens browser)        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Validate HTTPS (dev exception for localhost only if enabled). Optional marketing link is not login.

---

### S5 — Passphrase (unlock)

```
┌─────────────────────────────────────────────────────────────┐
│  AgentIO Companion                                      ● ○ │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│              Unlock vault                                   │
│                                                             │
│   https://vault.example.com                                 │
│                                                             │
│   Passphrase                                                │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ ••••••••••••••••••                                  │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│          ┌──────────────────────────┐                       │
│          │        Unlock            │                       │
│          └──────────────────────────┘                       │
│                                                             │
│   [ Change vault URL ]                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Unlock uses the hub’s existing unlock/session path (same as browser). Passphrase is not sent through the preload bridge to page JS as a companion API — prefer driving the remote unlock UI **or** a main-process call to the hub unlock endpoint consistent with today’s `/ui` session model (implementation detail; must not widen the bridge).

---

### S6 — Vault window (remote admin UI + Option A)

Same content as opening `https://<hub>/ui` in a browser, inside Electron, with companion controls visible:

```
┌─────────────────────────────────────────────────────────────┐
│  AgentIO Companion — vault.example.com            [⋯]  ● ○ │
├─────────────────────────────────────────────────────────────┤
│  (remote origin: https://vault.example.com/ui)              │
│                                                             │
│   Vault unlocked                                            │
│                                                             │
│   Profiles                                                  │
│   ┌─────────────────────────────────────────────────────┐   │
│   │ gmail / work          ···                           │   │
│   │ jira / personal       ···                           │   │
│   └─────────────────────────────────────────────────────┘   │
│                                                             │
│   ┌──────────────┐  ┌──────────────┐                        │
│   │ Add profile  │  │   Reauth     │   ← companion only     │
│   └──────────────┘  └──────────────┘                        │
│                                                             │
│   Keys · Devices · …     (existing hub UI)                  │
│                                                             │
│   ─────────────────────────────────────────────────────     │
│   In a normal browser this footer stays “use the CLI…”      │
│   and Add profile / Reauth are hidden.                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

Menu / `⋯`: Change vault, Update AgentIO CLI, Open terminal, Quit.

---

### S7 — Add profile (PTY / OAuth)

Triggered by Add profile (service picker on hub HTML or a small companion sheet):

```
┌─────────────────────────────────────────────────────────────┐
│  AgentIO Companion — Add profile                    ● ○ │
├─────────────────────────────────────────────────────────────┤
│  Service: Gmail                                             │
│                                                             │
│  ┌─ Terminal ─────────────────────────────────────────────┐ │
│  │ $ agentio gmail profile add                            │ │
│  │ Open http://127.0.0.1:3000/… in your browser           │ │
│  │ Waiting for OAuth callback…                            │ │
│  │ ✓ Profile saved to remote vault                        │ │
│  │ _                                                      │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                             │
│   [ Done ]     (refreshes profile list in vault window)     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

OAuth runs on localhost via the CLI; Companion does not intercept IdP redirects in the vault `BrowserWindow`.

---

### Returning launch (sketch)

```
  CLI missing/outdated? ──yes──► S1/S2/S3
         │ no
         ▼
  Remembered URL? ──no──► S4 → S5 → S6
         │ yes
         ▼
       S5 → S6
```

---

## 4. Architecture

### 4.1 High-level

```
┌─ Laptop (Electron Companion) ──────────────────────────────────────────┐
│  Onboarding (local): CLI install/update → vault URL → passphrase       │
│                                                                        │
│  Preload (contextIsolation)                                            │
│    window.agentioCompanion = {                                         │
│      present: true,                                                    │
│      addProfile(service),                                              │
│      reauth(service, name?),                                           │
│      openTerminal()                                                    │
│    }  ──IPC──► Main ──PTY──► installed agentio (remote mode)           │
│                                      │                                 │
│                                      ├─ OAuth 127.0.0.1:3000–3010      │
│                                      └─ PUT /v1/profiles/... → hub     │
│                                                                        │
│  BrowserWindow ──loadURL──► https://<hub>/ui                           │
│    index.html: if (agentioCompanion?.present) show Add/Reauth          │
│                else keep CLI footer                                    │
└──────────────────────────────────────────────┬─────────────────────────┘
                                               │ HTTPS
                                               ▼
┌─ Vault hub (self-hosted or commercially hosted) ───────────────────────┐
│  Same src/daemon/ui/index.html at /ui                                  │
│  /ui/api/* · /v1/* · vault.enc                                         │
│  No new OAuth endpoints                                                │
└────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Two channels (do not conflate)

| Channel | Transport | Auth | Purpose |
|---------|-----------|------|---------|
| **Owner UI** | `loadURL` → `https://hub/ui` | Cookie `agentio_session` after unlock | Unlock, keys, profiles list, devices |
| **Manage-profiles CLI** | Installed CLI → `https://hub/v1/...` | Bearer `agio1.…` | Remote profile add; OAuth locally |

Remote page JS never receives the agent API token. Companion actions only via the narrow preload bridge.

### 4.3 Option A — bridge + conditional HTML

```
window.agentioCompanion = {
  present: true,
  addProfile(service: string): Promise<void>,
  reauth(service: string, name?: string): Promise<void>,
  openTerminal(): Promise<void>,
}
```

- `contextIsolation: true`, `nodeIntegration: false`.
- Forbidden on the bridge: `exec`, raw shell, arbitrary argv, token/passphrase/filesystem readback to the page.
- Shared HTML: feature-detect `present`; browser keeps CLI footer; no UA/query gates; hub parity green; no new OAuth routes.

### 4.4 Components

| Component | Responsibility |
|-----------|----------------|
| Onboarding | S1–S5: CLI install/update, vault URL, passphrase |
| Electron main | Windows, IPC, PTY, CLI path, release download |
| Preload | `agentioCompanion` only |
| Vault BrowserWindow | `loadURL(hubBase + '/ui')` |
| Terminal panel | node-pty + xterm (S7) |
| Installed `agentio` | Latest CLI on disk |
| Hub `index.html` | Option A Add/Reauth |

---

## 5. Remote UI loading

- Document origin = hub. No iframe. Production HTTPS. Refresh profiles after Add profile.

---

## 6. Local CLI: remote mode + OAuth

1. `agentio login https://<hub>` or token with `--can-manage-profiles`.
2. `agentio profile add <service>` → OAuth 3000–3010 → PUT hub.
3. Do not bind those ports or steal IdP redirects in the vault window.
4. Remote `reauth` may be unavailable today — see open questions.

---

## 7. CLI install (onboarding — not bundled)

- Package contains **no** AgentIO binary.
- Onboarding always targets **latest** release (install or update).
- Main-process download only (S17); verify integrity as AgentIO publishes.
- Record installed version in About / S3.
- Network required for CLI setup and for the hub.

---

## 8. Ports

| Concern | Status |
|---------|--------|
| Local daemon ports | Not part of the product |
| OAuth 3000–3010 | Required; errors surface in PTY |

---

## 9. Security

| ID | Requirement |
|----|-------------|
| S1 | Vault + passphrase stay on the hub. |
| S2 | Laptop: UI session cookie; hub token (0600/keychain); optional `AGENTIO_TOKEN`. |
| S3 | `nodeIntegration: false`, `contextIsolation: true`; minimal bridge. |
| S4 | Production HTTPS hubs only. |
| S5 | No iframe of admin UI. |
| S6 | CLI from trusted releases over HTTPS; verify checksum/signature; no silent arbitrary PATH fallback without user intent. |
| S7 | Code-sign companion; notarize macOS. |
| S8 | PTY only via main from bridge/companion chrome. |
| S9 | No Electron OAuth protocol handler in v1. |
| S10 | can-manage-profiles key; risk explicit. |
| S11 | Remote HTML untrusted for Node; XSS ≠ laptop RCE — keep bridge minimal. |
| S12 | Capability = bridge present. |
| S13 | No token/passphrase readback on the bridge. |
| S14 | Logout / revoke guidance. |
| S15 | Autoupdate signed only. |
| S16 | No commercial account required. |
| S17 | CLI download/install is main-process only — never driven by remote page JS. |

---

## 10. Packaging

- Signed macOS Companion first; Windows/Linux later.
- electron-builder for the app only — no AgentIO inside the artifact.
- Onboarding installs/updates CLI; optional later “Update AgentIO CLI”.

---

## 11. Effort estimate

| Scope | Eng-days |
|-------|----------|
| Hub HTML Option A | 0.5–1 |
| Companion MVP (onboarding screens, loadURL, bridge, PTY, one OAuth E2E) | 6–9 |
| Packaging / notarization (app-only) | 1.5–3 |
| Hardening / UX | 2–4 |
| Upstream remote `reauth` (optional) | 0–3 |
| **Solid v1 total** | **~10–17** |

---

## 12. Phased roadmap

### Phase A — Shared admin HTML (Option A)

- Feature-detect; Add profile / Reauth; browser footer unchanged; parity green

### Phase B — Onboarding + vault window

- S1–S5 local screens (CLI → URL → passphrase)
- `loadURL` vault UI; preload stub

### Phase C — CLI setup + PTY

- Fetch/install/update latest CLI; PTY for `addProfile` / `openTerminal`
- Login / can-manage-profiles; E2E add → refresh

### Phase D — Reauth policy

- Wire or hide/disable with hub-host guidance

### Phase E — Distribution

- Notarized macOS app without embedded CLI; smoke onboarding + OAuth

### Phase F — Polish

- Tray, URL history, Windows/Linux, update UX

---

## 13. Open questions

1. New repo vs in-tree companion package?
2. Autoupdate: companion app, AgentIO CLI, both, or manual?
3. First OAuth service (Gmail assumed)?
4. can-manage-profiles: `login`, paste from UI, or both?
5. Reauth in v1: hide, hub-host message, or upstream remote reauth?
6. Remember one URL vs URL history?
7. App name / branding?
8. `addProfile`: confirm in PTY vs auto-run?
9. Service picker: hub HTML dropdown vs companion sheet?
10. Offline UX (CLI setup needs network)?
11. Dev-only `http://127.0.0.1`?
12. CLI install location (app support dir vs `~/.local` vs system)?
13. Existing PATH `agentio`: reuse vs always companion-managed? (“Advanced” on S1)
14. Passphrase: companion-owned S5 posting to hub unlock API vs load `/ui` and let remote unlock form handle it?

---

## 14. Reference index

| Path | Role |
|------|------|
| `src/daemon/ui/index.html` | Shared admin UI (Option A) |
| `src/daemon/routes-ui.ts` | `/ui` + CSP |
| `src/daemon/session.ts` | Session cookie |
| `src/auth/remote.ts` | Remote mode + `remoteSaveProfile` |
| `src/daemon/routes-v1.ts` | Agent API |
| `src/auth/oauth-server.ts` | Localhost OAuth |
| `src/commands/login.ts` | `agentio login` |
| `src/commands/key.ts` | `--can-manage-profiles` |
| `docker/README.md` | Hub ops |
| AgentIO GitHub Releases | CLI source for onboarding |

---

## 15. Document control

| Version | Date | Notes |
|---------|------|-------|
| 0.9 | 2026-09-25 | Onboarding screens (ASCII): CLI install/update → vault URL → passphrase → vault UI; Option A + PTY |
| 0.8 | 2026-09-25 | CLI via setup, not bundled; always latest |
| 0.5 | 2026-09-25 | Vault URL + passphrase; Option A; remote UI; commercial out of app |

Withdrawn: local-daemon companion, commercial login in app, Bun/Go matrix, embedding AgentIO in the Electron artifact.
