# Spacing & sizing

Everything snaps to a **4px base grid**. Prefer tokenized spacing over magic numbers.

---

## Spacing scale

| Token | Rem | Px | Common use |
|-------|-----|----|------------|
| `--space-0` | 0 | 0 | Reset |
| `--space-1` | 0.25rem | **4px** | Icon gaps, tight inline |
| `--space-2` | 0.5rem | **8px** | Label → field, checklist icon gap |
| `--space-3` | 0.75rem | **12px** | Compact stack, tip padding-y |
| `--space-4` | 1rem | **16px** | Default stack gap, field padding-x |
| `--space-5` | 1.25rem | **20px** | Card padding, section gaps |
| `--space-6` | 1.5rem | **24px** | Wizard vertical rhythm |
| `--space-7` | 2rem | **32px** | Title → body, major section break |
| `--space-8` | 2.5rem | **40px** | Top safe area under titlebar |
| `--space-9` | 3rem | **48px** | Large empty breathing room |
| `--space-10` | 4rem | **64px** | Rare; window edge luxury padding |

---

## Content column

| Token | Value | Notes |
|-------|-------|-------|
| `--layout-column` | **420px** | Max width of onboarding content |
| `--layout-column-padding-x` | **24px** (`--space-6`) | Horizontal inset inside window |
| Effective text width | `min(420px, 100% - 48px)` | Always centered |

Do **not** use the old 560px slate card width.

---

## Window sizes

| Mode | Min width | Min height | Default (suggested) |
|------|-----------|------------|---------------------|
| Onboarding wizard | **480px** | **560px** | 520 × 640 |
| Vault (bar + BrowserView) | **900px** | **640px** | 1100 × 760 |

See [layout.md](./layout.md) for traffic lights and drag regions.

---

## Radii

| Token | Px | Use |
|-------|----|-----|
| `--radius-control` | **8px** | Text fields, checkboxes container, secondary buttons |
| `--radius-card` | **12px** | Selection cards, tip/status callouts |
| `--radius-pill` | **999px** | Primary CTA pills, ghost pills |
| `--radius-window` | **0px** | Electron window (OS-controlled); do not fake window radius in CSS |
| `--radius-progress` | **4px** | Progress bar track/fill |

---

## Border widths

| Token | Value | Use |
|-------|-------|-----|
| `--border-width` | **1px** | Default borders |
| `--border-width-strong` | **1.5px** | Selected card ring (or 2px if subpixel issues) |
| Focus outline | `2px solid var(--color-focus-ring)` | Offset `2px` |

---

## Vault companion bar

| Token | Value |
|-------|-------|
| `--vault-bar-height` | **40px** |
| Bar horizontal padding | `12px` (`--space-3`) |
| Bar icon buttons | 28×28 hit, 16px icon |

---

## Icon sizes

| Token | Px | Use |
|-------|----|-----|
| `--icon-sm` | **14px** | Inline status, checklist pending |
| `--icon-md` | **16px** | Buttons, bar actions |
| `--icon-lg` | **24px** | Selection card leading icon |
| `--icon-xl` | **40px** | App mark / keyhole on welcome |
| `--icon-spinner` | **20px** | Teal ring spinner |

Stroke weight for outline icons: **1.5–2px** at 16–24px size.

---

## Hit targets

| Context | Minimum |
|---------|---------|
| Primary / secondary buttons | **height 40px**, width ≥ 120px or hug + 24px pad |
| Desktop compact controls (bar, ghost links) | **min 32×32px** |
| Preferred touch-friendly (checkboxes, cards) | **min 44×44px** tap area (padding may extend beyond visual) |
| Text field height | **40px** |
| Checkbox visual box | 18×18 inside 44px-tall row |

---

## Progress bar

| Token | Value |
|-------|-------|
| `--progress-height` | **6px** |
| Width | 100% of content column |
| `%` caption | Caption type, right-aligned or inline after bar with `--space-2` gap |

---

## App mark

| Property | Value |
|----------|-------|
| Mark size | 40×40 (`--icon-xl`) |
| Corner radius on mark container | `--radius-control` (8px) or circle if glyph is circular |
| Gap mark → title | `--space-4` (16px) |
