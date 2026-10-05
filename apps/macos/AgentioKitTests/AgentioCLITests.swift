import Foundation
import Testing
@testable import AgentioKit

/// An AgentioCLI whose `agentio` is the given shell script body.
func fakeCli(_ dir: TempDir, _ script: String, base: [String: String] = ["PATH": "/usr/bin:/bin"]) throws -> AgentioCLI {
    let location = CliLocation(root: dir.url)
    try FileManager.default.createDirectory(at: location.homeDir, withIntermediateDirectories: true)
    _ = try dir.write("bin/agentio", "#!/bin/sh\n" + script, executable: true)
    return AgentioCLI(location: location, baseEnvironment: base)
}

struct EventTests {
    @Test func readsAnEventAndIgnoresOtherLines() throws {
        let event = try #require(try parseEvent(#"{"v":1,"event":"vault","mode":"local"}"#))
        #expect(event.name == "vault")
        #expect(event.string("mode") == "local")
        for line in ["", "Vault is locked", "[]", "null", #"{"v":1}"#, #"{"v":1,"event":42}"#, #"{"event":"#] {
            #expect(try parseEvent(line) == nil, "line: \(line)")
        }
    }

    @Test func anotherFormatVersionIsRefused() {
        for line in [#"{"v":2,"event":"vault"}"#, #"{"event":"vault"}"#, #"{"v":"1","event":"vault"}"#, #"{"v":1.5,"event":"vault"}"#] {
            #expect(throws: unreadableFormat, "line: \(line)") { try parseEvent(line) }
        }
    }

    @Test func failurePrefersTheLastErrorEventOverStderr() throws {
        let stdout = """
        {"v":1,"event":"error","code":"OLD","message":"first"}
        {"v":1,"event":"denied","message":"The owner said no","suggestion":"Ask again"}
        """
        let result = RunResult(exitCode: 3, stdout: stdout, stderr: "Error [OTHER]: from stderr")
        #expect(failure(result, try events(in: stdout), fallback: "x")
                == AgentioError("The owner said no", suggestion: "Ask again", exitCode: 3))
        #expect(failure(RunResult(exitCode: 1, stdout: "", stderr: "error: unknown option '--json'"), [], fallback: "x")
                == AgentioError("error: unknown option '--json'", exitCode: 1))
        #expect(failure(RunResult(exitCode: nil, stdout: "", stderr: ""), [], fallback: "x") == AgentioError("x"))
        #expect(failure(RunResult(exitCode: 0, stdout: "", stderr: "Waiting…"), [], fallback: "x") == AgentioError("x", exitCode: 0))
    }
}

