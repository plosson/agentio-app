import Foundation

/// One option of a `choice` input.
public struct SetupChoice: Sendable, Equatable, Hashable {
    public let value: String
    public let label: String
    public init(value: String, label: String) { self.value = value; self.label = label }
}

public enum SetupInputKind: String, Sendable { case text, secret, url, email, file, choice }

/// A value a setup needs: asked up front (`needs`) or during the run (`ask`).
public struct SetupInput: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let kind: SetupInputKind
    public let required: Bool
    public let defaultValue: String?
    public let help: String?
    public let choices: [SetupChoice]

    public init(id: String, label: String, kind: SetupInputKind, required: Bool, defaultValue: String?, help: String?, choices: [SetupChoice]) {
        self.id = id; self.label = label; self.kind = kind; self.required = required
        self.defaultValue = defaultValue; self.help = help; self.choices = choices
    }
}

/// How a setup signs in, beyond its inputs.
public enum SetupAuth: String, Sendable {
    case none, browser, pairing
    case browserCode = "browser-code"
    case deviceCode = "device-code"
}

public struct SetupNeeds: Sendable, Equatable {
    public let inputs: [SetupInput]
    public let auth: SetupAuth
    public init(inputs: [SetupInput], auth: SetupAuth) { self.inputs = inputs; self.auth = auth }
}

/// A step of a running `profile add --json` or `profile reauth --json`.
public enum SetupEvent: Sendable, Equatable {
    case code(userCode: String, url: URL)
    case open(URL)
    case ask(SetupInput)
    case added(profile: String)
    case reauthed(profile: String)
}

let unreadableSetup = AgentioError("This agentio asks for something the app cannot show. Update AgentIO Companion.")

/// An http(s) address with a host; nil for anything else, which the app never opens.
func webAddress(_ text: String?) -> URL? {
    guard let text, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http", let host = url.host(), !host.isEmpty else { return nil }
    return url
}

extension SetupInput {
    /// An input spec as an event carries it; nil when any part is missing or unknown.
    init?(fields: [String: Any]) {
        let event = CliEvent(name: "input", fields: fields)
        guard let id = event.string("id"), !id.isEmpty, let label = event.string("label"),
              let kind = event.string("kind").flatMap(SetupInputKind.init(rawValue:)) else { return nil }
        if fields["required"] != nil && event.bool("required") == nil { return nil }
        var choices: [SetupChoice] = []
        if let raw = fields["choices"] {
            guard let list = raw as? [[String: Any]] else { return nil }
            for item in list {
                guard let value = item["value"] as? String, let text = item["label"] as? String else { return nil }
                choices.append(SetupChoice(value: value, label: text))
            }
        }
        if kind == .choice && choices.isEmpty { return nil }
        self.init(id: id, label: label, kind: kind, required: event.bool("required") ?? true,
                  defaultValue: event.string("default"), help: event.string("help"), choices: choices)
    }
}

extension SetupNeeds {
    /// A `needs` event; nil when it is not one this app can show.
    init?(event: CliEvent) {
        guard event.name == "needs", let auth = event.string("auth").flatMap(SetupAuth.init(rawValue:)),
              let list = event.fields["inputs"] as? [[String: Any]] else { return nil }
        var inputs: [SetupInput] = []
        for fields in list {
            guard let input = SetupInput(fields: fields) else { return nil }
            inputs.append(input)
        }
        self.init(inputs: inputs, auth: auth)
    }
}

