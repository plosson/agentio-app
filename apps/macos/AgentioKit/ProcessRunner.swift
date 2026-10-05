import Foundation

enum OutputSource: Sendable { case stdout, stderr }

struct RunResult: Sendable, Equatable {
    /// Nil when a signal ended it (a stop, a timeout, a cancellation, a crash).
    var exitCode: Int32?
    var stdout: String
    var stderr: String
}

struct RunOptions: Sendable {
    var environment: [String: String]
    var timeout: Duration
    /// Written to stdin, which is then closed; stdin is empty otherwise.
    var input: String?
    /// How long a stopped command gets to exit on SIGTERM before SIGKILL.
    var stopGrace: Duration
    /// Called with each complete stdout/stderr line as it arrives.
    var onLine: (@Sendable (String, OutputSource) -> Void)?

    init(
        environment: [String: String],
        timeout: Duration,
        input: String? = nil,
        stopGrace: Duration = .seconds(5),
        onLine: (@Sendable (String, OutputSource) -> Void)? = nil
    ) {
        self.environment = environment
        self.timeout = timeout
        self.input = input
        self.stopGrace = stopGrace
        self.onLine = onLine
    }
}

/// A child that exits before reading all its input closes the pipe; writing
/// to it must fail with EPIPE instead of killing the app with SIGPIPE.
private let ignoreSigpipe: Void = { signal(SIGPIPE, SIG_IGN) }()

/// Run a command to completion and collect its output. Never throws on a
/// non-zero exit (callers read `exitCode`), only when it cannot start.
/// A timeout or task cancellation stops it and reports a nil exit code.
func run(_ executable: URL, _ arguments: [String], _ options: RunOptions) async throws -> RunResult {
    let child = ChildProcess(executable, arguments, environment: options.environment, input: options.input,
                             collectsOutput: true, stopGrace: options.stopGrace)
    try child.start(onLine: options.onLine)
    return await child.finished(timeout: options.timeout)
}

