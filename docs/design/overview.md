# Overview — System Utility Vault

AgentIO’s local companion UI **and** the vault hub `/ui` share one visual language: a **macOS system utility** — calm, precise, and embedded in the desktop — not a marketing SaaS shell and not a GitHub-blue admin panel.

Product behavior for the companion lives in [electron-companion-spec.md](../plans/electron-companion-spec.md). Hub behavior lives in `plosson/agentio`. This doc locks the **visual principles** and the **unified screen map** implementers must follow.

Principles apply **everywhere** — companion onboarding, companion vault bar, and every hub screen (Unlock, Profiles, API keys, Settings, Authorize, dialogs, toasts). There is no “hub keeps its own CSS” exception.

Companion chrome bar + hub content should feel **continuous**: same soft-zinc background family, same system type stack, same teal accent, same near-black / near-white primary pills.

---

## Principles

### 1. Native first

- Prefer system fonts, OS traffic lights, and quiet window chrome.
- Background is the window / page itself (soft zinc), not a dark floating card on a darker void.
- Controls look like macOS / System Settings siblings: pills, clear hierarchy, restrained borders.

### 2. One accent

- Brand teal `#0F766E` appears sparingly: focus rings, progress fill, spinner, selected card edge, active tab underline, active chips, switches checked, sparse links.
- Primary actions are **near-black / near-white pills**, never teal-filled hero buttons, never sky cyan, never GitHub blue `#0969da`.

### 3. Honesty in progress

- Prefer **determinate** progress when bytes/steps are known (CLI download %).
- Use checklists and rotating status strings for multi-step work; never fake 100% early.
- Errors are plain language + retry — no playful failure illustrations.

### 4. Quiet chrome

- Onboarding: minimal titlebar, centered column, no sidebar, no marketing hero.
- Vault mode: thin companion bar + hub `/ui` in a `BrowserView` — chrome stays out of the way; bar surface matches hub header.
- Elevation is subtle (1px borders, soft radius); avoid heavy drop shadows and glass stacks.

---

## Do / Don’t

| Do | Don’t |
|----|-------|
| Full-window / full-page soft zinc background | Slate `#0f172a` / `#1e293b` “panel on void” |
| Centered ~420px wizard column (companion) | Wide dashboard layouts during onboarding |
| Hub main ~1040 max-width for tables | Different accent or button language in hub vs companion |
| Near-black / near-white primary pills | Sky `#38bdf8` **or** GitHub `#0969da` primary buttons |
| Teal for focus, progress, tabs, chips, switches | Teal wash backgrounds or teal-on-teal text |
| SF Pro / `system-ui` (+ system mono for codes) | Custom display fonts; IBM Plex as required brand |
| Mono for codes, paths, versions, authorize codes | Mono for body copy or button labels |
| Checklist + tip strips for delight | Mascots, confetti, emoji explosions |
| WCAG AA text/button contrast | Low-contrast muted-on-muted labels |
| `prefers-reduced-motion` respect | Endless bounce animations |
| Hub ships shared look natively | Companion CSS-inject into BrowserView |

---

## Inspiration (Mobbin — brief)

Use as **reference only**; do not copy artwork or copywriting:

| Reference | Takeaway |
|-----------|----------|
| **Skiff** onboarding | Soft, centered, system-like calm; sparse chrome |
| **PlanetScale** cards | Clear selection cards with restrained borders |
| **1Password** large type | Device / login codes in confident mono display |
| **Dropbox** % progress | Honest determinate bar + plain status line |
| **Cake** checklist | Step rows that tick off as work completes |

---

## Unified screen map

### Companion (local Electron renderer)

```
  [Welcome]
       │ Install / Update CLI (or skip if current)
       ▼
  [CLI progress] ──success──► [CLI ready]
                                   │
                                   ▼
                            [Choose vault]
                           ╱              ╲
                    Local vault        Remote vault
                           │              │
                           ▼              ▼
                 [Local passphrase]  [Connect URL]
                           │              │
                           │              ▼
                           │       [Device code]  (remote device login)
                           │              │
                           └──────┬───────┘
                                  ▼
                         [Vault bar + hub /ui]
```

| ID | Screen | Purpose | Repo |
|----|--------|---------|------|
| W | **Welcome** | Explain CLI need; Install / Update / use existing | agentio-app |
| P | **CLI progress** | Determinate install/update with checklist + tips | agentio-app |
| R | **CLI ready** | Confirm version + path; Continue | agentio-app |
| V | **Choose vault** | Selection cards: Local vs Remote | agentio-app |
| U | **Connect URL** | HTTPS vault hub URL + remember | agentio-app |
| D | **Device code** | Large-type device login code for remote hub | agentio-app |
| L | **Local passphrase** | Unlock local vault with passphrase field | agentio-app |
| B | **Vault bar** | Thin companion chrome over hub `/ui` | agentio-app |

Returning users may skip Welcome→CLI ready when CLI is current, and may skip Choose vault / URL when preferences are remembered (see product spec).

### Vault hub (`/ui` in BrowserView or browser)

```
  [Unlock] ──passphrase──► [Profiles] ←→ [API keys] ←→ [Settings]
                                  │
                                  └── hash #authorize=<code> → [Authorize]
```

| ID | Screen | Purpose | Repo |
|----|--------|---------|------|
| H | **Unlock** | Passphrase unlock; calm centered card matching companion passphrase vibe | agentio |
| Pr | **Profiles** | Header+tabs, chips, profile table, row menus | agentio |
| K | **API keys** | Key table, create form, token dialog | agentio |
| S | **Settings** | Setting rows, danger lock | agentio |
| A | **Authorize** | Large mono approval code + Approve / Deny | agentio |
| — | **Dialogs / toasts** | Confirm, rename, token reveal; toast stack | agentio |

Hub layout: sticky header with tabs on soft surface; `main` max-width ~1040. Colors, type, radius, and buttons match companion tokens — only density differs (tables need width).

Continuity rule: when the companion vault bar sits above the hub, the bar’s background and bottom border should match the hub header so the seam disappears.

---

## Related docs

- Ownership → [ui-ownership.md](./ui-ownership.md)
- Colors → [colors.md](./colors.md)
- Type → [typography.md](./typography.md)
- Space → [spacing-sizing.md](./spacing-sizing.md)
- Components → [components.md](./components.md)
- Motion → [motion-feedback.md](./motion-feedback.md)
- Layout → [layout.md](./layout.md)
- Tokens → [tokens.css](./tokens.css)
- Examples → [examples.md](./examples.md)
