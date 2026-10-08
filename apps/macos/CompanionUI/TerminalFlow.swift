import AgentioKit
import Foundation
import Observation

/// Adding a profile, or signing one in again, in a terminal: agentio asks, the user answers. The sheet's
/// terminal runs the command, attaches a way to stop it, and reports its exit here; cancelling stops it.
@MainActor @Observable
public final class TerminalFlow: Identifiable {
    public enum Purpose: Equatable, Sendable {
        case add
        case reauth(profile: String)
    }

    public enum Step: Equatable {
        /// The Read-only choice, before an add runs.
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
    public let purpose: Purpose
    public private(set) var step: Step = .ready
    public var readOnly = false
    public private(set) var isCancelled = false

    private let backend: any CompanionBackend
    /// The service, and the profile signed in again (nil for an add: its name is not known here).
    private let onDone: @MainActor (String, String?) -> Void
    /// Stops the terminal's process; set by the sheet's terminal once it runs.
    private var stop: (@MainActor () -> Void)?

    /// The profile signed in again; nil for an add.
    public var profile: String? {
        if case .reauth(let profile) = purpose { profile } else { nil }
    }

    /// Signing in again has no choice to make: it starts at once.
    init(service: String, displayName: String, purpose: Purpose = .add, backend: any CompanionBackend,
         onDone: @escaping @MainActor (String, String?) -> Void) {
        self.service = service
        self.displayName = displayName
        self.purpose = purpose
        self.backend = backend
        self.onDone = onDone
        if case .reauth = purpose { start() }
    }

    public func start() {
        guard step == .ready, !isCancelled else { return }
        do {
            switch purpose {
            case .add: step = .running(try backend.terminalProfileAdd(service, readOnly: readOnly))
            case .reauth(let profile): step = .running(try backend.terminalProfileReauth(service, profile: profile))
            }
        } catch {
            step = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// The terminal's process ended; only the first end of a running command counts.
    public func exited(_ code: Int32?) {
        guard case .running = step, !isCancelled else { return }
        if code == 0 {
            step = .succeeded
            onDone(service, profile)
        } else {
            step = .ended(exitCode: code)
        }
    }

    /// The sheet's terminal started the command; `stop` ends it. Already cancelled: it ends now.
    public func attach(stop: @escaping @MainActor () -> Void) {
        guard !isCancelled else { return stop() }
        self.stop = stop
    }

    /// The sheet is closing: stop the process, and ignore its end.
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        stop?()
        stop = nil
    }
}
