import Foundation

public enum OutputSource: Sendable { case stdout, stderr }

public struct RunResult: Sendable, Equatable {
    /// Nil when the command was killed (timeout or cancellation).
    public var exitCode: Int32?
    public var stdout: String
    public var stderr: String
}

public struct RunOptions: Sendable {
    public var environment: [String: String]
    public var timeout: Duration
    /// Written to stdin, which is then closed; stdin is empty otherwise.
    public var input: String?
    /// Called with each complete stdout/stderr line as it arrives.
    public var onLine: (@Sendable (String, OutputSource) -> Void)?

    public init(
        environment: [String: String],
        timeout: Duration,
        input: String? = nil,
        onLine: (@Sendable (String, OutputSource) -> Void)? = nil
    ) {
        self.environment = environment
        self.timeout = timeout
        self.input = input
        self.onLine = onLine
    }
}

/// A child that exits before reading all its input closes the pipe; writing
/// to it must fail with EPIPE instead of killing the app with SIGPIPE.
private let ignoreSigpipe: Void = { signal(SIGPIPE, SIG_IGN) }()

/// Run a command to completion and collect its output. Never throws on a
/// non-zero exit (callers read `exitCode`), only when it cannot start.
/// A timeout or task cancellation kills it and reports a nil exit code.
public func run(_ executable: URL, _ arguments: [String], _ options: RunOptions) async throws -> RunResult {
    _ = ignoreSigpipe
    let state = RunState(onLine: options.onLine)
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            state.start(executable, arguments, options, continuation)
        }
    } onCancel: {
        state.kill()
    }
}

/// One command's process, output and completion. The lock guards every
/// field: pipe handlers, the termination handler and kill() run on
/// different threads.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let onLine: (@Sendable (String, OutputSource) -> Void)?
    private var continuation: CheckedContinuation<RunResult, Error>?
    private var stdout = Stream()
    private var stderr = Stream()
    private var started = false
    private var killRequested = false
    private var exited = false
    private var exitCode: Int32?
    private var pipes: [Pipe] = []

    /// Bytes read so far, split into lines as they arrive.
    private struct Stream {
        var data = Data()
        var lines = LineSplitter()
        var eof = false
    }

    init(onLine: (@Sendable (String, OutputSource) -> Void)?) {
        self.onLine = onLine
    }

    func start(
        _ executable: URL,
        _ arguments: [String],
        _ options: RunOptions,
        _ continuation: CheckedContinuation<RunResult, Error>
    ) {
        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = options.input == nil ? nil : Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = options.environment
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe ?? FileHandle.nullDevice
        process.terminationHandler = { [self] process in
            didExit(process.terminationReason == .exit ? process.terminationStatus : nil, outPipe, errPipe)
        }
        outPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            didRead(handle.availableData, .stdout, handle)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            didRead(handle.availableData, .stderr, handle)
        }
        lock.withLock {
            self.continuation = continuation
            pipes = [outPipe, errPipe]
        }
        do {
            try process.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            lock.withLock { self.continuation = nil }
            continuation.resume(throwing: error)
            return
        }
        let killNow = lock.withLock {
            started = true
            return killRequested
        }
        if killNow { kill() }
        if let inPipe, let input = options.input {
            DispatchQueue.global().async {
                let writer = inPipe.fileHandleForWriting
                try? writer.write(contentsOf: Data(input.utf8))
                try? writer.close()
            }
        }
        let seconds = Double(options.timeout.components.seconds)
            + Double(options.timeout.components.attoseconds) / 1e18
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in kill() }
    }

    /// SIGTERM, once the process runs (a cancel can come before it starts).
    /// If it already exited but a descendant still holds the pipes open,
    /// stop waiting for EOF and finish with what was read.
    func kill() {
        let (running, exitedOpen) = lock.withLock {
            if !started { killRequested = true }
            return (started && !exited, started && exited)
        }
        if running { process.terminate() }
        if exitedOpen { abandonPipes() }
    }

    private func abandonPipes() {
        let open = lock.withLock { pipes }
        for pipe in open { pipe.fileHandleForReading.readabilityHandler = nil }
        let flushed = lock.withLock {
            finishStream(.stdout).map { ($0, OutputSource.stdout) } + finishStream(.stderr).map { ($0, OutputSource.stderr) }
        }
        for (line, source) in flushed { onLine?(line, source) }
        finishIfDone()
    }

    private func didRead(_ data: Data, _ source: OutputSource, _ handle: FileHandle) {
        if data.isEmpty { handle.readabilityHandler = nil }
        let lines = lock.withLock { () -> [String] in
            if data.isEmpty { return finishStream(source) }
            return appendToStream(source, data)
        }
        for line in lines { onLine?(line, source) }
        finishIfDone()
    }

    private func didExit(_ code: Int32?, _ outPipe: Pipe, _ errPipe: Pipe) {
        // Killed: a grandchild may still hold the pipes open, which would
        // delay EOF until it exits, so stop reading now.
        var flushed: [(String, OutputSource)] = []
        if code == nil {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
        }
        lock.withLock {
            exited = true
            exitCode = code
            if code == nil {
                flushed += finishStream(.stdout).map { ($0, .stdout) }
                flushed += finishStream(.stderr).map { ($0, .stderr) }
            }
        }
        for (line, source) in flushed { onLine?(line, source) }
        finishIfDone()
    }

    private func appendToStream(_ source: OutputSource, _ data: Data) -> [String] {
        var stream = source == .stdout ? stdout : stderr
        guard !stream.eof else { return [] }
        stream.data.append(data)
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
        let done = lock.withLock { () -> (CheckedContinuation<RunResult, Error>, RunResult)? in
            guard exited, stdout.eof, stderr.eof, let continuation else { return nil }
            self.continuation = nil
            return (continuation, RunResult(
                exitCode: exitCode,
                stdout: stripAnsi(String(decoding: stdout.data, as: UTF8.self)),
                stderr: stripAnsi(String(decoding: stderr.data, as: UTF8.self))
            ))
        }
        if let (continuation, result) = done { continuation.resume(returning: result) }
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