struct VaultStateTests {
    @Test func readsTheModeFromVaultStatus() async throws {
        let outputs: [(String, VaultState)] = [
            (#"{"v":1,"event":"vault","mode":"local","configured":false}"#, .none),
            (#"{"v":1,"event":"vault","mode":"local","configured":true,"path":"/v.enc","exists":true,"locked":false,"profiles":0}"#, .local),
            (#"{"v":1,"event":"vault","mode":"local","configured":true,"path":"/v.enc","exists":false}"#, .local),
            (#"{"v":1,"event":"vault","mode":"remote","hub":"https://h.example","tokenSource":"file"}"#, .remote(hub: "https://h.example")),
            (#"{"v":1,"event":"vault","mode":"local","configured":"true"}"#, .none),
        ]
        for (output, state) in outputs {
            let dir = try TempDir(); defer { dir.cleanUp() }
            let cli = try fakeCli(dir, "echo 'agentio log line' >&2; echo '\(output)'")
            #expect(try await cli.vaultState() == state, "output: \(output)")
        }
    }

    @Test func errorEventThrowsTheCliError() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo '{"v":1,"event":"error","code":"VAULT_CORRUPT","message":"Broken","suggestion":"Restore it"}'; exit 2"#)
        await #expect(throws: AgentioError("Broken", code: "VAULT_CORRUPT", suggestion: "Restore it", exitCode: 2)) { try await cli.vaultState() }
    }

    @Test func aVaultEventWithAFailingExitIsStillAFailure() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo '{"v":1,"event":"vault","mode":"local","configured":true}'; echo 'Error: crashed' >&2; exit 1"#)
        await #expect(throws: AgentioError("crashed", exitCode: 1)) { try await cli.vaultState() }
    }

    @Test func rejectsWhatIsNotAVaultEvent() async throws {
        let outputs = ["not json", "{}", #"{"v":1,"event":"other"}"#, #"{"v":1,"event":"vault","mode":"remote"}"#,
                       #"{"v":1,"event":"vault","mode":"remote","hub":42}"#, #"{"v":1,"event":"vault","mode":"cloud"}"#,
                       #"{"v":1,"event":"vault"}"#, #"{"v":2,"event":"vault","mode":"local","configured":true}"#]
        for output in outputs {
            let dir = try TempDir(); defer { dir.cleanUp() }
            let cli = try fakeCli(dir, "echo '\(output)'")
            await #expect(throws: AgentioError.self, "output: \(output)") { try await cli.vaultState() }
        }
    }

    @Test func anOldCliWithoutJsonFailsWithItsMessage() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, "echo \"error: unknown option '--json'\" >&2; exit 1")
        await #expect(throws: AgentioError("error: unknown option '--json'", exitCode: 1)) { try await cli.vaultState() }
    }

    @Test func passesExactArgumentsAndTheAppsHome() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo "$@|$HOME|$AGENTIO_TOKEN|$NO_COLOR" > "$HOME/args"; echo '{"v":1,"event":"vault","mode":"local","configured":false}'"#,
                              base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/real", "AGENTIO_TOKEN": "agio1.x"])
        _ = try await cli.vaultState()
        #expect(dir.read("home/args") == "vault status --json|\(cli.location.homeDir.path)||1\n")
    }

    @Test func missingBinaryThrows() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url), baseEnvironment: plainEnv)
        await #expect(throws: (any Error).self) { try await cli.vaultState() }
    }
}

struct InitVaultTests {
    @Test func passphraseGoesThroughStdinNotArguments() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo "$@" > "$HOME/args"; cat > "$HOME/stdin""#)
        let passphrase = "pa ss\nwörd'\"$(x)"
        try await cli.initVault(passphrase: passphrase)
        #expect(dir.read("home/args") == "vault init --passphrase-stdin --no-migrate\n")
        #expect(dir.read("home/stdin") == passphrase)
    }

    @Test func failureCarriesTheCliMessage() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, "cat >/dev/null; echo 'Error [CONFIG_ERROR]: A vault is already configured at /v.enc' >&2; echo 'Suggestion: Use `agentio vault set` to switch' >&2; exit 3")
        await #expect(throws: AgentioError("A vault is already configured at /v.enc", code: "CONFIG_ERROR",
                                           suggestion: "Use `agentio vault set` to switch", exitCode: 3)) {
            try await cli.initVault(passphrase: "12345678")
        }
    }
}

/// Codes passed to `onCode`, collected across threads.
final class CodeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [LoginCode] = []
    func add(_ code: LoginCode) { lock.withLock { stored.append(code) } }
    var codes: [LoginCode] { lock.withLock { stored } }
}

struct LoginTests {
    static let remote = #"{"v":1,"event":"vault","mode":"remote","hub":"https://h.example","tokenSource":"file"}"#
    static let codeEvent = #"{"v":1,"event":"code","userCode":"388P-V9XB","verifyUrl":"https://h.example/ui#authorize=388P-V9XB","expiresIn":600}"#
    static let approved = #"{"v":1,"event":"approved","url":"https://h.example","key":{"id":"k1","name":"n","canManageProfiles":true}}"#

    /// `login` prints `lines` on stdout, then exits `exit`; `vault status` prints `vault`.
    func loginCli(_ dir: TempDir, _ lines: [String], exit: Int = 0, vault: String = remote) throws -> AgentioCLI {
        try fakeCli(dir, """
        case "$1" in
          login) echo "$@" > "$HOME/args"; echo 'Waiting…' >&2; \(lines.map { "echo '\($0)'" }.joined(separator: "; ")); exit \(exit) ;;
          vault) echo '\(vault)' ;;
        esac
        """)
    }

