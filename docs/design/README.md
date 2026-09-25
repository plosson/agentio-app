# System Utility Vault — Design System

**Product surfaces:** AgentIO Companion (Electron) **and** AgentIO vault hub `/ui`  
**Visual direction:** System Utility Vault  
**Status:** Shared source of truth for look & feel across both apps  
**Spec (companion behavior):** [docs/plans/electron-companion-spec.md](../plans/electron-companion-spec.md)  
**Hub UI implementation:** [`plosson/agentio` → `src/daemon/ui/index.html`](https://github.com/plosson/agentio/blob/main/src/daemon/ui/index.html)

This folder is the single look-and-feel contract for implementers of:

1. **Electron companion** local renderer — onboarding wizard + thin vault bar (`apps/desktop` in this repo)
2. **AgentIO vault hub** — Unlock, Profiles, API keys, Settings, Authorize + dialogs/toasts (`plosson/agentio`)

Prefer these docs over ad-hoc choices. When rendering UI, use [`tokens.css`](./tokens.css) as the contract and match component anatomy in [`components.md`](./components.md).

**One visual system, two code homes** — see [ui-ownership.md](./ui-ownership.md). Companion must **not** CSS-inject into the hub `BrowserView`; the hub ships the shared look natively.

---

## How to use this system

1. **Read the vibe** — skim [overview.md](./overview.md) principles and the unified screen map before touching layout or color.
2. **Import / mirror tokens** — Companion: `@import` or copy [`tokens.css`](./tokens.css). Hub: map the same semantic values into `src/daemon/ui/index.html` CSS variables (keep names local if needed, keep hex/roles identical).
3. **Build screens from components** — use [`components.md`](./components.md) + [`layout.md`](./layout.md); copy markup patterns from [`examples.md`](./examples.md) (companion **and** hub examples).
4. **Motion last** — follow [`motion-feedback.md`](./motion-feedback.md) for progress, checklists, busy states, and `prefers-reduced-motion`.
5. **Migrate, don’t fork** — Companion: replace slate + sky cyan in `apps/desktop/src/renderer/styles.css`. Hub: replace deprecated GitHub blue `#0969da` with teal + near-black/white pills. Do not keep parallel palettes.

### Token import note (companion)

```css
/* apps/desktop renderer — prefer this over hard-coded slate/sky */
@import url("../../../../docs/design/tokens.css");
/* or, once packaged: copy tokens.css into src/renderer/tokens.css and import locally */
```

### Token contract (hub)

`tokens.css` is the **shared contract**. The hub may keep short local variable names (`--bg`, `--accent`, …) as long as they resolve to the same semantic values documented in [colors.md](./colors.md). When tokens change here, update the hub CSS in the same change set when possible.

CSS custom properties live on `:root` (light) and `@media (prefers-color-scheme: dark)` / `[data-theme="dark"]`. Electron can force theme via `data-theme` on `<html>` if the user preference should override OS.

---

## Vibe one-pager — System Utility Vault

| Trait | Meaning |
|-------|---------|
| **OS-embedded** | Feels like macOS System Settings or a native utility, not a SaaS dashboard in a window. |
| **Soft zinc field** | Full-window `#F5F5F7` (light) / dark twin — no floating slate card on a void; hub uses the same canvas family. |
| **Narrow wizard / calm hub** | Companion: centered ~420px column. Hub: main max-width ~1040 for tables — same type, radius, accent, buttons. |
| **One brand accent** | Teal `#0F766E` — progress, focus, active tab, chips, sparse highlights. **Not** GitHub blue `#0969da`. |
| **Honest primary CTAs** | Near-black pills (light) / near-white (dark). Never sky-cyan or GitHub-blue primary buttons. |
| **Quiet chrome** | Thin companion vault bar + hub header should feel continuous (same surface/border family). |
| **Fun via craft** | Motion, step checklists, rotating status copy, tip strips — not mascots or confetti. |

Away from: slate `#0f172a` / `#1e293b` panels, sky `#38bdf8` primaries, hub GitHub blue `#0969da`, random gradients, SaaS “glass card” stacks.

---

## Document index

| Doc | Contents |
|-----|----------|
| [overview.md](./overview.md) | Principles, do/don't, **unified** companion + hub screen map |
| [ui-ownership.md](./ui-ownership.md) | Which repo implements which screen; one visual system |
| [colors.md](./colors.md) | Light/dark semantic tokens, hex, WCAG, never-use, hub blue deprecation |
| [typography.md](./typography.md) | SF Pro / system stack, scale, mono rules |
| [spacing-sizing.md](./spacing-sizing.md) | 4px grid, column, radii, hit targets, vault bar |
| [components.md](./components.md) | Companion + hub component anatomy |
| [motion-feedback.md](./motion-feedback.md) | Durations, CLI checklist, tips, reduced motion |
| [layout.md](./layout.md) | Window sizes, titlebar, onboarding vs vault; hub main width |
| [tokens.css](./tokens.css) | Ready-to-import CSS custom properties (shared contract) |
| [examples.md](./examples.md) | Companion + hub HTML/CSS snippets using tokens |

---

## Ownership

| Concern | Home |
|---------|------|
| Design tokens & guidelines | This folder (`docs/design/` in **agentio-app**) |
| Companion product behavior & screen flow | `docs/plans/electron-companion-spec.md` |
| Companion implementation | `apps/desktop` (must converge on these tokens) |
| Vault hub `/ui` implementation | `plosson/agentio` → `src/daemon/ui/` (ships shared look natively) |

See [ui-ownership.md](./ui-ownership.md) for the screen → repo table.
