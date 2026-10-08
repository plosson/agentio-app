@testable import AgentioKit
import Foundation
import Testing
@testable import CompanionUI

let installed = CliInfo(path: URL(filePath: "/app/bin/agentio"), version: "3.14.0")

/// A scripted CompanionBackend: an installed CLI 3.14.0 and a hub 3.14.0
/// unless a test says otherwise. Sign-ins wait until the test calls
/// `finishLogin`, or until they are cancelled.
final class FakeBackend: CompanionBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _detected: CliInfo? = installed
    private var _installEvents: [InstallProgress] = []
    private var _installResult: Result<CliInfo, AgentioError> = .success(installed)
    private var _installs: [CliVersion] = []
    private var _installGate = false
    private var _hubVersion: Result<CliVersion, AgentioError> = .success(CliVersion("3.14.0")!)
    private var _hubChecks: [String] = []
    private var _hubVersionGates: Set<String> = []
    private var _vaultState: Result<VaultState, AgentioError> = .success(.none)
    private var _vaultStateCalls = 0
    private var _loginCode: LoginCode?
    private var _logins: [String] = []
    private var _loginOutcome: AsyncStream<Result<Void, AgentioError>>.Continuation?
    private var _loginRight: Bool? = true
    private var _initVault: Result<Void, AgentioError> = .success(())
    private var _passphrases: [String] = []
    private var _initVaultGate = false
    private var _daemons: [FakeDaemon] = []
    private var _daemonError: AgentioError?
    private var _cliUpdate: Result<CliUpdate, AgentioError> = .failure(AgentioError("no network"))
    private var _cliUpdateChecks = 0

    private var _terminalAdds: [String] = []
    private var _terminalReauths: [String] = []

    private func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }

    var detected: CliInfo? { get { locked { _detected } } set { locked { _detected = newValue } } }
    var installEvents: [InstallProgress] { get { locked { _installEvents } } set { locked { _installEvents = newValue } } }
    var installResult: Result<CliInfo, AgentioError> { get { locked { _installResult } } set { locked { _installResult = newValue } } }
    /// While true, `installCli` waits after its events (and stops when its task is cancelled).
    var installGate: Bool { get { locked { _installGate } } set { locked { _installGate = newValue } } }
    /// Let the held installs finish.
    func openInstallGate() { installGate = false }
    /// The minimum each install was asked for.
    var installs: [CliVersion] { locked { _installs } }
    var hubVersionResult: Result<CliVersion, AgentioError> { get { locked { _hubVersion } } set { locked { _hubVersion = newValue } } }
    var hubChecks: [String] { locked { _hubChecks } }
    /// While a hub is in this set, `hubVersion` for it waits (and stops when its task is cancelled).
    var hubVersionGates: Set<String> { get { locked { _hubVersionGates } } set { locked { _hubVersionGates = newValue } } }
    /// Let the held version checks for `hub` answer.
    func openHubVersionGate(_ hub: String) { locked { _ = _hubVersionGates.remove(hub) } }
    var vaultStateResult: Result<VaultState, AgentioError> { get { locked { _vaultState } } set { locked { _vaultState = newValue } } }
    var vaultStateCalls: Int { locked { _vaultStateCalls } }
    var loginCode: LoginCode? { get { locked { _loginCode } } set { locked { _loginCode = newValue } } }
    var logins: [String] { locked { _logins } }
    /// The managing right a successful sign-in reports.
    var loginRight: Bool? { get { locked { _loginRight } } set { locked { _loginRight = newValue } } }
    var initVaultResult: Result<Void, AgentioError> { get { locked { _initVault } } set { locked { _initVault = newValue } } }
    var passphrases: [String] { locked { _passphrases } }
    /// While true, `initVault` waits after recording its passphrase (and stops when its task is cancelled).
    var initVaultGate: Bool { get { locked { _initVaultGate } } set { locked { _initVaultGate = newValue } } }
    var daemons: [FakeDaemon] { locked { _daemons } }
    var daemonError: AgentioError? { get { locked { _daemonError } } set { locked { _daemonError = newValue } } }
    /// What `checkCliUpdate` answers; it cannot say unless a test sets it.
    var cliUpdateResult: Result<CliUpdate, AgentioError> { get { locked { _cliUpdate } } set { locked { _cliUpdate = newValue } } }
    var cliUpdateChecks: Int { locked { _cliUpdateChecks } }

    /// Each terminal add: "service|readOnly".
    var terminalAdds: [String] { locked { _terminalAdds } }
    /// Each terminal sign-in-again: "service|profile".
    var terminalReauths: [String] { locked { _terminalReauths } }

    func terminalProfileAdd(_ service: String, readOnly: Bool) throws -> TerminalCommand {
        locked { _terminalAdds.append("\(service)|\(readOnly)") }
        guard isServiceID(service) else { throw invalidService(service) }
        return TerminalCommand(executable: URL(filePath: "/app/bin/agentio"),
                               arguments: [service, "profile", "add"] + (readOnly ? ["--read-only"] : []), environment: [:])
    }

    func terminalProfileReauth(_ service: String, profile: String) throws -> TerminalCommand {
        locked { _terminalReauths.append("\(service)|\(profile)") }
        guard isServiceID(service) else { throw invalidService(service) }
        return TerminalCommand(executable: URL(filePath: "/app/bin/agentio"),
                               arguments: ["profile", "reauth", service, profile], environment: [:])
    }

    func detectCli() async -> CliInfo? { detected }

    /// A successful install is what `detectCli` finds afterwards.
    func installCli(atLeast minimum: CliVersion, onProgress: @escaping @Sendable (InstallProgress) -> Void) async throws -> CliInfo {
        locked { _installs.append(minimum) }
        for event in installEvents { onProgress(event) }
        while installGate { try await Task.sleep(for: .milliseconds(10)) }
        let info = try installResult.get()
        detected = info
        return info
    }

    func checkCliUpdate() async throws -> CliUpdate {
        locked { _cliUpdateChecks += 1 }
        return try cliUpdateResult.get()
    }

    func hubVersion(_ hub: String) async throws -> CliVersion {
        locked { _hubChecks.append(hub) }
        while hubVersionGates.contains(hub) { try await Task.sleep(for: .milliseconds(10)) }
        return try hubVersionResult.get()
    }

    func vaultState() async throws -> VaultState {
        locked { _vaultStateCalls += 1 }
        return try vaultStateResult.get()
    }

    func login(hub: String, name: String, onCode: @escaping @Sendable (LoginCode) -> Void) async throws -> VaultState {
        let (outcomes, continuation) = AsyncStream<Result<Void, AgentioError>>.makeStream()
        locked {
            _logins.append("\(hub)|\(name)")
            _loginOutcome = continuation
        }
        if let code = loginCode { onCode(code) }
        for await outcome in outcomes {
            try outcome.get()
            return .remote(hub: hub, canManageProfiles: loginRight)
        }
        throw AgentioError("Sign-in was cancelled")
    }

    /// End the running sign-in.
    func finishLogin(_ outcome: Result<Void, AgentioError>) {
        let continuation = locked { _loginOutcome }
        continuation?.yield(outcome)
    }

    func initVault(passphrase: String) async throws {
        locked { _passphrases.append(passphrase) }
        while initVaultGate { try await Task.sleep(for: .milliseconds(10)) }
        try initVaultResult.get()
    }

    func startLocalDaemon() async throws -> any LocalDaemon {
        if let error = daemonError { throw error }
        let daemon = FakeDaemon()
        locked { _daemons.append(daemon) }
        return daemon
    }
}

final class FakeDaemon: LocalDaemon, @unchecked Sendable {
    let url = URL(string: "http://127.0.0.1:63168")!
    private let lock = NSLock()
    private var _stopped = false
    private let exits: AsyncStream<Void>
    private let exitContinuation: AsyncStream<Void>.Continuation

    init() { (exits, exitContinuation) = AsyncStream<Void>.makeStream() }

    var stopped: Bool { lock.withLock { _stopped } }

    func waitForExit() async { for await _ in exits {} }

    func stop() async {
        lock.withLock { _stopped = true }
        exitContinuation.finish()
    }

    /// The daemon exits by itself.
    func crash() { exitContinuation.finish() }
}

/// Wait (up to 2 s) until `condition` holds on the main actor.
@MainActor func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(2)
    while !condition() {
        if clock.now > deadline {
            Issue.record("condition not met in 2 s", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

let code = LoginCode(userCode: "ABCD-1234", verifyURL: URL(string: "https://h.example/ui#authorize=ABCD-1234")!)
