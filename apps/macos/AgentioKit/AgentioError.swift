import Foundation

/// A failed step, with the CLI's own error code when it printed one.
public struct AgentioError: Error, Equatable, LocalizedError {
    public let message: String
    public let code: String?
    public let suggestion: String?
    public let exitCode: Int32?

    public init(_ message: String, code: String? = nil, suggestion: String? = nil, exitCode: Int32? = nil) {
        self.message = message
        self.code = code
        self.suggestion = suggestion
        self.exitCode = exitCode
    }

    public var errorDescription: String? { message }
}

/// Turn stderr and the exit code into an AgentioError. The CLI prints
/// `Error [CODE]: message` and optionally `Suggestion: …`; anything else
/// falls back to the last stderr line.
public func cliError(stderr: String, exitCode: Int32?, fallback: String) -> AgentioError {
    let lines = stderr.split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    var code: String?
    var message: String?
    var suggestion: String?
    for line in lines {
        if let m = line.wholeMatch(of: /Error \[([A-Z_]+)\]: (.+)/) {
            (code, message) = (String(m.1), String(m.2))
        } else if let m = line.wholeMatch(of: /Error: (.+)/) {
            (code, message) = (nil, String(m.1))
        } else if let m = line.wholeMatch(of: /Suggestion: (.+)/) {
            suggestion = String(m.1)
        }
    }
    return AgentioError(message ?? lines.last ?? fallback, code: code, suggestion: suggestion, exitCode: exitCode)
}
