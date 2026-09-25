# Layout

Electron window geometry and region rules for AgentIO Companion, plus vault hub `/ui` content width. Colors, type, radii, and buttons match System Utility Vault everywhere — only density differs.

---

## Electron window sizing

| Mode | Min W×H | Default W×H | Resizable |
|------|---------|-------------|-----------|
| **Onboarding** | 480 × 560 | 520 × 640 | Yes (keep column centered) |
| **Vault** | 900 × 640 | 1100 × 760 | Yes |

- Center on screen at first launch.  
- Remember vault window bounds in user prefs (optional MVP+).  
- Do not open onboarding at vault size — the empty zinc margins should feel intentional, not sparse-wrong.

Switching modes may `setMinimumSize` / `setSize` in main process; avoid animating OS window bounds.

---

## Traffic lights / titlebar drag

macOS-first:

```js
// BrowserWindow (illustrative)
{
  titleBarStyle: 'hiddenInset',
  trafficLightPosition: { x: 16, y: 18 }, // tune to bar height
  // vibrancy optional — prefer solid --color-bg for predictability
}
```

| Region | Rules |
|--------|-------|
| Titlebar / vault bar background | `-webkit-app-region: drag` |
| Buttons, inputs, cards, links | `-webkit-app-region: no-drag` |
| Traffic lights | OS-owned; leave left inset clear (**≥70px** content offset on first row if custom controls sit top-left) |

Onboarding: no custom close buttons — use OS lights.  
Vault bar: place host label to the **right** of traffic-light clearance.

---

## Onboarding centered layout

```
Window (--color-bg)
└─ Titlebar drag (hiddenInset)
└─ main.wizard
   └─ .column (max-width: 420px; margin-inline: auto; padding-inline: 24px)
      └─ stack: mark → title → body → status/progress → actions → footer links
```

| Rule | Value |
|------|-------|
| Column max | **420px** |
| Side padding | **24px** |
| Top padding under titlebar | **40px** (`--space-8`) minimum |
| Bottom padding | **48px** (`--space-9`) |
| Stack gap | **16–24px** between major blocks |
| Primary actions | Full width of column |
| Secondary / ghost | Centered or full width under primary with `--space-3` gap |

Vertical centering: acceptable for short screens (Welcome). Prefer **top-weighted** layout (padding-top fixed, content flows down) when fields + keyboard are involved (URL, passphrase) so inputs don’t jump.

---

## Vault mode (bar + BrowserView)

```
┌──────────────────────────────────────────┐
│  Vault companion bar (40px, drag)        │
├──────────────────────────────────────────┤
│                                          │
│  BrowserView → https://<hub>/ui          │
│  (or local vault UI surface)             │
│                                          │
└──────────────────────────────────────────┘
```

| Part | Spec |
|------|------|
| Bar height | **40px** fixed |
| BrowserView bounds | `y = 40`, height = `window - 40` (account for devicePixelRatio in main) |
| Safe padding in bar | `12px` horizontal; left offset clear of traffic lights |
| Overlay sheets (PTY / OAuth) | Prefer child window or modal over drawing on BrowserView; scrim `--color-overlay` |

Companion does **not** CSS-inject into the hub `BrowserView`. The hub ships System Utility Vault natively (`plosson/agentio` `src/daemon/ui/index.html`). Vault bar surface/border should match the hub header so chrome feels continuous.

---

## Safe padding

| Edge | Onboarding | Vault bar |
|------|------------|-----------|
| Top | Titlebar inset + 40px | Traffic lights + 12px |
| Sides | 24px | 12px |
| Bottom | 48px | n/a (BrowserView flush) |
| Focus rings | Keep ≥2px inside window edge | Same |

---

## Z-order

1. BrowserView / wizard content  
2. Tip/status callouts in flow (not floating toast required for MVP)  
3. Modal sheets + overlay  
4. OS titlebar controls  

No persistent floating FAB.


---

## Hub `/ui` content layout

Hub is a normal document inside the BrowserView (or a browser tab).

```
┌─ header (surface + bottom border) ──────── tabs ── meta ─┐
│                                                          │
│  main (max-width: ~1040px; margin auto; padding 24px)    │
│    page-head → chips → card/table → settings             │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

| Rule | Value |
|------|-------|
| Main max-width | **~1040px** (`--layout-hub-main`) — OK for profile tables |
| Side padding | **24px** |
| Page vertical rhythm | 32px top margin on main; 20px under page-head |
| Unlock / authorize narrow | ~400px centered (wizard-like), same tokens |
| Cards / dialogs radius | 8–10px controls; 12px dialogs |
| Shadows | Quiet (`--shadow`); no heavy SaaS elevation |

Companion onboarding stays **420px**. Hub tables stay **1040**. Shared: zinc canvas, teal accent, black/white pills, system type.
