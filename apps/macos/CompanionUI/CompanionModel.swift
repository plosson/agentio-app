import AgentioKit
import AppKit
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

/// A profile the hub page should learn about: it was just added, or signed in again.
public struct PageNotice: Equatable, Sendable {
    public let id: UUID
    public let service: String
    public let profile: String
}

/// What the hub-address field says about the address typed so far.
public enum HubCheck: Equatable, Sendable {
    case idle
    case checking(hub: String)
    case found(hub: String, version: String)
    /// Not an address the app accepts (normalizeHubBase refused it).
    case invalid
    case unreachable(hub: String)
    /// A hub older than minimumHubVersion: signing in from the app would fail.
    case tooOld(hub: String, version: String)
}

/// The onboarding's state and steps. Views read it and call its steps.
@MainActor @Observable
public final class CompanionModel {
    public private(set) var screen: Screen = .mode
    public private(set) var cli: CliInfo?
    /// Nil while the vault state is being read.
    public private(set) var vault: VaultState?
    public private(set) var loginCode: LoginCode?
    /// The app's CLI download, for the onboarding page.
    public struct DownloadState: Equatable, Sendable {
        public enum Phase: String, Sendable { case idle, downloading, settingUp, checking, ready, failed }
        public var phase: Phase = .idle
        /// 0–100 over the whole install: downloading fills 0–90, setting up is 90, checking is 95, ready is 100.
        public var percent = 0
        /// The installer's last lines (at most 50), for "Show details".
        public var log: [String] = []
    }
    public private(set) var download = DownloadState()
    /// Shown instead of the actions while a long step runs.
    public private(set) var busy: String?
    /// What the hub-address field says about the address typed so far.
    public private(set) var hubCheck: HubCheck = .idle
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

    /// The add-profile (or sign-in-again) sheet; nil when none is open.
    public private(set) var addFlow: AddProfileFlow?
    /// The last profile added, for the page to pick up.
    public private(set) var pageNotice: PageNotice?

    private let backend: any CompanionBackend
    private let openURL: @MainActor (URL) -> Void
    private let settings: CompanionSettings
    private let allowLocalHTTP: Bool
    private let deviceName: String
    private var loginTask: Task<VaultState, Error>?
    /// The running sign-in; a sign-in that is no longer current changes nothing.
    private var loginID: UUID?
    private var daemon: (any LocalDaemon)?
    /// The latest download; a step that needs the CLI waits for it while it runs.
    private var downloadTask: Task<Result<CliInfo, Error>, Never>?
    /// The running download; a download that is no longer current changes nothing.
    private var downloadID: UUID?
    /// The latest hub check; an older one still running changes nothing when it ends.
    private var hubCheckID: UUID?
    /// The screen a failed download goes back to on "Try again".
    private var downloadFrom: Screen?
    /// Loading the add sheet; stopped with the sheet.
    private var addFlowStart: Task<Void, Never>?

    public init(backend: any CompanionBackend, settings: CompanionSettings, allowLocalHTTP: Bool, deviceName: String,
                openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.backend = backend
        self.openURL = openURL
        self.settings = settings
        self.allowLocalHTTP = allowLocalHTTP
        self.deviceName = deviceName
        if let remembered = settings.rememberedHubURL { hubURL = remembered }
    }

    public var windowTitle: String {
        guard let host = vaultPage?.host() else { return "AgentIO Companion" }
        return "AgentIO Companion — \(host)\(vaultPage?.port.map { ":\($0)" } ?? "")"
    }

    /// Start the CLI download if the app's CLI is missing or too old, then show the mode screen.
    public func start() async {
        let installed = await backend.detectCli()
        if installed?.isAtLeast(minimumCliVersion) != true, !isDownloading {
            startDownload(atLeast: minimumCliVersion)
        }
        await enterMode()
    }

    // MARK: CLI (S2)

    /// The app's CLI at `minimum` or newer. When it is missing or older, wait
    /// for the running download, or start one, on the installing screen. False
    /// when that fails: the screen stays, with the error.
    private func ensureCli(atLeast minimum: CliVersion) async -> Bool {
        if let installed = await backend.detectCli(), installed.isAtLeast(minimum) {
            cli = installed
            return true
        }
        if screen != .installing { downloadFrom = screen }
        screen = .installing
        let running = isDownloading ? downloadTask : nil
        var outcome = await (running ?? startDownload(atLeast: minimum)).value
        // The launch download only reached the app's minimum; this step needs more.
        if case .success(let info) = outcome, !info.isAtLeast(minimum) {
            outcome = await startDownload(atLeast: minimum).value
        }
        switch outcome {
        case .success(let info) where info.isAtLeast(minimum):
            return true
        case .success:
            fail(AgentioError("agentio \(minimum) or later could not be installed"))
            return false
        case .failure(let failure):
            fail(failure)
            return false
        }
    }

    private var isDownloading: Bool { [.downloading, .settingUp, .checking].contains(download.phase) }

