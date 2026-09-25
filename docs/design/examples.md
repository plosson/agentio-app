# Examples

Short HTML/CSS snippets using **tokens only**. These are reference patterns for implementers — not a second design system.

Assume `tokens.css` is loaded. Class names are illustrative.

---

## Welcome

```html
<main class="wizard">
  <div class="column">
    <div class="mark" aria-hidden="true"><!-- keyhole SVG --></div>
    <h1 class="display">Welcome to AgentIO Companion</h1>
    <p class="body">
      To add services to a vault, this Mac needs the AgentIO CLI.
      We’ll install (or update) the latest release. Nothing is bundled inside this app.
    </p>
    <div class="status">
      <span class="caption">Status</span>
      <p class="body-strong">CLI not found</p>
    </div>
    <div class="actions">
      <button class="btn btn-primary" type="button">Install latest AgentIO</button>
      <button class="btn btn-ghost" type="button">Advanced: use existing CLI on PATH…</button>
    </div>
  </div>
</main>
```

```css
.wizard {
  min-height: 100%;
  background: var(--color-bg);
  color: var(--color-text);
  font-family: var(--font-sans);
  padding: var(--space-8) var(--layout-column-padding-x) var(--space-9);
}
.column {
  width: min(var(--layout-column), 100%);
  margin-inline: auto;
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}
.mark {
  width: var(--icon-xl);
  height: var(--icon-xl);
  border-radius: var(--radius-control);
  border: var(--border-width) solid var(--color-border);
  background: var(--color-bg-elevated);
  color: var(--color-accent);
}
.display {
  margin: 0;
  font-size: var(--text-display);
  font-weight: var(--font-weight-semibold);
  line-height: var(--text-display-lh);
  letter-spacing: var(--text-display-tracking);
}
.body {
  margin: 0;
  font-size: var(--text-body);
  line-height: var(--text-body-lh);
  color: var(--color-text-secondary);
}
.body-strong {
  margin: 0;
  font-size: var(--text-body);
  font-weight: var(--font-weight-semibold);
  color: var(--color-text);
}
.caption {
  font-size: var(--text-caption);
  line-height: var(--text-caption-lh);
  letter-spacing: var(--text-caption-tracking);
  color: var(--color-text-tertiary);
}
.status {
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius-card);
  background: var(--color-bg-elevated);
  border: var(--border-width) solid var(--color-border);
}
.actions {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  margin-top: var(--space-2);
}
.btn {
  appearance: none;
  height: var(--control-height);
  padding: 0 var(--space-5);
  font-size: var(--text-body);
  font-weight: var(--font-weight-semibold);
  font-family: inherit;
  cursor: pointer;
  transition: background-color var(--motion-fast) var(--ease-standard),
    border-color var(--motion-fast) var(--ease-standard),
    color var(--motion-fast) var(--ease-standard),
    opacity var(--motion-fast) var(--ease-standard);
}
.btn:focus-visible {
  outline: 2px solid var(--color-focus-ring);
  outline-offset: 2px;
}
.btn-primary {
  border: none;
  border-radius: var(--radius-pill);
  background: var(--color-cta-bg);
  color: var(--color-cta-fg);
}
.btn-primary:hover:not(:disabled) {
  filter: brightness(1.08);
}
.btn-ghost {
  border: none;
  border-radius: var(--radius-pill);
  background: transparent;
  color: var(--color-text-secondary);
}
.btn-ghost:hover:not(:disabled) {
  color: var(--color-text);
}
```

---

## CLI progress (47%)

```html
<main class="wizard">
  <div class="column">
    <h1 class="title">Setting up AgentIO CLI</h1>
    <p class="body status-line" aria-live="polite">Fetching latest release for macOS arm64…</p>

    <div class="progress-block">
      <div class="progress-meta">
        <span class="caption">Downloading</span>
        <span class="caption pct">47%</span>
      </div>
      <div class="progress" role="progressbar" aria-valuenow="47" aria-valuemin="0" aria-valuemax="100">
        <div class="progress-fill" style="width: 47%"></div>
      </div>
    </div>

    <ul class="checklist">
      <li data-state="done">Downloaded release</li>
      <li data-state="active">Verifying checksum</li>
      <li data-state="pending">Installing binary</li>
      <li data-state="pending">Confirming version</li>
    </ul>

    <aside class="tip">
      <p class="caption">Tip: Nothing is bundled inside this app — we install the real CLI once.</p>
    </aside>

    <button class="btn btn-ghost" type="button">Cancel</button>
  </div>
</main>
```

