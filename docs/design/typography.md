# Typography

AgentIO Companion uses the **system type stack** so the app reads as a macOS utility, not a branded web app.

---

## Font stacks

### UI (sans)

```css
--font-sans: "SF Pro Text", "SF Pro Display", -apple-system, BlinkMacSystemFont,
  "Segoe UI", system-ui, Helvetica, Arial, sans-serif;
```

- Prefer **SF Pro** on macOS (Electron resolves via `-apple-system` / system).
- Do not bundle Inter, Roboto, or custom display fonts for v1.
- Optical sizing: use SF Pro Display metrics only via system; we do not ship separate face files.

### Mono

```css
--font-mono: "SF Mono", ui-monospace, Menlo, Monaco, "Cascadia Code",
  "Roboto Mono", Consolas, "Liberation Mono", monospace;
```

---

## Scale

Base root: `html { font-size: 16px; }` → `1rem = 16px`.

| Role | Token | Size | Weight | Line-height | Letter-spacing | Use |
|------|-------|------|--------|-------------|----------------|-----|
| Display | `--text-display` | `1.75rem` / **28px** | 600 | 1.25 (`35px`) | `-0.02em` | Welcome title, CLI ready headline |
| Title | `--text-title` | `1.25rem` / **20px** | 600 | 1.30 (`26px`) | `-0.015em` | Screen titles (Connect, Unlock, Choose vault) |
| Body | `--text-body` | `0.875rem` / **14px** | 400 | 1.50 (`21px`) | `0` | Instructions, descriptions |
| Body emphasis | — | `0.875rem` / **14px** | 600 | 1.50 | `0` | Inline strong labels inside body |
| Caption | `--text-caption` | `0.75rem` / **12px** | 400 | 1.40 (`17px`) | `0.01em` | Chrome, hints, tip strip, % label |
| Caption strong | — | `0.75rem` / **12px** | 560–600 | 1.40 | `0.01em` | Section labels over fields |
| Mono body | `--text-mono` | `0.8125rem` / **13px** | 500 | 1.40 | `0` | Paths, versions, URLs in secondary lines |
| Mono display | `--text-mono-display` | `2rem` / **32px** | 600 | 1.20 | `0.08em` | Device / login code (large type) |
| Button | — | `0.875rem` / **14px** | 600 | 1 | `0` | All button labels |

CSS variables for sizes/line-heights are defined in [`tokens.css`](./tokens.css).

---

## Weights

| Weight | Value | Typical use |
|--------|-------|-------------|
| Regular | 400 | Body, caption |
| Medium | 500 | Mono paths, checklist pending labels |
| Semibold | 600 | Display, title, buttons, checklist done |
| Avoid | ≥700 | Too heavy for utility chrome; don’t use Black |

---

## When to use mono

**Mono only for:**

- Device / login codes (large mono display)
- File paths and install locations
- CLI version strings (`agentio 1.4.0`)
- Exact URLs shown as data (vault host line)
- Progress technical detail lines if needed

**Never mono for:**

- Screen titles or body instructions
- Button labels
- Tip strip prose
- Selection card titles (“Local vault”, “Remote vault”)

---

## Truncation & wrapping

- Body and titles: wrap naturally; max width = content column (420px).
- Paths / URLs: single line + ellipsis (`text-overflow: ellipsis`) when needed; full value in `title` tooltip.
- Device code: never truncate; allow wrap only at group boundaries if code is grouped (e.g. `ABCD-EFGH`).

---

## Color pairing

| Role | Color token |
|------|-------------|
| Display / title | `--color-text` |
| Body | `--color-text-secondary` (default) or `--color-text` for critical lines |
| Caption / chrome | `--color-text-tertiary` |
| Mono data | `--color-text` or `--color-text-secondary` |
| Links (sparse) | `--color-accent` |
| Errors | `--color-danger` |
| Success labels | `--color-ok` |
