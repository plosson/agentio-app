import Foundation

/*
 * The only way the app runs its agentio (`AgentioCLI.start`): the app's own
 * binary and environment, the same stop policy, and stdout read as --json
 * events. One JSON object per stdout line, each with the output format
 * version `v` and an `event` (agentio#87). `vault init` has no --json, so
 * only its exit code and stderr matter.
 */

/// The `--json` output format this app reads (agentio's JSON_OUTPUT_VERSION).
let jsonOutputVersion = 1

/// One `--json` event. The fields are JSONSerialization values, never mutated.
struct CliEvent: @unchecked Sendable {
    let name: String
    let fields: [String: Any]

    func string(_ key: String) -> String? { fields[key] as? String }

    /// A JSON `true` or `false` only: a number or a string is not a boolean.
    func bool(_ key: String) -> Bool? {
        guard let number = fields[key] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    /// An event that ends a command unsuccessfully.
    var isFailure: Bool { ["error", "denied", "expired"].contains(name) }

    /// An `error` (or `denied`, `expired`) event as an AgentioError.
    func error(exitCode: Int32?) -> AgentioError {
        AgentioError(string("message") ?? "agentio reported \(name)", code: string("code"),
                     suggestion: string("suggestion"), exitCode: exitCode)
    }
}

let unreadableFormat = AgentioError("This agentio prints a JSON format the app cannot read. Update AgentIO Companion.")

/// One stdout line as an event; nil for anything else (a blank or log line).
/// Throws for an event in another format version: this app cannot read it.
func parseEvent(_ line: String) throws -> CliEvent? {
    guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let name = object["event"] as? String else { return nil }
    guard let version = object["v"] as? Int, version == jsonOutputVersion else {
        throw unreadableFormat
    }
    return CliEvent(name: name, fields: object)
}

/// A finished agentio command: its exit code (nil when stopped), output,
/// and the events it printed, in order.
struct AgentioResult: Sendable {
    var exitCode: Int32?
    var stdout = ""
    var stderr = ""
    var events: [CliEvent] = []
}

/// Why a command failed: its last failure event. Without one, stderr (only
/// logs in JSON mode) explains a failing exit, such as an unknown option.
func failure(_ result: AgentioResult, fallback: String) -> AgentioError {
    if let event = result.events.last(where: \.isFailure) {
        return event.error(exitCode: result.exitCode)
    }
    if result.exitCode == 0 { return AgentioError(fallback, exitCode: 0) }
    return cliError(stderr: result.stderr, exitCode: result.exitCode, fallback: fallback)
}

/// Where the app's CLI keeps credentials.
public enum VaultState: Sendable, Equatable {
    case none
    case local
    /// `canManageProfiles`: whether the key may add and change profiles;
    /// nil when the hub could not say (down, older, or an older CLI).
    case remote(hub: String, canManageProfiles: Bool? = nil)
}

/// A login code to approve on the hub, and the page to approve it on.
public struct LoginCode: Sendable, Equatable {
    public let userCode: String
    public let verifyURL: URL
}

public struct CliInfo: Sendable, Equatable {
    public let path: URL
    public let version: String
}

/// The app's own agentio: where it lives and the environment it runs in.
public struct AgentioCLI: Sendable {
    public let location: CliLocation
    /// The app's environment; the CLI gets it without the user's AGENTIO_*
    /// settings and with its own HOME (`cliEnv`).
    public let baseEnvironment: [String: String]

    public init(location: CliLocation, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.location = location
        self.baseEnvironment = baseEnvironment
    }

    /// Start the app's agentio with `arguments`. `onEvent` gets each --json
    /// event as it is printed. A line in another format version stops the
    /// process; its `formatError` then says why.
    func start(
        _ arguments: [String],
        input: String? = nil,
        collectsOutput: Bool = true,
        keepsStderr: Bool = true,
        stopGrace: Duration = .seconds(5),
        onEvent: @escaping @Sendable (CliEvent) -> Void = { _ in }
    ) throws -> AgentioProcess {
        let child = ChildProcess(location.binPath, arguments, environment: cliEnv(location, base: baseEnvironment),
                                 input: input, collectsOutput: collectsOutput, keepsStderr: keepsStderr, stopGrace: stopGrace)
        let process = AgentioProcess(child)
        try process.start(onEvent: onEvent)
        return process
    }

    /// Run the app's agentio to completion. A timeout or task cancellation
    /// stops it (nil exit code). Throws when it cannot start, or when it
    /// prints a format version this app cannot read.
    func execute(
        _ arguments: [String],
        timeout: Duration,
        input: String? = nil,
        onEvent: @escaping @Sendable (CliEvent) -> Void = { _ in }
    ) async throws -> AgentioResult {
        let process = try start(arguments, input: input, onEvent: onEvent)
        let exit = await process.finished(timeout: timeout)
        if let formatError = process.formatError { throw formatError }
        return AgentioResult(exitCode: exit.exitCode, stdout: exit.stdout, stderr: exit.stderr, events: process.events)
    }

