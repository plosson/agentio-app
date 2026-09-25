# Overview — System Utility Vault

AgentIO Companion’s local UI (onboarding + thin vault chrome) should feel like a **macOS system utility**: calm, precise, and embedded in the desktop — not a marketing SaaS shell.

Product behavior lives in [electron-companion-spec.md](../plans/electron-companion-spec.md). This doc locks the **visual principles** and **screen map** implementers must follow.

---

## Principles

### 1. Native first

- Prefer system fonts, OS traffic lights, and quiet window chrome.
- Background is the window itself (soft zinc), not a dark floating card on a darker void.
- Controls look like macOS / System Settings siblings: pills, clear hierarchy, restrained borders.

### 2. One accent

- Brand teal `#0F766E` appears sparingly: focus rings, progress fill, spinner, selected card edge, sparse links.
- Primary actions are **near-black / near-white pills**, never teal-filled hero buttons and never sky cyan.

### 3. Honesty in progress

- Prefer **determinate** progress when bytes/steps are known (CLI download %).
- Use checklists and rotating status strings for multi-step work; never fake 100% early.
- Errors are plain language + retry — no playful failure illustrations.

### 4. Quiet chrome

- Onboarding: minimal titlebar, centered column, no sidebar, no marketing hero.
- Vault mode: thin companion bar + remote hub `/ui` in a `BrowserView` — chrome stays out of the way.
- Elevation is subtle (1px borders, soft radius); avoid heavy drop shadows and glass stacks.

---

## Do / Don’t

| Do | Don’t |
|----|-------|
| Full-window soft zinc background | Slate `#0f172a` / `#1e293b` “panel on void” |
| Centered ~420px wizard column | Wide dashboard layouts during onboarding |
| Near-black / near-white primary pills | Sky `#38bdf8` or cyan primary buttons |
| Teal for focus, progress, spinner only | Teal wash backgrounds or teal-on-teal text |
| SF Pro / `system-ui` | Custom display fonts or inter-as-brand |
| Mono for codes, paths, versions | Mono for body copy or button labels |
| Checklist + tip strips for delight | Mascots, confetti, emoji explosions |
| WCAG AA text/button contrast | Low-contrast muted-on-muted labels |
| `prefers-reduced-motion` respect | Endless bounce animations |

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

## Screen map

Local companion-owned screens (not the remote hub `/ui`):

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

| Screen ID | Name | Purpose |
|-----------|------|---------|
| W | **Welcome** | Explain CLI need; Install / Update / use existing |
| P | **CLI progress** | Determinate install/update with checklist + tips |
| R | **CLI ready** | Confirm version + path; Continue |
| V | **Choose vault** | Selection cards: Local vs Remote |
| U | **Connect URL** | HTTPS vault hub URL + remember |
| D | **Device code** | Large-type device login code for remote hub |
| L | **Local passphrase** | Unlock local vault with passphrase field |
| B | **Vault bar** | Thin companion chrome over remote/local UI |

Returning users may skip Welcome→CLI ready when CLI is current, and may skip Choose vault / URL when preferences are remembered (see product spec).

---

## Related docs

- Colors → [colors.md](./colors.md)
- Type → [typography.md](./typography.md)
- Space → [spacing-sizing.md](./spacing-sizing.md)
- Components → [components.md](./components.md)
- Motion → [motion-feedback.md](./motion-feedback.md)
- Layout → [layout.md](./layout.md)
- Tokens → [tokens.css](./tokens.css)
- Examples → [examples.md](./examples.md)
