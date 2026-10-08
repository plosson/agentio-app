import Foundation
import Testing
@testable import AgentioKit

struct TerminalCommandTests {
    let cli = AgentioCLI(location: CliLocation(root: URL(filePath: "/tmp/x y/cli")),
                         baseEnvironment: ["HOME": "/Users/someone", "PATH": "/usr/bin:/bin", "AGENTIO_TOKEN": "agio1.secret",
                                           "FORCE_COLOR": "1", "CLICOLOR_FORCE": "1", "NO_COLOR": "1", "TERM": "dumb"])

    @Test func runsTheAppsOwnBinaryWithProfileAdd() throws {
        let command = try cli.terminalProfileAdd("gcal", readOnly: false)
        #expect(command.executable.path == "/tmp/x y/cli/bin/agentio")
        #expect(command.arguments == ["gcal", "profile", "add"])
    }

    @Test func readOnlyAddsTheFlag() throws {
        #expect(try cli.terminalProfileAdd("gcal", readOnly: true).arguments == ["gcal", "profile", "add", "--read-only"])
    }

    @Test func refusesAnythingThatIsNotAServiceID() {
        for bad in ["", "GCAL", "-h", "--describe", "gcal profile", "../x", "gcal;rm", "gcal\n"] {
            #expect(throws: invalidService(bad), "service: \(bad)") { try cli.terminalProfileAdd(bad, readOnly: false) }
        }
    }

    @Test func signingInAgainRunsProfileReauthWithTheServiceAndTheName() throws {
        let command = try cli.terminalProfileReauth("gcal", profile: "pa@example.com")
        #expect(command.executable.path == "/tmp/x y/cli/bin/agentio")
        #expect(command.arguments == ["profile", "reauth", "gcal", "pa@example.com"])
        #expect(command.environment == (try cli.terminalProfileAdd("gcal", readOnly: false)).environment)
    }

    @Test func signingInAgainRefusesAServiceOrANameThatCouldBeReadAsSomethingElse() {
        for bad in ["", "-h", "--json", "gcal profile", "gcal\n"] {
            #expect(throws: invalidService(bad), "service: \(bad)") { try cli.terminalProfileReauth(bad, profile: "work") }
        }
        for bad in ["", "-x", "--json", "a\nb", String(repeating: "a", count: 201)] {
            #expect(throws: AgentioError.self, "profile: \(bad)") { try cli.terminalProfileReauth("gcal", profile: bad) }
        }
    }

    @Test func theUsersAgentioSettingsAndForcedColourDoNotReachTheTerminal() throws {
        let env = try cli.terminalProfileAdd("gcal", readOnly: false).environment
        #expect(env["AGENTIO_TOKEN"] == nil)
        #expect(env["FORCE_COLOR"] == nil)
        #expect(env["CLICOLOR_FORCE"] == nil)
        #expect(env["HOME"] == "/tmp/x y/cli/home")
        #expect(env["PATH"] == "/usr/bin:/bin")
    }

    @Test func theTerminalGetsColourAndAKnownTerminalType() throws {
        let env = try cli.terminalProfileAdd("gcal", readOnly: false).environment
        #expect(env["NO_COLOR"] == nil)
        #expect(env["TERM"] == "xterm-256color")
    }

    @Test func thePipedEnvironmentStaysPlain() {
        // The pipes the app reads still need plain text.
        let loc = CliLocation(root: URL(filePath: "/tmp/c"))
        #expect(cliEnv(loc, base: [:])["NO_COLOR"] == "1")
    }
}

struct TerminalExitTests {
    @Test func aWaitStatusDecodesToItsExitCode() {
        #expect(exitCode(fromWaitStatus: 0) == 0)
        #expect(exitCode(fromWaitStatus: 1 << 8) == 1)
        #expect(exitCode(fromWaitStatus: 130 << 8) == 130)
        #expect(exitCode(fromWaitStatus: 255 << 8) == 255)
    }

    @Test func aSignalDecodesToNil() {
        for signal: Int32 in [SIGTERM, SIGINT, SIGKILL, SIGHUP, SIGTERM | 0x80] {
            #expect(exitCode(fromWaitStatus: signal) == nil, "status: \(signal)")
        }
    }

    /// A child that is not reaped yet: its own status wins over the 0 a too-early WNOHANG reported.
    @Test func anUnreapedChildGivesItsRealStatus() throws {
        let pid = try spawn("exit 3")
        #expect(reapedExitCode(pid: pid, reported: 0) == 3)
        let killed = try spawn("kill -KILL $$")
        #expect(reapedExitCode(pid: killed, reported: 0) == nil)
    }

    /// A child someone else reaped: the reported status, decoded.
    @Test func anAlreadyReapedChildGivesTheReportedStatus() throws {
        let pid = try spawn("exit 4")
        var status: Int32 = 0
        #expect(waitpid(pid, &status, 0) == pid)
        #expect(reapedExitCode(pid: pid, reported: status) == 4)
        #expect(reapedExitCode(pid: pid, reported: SIGTERM) == nil)
    }

    private func spawn(_ script: String) throws -> pid_t {
        var pid: pid_t = 0
        let args = ["/bin/sh", "-c", script]
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let result = posix_spawn(&pid, "/bin/sh", nil, nil, &argv, nil)
        guard result == 0 else { throw AgentioError("posix_spawn failed: \(result)") }
        return pid
    }
}
