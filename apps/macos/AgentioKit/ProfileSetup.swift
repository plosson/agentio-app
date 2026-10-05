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

/// A step of a running `profile add --json`.
public enum SetupEvent: Sendable, Equatable {
    case code(userCode: String, url: URL)
    case open(URL)
    case ask(SetupInput)
    case added(profile: String)
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
    case "added":
        guard let profile = event.string("profile"), !profile.isEmpty else { throw unreadableSetup }
        return .added(profile: profile)
    default:
        return nil
    }
}