    @Test func reportsTheFirstCodeOnlyAndPassesTheName() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let second = Self.codeEvent.replacing("388P-V9XB", with: "WXYZ-9876")
        let cli = try loginCli(dir, [Self.codeEvent, second, Self.approved])
        let log = CodeLog()
        try await cli.login(hub: "https://h.example", name: "AgentIO Companion on Mac's mini", onCode: log.add)
        #expect(log.codes == [LoginCode(userCode: "388P-V9XB", verifyURL: URL(string: "https://h.example/ui#authorize=388P-V9XB")!)])
        #expect(dir.read("home/args") == "login https://h.example --json --name AgentIO Companion on Mac's mini\n")
    }

    @Test func ignoresCodesOnStderrAndIncompleteCodeEvents() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, """
        case "$1" in
          login) echo '\(Self.codeEvent)' >&2
                 echo '{"v":1,"event":"code","userCode":"ABCD-1234"}'
                 echo '{"v":1,"event":"code","verifyUrl":"https://h.example/ui"}'
                 echo '{"v":2,"event":"code","userCode":"ABCD-1234","verifyUrl":"https://h.example/ui"}'
                 echo 'Your code: ABCD-1234'
                 echo '\(Self.approved)' ;;
          vault) echo '\(Self.remote)' ;;
        esac
        """)
        let log = CodeLog()
        await #expect(throws: AgentioError.self) { try await cli.login(hub: "https://h.example", name: "n", onCode: log.add) }
        #expect(log.codes.isEmpty)
    }

    @Test(arguments: [
        (#"{"v":1,"event":"denied","message":"The hub owner denied this login","suggestion":"Ask them"}"#, 3,
         AgentioError("The hub owner denied this login", suggestion: "Ask them", exitCode: 3)),
        (#"{"v":1,"event":"expired","message":"The code expired"}"#, 3, AgentioError("The code expired", exitCode: 3)),
        (#"{"v":1,"event":"error","code":"NETWORK_ERROR","message":"Cannot reach the vault hub"}"#, 4,
         AgentioError("Cannot reach the vault hub", code: "NETWORK_ERROR", exitCode: 4)),
    ])
    func refusalsThrowTheirMessage(line: String, exit: Int, expected: AgentioError) async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try loginCli(dir, [Self.codeEvent, line], exit: exit)
        await #expect(throws: expected) { try await cli.login(hub: "https://h.example", name: "n") { _ in } }
    }

    @Test func exitZeroWithoutApprovalIsAFailure() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try loginCli(dir, [Self.codeEvent])
        await #expect(throws: AgentioError("Sign-in failed", exitCode: 0)) {
            try await cli.login(hub: "https://h.example", name: "n") { _ in }
        }
    }

    @Test func approvalForAnotherHubIsAFailure() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try loginCli(dir, [Self.approved], vault: Self.remote.replacing("h.example", with: "other.example"))
        await #expect(throws: AgentioError("agentio finished the sign-in, but does not report this hub", exitCode: 0)) {
            try await cli.login(hub: "https://h.example", name: "n") { _ in }
        }
    }

    @Test func cancellingStopsTheLoginAndSaysSo() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, "echo '\(Self.codeEvent)'; exec sleep 30")
        let log = CodeLog()
        let task = Task { try await cli.login(hub: "https://h.example", name: "n", onCode: log.add) }
        while log.codes.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        task.cancel()
        await #expect(throws: AgentioError("Sign-in was cancelled")) { try await task.value }
    }
}

struct DetectTests {
    @Test func aCliThatFailsOrPrintsNothingIsNotInstalled() async throws {
        for script in ["exit 1", "exit 0", "echo '  '"] {
            let dir = try TempDir(); defer { dir.cleanUp() }
            let cli = try fakeCli(dir, script)
            #expect(await cli.detect() == nil, "script: \(script)")
        }
    }

    @Test func aHangingCliIsNotInstalled() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, "exec sleep 30")
        #expect(await cli.detect(timeout: .seconds(1)) == nil)
    }

    @Test func waitsForASlowFirstRun() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        // macOS scans a new binary before its first run; that can take seconds.
        let cli = try fakeCli(dir, "sleep 6; echo 3.12.2")
        #expect(await cli.detect()?.version == "3.12.2")
    }

    @Test func missingCliIsNotInstalled() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        #expect(await AgentioCLI(location: CliLocation(root: dir.url), baseEnvironment: plainEnv).detect() == nil)
    }
}
