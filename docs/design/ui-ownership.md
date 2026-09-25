# UI ownership — one visual system, two code homes

**Visual design** is shared (this folder + [`tokens.css`](./tokens.css)).  
**Code ownership** is split by surface. Do not blur the boundary by injecting styles across process / origin boundaries.

---

## Rule

| Rule | Detail |
|------|--------|
| **One design system** | System Utility Vault tokens, type, radii, and component language apply to companion **and** hub. |
| **No CSS injection** | Companion must **not** inject CSS into the hub `BrowserView`. The hub ships the shared look in `src/daemon/ui/index.html`. |
| **Tokens are the contract** | Change hex/roles here first; mirror into hub CSS variables in `plosson/agentio`. Companion imports `tokens.css` (or a packaged copy). |
| **Behavior stays local** | Companion owns Electron IPC, CLI install, device-code polling. Hub owns vault unlock, profiles, keys, settings, authorize. |

---

## Screen → repo

| Screen | Product surface | Implements in | Notes |
|--------|-----------------|---------------|-------|
| Welcome | Companion onboarding | `plosson/agentio-app` → `apps/desktop` | Local renderer |
| CLI progress / ready | Companion onboarding | agentio-app | |
| Choose vault | Companion onboarding | agentio-app | |
| Connect URL | Companion onboarding | agentio-app | |
| Device code | Companion onboarding | agentio-app | Large mono — same language as hub Authorize |
| Local passphrase | Companion onboarding | agentio-app | Match hub Unlock calm |
| Vault companion bar | Companion chrome | agentio-app | Surface/border match hub header |
| Unlock | Vault hub `/ui` | `plosson/agentio` → `src/daemon/ui/index.html` | |
| Profiles (+ chips, table, menus) | Vault hub `/ui` | agentio | |
| API keys | Vault hub `/ui` | agentio | |
| Settings (+ danger lock) | Vault hub `/ui` | agentio | |
| Authorize | Vault hub `/ui` | agentio | Hash `#authorize=<code>` |
| Dialogs / toasts | Vault hub `/ui` | agentio | |

Embedded HTML for the hub is loaded by the daemon (`assets.ts` text-imports `index.html`). Any visual change lands in that HTML (and whatever build/embed step already exists) — not via companion overlay CSS.

---

## Continuity checklist (vault mode)

When the user is in vault mode:

1. Companion bar height 40px; bg `--color-bg-elevated` or `--color-bg`; bottom border `--color-border`.
2. Hub header uses the same surface + border family so the two strips read as one chrome band.
3. Hub canvas `--color-bg` / `--bg` = soft zinc (`#F5F5F7` light / `#1C1C1E` dark).
4. Primary buttons: near-black / near-white pills (or filled near-black — **not** `#0969da`).
5. Accent teal only for tabs, chips active, focus, links, switches, testing badges.

---

## Related

- Principles & screen map → [overview.md](./overview.md)
- Tokens → [tokens.css](./tokens.css)
- Hub path → https://github.com/plosson/agentio/blob/main/src/daemon/ui/index.html