```css
.title {
  margin: 0;
  font-size: var(--text-title);
  font-weight: var(--font-weight-semibold);
  line-height: var(--text-title-lh);
  letter-spacing: var(--text-title-tracking);
}
.progress-meta {
  display: flex;
  justify-content: space-between;
  margin-bottom: var(--space-2);
}
.pct {
  font-variant-numeric: tabular-nums;
  color: var(--color-text-secondary);
}
.progress {
  height: var(--progress-height);
  border-radius: var(--radius-progress);
  background: var(--color-progress-track);
  overflow: hidden;
}
.progress-fill {
  height: 100%;
  background: var(--color-progress-fill);
  border-radius: var(--radius-progress);
  transition: width var(--motion-base) var(--ease-standard);
}
.checklist {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  font-size: var(--text-body);
}
.checklist li[data-state="done"] { color: var(--color-text-secondary); }
.checklist li[data-state="active"] {
  color: var(--color-text);
  font-weight: var(--font-weight-semibold);
}
.checklist li[data-state="pending"] { color: var(--color-text-tertiary); }
.tip {
  padding: var(--space-3) var(--space-4);
  border-radius: var(--radius-card);
  background: var(--color-tip-bg);
}
.tip .caption { color: var(--color-text-secondary); margin: 0; }
```

---

## Device code

```html
<main class="wizard">
  <div class="column" style="text-align: center">
    <h1 class="title">Device login</h1>
    <p class="body">Enter this code to authorize this Mac with your vault hub.</p>

    <div class="code-panel" aria-label="Device code">
      <p class="device-code">ABCD-EFGH</p>
    </div>

    <p class="caption" aria-live="polite">Waiting for approval…</p>
    <div class="spinner" role="status" aria-label="Waiting"></div>

    <button class="btn btn-ghost" type="button">Cancel</button>
  </div>
</main>
```

```css
.code-panel {
  margin: var(--space-4) 0;
  padding: var(--space-5);
  border-radius: var(--radius-card);
  background: var(--color-bg-elevated);
  border: var(--border-width) solid var(--color-border);
}
.device-code {
  margin: 0;
  font-family: var(--font-mono);
  font-size: var(--text-mono-display);
  font-weight: var(--font-weight-semibold);
  line-height: var(--text-mono-display-lh);
  letter-spacing: var(--text-mono-display-tracking);
  color: var(--color-text);
}
.spinner {
  width: var(--icon-spinner);
  height: var(--icon-spinner);
  margin: var(--space-3) auto 0;
  border: 2px solid var(--color-border);
  border-top-color: var(--color-accent);
  border-radius: 50%;
  animation: spin var(--motion-spinner) linear infinite;
}
@keyframes spin {
  to { transform: rotate(360deg); }
}
@media (prefers-reduced-motion: reduce) {
  .spinner { animation: none; border-top-color: var(--color-accent); opacity: 0.8; }
}
```

---

## Choose-vault cards

```html
<main class="wizard">
  <div class="column">
    <h1 class="title">Choose your vault</h1>
    <p class="body">Local stores secrets on this Mac. Remote connects to your hub URL.</p>

    <div class="choice-stack" role="radiogroup" aria-label="Vault type">
      <button class="choice-card" role="radio" aria-checked="true" type="button">
        <span class="choice-title">Local vault</span>
        <span class="choice-desc">Encrypted vault file on this Mac. Unlock with your passphrase.</span>
      </button>
      <button class="choice-card" role="radio" aria-checked="false" type="button">
        <span class="choice-title">Remote vault</span>
        <span class="choice-desc">Self-hosted or hosted hub. Sign in with device code, then open /ui.</span>
      </button>
    </div>

    <button class="btn btn-primary" type="button">Continue</button>
  </div>
</main>
```

```css
.choice-stack {
  display: flex;
  flex-direction: column;
  gap: var(--space-3);
  margin: var(--space-2) 0 var(--space-4);
}
.choice-card {
  text-align: left;
  padding: var(--space-5);
  border-radius: var(--radius-card);
  background: var(--color-bg-elevated);
  border: var(--border-width) solid var(--color-border);
  color: var(--color-text);
  cursor: pointer;
  font-family: inherit;
  display: flex;
  flex-direction: column;
  gap: var(--space-2);
  transition: border-color var(--motion-fast) var(--ease-standard),
    background-color var(--motion-fast) var(--ease-standard);
}
.choice-card:hover {
  border-color: var(--color-border-strong);
}
.choice-card[aria-checked="true"] {
  border-width: var(--border-width-strong);
  border-color: var(--color-accent);
  background: var(--color-accent-muted);
}
.choice-card:focus-visible {
  outline: 2px solid var(--color-focus-ring);
  outline-offset: 2px;
}
.choice-title {
  font-size: var(--text-body);
  font-weight: var(--font-weight-semibold);
}
.choice-desc {
  font-size: var(--text-caption);
  line-height: var(--text-caption-lh);
  color: var(--color-text-secondary);
}
```

---

## Migration note

When wiring the real renderer, replace slate/sky rules in `apps/desktop/src/renderer/styles.css` with the patterns above and the shared tokens file. Keep behavior (IPC, screens) unchanged while swapping visuals.
