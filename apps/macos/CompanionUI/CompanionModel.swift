import AgentioKit
import Foundation
import Observation

/// The app's screens. S2–S6 are the spec's screen ids.
public enum Screen: Equatable, Sendable {
    /// The first screen: the vault this app uses, or the choice of one.
    case mode
    /// S2: the installer runs, when the CLI is missing or older than needed.
    case installing
    /// S4: the hub's URL.
    case hubURL
    /// `agentio login` runs: waiting for its code, then for approval.
    case login
    /// The hub's approval page fills the window.
    case approving
    /// Create a local vault.
    case local
    /// S6: the hub's page fills the window.
    case vault
}

/// The onboarding's state and steps. Views read it and call its steps.
@MainActor @Observable
public final class CompanionModel {
    public private(set) var screen: Screen = .mode
    public private(set) var cli: CliInfo?
    /// Nil while the vault state is being read.
    public private(set) var vault: VaultState?
    public private(set) var loginCode: LoginCode?
    public private(set) var installPercent = 0
    public private(set) var installLabel = ""
    /// Shown instead of the actions while a long step runs.
    public private(set) var busy: String?
    public var error: String?
    /// The hub's base URL: remembered, entered, or reported by the CLI.
    public private(set) var hubURL = ""
    public var rememberURL = true
    /// The hub page that fills the window; nil shows the app's own screens.
    public private(set) var vaultPage: URL?
    /// Whether the hub's key may add and change profiles; nil for a local
    /// vault, or when the hub could not say. The hub's page offers to sign
    /// in again when it is false.
    public private(set) var canManageProfiles: Bool?

    private let backend: any CompanionBackend
    private let settings: CompanionSettings
    private let allowLocalHTTP: Bool
    private let deviceName: String
    private var loginTask: Task<VaultState, Error>?
    /// The running sign-in; a sign-in that is no longer current changes nothing.
    private var loginID: UUID?
    private var daemon: (any LocalDaemon)?

    public init(backend: any CompanionBackend, settings: CompanionSettings, allowLocalHTTP: Bool, deviceName: String) {
        self.backend = backend
        self.settings = settings
        self.allowLocalHTTP = allowLocalHTTP
        self.deviceName = deviceName
        if let remembered = settings.rememberedHubURL { hubURL = remembered }
    }

    public var windowTitle: String {
        guard let host = vaultPage?.host() else { return "AgentIO Companion" }
        return "AgentIO Companion — \(host)\(vaultPage?.port.map { ":\($0)" } ?? "")"
    }

    public func start() async {
        await enterMode()
    }

    // MARK: CLI (S2)

    /// The app's CLI at `minimum` or newer. When it is missing or older,
    /// install the latest on the installing screen. False when that fails:
    /// the error shows on the screen it came from.
    private func ensureCli(atLeast minimum: CliVersion) async -> Bool {
        if let installed = await backend.detectCli(), installed.isAtLeast(minimum) {
            cli = installed
            return true
        }
        let from = screen
        installPercent = 5
        installLabel = "Starting…"
        screen = .installing
        // Progress arrives on the installer's threads; apply it in order,
        // and all of it before the final 100%.
        let (events, sink) = AsyncStream<InstallProgress>.makeStream()
        let applying = Task {
            for await event in events { applyInstallProgress(event) }
        }
        let backend = backend
        let outcome: Result<CliInfo, Error>
        do {
            outcome = .success(try await backend.installCli(atLeast: minimum) { sink.yield($0) })
        } catch {
            outcome = .failure(error)
        }
        sink.finish()
        await applying.value
        switch outcome {
        case .success(let info):
            cli = info
            installPercent = 100
            installLabel = "agentio \(info.version) is ready"
            return true
        case .failure(let failure):
            screen = from
            fail(failure)
            return false
        }
    }

    /// The download's percent fills 5–95%; the ends mark start and verification.
    private func applyInstallProgress(_ progress: InstallProgress) {
        switch progress {
        case .label(let text): installLabel = text
        case .percent(let percent): installPercent = 5 + Int((min(max(percent, 0), 100) * 0.9).rounded())
        }
    }

    /// The CLI version a hub needs: its own, and never below the app's minimum.
    /// A new sign-in also needs a hub that knows `login --scope`.
    private func requiredCli(for hub: String, signingIn: Bool = false) async throws -> CliVersion {
        let version = try await backend.hubVersion(hub)
        if signingIn, version < minimumHubVersion {
            throw AgentioError("The vault hub at \(hub) runs agentio \(version). Signing in from this app needs agentio \(minimumHubVersion) or later on the hub.")
        }
        return max(minimumCliVersion, version)
    }

    // MARK: Vault choice

    /// Show the mode screen and read the vault state for it. Without the
    /// app's CLI, nothing is set up yet.
    public func enterMode() async {
        screen = .mode
        vault = nil
        guard let installed = await backend.detectCli() else {
            vault = VaultState.none
            return
        }
        cli = installed
        do {
            vault = try await backend.vaultState()
        } catch {
            vault = VaultState.none
            fail(error)
        }
    }

    public func goRemote() {
        error = nil
        screen = .hubURL
    }

    public func goLocal() async {
        error = nil
        guard await ensureCli(atLeast: minimumCliVersion) else { return }
        screen = .local
    }

