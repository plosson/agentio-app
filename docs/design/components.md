# Components

Precise specs for AgentIO Companion local chrome **and** AgentIO vault hub `/ui`. One System Utility Vault language. Colors → [colors.md](./colors.md); type → [typography.md](./typography.md); space → [spacing-sizing.md](./spacing-sizing.md); motion → [motion-feedback.md](./motion-feedback.md); ownership → [ui-ownership.md](./ui-ownership.md).

All interactive components support: **default · hover · active · disabled · busy · focus-visible**.

---

## 1. Window chrome / titlebar

**Anatomy**

```
┌─ [● ○]  drag region ───────────────── title (optional) ── [⋯] ─┐
│  traffic lights (macOS)                                         │
```

| Part | Spec |
|------|------|
| Height | **52px** total including traffic-light safe zone; content starts below with `--space-8` (40px) top padding in wizard **or** use `titleBarStyle: 'hiddenInset'` with ~28–32px drag strip |
| Drag | `-webkit-app-region: drag` on chrome; `no-drag` on buttons |
| Background | `--color-bg` (same as canvas — no separate slate bar) |
| Border bottom | none in onboarding; vault mode may use `1px solid var(--color-border)` under vault bar |
| Title text | Caption / tertiary; often omitted (window title set in Electron) |

**States:** chrome is non-interactive except menu `⋯` (ghost icon button, 32×32 hit).

---

## 2. Wizard shell

**Not** a floating slate card. Full-window zinc canvas + centered column.

```
┌────────────────────────────────────────┐
│ titlebar                                │
│                                         │
│         ┌─ column 420px ─┐              │
│         │  mark           │              │
│         │  title          │              │
│         │  body           │              │
│         │  …controls…     │              │
│         └─────────────────┘              │
│                                         │
└────────────────────────────────────────┘
```

| Property | Token / value |
|----------|---------------|
| Canvas | `--color-bg` |
| Column | `width: min(var(--layout-column), 100%); margin-inline: auto; padding-inline: var(--space-6)` |
| Vertical align | Content optically centered in remaining viewport; prefer `padding-block: var(--space-8) var(--space-9)` over absolute center if keyboard/field focus shifts |
| Card chrome | **None** — no `--color-bg-elevated` wrapper around the whole wizard |

---

## 3. App mark / keyhole icon

| Property | Value |
|----------|-------|
| Size | 40×40 |
| Treatment | Monochrome glyph using `--color-text`, or teal keyhole using `--color-accent` at ≤40% of mark area |
| Container | Optional 40×40 with `--radius-control`, bg `--color-bg-elevated`, border `1px solid var(--color-border)` |
| Shadow | None |
| Placement | Above display title, centered in column |

Do not animate the mark on every screen — optional subtle opacity fade on welcome only (see motion).

---

## 4. Buttons

Shared: font body/button (14px / 600), height **40px**, padding `0 20px`, transition `120ms` colors/opacity.

### 4.1 Primary pill

| State | Background | Text | Border |
|-------|------------|------|--------|
| Default | `--color-text` | Light: `#FFFFFF` / Dark: `--color-bg` | transparent |
| Hover | Light: `#000000` · Dark: `#FFFFFF` | same | transparent |
| Active | 92% opacity of hover | same | transparent |
| Disabled | `--color-text` @ 32% opacity | same @ 32% | transparent |
| Busy | same as default + spinner | hide label or keep + spinner | — |
| Focus | + `outline: 2px solid var(--color-focus-ring); outline-offset: 2px` | | |

Radius: `--radius-pill`. Width: full column **or** hug (min 120px), full-width preferred for primary in wizard.

### 4.2 Secondary outline

| State | Background | Text | Border |
|-------|------------|------|--------|
| Default | transparent | `--color-text` | `1px solid var(--color-border)` |
| Hover | `--color-bg-elevated` | `--color-text` | `--color-border-strong` |
| Active | `--color-bg-subtle` | `--color-text` | `--color-border-strong` |
| Disabled | transparent @ 40% | tertiary | border @ 40% |
| Focus | focus-ring outline | | |

Radius: `--radius-control` (8px) **or** pill if paired under primary — prefer **pill** when stacked with primary for rhythm.

### 4.3 Ghost / link

| State | Appearance |
|-------|------------|
| Default | No fill/border; `--color-text-secondary`; underline on hover optional |
| Hover | `--color-text` |
| Focus | focus-ring |
| Disabled | `--color-text-tertiary` |

Height min 32px; used for “Advanced…”, “Change vault URL”, “Cancel”.

### 4.4 Destructive

Same geometry as secondary; text + border `--color-danger`; hover bg `--color-danger-muted`. Never use as default primary.

**Markup pattern**

```html
<button class="btn btn-primary" type="button">Continue</button>
<button class="btn btn-secondary" type="button">Cancel</button>
<button class="btn btn-ghost" type="button">Change vault URL</button>
<button class="btn btn-danger" type="button">Remove</button>
```

