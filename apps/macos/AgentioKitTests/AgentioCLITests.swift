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

    @Test func failurePrefersTheLastFailureEventOverStderr() throws {
        let events = try [
            #"{"v":1,"event":"error","code":"OLD","message":"first"}"#,
            #"{"v":1,"event":"denied","message":"The owner said no","suggestion":"Ask again"}"#,
            #"{"v":1,"event":"vault","mode":"local"}"#,
        ].compactMap(parseEvent)
        #expect(failure(AgentioResult(exitCode: 3, stderr: "Error [OTHER]: from stderr", events: events), fallback: "x")
                == AgentioError("The owner said no", suggestion: "Ask again", exitCode: 3))
        #expect(failure(AgentioResult(exitCode: 1, stderr: "error: unknown option '--json'"), fallback: "x")
                == AgentioError("error: unknown option '--json'", exitCode: 1))
        #expect(failure(AgentioResult(exitCode: nil), fallback: "x") == AgentioError("x"))
        #expect(failure(AgentioResult(exitCode: 0, stderr: "Waiting…"), fallback: "x") == AgentioError("x", exitCode: 0))
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
            (#"{"v":1,"event":"vault","mode":"remote","hub":"https://h.example","tokenSource":"file","canManageProfiles":true}"#,
             .remote(hub: "https://h.example", canManageProfiles: true)),
            (#"{"v":1,"event":"vault","mode":"remote","hub":"https://h.example","tokenSource":"file","canManageProfiles":false}"#,
             .remote(hub: "https://h.example", canManageProfiles: false)),
            // Anything but a JSON boolean is not an answer: the right stays unknown.
            (#"{"v":1,"event":"vault","mode":"remote","hub":"https://h.example","tokenSource":"file","canManageProfiles":"false"}"#,
             .remote(hub: "https://h.example", canManageProfiles: nil)),
            (#"{"v":1,"event":"vault","mode":"remote","hub":"https://h.example","tokenSource":"file","canManageProfiles":0}"#,
             .remote(hub: "https://h.example", canManageProfiles: nil)),
            (#"{"v":1,"event":"vault","mode":"remote","hub":"https://h.example","tokenSource":"file","canManageProfiles":null}"#,
             .remote(hub: "https://h.example", canManageProfiles: nil)),
        ]
        for (output, state) in outputs {
            let dir = try TempDir(); defer { dir.cleanUp() }
            let cli = try fakeCli(dir, "echo 'agentio log line' >&2; echo '\(output)'")
            #expect(try await cli.vaultState() == state, "output: \(output)")
        }
    }

    @Test func aLastEventWithoutANewlineIsStillRead() async throws {
        for _ in 0..<20 {
            let dir = try TempDir(); defer { dir.cleanUp() }
            let cli = try fakeCli(dir, #"printf '%s' '{"v":1,"event":"vault","mode":"local","configured":true}'"#)
            #expect(try await cli.vaultState() == .local)
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
        #expect(dir.read("home/args") == "login https://h.example --json --name AgentIO Companion on Mac's mini --scope profiles:write --scope profiles:manage\n")
    }

    @Test func returnsTheRightTheHubGaveTheNewKey() async throws {
        for (vault, right) in [(Self.remote.replacing("}", with: #","canManageProfiles":true}"#), Optional(true)),
                               (Self.remote.replacing("}", with: #","canManageProfiles":false}"#), false),
                               (Self.remote, nil)] {
            let dir = try TempDir(); defer { dir.cleanUp() }
            let cli = try loginCli(dir, [Self.codeEvent, Self.approved], vault: vault)
            let state = try await cli.login(hub: "https://h.example", name: "n") { _ in }
            #expect(state == .remote(hub: "https://h.example", canManageProfiles: right), "vault: \(vault)")
        }
    }

    @Test(.timeLimit(.minutes(1))) func aCodeInAnotherFormatStopsTheSignInAtOnce() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, """
        case "$1" in
          login) echo $$ > "$HOME/pid"
                 echo '{"v":2,"event":"code","userCode":"ABCD-1234","verifyUrl":"https://h.example/ui"}'
                 exec sleep 30 ;;
          vault) echo '\(Self.remote)' ;;
        esac
        """)
        let log = CodeLog()
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: unreadableFormat) { try await cli.login(hub: "https://h.example", name: "n", onCode: log.add) }
        #expect(clock.now - start < .seconds(5))
        #expect(log.codes.isEmpty)
        let pid = try #require(dir.read("home/pid").flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        #expect(kill(pid, 0) != 0)
    }

    @Test func ignoresCodesOnStderrAndIncompleteCodeEvents() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, """
        case "$1" in
          login) echo '\(Self.codeEvent)' >&2
                 echo '{"v":1,"event":"code","userCode":"ABCD-1234"}'
                 echo '{"v":1,"event":"code","verifyUrl":"https://h.example/ui"}'
                 echo 'Your code: ABCD-1234'
                 echo '\(Self.approved)' ;;
          vault) echo '\(Self.remote)' ;;
        esac
        """)
        let log = CodeLog()
        try await cli.login(hub: "https://h.example", name: "n", onCode: log.add)
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

struct DevAgentioTests {
    /// A dev AgentioCLI for a checkout in a folder with a space, whose "bun" records
    /// its arguments and HOME, and answers as agentio 3.99.0.
    func devCli(_ dir: TempDir) throws -> AgentioCLI {
        _ = try dir.write("my repo/src/index.ts", "")
        let bun = try dir.write("bun", """
            #!/bin/sh
            printf '%s\\n' "$@" > "\(dir.url.path)/bun-args"
            echo "$HOME" > "\(dir.url.path)/bun-home"
            echo 3.99.0
            """, executable: true)
        return AgentioCLI(location: CliLocation(root: dir.url.appending(path: "cli", directoryHint: .isDirectory)),
                          baseEnvironment: plainEnv,
                          dev: DevAgentio(repo: dir.url.appending(path: "my repo", directoryHint: .isDirectory), bun: bun))
    }

    @Test func runsTheCheckoutWithBunInsteadOfTheAppsBinary() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try devCli(dir)
        let info = try #require(await cli.detect())
        #expect(info == CliInfo(path: try #require(cli.dev).entry, version: "3.99.0"))
        #expect(dir.read("bun-args") == "\(dir.url.path)/my repo/src/index.ts\n--version\n")
        #expect(dir.read("bun-home") == cli.location.homeDir.path + "\n")
    }

    @Test func theAppNeverInstallsOverACheckout() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try devCli(dir)
        let repo = dir.url.appending(path: "my repo").path
        await #expect(throws: AgentioError("The dev AgentIO in \(repo) does not run, or is older than 4.0.0. The app does not install over it: fix the checkout, or remove the devAgentioRepo setting.")) {
            try await cli.install(atLeast: CliVersion("4.0.0")!, fetchScript: { Issue.record("fetched the installer"); return Data() }) { _ in
                Issue.record("reported install progress")
            }
        }
        #expect(!FileManager.default.fileExists(atPath: cli.location.binDir.path))
    }

    @Test func aMissingBunOrEntryIsNamedInTheError() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let location = CliLocation(root: dir.url.appending(path: "cli", directoryHint: .isDirectory))
        let noBun = AgentioCLI(location: location, baseEnvironment: plainEnv,
                               dev: DevAgentio(repo: dir.url, bun: dir.url.appending(path: "nowhere/bun")))
        await #expect(throws: AgentioError("bun is not at \(dir.url.path)/nowhere/bun. Install bun, or remove the devAgentioRepo setting.")) {
            try await noBun.install(atLeast: minimumCliVersion) { _ in }
        }
        let bun = try dir.write("bun", "#!/bin/sh\n", executable: true)
        let noEntry = AgentioCLI(location: location, baseEnvironment: plainEnv, dev: DevAgentio(repo: dir.url, bun: bun))
        await #expect(throws: AgentioError("\(dir.url.path)/src/index.ts does not exist. Check the devAgentioRepo setting.")) {
            try await noEntry.install(atLeast: minimumCliVersion) { _ in }
        }
    }

    @Test func bunIsTheFirstFileThatCanRun() throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let missing = dir.url.appending(path: "a/bun")
        let notExecutable = try dir.write("b/bun", "")
        let folder = dir.url.appending(path: "c/bun", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = try dir.write("d/bun", "#!/bin/sh\n", executable: true)
        #expect(DevAgentio.findBun(in: [missing, notExecutable, folder, executable]) == executable)
        // None: the first, so the error says where bun should be.
        #expect(DevAgentio.findBun(in: [missing, notExecutable, folder]) == missing)
    }

    @Test func theTerminalRunsTheCheckoutToo() throws {
        let cli = AgentioCLI(location: CliLocation(root: URL(filePath: "/tmp/x y/cli")), baseEnvironment: plainEnv,
                             dev: DevAgentio(repo: URL(filePath: "/src/my agentio"), bun: URL(filePath: "/b/bun")))
        let command = try cli.terminalProfileAdd("gcal", readOnly: true)
        #expect(command.executable.path == "/b/bun")
        #expect(command.arguments == ["/src/my agentio/src/index.ts", "gcal", "profile", "add", "--read-only"])
        #expect(command.environment["HOME"] == "/tmp/x y/cli/home")
    }
}
