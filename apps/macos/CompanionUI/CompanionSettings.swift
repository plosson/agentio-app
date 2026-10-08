import Foundation

/// What the app remembers between launches, in its user defaults.
public struct CompanionSettings: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let hubURLKey = "rememberedHubURL"
    /// For developers, set with `defaults write com.plosson.agentio-companion devAgentioRepo <path>`.
    public static let devAgentioRepoKey = "devAgentioRepo"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The hub URL to prefill, when the user asked to remember it.
    public var rememberedHubURL: String? {
        get { defaults.string(forKey: Self.hubURLKey) }
        nonmutating set {
            if let newValue { defaults.set(newValue, forKey: Self.hubURLKey) }
            else { defaults.removeObject(forKey: Self.hubURLKey) }
        }
    }

    /// An agentio checkout to run instead of the app's own CLI: an absolute
    /// path, or one that starts with `~/`. Anything else is ignored.
    public var devAgentioRepo: URL? {
        guard let stored = defaults.string(forKey: Self.devAgentioRepoKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              stored.hasPrefix("/") || stored.hasPrefix("~/") else { return nil }
        return URL(filePath: (stored as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }
}
