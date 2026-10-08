import Foundation

/// What a terminal runs: the app's agentio, its arguments and its environment.
public struct TerminalCommand: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
}

/// A service id as agentio names them; anything else never reaches a command line.
func isServiceID(_ text: String) -> Bool {
    text.range(of: #"^[a-z0-9][a-z0-9-]*$"#, options: .regularExpression) != nil
}

func invalidService(_ text: String) -> AgentioError { AgentioError("Not a service: \(text)") }

/// A profile name that can reach a command line as one argument: not empty, at most 200
/// characters, on one line, and not read as an option.
public func isProfileName(_ text: String) -> Bool {
    !text.isEmpty && text.count <= 200 && !text.contains(where: \.isNewline) && !text.hasPrefix("-")
}

extension AgentioCLI {
    /// `agentio <service> profile add [--read-only]`, for the user to answer in a terminal.
    public func terminalProfileAdd(_ service: String, readOnly: Bool) throws -> TerminalCommand {
        guard isServiceID(service) else { throw invalidService(service) }
        return terminalCommand([service, "profile", "add"] + (readOnly ? ["--read-only"] : []))
    }

    /// `agentio profile reauth <service> <profile>`: sign the profile in again, in a terminal.
    public func terminalProfileReauth(_ service: String, profile: String) throws -> TerminalCommand {
        guard isServiceID(service) else { throw invalidService(service) }
        guard isProfileName(profile) else { throw AgentioError("Not a profile name: \(profile)") }
        return terminalCommand(["profile", "reauth", service, profile])
    }

    private func terminalCommand(_ arguments: [String]) -> TerminalCommand {
        let command = command(arguments)
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
