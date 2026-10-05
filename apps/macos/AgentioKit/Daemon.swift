import Foundation

/*
 * The local daemon: `daemon start --host 127.0.0.1 --port 0 --json`. The
 * system picks a free port, so it never collides with the user's own
 * daemon, and the daemon prints its URL in a `listening` event.
 */

/// A daemon this app started.
public final class DaemonHandle: Sendable {
    public let url: URL
    private let process: AgentioProcess

    init(url: URL, process: AgentioProcess) {
        self.url = url
        self.process = process
    }

    /// Returns when the daemon exits, for whatever reason.
    public func waitForExit() async { _ = await process.exited() }

    /// SIGTERM (the daemon shuts down cleanly on it), then SIGKILL if it lingers.
    public func stop() async {
        process.stop()
        _ = await process.finished()
    }
}

/// How a daemon start ends: its URL, its failure event, the end of its
/// output (it exited), the timeout, or the caller's cancellation.
private enum DaemonStart: Sendable {
    case listening(URL)
    case failed(AgentioError)
    case ended(Int32?)
    case timedOut
    case cancelled
}

extension AgentioCLI {
    /// Start the daemon and return once it prints its `listening` event.
    /// The timeout covers macOS's scan of a new binary on its first run.
    public func startDaemon(startTimeout: Duration = .seconds(30), stopGrace: Duration = .seconds(5)) async throws -> DaemonHandle {
        let (starts, startSink) = AsyncStream<DaemonStart>.makeStream()
        // Its log goes to stderr, which nobody reads; errors come as events on stdout.
        let process = try start(["daemon", "start", "--host", "127.0.0.1", "--port", "0", "--json"],
                                collectsOutput: false, keepsStderr: false, stopGrace: stopGrace) { event in
            if event.name == "listening", let url = event.string("url").flatMap(URL.init(string:)) {
                startSink.yield(.listening(url))
            } else if event.isFailure {
                startSink.yield(.failed(event.error(exitCode: nil)))
            }
        }
        // finished() returns after the last line was handled, so an error
        // printed just before exiting is never lost.
        let watcher = Task {
            startSink.yield(.ended(await process.finished().exitCode))
        }
        let timer = Task {
            try await Task.sleep(for: startTimeout)
            startSink.yield(.timedOut)
        }
        defer {
            timer.cancel()
            watcher.cancel()
        }

        var outcome = DaemonStart.cancelled
        for await start in starts {
            outcome = start
            break
        }
        switch outcome {
        case .listening(let url):
            return DaemonHandle(url: url, process: process)
        case .failed(let error):
            process.stop()
            _ = await process.finished()
            throw error
        case .ended(let exitCode):
            // An unreadable format stopped it.
            if let formatError = process.formatError { throw formatError }
            throw AgentioError("The agentio daemon stopped while starting", exitCode: exitCode)
        case .timedOut:
            process.stop()
            _ = await process.finished()
            throw AgentioError("The agentio daemon did not start in time")
        case .cancelled:
            process.stop()
            _ = await process.finished()
            throw CancellationError()
        }
    }
}
