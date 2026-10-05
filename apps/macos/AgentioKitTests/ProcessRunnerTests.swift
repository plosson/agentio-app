import Foundation
import Testing
@testable import AgentioKit

/// Lines passed to `onLine`, collected across threads.
final class LineLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, OutputSource)] = []

    func add(_ line: String, _ source: OutputSource) { lock.withLock { entries.append((line, source)) } }
    func lines(_ source: OutputSource) -> [String] { lock.withLock { entries.filter { $0.1 == source }.map(\.0) } }
}

struct ProcessRunnerTests {
    @Test func collectsOutputAndANonZeroExitWithoutThrowing() async throws {
        let result = try await run(sh, ["-c", "echo out; echo err >&2; exit 3"], RunOptions(environment: plainEnv, timeout: .seconds(5)))
        #expect(result == RunResult(exitCode: 3, stdout: "out\n", stderr: "err\n"))
    }

    @Test func throwsWhenTheCommandCannotStart() async {
        await #expect(throws: (any Error).self) {
            try await run(URL(filePath: "/nonexistent/agentio"), [], RunOptions(environment: plainEnv, timeout: .seconds(5)))
        }
    }

    @Test func splitsLinesOnCarriageReturnsAndAcrossWrites() async throws {
        let log = LineLog()
        let script = "printf 'one\\r##  4'; sleep 0.1; printf '2%%\\rtwo\\nthr'; sleep 0.1; printf 'ee'"
        _ = try await run(sh, ["-c", script], RunOptions(environment: plainEnv, timeout: .seconds(5), onLine: log.add))
        #expect(log.lines(.stdout) == ["one", "##  42%", "two", "three"])
    }

    @Test func keepsAMultiByteCharacterSplitAcrossWrites() async throws {
        let log = LineLog()
        // "é" is 0xC3 0xA9; write the two bytes separately.
        let result = try await run(sh, ["-c", "printf 'caf\\303'; sleep 0.1; printf '\\251\\n'"],
                                   RunOptions(environment: plainEnv, timeout: .seconds(5), onLine: log.add))
        #expect(log.lines(.stdout) == ["café"])
        #expect(result.stdout == "café\n")
    }

    @Test func stripsColourFromLinesAndOutput() async throws {
        let log = LineLog()
        let result = try await run(sh, ["-c", "printf '\\033[31mYour code: AB\\033[0m\\n' >&2"],
                                   RunOptions(environment: plainEnv, timeout: .seconds(5), onLine: log.add))
        #expect(log.lines(.stderr) == ["Your code: AB"])
        #expect(result.stderr == "Your code: AB\n")
    }

    @Test func passesInputOnStdinAndClosesIt() async throws {
        let result = try await run(sh, ["-c", "cat"], RunOptions(environment: plainEnv, timeout: .seconds(5), input: "pass word\nwith ü"))
        #expect(result.stdout == "pass word\nwith ü")
    }

    @Test func stdinIsEmptyWithoutInput() async throws {
        let result = try await run(sh, ["-c", "cat; echo end"], RunOptions(environment: plainEnv, timeout: .seconds(5)))
        #expect(result.stdout == "end\n")
    }

    @Test func survivesAChildThatExitsWithoutReadingLargeInput() async throws {
        let input = String(repeating: "x", count: 1_000_000)
        let result = try await run(sh, ["-c", "exit 4"], RunOptions(environment: plainEnv, timeout: .seconds(5), input: input))
        #expect(result.exitCode == 4)
    }

    @Test func usesOnlyTheGivenEnvironment() async throws {
        let result = try await run(sh, ["-c", "echo \"[$HOME][$AGENTIO_TOKEN]\""],
                                   RunOptions(environment: ["PATH": "/usr/bin:/bin", "HOME": "/h"], timeout: .seconds(5)))
        #expect(result.stdout == "[/h][]\n")
    }

    @Test func timeoutKillsAndReportsNoExitCode() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await run(sh, ["-c", "echo started; exec sleep 30"], RunOptions(environment: plainEnv, timeout: .milliseconds(300)))
        #expect(result.exitCode == nil)
        #expect(result.stdout == "started\n")
        #expect(clock.now - start < .seconds(5))
    }

    @Test(.timeLimit(.minutes(1))) func aTimeoutForcesACommandThatIgnoresSigterm() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await run(sh, ["-c", "trap '' TERM; echo started; while true; do sleep 0.1; done"],
                                   RunOptions(environment: plainEnv, timeout: .milliseconds(300), stopGrace: .milliseconds(300)))
        #expect(result.exitCode == nil)
        #expect(result.stdout == "started\n")
        #expect(clock.now - start < .seconds(5))
    }

    @Test(.timeLimit(.minutes(1))) func cancellingForcesACommandThatIgnoresSigterm() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task {
            try await run(sh, ["-c", "trap '' TERM; while true; do sleep 0.1; done"],
                          RunOptions(environment: plainEnv, timeout: .seconds(60), stopGrace: .milliseconds(300)))
        }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = try await task.value
        #expect(result.exitCode == nil)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func aGrandchildHoldingThePipesDoesNotDelayAKill() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        // The background sleep keeps stdout open after sh is killed.
        let result = try await run(sh, ["-c", "sleep 30 & wait"], RunOptions(environment: plainEnv, timeout: .milliseconds(300)))
        #expect(result.exitCode == nil)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func aGrandchildHoldingThePipesDoesNotOutlastATimeoutAfterANormalExit() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        // sh exits 0 at once; the background sleep keeps the pipes open.
        let result = try await run(sh, ["-c", "echo done; sleep 30 & exit 0"], RunOptions(environment: plainEnv, timeout: .milliseconds(300)))
        #expect(result.exitCode == 0)
        #expect(result.stdout == "done\n")
        #expect(clock.now - start < .seconds(5))
    }

    @Test func cancellingUnblocksANormalExitWhoseGrandchildHoldsThePipes() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { try await run(sh, ["-c", "sleep 30 & exit 0"], RunOptions(environment: plainEnv, timeout: .seconds(60))) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let result = try await task.value
        #expect(result.exitCode == 0)
        #expect(clock.now - start < .seconds(5))
    }

    @Test func cancellingTheTaskKillsTheCommand() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { try await run(sh, ["-c", "exec sleep 30"], RunOptions(environment: plainEnv, timeout: .seconds(60))) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let result = try await task.value
        #expect(result.exitCode == nil)
        #expect(clock.now - start < .seconds(5))
    }

    @Test(.timeLimit(.minutes(1))) func aStopBeforeStartStopsItAsSoonAsItStarts() async throws {
        let child = ChildProcess(sh, ["-c", "exec sleep 30"], environment: plainEnv, collectsOutput: true, stopGrace: .seconds(5))
        child.stop()
        try child.start(onLine: nil)
        let result = await child.finished()
        #expect(result.exitCode == nil)
    }

    @Test func cancellingBeforeTheCommandStartsStillKillsIt() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await run(sh, ["-c", "exec sleep 30"], RunOptions(environment: plainEnv, timeout: .seconds(60)))
        }
        let result = try await task.value
        #expect(result.exitCode == nil)
    }
}
