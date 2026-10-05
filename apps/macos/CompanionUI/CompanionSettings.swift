import Foundation

/// What the app remembers between launches, in its user defaults.
public struct CompanionSettings: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let hubURLKey = "rememberedHubURL"

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
}
