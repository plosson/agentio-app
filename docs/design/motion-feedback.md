# Motion & feedback

Delight comes from **honest progress**, checklists, rotating status copy, and tip strips — not mascots or confetti.

---

## Durations & easing

| Token | Ms | Easing | Use |
|-------|----|--------|-----|
| `--motion-fast` | **120ms** | `cubic-bezier(0.2, 0.8, 0.2, 1)` | Hover, button color, border |
| `--motion-base` | **200ms** | `cubic-bezier(0.2, 0.8, 0.2, 1)` | Fade in tip, step complete |
| `--motion-slow` | **320ms** | `cubic-bezier(0.2, 0.8, 0.2, 1)` | Screen cross-fade |
| `--motion-spinner` | **700ms** | `linear` | Teal ring rotation |
| `--motion-indeterminate` | **1200ms** | `ease-in-out` | Indeterminate bar loop |

Prefer opacity + transform (translateY ≤ 4px). Avoid bounce/spring overshoot on utility chrome.

---

## Determinate vs indeterminate

| Situation | Mode |
|-----------|------|
| CLI download with known Content-Length / progress events | **Determinate** bar + integer `%` |
| Checksum / unpack with measurable steps | Determinate by **step index** (checklist) + optional bar |
| Waiting on network with no bytes | **Indeterminate** bar **or** spinner + status string — never fake % |
| Device code polling | Spinner + rotating status; no % |

Never jump to 100% before success beat. Cap UI at 99% until the process confirms completion, then animate to 100% in ≤200ms and run success beat.

---

## CLI install checklist

Recommended steps (labels may vary slightly by install vs update):

1. Fetching latest release  
2. Verifying checksum  
3. Installing binary  
4. Linking on PATH / verifying `agentio --version`

**Row states:** `pending` → `active` → `done` (or `error`). Only one `active` at a time. Completing a step: 200ms check fade-in.

### Example rotating status strings

Rotate every **2.5–3.5s** while a step is active (fade 200ms). Pause rotation on error.

**Fetching**

- “Fetching latest release for macOS arm64…”
- “Talking to GitHub Releases…”
- “Downloading agentio package…”

**Verifying**

- “Checking SHA-256…”
- “Making sure the download wasn’t corrupted…”

**Installing**

- “Writing binary into Application Support…”
- “Setting executable permissions…”
- “Almost there — registering the CLI…”

**Verifying install**

- “Running `agentio --version`…”
- “Confirming the CLI responds…”

### Tip strip examples

Show below the bar; rotate less often (**8–12s**) or pin one tip per session phase.

- “Nothing is bundled inside this app — we install the real CLI once.”
- “You can use a self-hosted hub or a hosted vault URL the same way.”
- “OAuth for services always runs locally on your Mac (ports 3000–3010).”
- “Tip: keep this window open until the checklist finishes.”

Tips use `--color-tip-bg` + caption type. No emoji spam (one subtle leading icon OK).

---

## Success beat rules

On CLI ready / unlock success / vault connected:

1. Progress hits **100%** or checklist all `done` (≤200ms).  
2. Brief **ok** flash: check icon scale 0.92→1.0 @ 200ms; optional status callout `--color-ok-muted`.  
3. Hold **400–600ms** so the user can read “AgentIO CLI is ready”.  
4. Enable primary **Continue** (or auto-advance only if product spec says so — default is manual Continue).

No confetti, no full-screen green wash, no haptic assumptions.

---

## Button busy

- Replace or prefix label with 16px teal spinner.  
- Keep button width stable (min-width from idle label).  
- `aria-busy="true"`; ignore further clicks.  
- On failure: restore label, show error callout, focus retry.

---

## Screen transitions

| Transition | Spec |
|------------|------|
| Wizard step forward | Cross-fade 200–320ms; optional 4px upward drift on entering content |
| Back | Same, reverse drift |
| To vault mode | Fade wizard out 200ms; vault bar + BrowserView fade in |

Do not slide entire windows; Electron window size may change without animated CSS.

---

## Reduced-motion policy

When `prefers-reduced-motion: reduce`:

| Effect | Fallback |
|--------|----------|
| Spinner rotation | Static teal arc or text “Working…” |
| Indeterminate bar | Static track + caption “In progress” |
| Status string rotation | Show first string only; update on real phase change |
| Step check animation | Instant state swap |
| Screen cross-fade | Instant cut (0–50ms max) |
| Success scale | Instant check appearance |

Still update **content** promptly — reduced motion is not reduced feedback.

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

Prefer finer-grained overrides (disable spinner animation only) so focus rings still ease if desired — either approach is acceptable if documented in renderer.
