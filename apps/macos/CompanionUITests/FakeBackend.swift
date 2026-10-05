@testable import AgentioKit
import Foundation
import Testing
@testable import CompanionUI

let installed = CliInfo(path: URL(filePath: "/app/bin/agentio"), version: "3.12.2")

/// A scripted CompanionBackend: an installed CLI 3.12.2 and a hub 3.12.2
/// unless a test says otherwise. Sign-ins wait until the test calls
/// `finishLogin`, or until they are cancelled.
final class FakeBackend: CompanionBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _detected: CliInfo? = installed
    private var _installEvents: [InstallProgress] = []
    private var _installResult: Result<CliInfo, AgentioError> = .success(installed)
    private var _installs: [CliVersion] = []
    private var _hubVersion: Result<CliVersion, AgentioError> = .success(CliVersion("3.12.2")!)
    private var _hubChecks: [String] = []
    private var _vaultState: Result<VaultState, AgentioError> = .success(.none)
    private var _vaultStateCalls = 0
    private var _loginCode: LoginCode?
    private var _logins: [String] = []
    private var _loginOutcome: AsyncStream<Result<Void, AgentioError>>.Continuation?
    private var _initVault: Result<Void, AgentioError> = .success(())
    private var _passphrases: [String] = []
    private var _daemons: [FakeDaemon] = []
    private var _daemonError: AgentioError?

    private func locked<T>(_ body: () -> T) -> T { lock.withLock(body) }

    var detected: CliInfo? { get { locked { _detected } } set { locked { _detected = newValue } } }
    var installEvents: [InstallProgress] { get { locked { _installEvents } } set { locked { _installEvents = newValue } } }
    var installResult: Result<CliInfo, AgentioError> { get { locked { _installResult } } set { locked { _installResult = newValue } } }
    /// The minimum each install was asked for.
    var installs: [CliVersion] { locked { _installs } }
    var hubVersionResult: Result<CliVersion, AgentioError> { get { locked { _hubVersion } } set { locked { _hubVersion = newValue } } }
    var hubChecks: [String] { locked { _hubChecks } }
    var vaultStateResult: Result<VaultState, AgentioError> { get { locked { _vaultState } } set { locked { _vaultState = newValue } } }
    var vaultStateCalls: Int { locked { _vaultStateCalls } }
    var loginCode: LoginCode? { get { locked { _loginCode } } set { locked { _loginCode = newValue } } }
    var logins: [String] { locked { _logins } }
    var initVaultResult: Result<Void, AgentioError> { get { locked { _initVault } } set { locked { _initVault = newValue } } }
    var passphrases: [String] { locked { _passphrases } }
    var daemons: [FakeDaemon] { locked { _daemons } }
    var daemonError: AgentioError? { get { locked { _daemonError } } set { locked { _daemonError = newValue } } }

    func detectCli() async -> CliInfo? { detected }

    /// A successful install is what `detectCli` finds afterwards.
    func installCli(atLeast minimum: CliVersion, onProgress: @escaping @Sendable (InstallProgress) -> Void) async throws -> CliInfo {
        locked { _installs.append(minimum) }
        for event in installEvents { onProgress(event) }
        let info = try installResult.get()
        detected = info
        return info
    }

    func hubVersion(_ hub: String) async throws -> CliVersion {
        locked { _hubChecks.append(hub) }
        return try hubVersionResult.get()
    }

    func vaultState() async throws -> VaultState {
        locked { _vaultStateCalls += 1 }
        return try vaultStateResult.get()
    }

    func login(hub: String, name: String, onCode: @escaping @Sendable (LoginCode) -> Void) async throws {
        let (outcomes, continuation) = AsyncStream<Result<Void, AgentioError>>.makeStream()
        locked {
            _logins.append("\(hub)|\(name)")
            _loginOutcome = continuation
        }
        if let code = loginCode { onCode(code) }
        for await outcome in outcomes { return try outcome.get() }
        throw AgentioError("Sign-in was cancelled")
    }

    /// End the running sign-in.
    func finishLogin(_ outcome: Result<Void, AgentioError>) {
        let continuation = locked { _loginOutcome }
        continuation?.yield(outcome)
    }

    func initVault(passphrase: String) async throws {
        locked { _passphrases.append(passphrase) }
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
