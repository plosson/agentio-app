import Foundation

/*
 * The only place that reads the CLI's output, apart from the daemon's
 * events (Daemon.swift). Commands run with --json: one JSON object per
 * stdout line, each with the output format version `v` and an `event`
 * (agentio#87). `vault init` has no --json, so only its exit code matters.
 */

/// The `--json` output format this app reads (agentio's JSON_OUTPUT_VERSION).
let jsonOutputVersion = 1

/// One `--json` event. The fields are JSONSerialization values, never mutated.
struct CliEvent: @unchecked Sendable {
    let name: String
    let fields: [String: Any]

    func string(_ key: String) -> String? { fields[key] as? String }

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

/// Every event a finished command printed, in order.
func events(in stdout: String) throws -> [CliEvent] {
    try stdout.split(whereSeparator: \.isNewline).compactMap { try parseEvent(String($0)) }
}

/// Why a command failed: its last error event. Without one, stderr (only
/// logs in JSON mode) explains a failing exit, such as an unknown option.
func failure(_ result: RunResult, _ events: [CliEvent], fallback: String) -> AgentioError {
    let failures: Set<String> = ["error", "denied", "expired"]
    if let event = events.last(where: { failures.contains($0.name) }) {
        return event.error(exitCode: result.exitCode)
    }
    if result.exitCode == 0 { return AgentioError(fallback, exitCode: 0) }
    return cliError(stderr: result.stderr, exitCode: result.exitCode, fallback: fallback)
}

/// Where the app's CLI keeps credentials.
public enum VaultState: Sendable, Equatable {
    case none
    case local
    case remote(hub: String)
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
    /// The app's environment; `env` removes the user's AGENTIO_* settings.
    public let baseEnvironment: [String: String]

    public init(location: CliLocation, baseEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.location = location
        self.baseEnvironment = baseEnvironment
    }

    var env: [String: String] { cliEnv(location, base: baseEnvironment) }

    func options(timeout: Duration, input: String? = nil,
                 onLine: (@Sendable (String, OutputSource) -> Void)? = nil) -> RunOptions {
        RunOptions(environment: env, timeout: timeout, input: input, onLine: onLine)
    }

    /// The installed CLI's `--version`; nil if it is missing or does not run.
    /// The first run of a new binary waits for macOS's malware scan, which
    /// takes seconds, so the timeout is generous.
    public func detect(timeout: Duration = .seconds(30)) async -> CliInfo? {
        guard let result = try? await run(location.binPath, ["--version"], options(timeout: timeout)) else {
            return nil
        }
        let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.exitCode == 0 && !version.isEmpty ? CliInfo(path: location.binPath, version: version) : nil
    }

    /// `vault status --json`: remote mode names the hub; a local vault that
    /// is not configured yet is `none`. It never prompts.
    public func vaultState() async throws -> VaultState {
        let result = try await run(location.binPath, ["vault", "status", "--json"], options(timeout: .seconds(30)))
        let printed = try events(in: result.stdout)
        guard result.exitCode == 0, let vault = printed.last(where: { $0.name == "vault" }) else {
            throw failure(result, printed, fallback: "agentio vault status failed")
        }
        switch vault.string("mode") {
        case "remote":
            guard let hub = vault.string("hub") else {
                throw AgentioError("agentio reported a remote vault without its hub", exitCode: 0)
            }
            return .remote(hub: hub)
        case "local":
            return vault.fields["configured"] as? Bool == true ? .local : .none
        default:
            throw AgentioError("agentio reported an unknown vault mode", exitCode: 0)
        }
    }

    /// Create a local vault. The passphrase goes through stdin, never argv.
    public func initVault(passphrase: String) async throws {
        let result = try await run(location.binPath, ["vault", "init", "--passphrase-stdin", "--no-migrate"],
                                   options(timeout: .seconds(30), input: passphrase))
        if result.exitCode != 0 {
            throw cliError(stderr: result.stderr, exitCode: result.exitCode, fallback: "Could not create the vault")
        }
    }

    /// Sign in to a hub with `agentio login --json`, which stores a key
    /// token in the CLI's home. `onCode` gets the `code` event's code and
    /// approval page as soon as it is printed. Success is the `approved`
    /// event, confirmed with `vaultState`. The CLI gives up after its
    /// 10-minute code expiry; the timeout only guards a hang.
    public func login(hub: String, name: String, onCode: @escaping @Sendable (LoginCode) -> Void) async throws {
        let seen = CodeLatch()
        let result = try await run(location.binPath, ["login", hub, "--json", "--name", name],
                                   options(timeout: .seconds(11 * 60)) { line, source in
            guard source == .stdout, let event = try? parseEvent(line), event.name == "code",
                  let userCode = event.string("userCode"),
                  let url = event.string("verifyUrl").flatMap(URL.init(string:)),
                  seen.claim() else { return }
            onCode(LoginCode(userCode: userCode, verifyURL: url))
        })
        if Task.isCancelled {
            throw AgentioError("Sign-in was cancelled", exitCode: result.exitCode)
        }
        let printed = try events(in: result.stdout)
        guard result.exitCode == 0, printed.contains(where: { $0.name == "approved" }) else {
            throw failure(result, printed, fallback: "Sign-in failed")
        }
        guard try await vaultState() == .remote(hub: hub) else {
            throw AgentioError("agentio finished the sign-in, but does not report this hub", exitCode: 0)
        }
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
