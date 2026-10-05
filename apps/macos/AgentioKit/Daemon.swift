import Foundation

/*
 * The local daemon: `daemon start --host 127.0.0.1 --port 0 --json`. The
 * system picks a free port, so it never collides with the user's own
 * daemon, and the daemon prints its URL in a `listening` event.
 */

/// A daemon this app started.
public final class DaemonHandle: Sendable {
    public let url: URL
    private let process: Process
    private let exitTask: Task<Int32?, Never>
    private let stopGrace: Duration

    init(url: URL, process: Process, exitTask: Task<Int32?, Never>, stopGrace: Duration) {
        self.url = url
        self.process = process
        self.exitTask = exitTask
        self.stopGrace = stopGrace
    }

    /// Returns when the daemon exits, for whatever reason.
    public func waitForExit() async { _ = await exitTask.value }

    public func stop() async { await stopDaemon(process, exitTask, grace: stopGrace) }
}

/// SIGTERM (the daemon shuts down cleanly on it), then SIGKILL if it lingers.
private func stopDaemon(_ process: Process, _ exitTask: Task<Int32?, Never>, grace: Duration) async {
    guard process.isRunning else { return }
    process.terminate()
    let pid = process.processIdentifier
    let killer = Task {
        try await Task.sleep(for: grace)
        kill(pid, SIGKILL)
    }
    _ = await exitTask.value
    killer.cancel()
}

/// How a daemon start ends: its URL, its error event, the end of its
/// output (it exited), or the timeout.
private enum DaemonStart: Sendable {
    case listening(URL)
    case failed(AgentioError)
    case ended
    case timedOut
}

extension AgentioCLI {
    /// Start the daemon and return once it prints its `listening` event.
    /// The timeout covers macOS's scan of a new binary on its first run.
    public func startDaemon(startTimeout: Duration = .seconds(30), stopGrace: Duration = .seconds(5)) async throws -> DaemonHandle {
        let process = Process()
        let outPipe = Pipe()
        process.executableURL = location.binPath
        process.arguments = ["daemon", "start", "--host", "127.0.0.1", "--port", "0", "--json"]
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        // Its log; errors come as events on stdout.
        process.standardError = FileHandle.nullDevice

        let (starts, startSink) = AsyncStream<DaemonStart>.makeStream()
        let reader = EventReader(onEnd: { startSink.yield(.ended) }) { line in
            do {
                guard let event = try parseEvent(line) else { return }
                if event.name == "listening", let url = event.string("url").flatMap(URL.init(string:)) {
                    startSink.yield(.listening(url))
                } else if event.name == "error" {
                    startSink.yield(.failed(event.error(exitCode: nil)))
                }
            } catch {
                startSink.yield(.failed(error as? AgentioError ?? unreadableFormat))
            }
        }
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            reader.read(data)
        }
        let (exits, exitSink) = AsyncStream<Int32?>.makeStream()
        process.terminationHandler = { process in
            exitSink.yield(process.terminationReason == .exit ? process.terminationStatus : nil)
            exitSink.finish()
        }
        try process.run()
        let exitTask = Task<Int32?, Never> {
            for await code in exits { return code }
            return nil
        }
        let timer = Task {
            try await Task.sleep(for: startTimeout)
            startSink.yield(.timedOut)
        }
        defer { timer.cancel() }

        var outcome = DaemonStart.timedOut
        for await start in starts {
            outcome = start
            break
        }
        switch outcome {
        case .listening(let url):
            return DaemonHandle(url: url, process: process, exitTask: exitTask, stopGrace: stopGrace)
        case .failed(let error):
            await stopDaemon(process, exitTask, grace: stopGrace)
            throw error
        case .ended:
            throw AgentioError("The agentio daemon stopped while starting", exitCode: await exitTask.value)
        case .timedOut:
            await stopDaemon(process, exitTask, grace: stopGrace)
            throw AgentioError("The agentio daemon did not start in time")
        }
    }
}

/// Splits the daemon's stdout into lines for `onLine`, across reads, and
/// calls `onEnd` after the last one.
private final class EventReader: @unchecked Sendable {
    private let lock = NSLock()
    private var lines = LineSplitter()
    private let onEnd: @Sendable () -> Void
    private let onLine: @Sendable (String) -> Void

    init(onEnd: @escaping @Sendable () -> Void, onLine: @escaping @Sendable (String) -> Void) {
        self.onEnd = onEnd
        self.onLine = onLine
    }

    /// Empty data is the end of the output.
    func read(_ data: Data) {
        let complete = lock.withLock { data.isEmpty ? lines.finish() : lines.add(data) }
        for line in complete { onLine(line) }
        if data.isEmpty { onEnd() }
    }
}