---

## 5. Text fields / password / URL

**Anatomy:** label (caption strong) → input → optional hint / error.

| Property | Value |
|----------|-------|
| Height | 40px |
| Padding | `0 12px` |
| Radius | `--radius-control` |
| Background | `--color-bg-elevated` |
| Border | `1px solid var(--color-border)` |
| Text | `--color-text` / body 14px |
| Placeholder | `--color-text-tertiary` |

| State | Spec |
|-------|------|
| Hover | Border `--color-border-strong` |
| Focus | Border `--color-accent` + focus-ring outline (or 2px accent border without double ring) |
| Disabled | bg `--color-bg-subtle`; opacity 0.6 |
| Error | Border `--color-danger`; hint `--color-danger` caption |
| Busy | readonly + spinner in trailing slot |

**Password:** same; trailing show/hide icon button (32×32, ghost).  
**URL:** `inputmode="url"`; mono optional for value once committed; during edit prefer sans.

```html
<label class="field">
  <span class="field-label">Vault URL</span>
  <input class="field-input" type="url" placeholder="https://vault.example.com" />
  <span class="field-hint">HTTPS required</span>
</label>
```

---

## 6. Checkbox row

| Property | Value |
|----------|-------|
| Row min height | 44px |
| Box | 18×18, radius 4px, border `--color-border` |
| Checked | bg `--color-accent`, check `--color-accent-fg` (or white on light) |
| Label | body 14px `--color-text` |
| Gap | `--space-2` (8px) |

```html
<label class="check-row">
  <input type="checkbox" />
  <span>Remember this URL</span>
</label>
```

---

## 7. Selection cards (Local vs Remote)

Two cards in a vertical stack (gap `--space-3`) or 1-column list.

| Property | Value |
|----------|-------|
| Padding | `--space-5` (20px) |
| Radius | `--radius-card` |
| Background | `--color-bg-elevated` |
| Border | `1px solid var(--color-border)` |
| Title | title or body emphasis 14–16px / 600 |
| Description | caption/body secondary |
| Leading icon | `--icon-lg` (24px) |

| State | Spec |
|-------|------|
| Default | as above |
| Hover | border `--color-border-strong` |
| Selected | border `--color-accent` (1.5–2px); bg `--color-accent-muted` |
| Focus | focus-ring on card (`tabindex="0"` or radio) |
| Disabled | opacity 0.5 |

```html
<div class="choice-stack" role="radiogroup">
  <button class="choice-card" role="radio" aria-checked="true">
    <span class="choice-icon">…</span>
    <span class="choice-title">Local vault</span>
    <span class="choice-desc">Store secrets on this Mac</span>
  </button>
  <button class="choice-card" role="radio" aria-checked="false">…</button>
</div>
```

---

## 8. Status / tip callout

| Variant | Background | Border | Text |
|---------|------------|--------|------|
| Tip | `--color-tip-bg` | none or subtle border | secondary + caption |
| Status | `--color-bg-elevated` | `1px solid var(--color-border)` | text |
| Success | `--color-ok-muted` | none | `--color-ok` label |
| Error | `--color-danger-muted` | none | `--color-danger` |

Padding: `12px 14px`; radius `--radius-card`; optional leading 16px icon.

---

## 9. Login / device code (large type)

| Property | Value |
|----------|-------|
| Type | `--text-mono-display` (32px / 600 / tracking 0.08em) |
| Color | `--color-text` |
| Alignment | center |
| Grouping | e.g. `ABCD-EFGH` with hyphen in tertiary |
| Container | optional elevated card, padding `--space-5`, radius `--radius-card` |
| Helper | caption secondary below (“Enter this code in your browser”) |

Do not blur or skeleton the code while loading — show spinner elsewhere until code exists.

---

## 10. Vault companion bar

Thin strip above `BrowserView` / vault content.

| Property | Value |
|----------|-------|
| Height | `--vault-bar-height` **40px** |
| Background | `--color-bg-elevated` or `--color-bg` |
| Border bottom | `1px solid var(--color-border)` |
| Left | host label (mono 13px / secondary) or app mark 16px + title caption |
| Right | ghost icon buttons: menu, reload (optional), disconnect |
| Drag | bar is drag region except controls |

```
┌─ [host mono] ─────────────── [⋯] ─┐  40px
├───────────────────────────────────┤
│         BrowserView /ui           │
```

---

## 11. Checklist step rows

| Property | Value |
|----------|-------|
| Row gap | `--space-2` |
| Icon | 16px circle: pending tertiary border; active accent spinner/dot; done `--color-ok` check |
| Label pending | text-secondary / 500 |
| Label active | text / 600 |
| Label done | text-secondary / 500 + optional strikethrough **off** (prefer check only) |

```html
<ul class="checklist">
  <li data-state="done">Downloaded release</li>
  <li data-state="active">Verifying checksum</li>
  <li data-state="pending">Installing binary</li>
</ul>
```

