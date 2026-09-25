# Colors

Semantic tokens for AgentIO Companion. **Never hard-code hex in components** — use the CSS variables from [`tokens.css`](./tokens.css).

**Locked anchors**

- Light canvas: `#F5F5F7`
- Brand accent: `#0F766E` (teal — sparse use)
- Primary CTA fill (light): near-black `#1D1D1F` (maps to `--text` on light; see buttons)
- Away from: slate `#0f172a` / `#1e293b`, sky `#38bdf8`

---

## Semantic tokens

### Light (`:root`)

| Token | CSS variable | Hex / value | Usage |
|-------|--------------|-------------|-------|
| bg | `--color-bg` | `#F5F5F7` | Window / wizard canvas |
| bg-elevated | `--color-bg-elevated` | `#FFFFFF` | Inputs, selection cards, tip strips |
| bg-subtle | `--color-bg-subtle` | `#E8E8ED` | Checkbox wells, progress track siblings, inset rows |
| border | `--color-border` | `#D2D2D7` | Default control & card borders |
| border-strong | `--color-border-strong` | `#A1A1A6` | Hover borders, emphasis dividers |
| text | `--color-text` | `#1D1D1F` | Titles, primary labels, primary CTA fill (light) |
| text-secondary | `--color-text-secondary` | `#6E6E73` | Body supporting copy |
| text-tertiary | `--color-text-tertiary` | `#8E8E93` | Hints, chrome labels, timestamps |
| accent | `--color-accent` | `#0F766E` | Focus ring, progress fill, spinner, selected accent |
| accent-muted | `--color-accent-muted` | `#E6F4F2` | Selected card wash, soft accent chip bg |
| accent-fg | `--color-accent-fg` | `#FFFFFF` | Text/icons on solid accent (rare) |
| danger | `--color-danger` | `#DC2626` | Errors, destructive labels |
| danger-muted | `--color-danger-muted` | `#FEE2E2` | Error callout background |
| ok | `--color-ok` | `#16A34A` | Success checkmarks, ready state |
| ok-muted | `--color-ok-muted` | `#DCFCE7` | Success callout background |
| focus-ring | `--color-focus-ring` | `#0F766E` | `:focus-visible` outline color |
| selection | `--color-selection` | `rgba(15, 118, 110, 0.18)` | Text selection highlight |
| tip-bg | `--color-tip-bg` | `#EEF0F4` | Tip strip background |
| progress-track | `--color-progress-track` | `#E5E5EA` | Progress bar track |
| progress-fill | `--color-progress-fill` | `#0F766E` | Progress bar fill |
| overlay | `--color-overlay` | `rgba(0, 0, 0, 0.36)` | Modal/sheet scrim |

### Dark (`prefers-color-scheme: dark` or `[data-theme="dark"]`)

Cohesive twin of the light zinc / teal system — slightly lifted surfaces, brighter teal for contrast on dark canvas.

| Token | CSS variable | Hex / value | Usage |
|-------|--------------|-------------|-------|
| bg | `--color-bg` | `#1C1C1E` | Window / wizard canvas |
| bg-elevated | `--color-bg-elevated` | `#2C2C2E` | Inputs, cards, tip strips |
| bg-subtle | `--color-bg-subtle` | `#232326` | Inset rows, wells |
| border | `--color-border` | `#3A3A3C` | Default borders |
| border-strong | `--color-border-strong` | `#636366` | Hover / emphasis |
| text | `--color-text` | `#F5F5F7` | Titles, primary labels, primary CTA fill (dark = near-white) |
| text-secondary | `--color-text-secondary` | `#A1A1A6` | Body supporting copy |
| text-tertiary | `--color-text-tertiary` | `#8E8E93` | Hints, chrome |
| accent | `--color-accent` | `#2DD4BF` | Focus, progress, spinner (brighter twin of `#0F766E`) |
| accent-muted | `--color-accent-muted` | `#134E4A` | Selected card wash |
| accent-fg | `--color-accent-fg` | `#042F2E` | Text on solid accent fills in dark (if used) |
| danger | `--color-danger` | `#F87171` | Errors |
| danger-muted | `--color-danger-muted` | `#450A0A` | Error callout bg |
| ok | `--color-ok` | `#4ADE80` | Success |
| ok-muted | `--color-ok-muted` | `#052E16` | Success callout bg |
| focus-ring | `--color-focus-ring` | `#2DD4BF` | Focus outline |
| selection | `--color-selection` | `rgba(45, 212, 191, 0.28)` | Selection |
| tip-bg | `--color-tip-bg` | `#2A2A2E` | Tip strip |
| progress-track | `--color-progress-track` | `#3A3A3C` | Track |
| progress-fill | `--color-progress-fill` | `#2DD4BF` | Fill |
| overlay | `--color-overlay` | `rgba(0, 0, 0, 0.56)` | Scrim |

