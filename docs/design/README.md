# AgentIO Companion — Design System

**Product:** AgentIO Companion (native macOS app, Swift/SwiftUI)  
**Visual direction:** System Utility Vault  
**Status:** Source of truth for companion chrome & onboarding UI  
**Spec:** [docs/plans/companion-spec.md](../plans/companion-spec.md)

This folder is the single look-and-feel contract for implementers. Prefer these docs over ad-hoc choices in `apps/macos`. When rendering UI, use the `Theme` tokens in `apps/macos/CompanionUI/Theme.swift` (which mirror [`tokens.css`](./tokens.css)) and match component anatomy in [`components.md`](./components.md).

---

## How to use this system

1. **Read the vibe** — skim [overview.md](./overview.md) principles and do/don't before touching layout or color.
2. **Use tokens** — SwiftUI code uses `Theme`, which copies the values of [`tokens.css`](./tokens.css). Do not invent new hex values; add a token to `tokens.css` and `Theme.swift` together and document it here.
3. **Build screens from components** — use [`components.md`](./components.md) + [`layout.md`](./layout.md); copy markup patterns from [`examples.md`](./examples.md).
4. **Motion last** — follow [`motion-feedback.md`](./motion-feedback.md) for progress, checklists, busy states, and `prefers-reduced-motion`.

### Tokens in the app

`tokens.css` is the source of truth for values. `apps/macos/CompanionUI/Theme.swift` copies its light and dark colours, type sizes and control sizes; the app follows the system appearance.

---

## Vibe one-pager — System Utility Vault

| Trait | Meaning |
|-------|---------|
| **OS-embedded** | Feels like macOS System Settings or a native utility, not a SaaS dashboard in a window. |
| **Soft zinc field** | Full-window `#F5F5F7` (light) / dark twin — no floating slate card on a void. |
| **Narrow wizard** | Centered ~420px content column; generous quiet margins. |
| **One brand accent** | Teal `#0F766E` — progress, focus, spinner, sparse highlights only. |
| **Honest primary CTAs** | Near-black pills (light) / near-white (dark). Never sky-cyan primary buttons. |
| **Quiet chrome** | Thin titlebar / vault bar; traffic lights respected; no heavy shadows or gradients. |
| **Fun via craft** | Motion, step checklists, rotating status copy, tip strips — not mascots or confetti. |

Away from: slate `#0f172a` / `#1e293b` panels, sky `#38bdf8` primaries, random gradients, SaaS “glass card” stacks.

---

## Document index

| Doc | Contents |
|-----|----------|
| [overview.md](./overview.md) | Principles, do/don't, screen map |
| [colors.md](./colors.md) | Light/dark semantic tokens, hex, WCAG, never-use |
| [typography.md](./typography.md) | SF Pro / system stack, scale, mono rules |
| [spacing-sizing.md](./spacing-sizing.md) | 4px grid, column, radii, hit targets, vault bar |
| [components.md](./components.md) | Anatomy & states for every UI piece |
| [motion-feedback.md](./motion-feedback.md) | Durations, CLI checklist, tips, reduced motion |
| [layout.md](./layout.md) | Window sizes, titlebar, onboarding vs vault mode |
| [tokens.css](./tokens.css) | Ready-to-import CSS custom properties |
| [examples.md](./examples.md) | HTML/CSS snippets using tokens only |

---

## Ownership

- Design tokens & guidelines: this folder (`docs/design/`).
- Product behavior & screen flow: `docs/plans/companion-spec.md`.
- Implementation: `apps/macos` (`Theme.swift` mirrors these tokens).
