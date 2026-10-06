import AgentioKit
import Foundation
import Observation

/// Adding one profile in a terminal: agentio asks, the user answers. The sheet's terminal runs the command
/// and reports its exit here; closing the sheet stops it.
@MainActor @Observable
public final class TerminalFlow: Identifiable {
    public enum Step: Equatable {
        /// The Read-only choice, before anything runs.
        case ready
        case running(TerminalCommand)
        case succeeded
        /// A non-zero exit, or nil for a signal.
        case ended(exitCode: Int32?)
        case failed(String)
    }

    public let id = UUID()
    public let service: String
    public let displayName: String
    public private(set) var step: Step = .ready
    public var readOnly = false
    public private(set) var isCancelled = false

    private let backend: any CompanionBackend
    private let onAdded: @MainActor (String) -> Void

    init(service: String, displayName: String, backend: any CompanionBackend, onAdded: @escaping @MainActor (String) -> Void) {
        self.service = service
        self.displayName = displayName
        self.backend = backend
        self.onAdded = onAdded
    }

    public func start() {
        guard step == .ready, !isCancelled else { return }
        do {
            step = .running(try backend.terminalProfileAdd(service, readOnly: readOnly))
        } catch {
            step = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The terminal's process ended; only the first end of a running command counts.
    public func exited(_ code: Int32?) {
        guard case .running = step, !isCancelled else { return }
        if code == 0 {
            step = .succeeded
            onAdded(service)
        } else {
            step = .ended(exitCode: code)
        }
    }

    public func cancel() { isCancelled = true }
}
