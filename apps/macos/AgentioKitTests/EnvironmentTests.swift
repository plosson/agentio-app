import Foundation
import Testing
@testable import AgentioKit

struct EnvironmentTests {
    @Test func dropsEveryAgentioVariableAndForcedColour() {
        let env = isolatedEnv([
            "AGENTIO_TOKEN": "agio1.secret", "AGENTIO_VERSION": "9.9.9", "AGENTIO_": "x",
            "FORCE_COLOR": "1", "CLICOLOR_FORCE": "1", "PATH": "/usr/bin", "NO_COLOR": "0",
        ])
        #expect(env == ["PATH": "/usr/bin", "NO_COLOR": "1"])
    }

    @Test func keepsVariablesThatOnlyContainAgentio() {
        let env = isolatedEnv(["MY_AGENTIO_TOKEN": "keep", "agentio_lower": "keep"])
        #expect(env["MY_AGENTIO_TOKEN"] == "keep")
        #expect(env["agentio_lower"] == "keep")
    }

    @Test func cliEnvReplacesTheUsersHome() {
        let loc = CliLocation(root: URL(filePath: "/tmp/x y/cli"))
        let env = cliEnv(loc, base: ["HOME": "/Users/someone", "AGENTIO_TOKEN": "t"])
        #expect(env["HOME"] == "/tmp/x y/cli/home")
        #expect(env["AGENTIO_TOKEN"] == nil)
    }

    @Test func appDefaultIsUnderApplicationSupportByBundleID() {
        let loc = CliLocation.appDefault(applicationSupport: URL(filePath: "/Users/u/Library/Application Support"),
                                         bundleID: "com.plosson.agentio-companion")
        #expect(loc.binPath.path == "/Users/u/Library/Application Support/com.plosson.agentio-companion/cli/bin/agentio")
        #expect(loc.homeDir.path == "/Users/u/Library/Application Support/com.plosson.agentio-companion/cli/home")
    }

    @Test func stripsColourAndCursorSequencesOnly() {
        #expect(stripAnsi("\u{1B}[1;31mError\u{1B}[0m: x\u{1B}[2K\u{1B}[?25l") == "Error: x")
        #expect(stripAnsi("50% [done]") == "50% [done]")
    }
}

struct CliErrorTests {
    @Test func readsCodeMessageAndSuggestion() {
        let err = cliError(stderr: "noise\nError [VAULT_LOCKED]: The vault is locked\nSuggestion: Run agentio unlock\n", exitCode: 2, fallback: "f")
        #expect(err == AgentioError("The vault is locked", code: "VAULT_LOCKED", suggestion: "Run agentio unlock", exitCode: 2))
    }

    @Test func aLaterPlainErrorReplacesAnEarlierCode() {
        let err = cliError(stderr: "Error [A_B]: first\nError: second", exitCode: 1, fallback: "f")
        #expect(err.code == nil)
        #expect(err.message == "second")
    }

    @Test func lowercaseCodeIsNotACode() {
        let err = cliError(stderr: "Error [bad]: nope", exitCode: 1, fallback: "f")
        #expect(err.code == nil)
        #expect(err.message == "Error [bad]: nope")
    }

    @Test func fallsBackToLastNonBlankLineThenToFallback() {
        #expect(cliError(stderr: "a\n  b  \n\n \r\n", exitCode: 1, fallback: "f").message == "b")
        #expect(cliError(stderr: " \n", exitCode: nil, fallback: "f").message == "f")
    }
}
