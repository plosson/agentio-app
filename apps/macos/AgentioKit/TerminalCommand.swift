import Foundation

/// What a terminal runs: the app's agentio, its arguments and its environment.
public struct TerminalCommand: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
}

extension AgentioCLI {
    /// `agentio <service> profile add [--read-only]`, for the user to answer in a terminal.
    public func terminalProfileAdd(_ service: String, readOnly: Bool) throws -> TerminalCommand {
        guard isServiceID(service) else { throw invalidService(service) }
        let command = command([service, "profile", "add"] + (readOnly ? ["--read-only"] : []))
        return TerminalCommand(executable: command.executable, arguments: command.arguments,
                               environment: terminalEnv(location, base: baseEnvironment))
    }
}

/// A `waitpid` status as an exit code; nil when a signal ended the process.
public func exitCode(fromWaitStatus status: Int32) -> Int32? {
    status & 0x7f == 0 ? (status >> 8) & 0xff : nil
}

/// How a terminal's child ended. SwiftTerm reports the raw status of a `waitpid(WNOHANG)`, which is 0
/// when the child was not reapable yet; so reap it here, and use the reported status only when it
/// was already reaped.
public func reapedExitCode(pid: pid_t, reported: Int32) -> Int32? {
    var status: Int32 = 0
    if pid > 0, waitpid(pid, &status, 0) == pid { return exitCode(fromWaitStatus: status) }
    return exitCode(fromWaitStatus: reported)
}