    // MARK: Remote vault (S4, login, approving)

    /// Check the hub's version, bring the CLI up to it, then `agentio login`,
    /// approved by the hub owner on the hub's page.
    public func signIn(url raw: String, remember: Bool) async {
        error = nil
        let hub: String
        do {
            hub = try normalizeHubBase(raw, allowLocalHTTP: allowLocalHTTP)
        } catch {
            return fail(error)
        }
        hubURL = hub
        rememberURL = remember
        settings.rememberedHubURL = remember ? hub : nil
        abandonLogin()
        let id = UUID()
        loginID = id
        busy = "Checking the hub…"
        let required: CliVersion
        do {
            required = try await requiredCli(for: hub, signingIn: true)
        } catch {
            if loginID == id { loginID = nil; fail(error) }
            return
        }
        busy = nil
        guard loginID == id else { return }
        guard await ensureCli(atLeast: required) else {
            loginID = nil
            return
        }
        guard loginID == id else { return }
        screen = .login
        let (codes, sink) = AsyncStream<LoginCode>.makeStream()
        let showing = Task {
            for await code in codes where loginID == id { loginCode = code }
        }
        let backend = backend
        let name = deviceName
        let task = Task { try await backend.login(hub: hub, name: name) { sink.yield($0) } }
        loginTask = task
        let result = await task.result
        sink.finish()
        await showing.value
        guard loginID == id else { return }
        loginID = nil
        loginTask = nil
        loginCode = nil
        switch result {
        case .success(let state):
            if case .remote(_, let right) = state { canManageProfiles = right }
            showVault("\(hub)/ui")
        case .failure(let failure):
            // Failed or cancelled: drop the approval page, if it is showing.
            vaultPage = nil
            fail(failure)
        }
    }

    /// Show the hub's approval page for the current code.
    public func openApproval() {
        guard let loginCode else {
            return fail(AgentioError("There is no sign-in code to approve"))
        }
        vaultPage = loginCode.verifyURL
        screen = .approving
    }

    public func cancelLogin() {
        loginTask?.cancel()
    }

    /// Already signed in (e.g. after a restart): open the hub the CLI
    /// reports, once the CLI is up to the hub's version.
    public func openRemoteVault() async {
        error = nil
        busy = "Checking the hub…"
        defer { busy = nil }
        do {
            guard case .remote(let hub, let right) = try await backend.vaultState() else {
                throw AgentioError("This app is not signed in to a vault hub")
            }
            let required = try await requiredCli(for: hub)
            busy = nil
            guard await ensureCli(atLeast: required) else { return }
            hubURL = hub
            canManageProfiles = right
            showVault("\(hub)/ui")
        } catch {
            fail(error)
        }
    }

    // MARK: Local vault

    public func createLocalVault(passphrase: String, again: String) async {
        error = nil
        guard passphrase.count >= 8 else {
            return fail(AgentioError("The passphrase needs at least 8 characters"))
        }
        guard passphrase == again else {
            return fail(AgentioError("The two passphrases are different"))
        }
        busy = "Creating the vault and starting it…"
        defer { busy = nil }
        do {
            try await backend.initVault(passphrase: passphrase)
            try await showLocalVault()
        } catch {
            fail(error)
        }
    }

    public func openLocalVault() async {
        error = nil
        guard await ensureCli(atLeast: minimumCliVersion) else { return }
        busy = "Starting the local vault…"
        defer { busy = nil }
        do {
            try await showLocalVault()
        } catch {
            fail(error)
        }
    }

    /// Start the local daemon (unless this app already runs it) and open its UI.
    private func showLocalVault() async throws {
        let running: any LocalDaemon
        if let daemon {
            running = daemon
        } else {
            running = try await backend.startLocalDaemon()
            daemon = running
            Task {
                await running.waitForExit()
                if daemon === running { daemon = nil }
            }
        }
        hubURL = running.url.absoluteString
        canManageProfiles = nil
        showVault("\(hubURL)/ui")
    }

    // MARK: Vault window (S6)

    /// Back to the app's own screens (the local daemon, if any, keeps running).
    public func switchVault() async {
        vaultPage = nil
        await enterMode()
    }

    /// The hub's page asked for a key that may manage profiles: sign in to
    /// the same hub again, from the app's own screens. Only for a remote vault.
    public func signInAgain() async {
        guard screen == .vault, hubURL != daemon?.url.absoluteString else { return }
        vaultPage = nil
        await signIn(url: hubURL, remember: settings.rememberedHubURL == hubURL)
    }

    /// Before quitting: no sign-in left polling the hub, no daemon left running.
    public func shutdown() async {
        abandonLogin()
        await daemon?.stop()
        daemon = nil
    }

    private func showVault(_ page: String) {
        guard let url = URL(string: page) else {
            return fail(AgentioError("Invalid vault URL"))
        }
        vaultPage = url
        screen = .vault
    }

    private func abandonLogin() {
        loginID = nil
        loginTask?.cancel()
        loginTask = nil
        loginCode = nil
    }

    /// Show the error; a failed or cancelled sign-in goes back to the hub URL.
    private func fail(_ failure: Error) {
        busy = nil
        error = (failure as? LocalizedError)?.errorDescription ?? failure.localizedDescription
        if screen == .login || screen == .approving { screen = .hubURL }
    }
}