/// The step an event is, nil for other events and for an address that is not a web page.
/// Throws for a question or an end it cannot read: the run cannot go on.
func setupEvent(_ event: CliEvent) throws -> SetupEvent? {
    switch event.name {
    case "code":
        guard let code = event.string("userCode"), let url = webAddress(event.string("verificationUrl")) else { return nil }
        return .code(userCode: code, url: url)
    case "open":
        return webAddress(event.string("url")).map(SetupEvent.open)
    case "ask":
        guard let input = SetupInput(fields: event.fields) else { throw unreadableSetup }
        return .ask(input)
    case "added", "reauthed":
        guard let profile = event.string("profile"), !profile.isEmpty else { throw unreadableSetup }
        return event.name == "added" ? .added(profile: profile) : .reauthed(profile: profile)
    default:
        return nil
    }
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

/// One JSON object on one line, for agentio's stdin.
func jsonLine(_ object: [String: String]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    return String(decoding: data, as: UTF8.self) + "\n"
}

/// A running `profile add --json` or `profile reauth --json`.
public protocol ProfileAddRunning: AnyObject, Sendable {
    /// Answer the question the run asked (`.ask`).
    func answer(id: String, value: String)
    /// Stop the run; `finished()` then throws "cancelled".
    func cancel()
    /// The profile's name once added (or signed in again); the failure otherwise.
    func finished() async throws -> String
}

final class ProfileAddRun: ProfileAddRunning, @unchecked Sendable {
    /// The event that ends the run well, and what the run is called in its errors.
    private let endEvent: String
    private let action: String
    private let lock = NSLock()
    private var process: AgentioProcess?
    private var cancelled = false
    private var unreadable = false

    init(endEvent: String = "added", action: String = "Adding the profile") {
        self.endEvent = endEvent
        self.action = action
    }

    /// Events can arrive before this; an unreadable one then stops the process here.
    func attach(_ process: AgentioProcess) {
        let stopNow = lock.withLock { () -> Bool in
            self.process = process
            return unreadable || cancelled
        }
        if stopNow { process.stop() }
    }

    /// An event the app cannot read stops the run.
    func stopUnreadable() {
        let process = lock.withLock { () -> AgentioProcess? in unreadable = true; return self.process }
        process?.stop()
    }

    func answer(id: String, value: String) {
        lock.withLock { process }?.send(jsonLine(["id": id, "value": value]))
    }

    func cancel() {
        let process = lock.withLock { () -> AgentioProcess? in cancelled = true; return self.process }
        process?.stop()
    }

    func finished() async throws -> String {
        guard let process = lock.withLock({ self.process }) else { throw AgentioError("\(action) did not start") }
        // OAuth waits up to 5 minutes and device codes up to 10; this only guards a hang.
        let exit = await process.finished(timeout: .seconds(20 * 60))
        if let formatError = process.formatError { throw formatError }
        let (cancelled, unreadable) = lock.withLock { (self.cancelled, self.unreadable) }
        if cancelled { throw AgentioError("\(action) was cancelled", exitCode: exit.exitCode) }
        if unreadable { throw unreadableSetup }
        let result = AgentioResult(exitCode: exit.exitCode, stdout: exit.stdout, stderr: exit.stderr, events: process.events)
        guard exit.exitCode == 0, let profile = process.events.last(where: { $0.name == endEvent })?.string("profile") else {
            throw failure(result, fallback: "\(action) failed")
        }
        return profile
    }
}

extension AgentioCLI {
    /// `profile add --describe --json`. Nil when this agentio cannot set the service up that way:
    /// it says so, or it predates `--describe`.
    public func describeSetup(_ service: String) async throws -> SetupNeeds? {
        guard isServiceID(service) else { throw invalidService(service) }
        let result = try await execute([service, "profile", "add", "--describe", "--json"], timeout: .seconds(30))
        if result.exitCode == 0, let event = result.events.last(where: { $0.name == "needs" }) {
            guard let needs = SetupNeeds(event: event) else { throw unreadableSetup }
            return needs
        }
        if result.events.last(where: \.isFailure)?.string("message")?.hasSuffix("cannot be set up with --json yet") == true { return nil }
        if result.events.isEmpty, result.stderr.contains("unknown option '--describe'") { return nil }
        throw failure(result, fallback: "agentio could not describe the \(service) setup")
    }

    /// `profile add --json --input -`: `values` on stdin, kept open for answers; each step to `onEvent`.
    public func startProfileAdd(_ service: String, values: [String: String], readOnly: Bool,
                                onEvent: @escaping @Sendable (SetupEvent) -> Void) throws -> any ProfileAddRunning {
        guard isServiceID(service) else { throw invalidService(service) }
        let run = ProfileAddRun()
        let arguments = [service, "profile", "add", "--json", "--input", "-"] + (readOnly ? ["--read-only"] : [])
        return try startSetupRun(run, arguments, input: jsonLine(values), onEvent: onEvent)
    }

    /// `profile reauth <service> <profile> --json`: stdin kept open for answers only; each step to `onEvent`.
    public func startProfileReauth(_ service: String, profile: String,
                                   onEvent: @escaping @Sendable (SetupEvent) -> Void) throws -> any ProfileAddRunning {
        guard isServiceID(service) else { throw invalidService(service) }
        guard isProfileName(profile) else { throw AgentioError("Not a profile name: \(profile)") }
        let run = ProfileAddRun(endEvent: "reauthed", action: "Signing in again")
        return try startSetupRun(run, ["profile", "reauth", service, profile, "--json"], input: nil, onEvent: onEvent)
    }

    /// Start a run whose steps go to `onEvent`; an event the app cannot read stops it.
    private func startSetupRun(_ run: ProfileAddRun, _ arguments: [String], input: String?,
                               onEvent: @escaping @Sendable (SetupEvent) -> Void) throws -> ProfileAddRun {
        let process = try start(arguments, input: input, keepsInputOpen: true) { event in
            do {
                if let step = try setupEvent(event) { onEvent(step) }
            } catch {
                run.stopUnreadable()
            }
        }
        run.attach(process)
        return run
    }
}
