import Foundation

/// The app runs its own agentio, never the user's: the binary lives in `bin/`
/// and the CLI gets `home/` as HOME, so its ~/.config/agentio is separate too.
public struct CliLocation: Sendable, Equatable {
    public let binDir: URL
    public let binPath: URL
    public let homeDir: URL

    public init(root: URL) {
        binDir = root.appending(path: "bin", directoryHint: .isDirectory)
        binPath = binDir.appending(path: "agentio", directoryHint: .notDirectory)
        homeDir = root.appending(path: "home", directoryHint: .isDirectory)
    }

    /// `<Application Support>/<bundle id>/cli`, the app's own folder.
    public static func appDefault(
        applicationSupport: URL = URL.applicationSupportDirectory,
        bundleID: String = Bundle.main.bundleIdentifier ?? "com.plosson.agentio-companion"
    ) -> CliLocation {
        CliLocation(root: applicationSupport
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "cli", directoryHint: .isDirectory))
    }
}