    /// Install the latest CLI in the background, showing its progress in `download`.
    @discardableResult
    private func startDownload(atLeast minimum: CliVersion) -> Task<Result<CliInfo, Error>, Never> {
        download = DownloadState(phase: .downloading)
        let id = UUID()
        downloadID = id
        let backend = backend
        let task = Task { () -> Result<CliInfo, Error> in
            // Progress arrives on the installer's threads; apply it in order,
            // and all of it before the final 100%.
            let (events, sink) = AsyncStream<InstallProgress>.makeStream()
            let applying = Task {
                for await event in events where downloadID == id { applyInstallProgress(event) }
            }
            let outcome: Result<CliInfo, Error>
            do {
                outcome = .success(try await backend.installCli(atLeast: minimum) { sink.yield($0) })
            } catch {
                outcome = .failure(error)
            }
            sink.finish()
            await applying.value
            guard downloadID == id else { return outcome }
            switch outcome {
            case .success(let info):
                cli = info
                download.phase = .ready
                download.percent = 100
                appendLog("agentio \(info.version) is ready")
            case .failure:
                download.phase = .failed
            }
            return outcome
        }
        downloadTask = task
        return task
    }

    /// Restart a failed download in the background, and go back to the screen it failed on.
    public func retryDownload() {
        guard download.phase == .failed else { return }
        error = nil
        screen = downloadFrom ?? .mode
        startDownload(atLeast: minimumCliVersion)
    }

    /// The download's percent fills 0–90%; setting up and checking mark 90 and 95.
    private func applyInstallProgress(_ progress: InstallProgress) {
        switch progress {
        case .label(let text): appendLog(text)
        case .percent(let percent):
            let clamped = percent.isNaN ? 0 : min(max(percent, 0), 100)
            download.phase = clamped >= 100 ? .settingUp : .downloading
            download.percent = Int((clamped * 0.9).rounded())
        case .checking:
            download.phase = .checking
            download.percent = 95
        }
    }

    private func appendLog(_ line: String) {
        download.log.append(line)
        if download.log.count > 50 { download.log.removeFirst(download.log.count - 50) }
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
        hubCheckID = nil
        hubCheck = .idle
        screen = .hubURL
    }

    /// Show the passphrase screen at once; the CLI is needed only when the vault is created.
    public func goLocal() {
        error = nil
        screen = .local
    }

    // MARK: Remote vault (S4, login, approving)

    /// Check `raw` as the user types; a newer call wins over an older one still running.
    public func checkHub(_ raw: String) async {
        let id = UUID()
        hubCheckID = id
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return hubCheck = .idle }
        let hub: String
        do {
            hub = try normalizeHubBase(raw, allowLocalHTTP: allowLocalHTTP)
        } catch {
            return hubCheck = .invalid
        }
        hubCheck = .checking(hub: hub)
        let result: HubCheck
        do {
            let version = try await backend.hubVersion(hub)
            result = version < minimumHubVersion
                ? .tooOld(hub: hub, version: version.description)
                : .found(hub: hub, version: version.description)
        } catch {
            result = .unreachable(hub: hub)
        }
        guard hubCheckID == id else { return }
        hubCheck = result
    }

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
        guard await ensureCli(atLeast: minimumCliVersion) else { return }
        if screen == .installing { screen = .local }
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
        closeAddFlow()
        vaultPage = nil
        await enterMode()
    }

    /// The hub's page asked for a key that may manage profiles: sign in to
    /// the same hub again, from the app's own screens. Only for a remote vault.
    public func signInAgain() async {
        closeAddFlow()
        guard screen == .vault, hubURL != daemon?.url.absoluteString else { return }
        vaultPage = nil
        screen = .hubURL
        await signIn(url: hubURL, remember: settings.rememberedHubURL == hubURL)
    }

    // MARK: Adding a profile (from the hub page)

    /// The hub page asked to add `service`. Only on an open remote vault whose key may manage profiles,
    /// and one at a time.
    public func addProfile(service: String, displayName: String?) {
        openFlow(service: service, displayName: displayName ?? service, purpose: .add)
    }

    /// The hub page asked to sign `profile` of `service` in again. Same conditions as `addProfile`,
    /// and the name must be one.
    public func reauthProfile(service: String, profile: String, displayName: String? = nil) {
        guard isProfileName(profile) else { return }
        openFlow(service: service, displayName: displayName ?? service, purpose: .reauth(profile: profile))
    }

    private func openFlow(service: String, displayName: String, purpose: AddProfileFlow.Purpose) {
        guard screen == .vault, hubURL != daemon?.url.absoluteString, canManageProfiles == true, addFlow == nil else { return }
        let flow = AddProfileFlow(service: service, displayName: displayName, purpose: purpose, backend: backend,
                                  openURL: openURL) { [weak self] service, profile in
            self?.pageNotice = PageNotice(id: UUID(), service: service, profile: profile)
        }
        addFlow = flow
        addFlowStart = Task { await flow.start() }
    }

    /// Close the sheet; an add still running is stopped.
    public func closeAddFlow() {
        addFlowStart?.cancel()
        addFlowStart = nil
        addFlow?.cancel()
        addFlow = nil
    }

    /// Before quitting: no sign-in left polling the hub, no daemon left running.
    public func shutdown() async {
        closeAddFlow()
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
