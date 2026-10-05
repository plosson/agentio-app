import Foundation
import Testing
@testable import AgentioKit

/// The real daemon's first event, for a fake to print.
let listening = #"{"v":1,"event":"listening","url":"http://127.0.0.1:63168","locked":true}"#

struct StartDaemonTests {
    @Test func returnsTheReportedURLAndStopEndsIt() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, """
        echo "$@" > "$HOME/args"; echo 'agentio-daemon starting' >&2; echo 'not an event'
        sleep 0.3; echo '\(listening)'; exec sleep 30
        """)
        let daemon = try await cli.startDaemon()
        #expect(daemon.url == URL(string: "http://127.0.0.1:63168"))
        #expect(dir.read("home/args") == "daemon start --host 127.0.0.1 --port 0 --json\n")
        await daemon.stop()
        await daemon.waitForExit()
    }

    @Test func anEventSplitAcrossWritesIsStillRead() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let half = listening.count / 2
        let cli = try fakeCli(dir, """
        printf '%s' '\(listening.prefix(half))'; sleep 0.2; echo '\(listening.dropFirst(half))'; exec sleep 30
        """)
        let daemon = try await cli.startDaemon()
        #expect(daemon.url == URL(string: "http://127.0.0.1:63168"))
        await daemon.stop()
    }

    @Test func errorEventIsThrownAndTheProcessIsGone() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        // Like a port in use, but the fake keeps running after its error.
        let cli = try fakeCli(dir, """
        echo $$ > "$HOME/pid"
        echo '{"v":1,"event":"error","code":"CONFIG_ERROR","message":"Cannot listen on 127.0.0.1:0","suggestion":"Pick another port"}'
        exec sleep 30
        """)
        await #expect(throws: AgentioError("Cannot listen on 127.0.0.1:0", code: "CONFIG_ERROR", suggestion: "Pick another port")) {
            try await cli.startDaemon()
        }
        let pid = try #require(dir.read("home/pid").flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        #expect(kill(pid, 0) != 0)
    }

    @Test func anErrorPrintedJustBeforeExitingIsNotLost() async throws {
        for _ in 0..<5 {
            let dir = try TempDir(); defer { dir.cleanUp() }
            let cli = try fakeCli(dir, #"echo '{"v":1,"event":"error","code":"VAULT_LOCKED","message":"Unlock first"}'; exit 3"#)
            await #expect(throws: AgentioError("Unlock first", code: "VAULT_LOCKED")) { try await cli.startDaemon() }
        }
    }

    @Test func exitWithoutAnEventReportsTheExitCode() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, "echo \"error: unknown option '--json'\" >&2; exit 1")
        await #expect(throws: AgentioError("The agentio daemon stopped while starting", exitCode: 1)) {
            try await cli.startDaemon()
        }
    }

    @Test func anotherFormatVersionIsRefused() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo '{"v":2,"event":"listening","url":"http://127.0.0.1:1"}'; exec sleep 30"#)
        await #expect(throws: unreadableFormat) { try await cli.startDaemon() }
    }

    @Test func aListeningEventWithoutAURLIsIgnored() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo '{"v":1,"event":"listening","locked":true}'; exit 0"#)
        await #expect(throws: AgentioError("The agentio daemon stopped while starting", exitCode: 0)) {
            try await cli.startDaemon()
        }
    }

    @Test func silentTimesOutAndLeavesNoProcess() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"[ "$1" = --version ] && { echo 3.12.2; exit 0; }; echo $$ > "$HOME/pid"; exec sleep 30"#)
        // Run it once first: macOS scans a new script on its first run, which can outlast the timeout.
        #expect(await cli.detect() != nil)
        await #expect(throws: AgentioError("The agentio daemon did not start in time")) {
            try await cli.startDaemon(startTimeout: .seconds(1))
        }
        let pid = try #require(dir.read("home/pid").flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) })
        #expect(kill(pid, 0) != 0)
    }

    @Test func stopKillsADaemonThatIgnoresSigterm() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, "trap '' TERM; echo '\(listening)'; while true; do sleep 0.1; done")
        let daemon = try await cli.startDaemon(stopGrace: .milliseconds(300))
        let clock = ContinuousClock()
        let start = clock.now
        await daemon.stop()
        #expect(clock.now - start < .seconds(3))
    }

    @Test func stoppingTwiceIsHarmless() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, "echo '\(listening)'; exec sleep 30")
        let daemon = try await cli.startDaemon()
        await daemon.stop()
        await daemon.stop()
    }
}
