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

    @Test func theFormsEnvironmentIsUnchanged() {
        // The pipes the app reads still need plain text.
        let loc = CliLocation(root: URL(filePath: "/tmp/c"))
        #expect(cliEnv(loc, base: [:])["NO_COLOR"] == "1")
    }
}