    /// The installed CLI's `--version`; nil if it is missing or does not run.
    /// The first run of a new binary waits for macOS's malware scan, which
    /// takes seconds, so the timeout is generous.
    public func detect(timeout: Duration = .seconds(30)) async -> CliInfo? {
        guard let result = try? await execute(["--version"], timeout: timeout) else {
            return nil
        }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !version.isEmpty ? CliInfo(path: location.binPath, version: version) : nil
    }

    /// `vault status --json`: remote mode names the hub; a local vault that
    /// is not configured yet is `none`. It never prompts.
    public func vaultState() async throws -> VaultState {
        let result = try await execute(["vault", "status", "--json"], timeout: .seconds(30))
        guard result.exitCode == 0, let vault = result.events.last(where: { $0.name == "vault" }) else {
            throw failure(result, fallback: "agentio vault status failed")
        }
        switch vault.string("mode") {
        case "remote":
            guard let hub = vault.string("hub") else {
                throw AgentioError("agentio reported a remote vault without its hub", exitCode: 0)
            }
            return .remote(hub: hub, canManageProfiles: vault.bool("canManageProfiles"))
        case "local":
            return vault.fields["configured"] as? Bool == true ? .local : .none
        default:
            throw AgentioError("agentio reported an unknown vault mode", exitCode: 0)
        }
    }

    /// Create a local vault. The passphrase goes through stdin, never argv.
    public func initVault(passphrase: String) async throws {
        let result = try await execute(["vault", "init", "--passphrase-stdin", "--no-migrate"],
                                       timeout: .seconds(30), input: passphrase)
        if result.exitCode != 0 {
            throw cliError(stderr: result.stderr, exitCode: result.exitCode, fallback: "Could not create the vault")
        }
    }

    /// Sign in to a hub with `agentio login --json`, which stores a key
    /// token in the CLI's home. `onCode` gets the `code` event's code and
    /// approval page as soon as it is printed. Success is the `approved`
    /// event, confirmed with `vaultState`, which it returns. It asks for
    /// `loginScopes`. The CLI gives up after its 10-minute code expiry; the
    /// timeout only guards a hang.
    @discardableResult
    public func login(hub: String, name: String, onCode: @escaping @Sendable (LoginCode) -> Void) async throws -> VaultState {
        let seen = CodeLatch()
        let scopes = loginScopes.flatMap { ["--scope", $0] }
        let result = try await execute(["login", hub, "--json", "--name", name] + scopes, timeout: .seconds(11 * 60)) { event in
            guard event.name == "code",
                  let userCode = event.string("userCode"),
                  let url = event.string("verifyUrl").flatMap(URL.init(string:)),
                  seen.claim() else { return }
            onCode(LoginCode(userCode: userCode, verifyURL: url))
        }
        if Task.isCancelled {
            throw AgentioError("Sign-in was cancelled", exitCode: result.exitCode)
        }
        guard result.exitCode == 0, result.events.contains(where: { $0.name == "approved" }) else {
            throw failure(result, fallback: "Sign-in failed")
        }
        let state = try await vaultState()
        guard case .remote(hub, _) = state else {
            throw AgentioError("agentio finished the sign-in, but does not report this hub", exitCode: 0)
        }
        return state
    }
}

/// The app's agentio while it runs: its process and the --json events it
/// printed so far. Built only by `AgentioCLI.start`.
final class AgentioProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let child: ChildProcess
    private var printed: [CliEvent] = []
    private var unreadable = false

    fileprivate init(_ child: ChildProcess) {
        self.child = child
    }

    /// The child keeps this alive through `onLine` until it finishes.
    fileprivate func start(onEvent: @escaping @Sendable (CliEvent) -> Void) throws {
        try child.start { line, source in
            guard source == .stdout else { return }
            self.read(line, onEvent)
        }
    }

    /// The events printed so far, in order.
    var events: [CliEvent] { lock.withLock { printed } }

    /// Set when it printed a format version this app cannot read.
    var formatError: AgentioError? { lock.withLock { unreadable ? unreadableFormat : nil } }

    func stop() { child.stop() }

    func finished() async -> RunResult { await child.finished() }

    func exited() async -> Int32? { await child.exited() }

    func finished(timeout: Duration) async -> RunResult { await child.finished(timeout: timeout) }

    /// The first line in another format version stops the process; later lines are ignored.
    private func read(_ line: String, _ onEvent: @Sendable (CliEvent) -> Void) {
        let event: CliEvent?
        do {
            event = try parseEvent(line)
        } catch {
            lock.withLock { unreadable = true }
            stop()
            return
        }
        guard let event, lock.withLock({ () -> Bool in
            guard !unreadable else { return false }
            printed.append(event)
            return true
        }) else { return }
        onEvent(event)
    }
}

/// True for the first `claim()` only.
private final class CodeLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