---

## 12. Progress bar + % display

| Property | Value |
|----------|-------|
| Track height | `--progress-height` **6px** |
| Track | `--color-progress-track`, radius `--radius-progress` |
| Fill | `--color-progress-fill`, width = % |
| Label | caption, e.g. `47%`, `--color-text-secondary` |
| Layout | bar full width; % above-right or inline end |

Indeterminate: sliding 30% chunk (see motion) — only when % unknown.

---

## 13. Spinner (teal ring)

| Property | Value |
|----------|-------|
| Size | `--icon-spinner` **20px** (16px in buttons) |
| Stroke | 2px |
| Color | `--color-accent` arc on `--color-border` track |
| Speed | 0.7s linear infinite |
| Reduced motion | static arc at 120° or hide and use “Working…” text |

Used in: busy primary button, CLI progress active step, vault bar connecting.

---



---

## Hub components (vault `/ui`)

Implement in `plosson/agentio` `src/daemon/ui/index.html`. Map to shared tokens (teal accent, soft zinc, radius 8–10px). Do **not** use `#0969da`.

### 14. Hub header + tabs

```
┌─ [AgentIO vault]  [Profiles] [API keys] [Settings] ──── meta ─┐
│  surface bg · 1px bottom border · matches companion vault bar │
```

| Part | Spec |
|------|------|
| Background | `--color-bg-elevated` / hub `--surface` |
| Border bottom | `1px solid var(--color-border)` |
| Title | ~18px / 600; `--color-text` |
| Tab | body 14px / 500; secondary text; padding 0 12px; stretch to header height |
| Tab hover | `--color-text` |
| Tab active | `--color-text` + `border-bottom: 2px solid var(--color-accent)` |
| Meta | caption / secondary |

### 15. Profile / key table

| Part | Spec |
|------|------|
| Card wrap | elevated surface, `1px` border, `--radius-control` or `--radius-hub` (~8–10px), quiet shadow |
| `thead th` | bg `--color-table-header`; secondary caption weight 500 |
| Row border | `--color-bg-subtle` / `--border-light` |
| Primary cell | semibold text; secondary line caption |
| Empty state | centered secondary, generous padding |

### 16. Chips (service filters)

| State | Spec |
|-------|------|
| Default | pill; border `--color-border`; bg `--color-chip-bg` / surface; text secondary |
| Hover | text → `--color-text` |
| Active | border + text `--color-accent`; bg `--color-accent-muted` |
| Invalid emphasis | text `--color-danger`; weight 600 |

### 17. Badges

| Variant | Background | Color |
|---------|------------|-------|
| ok | `--color-ok-muted` | `--color-ok` |
| invalid / error | `--color-danger-muted` | `--color-danger` |
| no-creds / warn | `--color-warn-muted` | `--color-warn` |
| skipped | table-header / code-bg | tertiary |
| testing | `--color-accent-muted` | `--color-accent` |

Pill radius; 12px / 600; padding `2px 8px`.

### 18. Setting rows

| Property | Value |
|----------|-------|
| Layout | flex space-between; gap 24px; padding 16px 0 |
| Divider | top border `--color-bg-subtle` (skip first) |
| Title | strong ~15px |
| Description | body secondary |
| Control | switch (checked = accent) or secondary/danger button |

Danger card: border `--color-danger`; heading danger colored.

### 19. Dialogs

| Property | Value |
|----------|-------|
| Panel | elevated; border; radius `--radius-card` (12px); padding 24px; max width ~480 |
| Backdrop | `--color-dialog-backdrop` / `--color-overlay` |
| Title | 18px / 600 |
| Body | 14px secondary |
| Actions | row end; primary = CTA pills; destructive solid uses danger |

### 20. Toasts

| Property | Value |
|----------|-------|
| Position | fixed bottom-right stack |
| Default | bg `--color-text`; fg inverted canvas; radius control; quiet shadow |
| Error | bg `--color-danger`; fg white |

### 21. Authorize code display

Same language as companion device code:

| Property | Value |
|----------|-------|
| Type | large mono (`--text-mono-display` or ≥1.5–2rem / 600 / tracking ~0.08–0.1em) |
| Color | `--color-text` |
| Class | hub `.code` — prefer larger type to match companion |

### 22. Unlock view

Centered ~400px column; soft mark in accent-muted circle; title + secondary body; passphrase field; full-width primary CTA (near-black pill). Matches companion local passphrase calm — no GitHub-blue hero.

## State checklist (all controls)

| State | Required behavior |
|-------|-------------------|
| default | Resting tokens |
| hover | Darken/lighten or border strengthen per above |
| active | Pressed (opacity or subtle bg) |
| disabled | ≥40% opacity reduction; `cursor: not-allowed`; no hover |
| busy | Spinner; prevent double-submit |
| focus | `:focus-visible` only; teal ring; keyboard path |
