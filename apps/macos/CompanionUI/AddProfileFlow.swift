import AgentioKit
import Foundation
import Observation

/// Adding one profile from the hub page, or signing one in again: what the sheet shows, step by step.
@MainActor @Observable
public final class AddProfileFlow: Identifiable {
    public enum Purpose: Equatable, Sendable {
        case add
        case reauth(profile: String)
    }

    public enum Step: Equatable {
        /// Signing in again: the profile, before anything runs.
        case confirm
        case loading
        case unsupported
        case form(SetupNeeds)
        case working(SetupAuth)
        case code(userCode: String, url: URL)
        case asking(SetupInput)
        case added(profile: String)
        case failed(String)
    }

    public let id = UUID()
    public let service: String
    public let displayName: String
    public let purpose: Purpose
    public private(set) var step: Step
    public var values: [String: String] = [:]
    public var readOnly = false
    public var answer = ""
    public private(set) var lastOpened: URL?
    /// agentio's own suggestion for the failure, when it gave one.
    public private(set) var failureSuggestion: String?

    private let backend: any CompanionBackend
    private let openURL: @MainActor (URL) -> Void
    private let onAdded: @MainActor (String, String) -> Void
    private var run: (any ProfileAddRunning)?
    private var auth: SetupAuth = .none
    private var cancelled = false

    init(service: String, displayName: String, purpose: Purpose = .add, backend: any CompanionBackend,
         openURL: @escaping @MainActor (URL) -> Void, onAdded: @escaping @MainActor (String, String) -> Void) {
        self.service = service
        self.displayName = displayName
        self.purpose = purpose
        self.step = purpose == .add ? .loading : .confirm
        self.backend = backend
        self.openURL = openURL
        self.onAdded = onAdded
    }

    public var canSubmit: Bool {
        switch step {
        case .confirm:
            return !cancelled
        case .form(let needs):
            return needs.inputs.allSatisfy { !$0.required || !(values[$0.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
        case .asking(let input):
            return !input.required || !answer.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return false
        }
    }

    /// Describe the setup; signing in again has nothing to describe.
    public func start() async {
        guard purpose == .add else { return }
        do {
            guard let needs = try await backend.describeSetup(service) else { step = .unsupported; return }
            for input in needs.inputs { if let value = input.defaultValue { values[input.id] = value } }
            step = .form(needs)
        } catch {
            fail(error)
        }
    }

    /// Continue: start the add with the form's values, or the sign-in again.
    public func submit() {
        guard canSubmit else { return }
        let onEvent: @Sendable (SetupEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.receive(event) }
        }
        switch (step, purpose) {
        case (.form(let needs), .add):
            let given = values.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            let readOnly = readOnly
            begin(needs.auth) { try backend.startProfileAdd(service, values: given, readOnly: readOnly, onEvent: onEvent) }
        case (.confirm, .reauth(let profile)):
            begin(.none) { try backend.startProfileReauth(service, profile: profile, onEvent: onEvent) }
        default:
            return
        }
    }

    private func begin(_ auth: SetupAuth, _ starting: () throws -> any ProfileAddRunning) {
        self.auth = auth
        step = .working(auth)
        do {
            let run = try starting()
            self.run = run
            Task { await finish(run) }
        } catch {
            fail(error)
        }
    }

    public func sendAnswer() {
        guard case .asking(let input) = step, canSubmit else { return }
        run?.answer(id: input.id, value: answer.trimmingCharacters(in: .whitespaces))
        step = .working(auth)
    }

    public func cancel() {
        cancelled = true
        run?.cancel()
    }

    public func reopen() {
        if let lastOpened { openURL(lastOpened) }
    }

    private func receive(_ event: SetupEvent) {
        guard !cancelled else { return }
        switch event {
        case .open(let url):
            lastOpened = url
            openURL(url)
        case .code(let code, let url):
            step = .code(userCode: code, url: url)
        case .ask(let input):
            answer = input.defaultValue ?? ""
            step = .asking(input)
        case .added, .reauthed:
            break
        }
    }

    private func finish(_ run: any ProfileAddRunning) async {
        do {
            let profile = try await run.finished()
            guard !cancelled else { return }
            step = .added(profile: profile)
            onAdded(service, profile)
        } catch {
            guard !cancelled else { return }
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        failureSuggestion = (error as? AgentioError)?.suggestion
        step = .failed(message(error))
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
