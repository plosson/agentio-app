# AgentIO Companion

Electron companion for a remote AgentIO vault hub.

The app walks first-launch onboarding (CLI install/update → vault URL → passphrase), then `loadURL`s the hub’s `/ui`. A narrow preload bridge (`window.agentioCompanion`) lets the shared admin HTML show **Add profile** / **Reauth** only inside the companion. The AgentIO CLI is **not** bundled; onboarding installs or updates it separately.

## Status

Skeleton (Phase B wireframe). Onboarding screens S1–S6 are stubbed; CLI download/install is fake progress; unlock does not call the hub yet; vault window can `loadURL` a configurable hub URL; PTY / OAuth (S7) is not implemented. See the locked product decisions in the spec.

## Spec

Full project specification:

- [`docs/plans/electron-companion-spec.md`](docs/plans/electron-companion-spec.md) (v0.9)

## Layout

```
apps/desktop/     Electron main, preload, onboarding renderer (Vite)
docs/plans/       Product / architecture spec
```

Desktop-only pnpm workspace (mirrors [plosson/app-starter](https://github.com/plosson/app-starter) desktop conventions; no mobile/web apps).

## Requirements

- Node.js ≥ 20
- pnpm 9 (`corepack enable` or install pnpm)

## Setup

```bash
pnpm install
```

## Run (desktop)

```bash
# From repo root — builds main/preload, starts Vite for onboarding, launches Electron
pnpm desktop
# or
pnpm --filter @agentio/desktop dev
```

Headless / CI (no GUI): typecheck and build without launching Electron:

```bash
pnpm typecheck
pnpm build
```

## Pack

```bash
pnpm pack:desktop:dir      # unpacked dir
pnpm pack:desktop:linux    # AppImage / deb (Linux)
pnpm pack:desktop          # mac / win / linux targets via electron-builder
```

## What is stubbed vs real

| Piece | Status |
|-------|--------|
| Repo layout, TypeScript, electron-builder scripts | Real |
| `contextIsolation` + `window.agentioCompanion` bridge | Real (stubs log / IPC) |
| Onboarding screen router S1–S6 | Real UI placeholders |
| CLI install / update download | **Stub** (fake progress) |
| Passphrase unlock against hub | **Stub** (proceeds to vault window) |
| Vault `BrowserWindow` `loadURL(hub + '/ui')` | Real wiring (needs a reachable hub) |
| PTY / Add profile OAuth (S7) | Not yet |
| Commercial account login | Out of scope (by design) |

## Bridge (Option A)

Preload exposes:

```ts
window.agentioCompanion = {
  present: true,
  addProfile(service: string): Promise<void>,
  reauth(service: string, name?: string): Promise<void>,
  openTerminal(): Promise<void>,
}
```

`nodeIntegration` is off; the bridge does not expose shell, tokens, or passphrase APIs.

## License

Private / TBD — © Pierre A. Losson
