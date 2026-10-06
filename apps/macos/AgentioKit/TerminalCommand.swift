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
        return TerminalCommand(executable: location.binPath,
                               arguments: [service, "profile", "add"] + (readOnly ? ["--read-only"] : []),
                               environment: terminalEnv(location, base: baseEnvironment))
    }
}