/// One process: streams its output lines, reports its end once its output
/// is read, and stops with SIGTERM, then SIGKILL after a grace. Every way
/// the app runs a process goes through it, so they all stop the same way.
/// The lock guards every field: pipe handlers, the termination handler and
/// stop() run on different threads.
final class ChildProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let input: String?
    private let keepsInputOpen: Bool
    private var inputWriter: FileHandle?
    private let inputQueue = DispatchQueue(label: "com.plosson.agentio-companion.stdin")
    private let collectsOutput: Bool
    private let keepsStderr: Bool
    private let stopGrace: Duration
    /// Cleared once finished, which ends the cycle with whoever it captures.
    private var onLine: (@Sendable (String, OutputSource) -> Void)?
    private var stdout = Stream()
    private var stderr = Stream()
    private var pipes: [Pipe] = []
    private var started = false
    private var stopRequested = false
    private var killScheduled = false
    private var exited = false
    private var exitCode: Int32?
    /// Lines taken from a stream but not yet handed to `onLine`.
    private var delivering = 0
    private var result: RunResult?
    private var waiters: [CheckedContinuation<RunResult, Never>] = []
    private var exitWaiters: [CheckedContinuation<Int32?, Never>] = []

    /// Bytes read so far (kept only when collecting), split into lines as they arrive.
    private struct Stream {
        var data = Data()
        var lines = LineSplitter()
        var eof = false
    }

    /// `keepsStderr: false` sends stderr to /dev/null, for a long-running
    /// process whose log nobody reads.
    init(
        _ executable: URL,
        _ arguments: [String],
        environment: [String: String],
        input: String? = nil,
        keepsInputOpen: Bool = false,
        collectsOutput: Bool,
        keepsStderr: Bool = true,
        stopGrace: Duration
    ) {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        self.input = input
        self.keepsInputOpen = keepsInputOpen
        self.collectsOutput = collectsOutput
        self.keepsStderr = keepsStderr
        self.stopGrace = stopGrace
    }

    /// Launch it. `onLine` gets each complete output line, before
    /// `finished()` returns. Throws only when the process cannot start.
    func start(onLine: (@Sendable (String, OutputSource) -> Void)?) throws {
        _ = ignoreSigpipe
        let outPipe = Pipe()
        let errPipe = keepsStderr ? Pipe() : nil
        let inPipe = (input == nil && !keepsInputOpen) ? nil : Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe ?? FileHandle.nullDevice
        process.standardInput = inPipe ?? FileHandle.nullDevice
        process.terminationHandler = { [self] process in
            didExit(process.terminationReason == .exit ? process.terminationStatus : nil)
        }
        outPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            didRead(handle.availableData, .stdout, handle)
        }
        errPipe?.fileHandleForReading.readabilityHandler = { [self] handle in
            didRead(handle.availableData, .stderr, handle)
        }
        lock.withLock {
            self.onLine = onLine
            pipes = [outPipe] + (errPipe.map { [$0] } ?? [])
            if errPipe == nil { stderr.eof = true }
        }
        do {
            try process.run()
        } catch {
            for pipe in [outPipe] + (errPipe.map { [$0] } ?? []) { pipe.fileHandleForReading.readabilityHandler = nil }
            lock.withLock { self.onLine = nil }
            throw error
        }
        let stopNow = lock.withLock {
            started = true
            return stopRequested
        }
        if stopNow { stop() }
        if let inPipe {
            let writer = inPipe.fileHandleForWriting
            if keepsInputOpen {
                lock.withLock { inputWriter = writer }
                if let input { writeInput(input) }
            } else if let input {
                DispatchQueue.global().async {
                    try? writer.write(contentsOf: Data(input.utf8))
                    try? writer.close()
                }
            }
        }
    }

    /// More input, for a process started with `keepsInputOpen`; in order, never blocking the caller.
    /// Ignored once the input is closed.
    func writeInput(_ text: String) {
        guard let writer = lock.withLock({ inputWriter }) else { return }
        inputQueue.async { try? writer.write(contentsOf: Data(text.utf8)) }
    }

    /// End the input: a reader then sees end of file. Safe to call more than once.
    func closeInput() {
        let writer = lock.withLock { () -> FileHandle? in
            defer { inputWriter = nil }
            return inputWriter
        }
        guard let writer else { return }
        inputQueue.async { try? writer.close() }
    }

    /// Returns once the process exited and its output is read (or abandoned
    /// after stop()). Any number of callers can wait.
    func finished() async -> RunResult {
        await withCheckedContinuation { continuation in
            let done = lock.withLock { () -> RunResult? in
                if let result { return result }
                waiters.append(continuation)
                return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }

    /// Returns once the process itself exited, with its exit code, even if
    /// a descendant still holds its output open.
    func exited() async -> Int32? {
        await withCheckedContinuation { continuation in
            let done = lock.withLock { () -> Int32?? in
                if exited { return .some(exitCode) }
                exitWaiters.append(continuation)
                return .none
            }
            if let done { continuation.resume(returning: done) }
        }
    }

    /// `finished()`, but a timeout or task cancellation stops it first.
    func finished(timeout: Duration) async -> RunResult {
        let timer = Task {
            try await Task.sleep(for: timeout)
            stop()
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await finished()
        } onCancel: {
            stop()
        }
    }

    /// SIGTERM now, SIGKILL if it still runs after the grace. Once it exits,
    /// output a descendant may still hold open is abandoned instead of
    /// waited for. Before start(), the stop happens as soon as it starts.
    /// Calling it again is harmless.
    func stop() {
        enum Action { case none, terminate(scheduleKill: Bool), abandonPipes }
        let action = lock.withLock { () -> Action in
            stopRequested = true
            if !started { return .none }
            if exited { return .abandonPipes }
            defer { killScheduled = true }
            return .terminate(scheduleKill: !killScheduled)
        }
        switch action {
        case .none:
            return
        case .abandonPipes:
            abandonPipes()
        case .terminate(let scheduleKill):
            process.terminate()
            guard scheduleKill else { return }
            let pid = process.processIdentifier
            Task { [self] in
                try? await Task.sleep(for: stopGrace)
                // Checked under the lock: once reaped, the pid may be reused.
                lock.withLock { if !exited && process.isRunning { kill(pid, SIGKILL) } }
            }
        }
    }

    private func abandonPipes() {
        let open = lock.withLock { pipes }
        for pipe in open { pipe.fileHandleForReading.readabilityHandler = nil }
        let lines = lock.withLock {
            take(finishStream(.stdout).map { ($0, OutputSource.stdout) } + finishStream(.stderr).map { ($0, OutputSource.stderr) })
        }
        deliver(lines)
    }

    private func didRead(_ data: Data, _ source: OutputSource, _ handle: FileHandle) {
        if data.isEmpty { handle.readabilityHandler = nil }
        let lines = lock.withLock {
            take((data.isEmpty ? finishStream(source) : appendToStream(source, data)).map { ($0, source) })
        }
        deliver(lines)
    }

    /// A stopped process's output is abandoned once it exits; otherwise its
    /// output is read to the end, so nothing it printed before dying is lost.
    private func didExit(_ code: Int32?) {
        closeInput()
        let (abandon, waiting) = lock.withLock {
            exited = true
            exitCode = code
            defer { exitWaiters = [] }
            return (stopRequested, exitWaiters)
        }
        for continuation in waiting { continuation.resume(returning: code) }
        if abandon { abandonPipes() } else { finishIfDone() }
    }

    /// Counts lines taken from a stream until they are delivered, so
    /// `finished()` cannot return before `onLine` saw them. Lock held.
    private func take(_ lines: [(String, OutputSource)]) -> [(String, OutputSource)] {
        delivering += 1
        return lines
    }

    private func deliver(_ lines: [(String, OutputSource)]) {
        let handler = lock.withLock { onLine }
        for (line, source) in lines { handler?(line, source) }
        lock.withLock { delivering -= 1 }
        finishIfDone()
    }

    private func appendToStream(_ source: OutputSource, _ data: Data) -> [String] {
        var stream = source == .stdout ? stdout : stderr
        guard !stream.eof else { return [] }
        if collectsOutput { stream.data.append(data) }
        let lines = stream.lines.add(data)
        if source == .stdout { stdout = stream } else { stderr = stream }
        return lines
    }

    private func finishStream(_ source: OutputSource) -> [String] {
        var stream = source == .stdout ? stdout : stderr
        guard !stream.eof else { return [] }
        stream.eof = true
        let last = stream.lines.finish()
        if source == .stdout { stdout = stream } else { stderr = stream }
        return last
    }

    private func finishIfDone() {
        let done = lock.withLock { () -> (RunResult, [CheckedContinuation<RunResult, Never>])? in
            guard exited, stdout.eof, stderr.eof, delivering == 0, result == nil else { return nil }
            let ended = RunResult(
                exitCode: exitCode,
                stdout: stripAnsi(String(decoding: stdout.data, as: UTF8.self)),
                stderr: stripAnsi(String(decoding: stderr.data, as: UTF8.self))
            )
            result = ended
            onLine = nil
            defer { waiters = [] }
            return (ended, waiters)
        }
        if let (ended, waiting) = done {
            for continuation in waiting { continuation.resume(returning: ended) }
        }
    }
}

/// Complete lines from output that arrives in chunks. Splits on \n and \r
/// (progress bars redraw with \r) and keeps the unfinished tail. Splitting
/// bytes, not text, keeps multi-byte characters whole.
struct LineSplitter {
    private var pending = Data()

    mutating func add(_ data: Data) -> [String] {
        let buffer = pending + data
        var lines: [String] = []
        var lineStart = buffer.startIndex
        for index in buffer.indices where buffer[index] == 0x0A || buffer[index] == 0x0D {
            lines.append(stripAnsi(String(decoding: buffer[lineStart..<index], as: UTF8.self)))
            lineStart = index + 1
        }
        pending = Data(buffer[lineStart...])
        return lines
    }

    /// The unfinished last line, if any.
    mutating func finish() -> [String] {
        defer { pending = Data() }
        return pending.isEmpty ? [] : [stripAnsi(String(decoding: pending, as: UTF8.self))]
    }
}