### Primary CTA mapping (not separate semantic colors)

| Theme | Primary button background | Primary button label |
|-------|---------------------------|----------------------|
| Light | `--color-text` (`#1D1D1F`) | `--color-bg-elevated` (`#FFFFFF`) |
| Dark | `--color-text` (`#F5F5F7`) | `--color-bg` (`#1C1C1E`) |

Secondary / ghost / destructive use border + text / danger tokens — see [components.md](./components.md).

---

## Contrast notes (WCAG AA)

Targets: **≥ 4.5:1** for body text; **≥ 3:1** for large text (≥18px/14px bold) and non-text UI (icons, focus, progress).

| Pair (light) | Approx ratio | OK for |
|--------------|--------------|--------|
| `#1D1D1F` on `#F5F5F7` | ~16:1 | Body, titles |
| `#6E6E73` on `#F5F5F7` | ~4.6:1 | Secondary body (AA) |
| `#8E8E93` on `#F5F5F7` | ~3.2:1 | Tertiary / chrome only (large or non-essential) |
| `#FFFFFF` on `#1D1D1F` | ~16:1 | Primary CTA label |
| `#0F766E` on `#F5F5F7` | ~5.5:1 | Accent text / links |
| `#FFFFFF` on `#0F766E` | ~4.7:1 | Text on accent (rare) |

| Pair (dark) | Approx ratio | OK for |
|-------------|--------------|--------|
| `#F5F5F7` on `#1C1C1E` | ~15:1 | Body, titles |
| `#A1A1A6` on `#1C1C1E` | ~7:1 | Secondary |
| `#1C1C1E` on `#F5F5F7` | ~15:1 | Primary CTA label on dark |
| `#2DD4BF` on `#1C1C1E` | ~9:1 | Accent text / progress |

**Rules**

- Do not use `--color-text-tertiary` for essential instructions or error text.
- Destructive text (`--color-danger`) on `--color-bg` must remain AA; pair with `--color-danger-muted` backgrounds for callouts.
- Focus ring must meet **3:1** against adjacent bg (teal on zinc satisfies).

---

## Never-use list

| Forbidden | Why |
|-----------|-----|
| Sky cyan `#38bdf8` / `#7dd3fc` as primary or accent | Old renderer palette; fights System Utility direction |
| Slate panels `#0f172a`, `#1e293b`, `#334155` | SaaS “dark card” look |
| Random gradients (purple→blue, mesh, aurora) | Marketing, not utility |
| Pure black `#000000` full-bleed backgrounds | Harsh vs soft zinc twin |
| Accent as primary CTA fill by default | Teal is sparse; CTAs are near-black / near-white |
| Low-contrast gray-on-gray body | Fails AA; use secondary/tertiary rules |
| Colored shadows (glow cyan/teal) | No neon chrome |

If a new color is required, add a **named semantic token** here and in `tokens.css` — do not sprinkle one-off hex in components.
