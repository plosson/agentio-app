# AgentIO Companion

Native macOS app (Swift, SwiftUI) for an AgentIO vault: a remote hub or a local vault.

The app installs its own copy of the AgentIO CLI, at least the version the hub runs, then signs in to a hub (or creates a local vault) and shows the vault's `/ui` page. New AgentIO services and plugins need no app update: the hub's page shows them, and the app updates its CLI when the hub is newer. A narrow bridge (`window.agentioCompanion`) lets the vault page show **Add profile** and **Reauth** only inside the app. The CLI is not bundled in the app.

## Status

Onboarding, CLI install, hub sign-in, local vault and the vault window work. Add profile, Reauth and Open terminal only log a message for now: the terminal (spec S7) comes next.

## Spec

- [`docs/plans/companion-spec.md`](docs/plans/companion-spec.md): product and architecture
- [`docs/design/`](docs/design/): design system

## Requirements

- macOS 14 or later, Xcode 26
- XcodeGen: `brew install xcodegen`
- For a remote vault: a hub that runs agentio 3.14.0 or later. The app signs in with the scopes `profiles:write` and `profiles:manage`.

## Build, test and run

```bash
cd apps/macos
xcodegen generate                       # creates AgentioCompanion.xcodeproj
open AgentioCompanion.xcodeproj         # or use the commands below

xcodebuild -scheme AgentioCompanion -destination 'platform=macOS' -derivedDataPath build test
xcodebuild -scheme AgentioCompanion -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/AgentIO Companion.app"
```

Logs: `log stream --predicate 'subsystem == "com.plosson.agentio-companion"'`

## Where the app keeps things

| What | Where |
|------|-------|
| The app's CLI and its HOME | `~/Library/Application Support/com.plosson.agentio-companion/cli/` |
| Remembered hub URL | `defaults read com.plosson.agentio-companion` |

## Bridge

The vault page gets:

```ts
window.agentioCompanion = {
  present: true,
  addProfile(service: string): Promise<void>,
  reauth(service: string, name?: string): Promise<void>,
  openTerminal(): Promise<void>,
}
```

Only the main frame gets it. It exposes no shell, tokens or passphrase APIs.

## License

Private / TBD — © Pierre A. Losson
