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

/// A developer's agentio checkout, run from source with bun instead of the
/// app's binary (the `devAgentioRepo` setting). The app never installs over it.
public struct DevAgentio: Sendable, Equatable {
    public let repo: URL
    public let bun: URL

    public init(repo: URL, bun: URL? = nil) {
        self.repo = repo
        self.bun = bun ?? Self.findBun()
    }

    /// The CLI's entry point in the checkout.
    public var entry: URL { repo.appending(path: "src/index.ts", directoryHint: .notDirectory) }

    /// Where bun usually is. An app opened from Finder has no shell PATH to find it with.
    static let bunCandidates: [URL] = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".bun/bin/bun", directoryHint: .notDirectory),
        URL(filePath: "/opt/homebrew/bin/bun"),
        URL(filePath: "/usr/local/bin/bun"),
    ]

    /// The first candidate that is a file that can run; else the first, so an error says where bun should be.
    static func findBun(in candidates: [URL] = bunCandidates) -> URL {
        candidates.first { url in
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && !isFolder.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        } ?? candidates[0]
    }

    /// Why the app does not install: the checkout is what runs, whatever its state.
    func cannotInstall(atLeast minimum: CliVersion) -> AgentioError {
        if !FileManager.default.isExecutableFile(atPath: bun.path) {
            return AgentioError("bun is not at \(bun.path). Install bun, or remove the devAgentioRepo setting.")
        }
        if !FileManager.default.fileExists(atPath: entry.path) {
            return AgentioError("\(entry.path) does not exist. Check the devAgentioRepo setting.")
        }
        return AgentioError("The dev AgentIO in \(repo.path) does not run, or is older than \(minimum). The app does not install over it: fix the checkout, or remove the devAgentioRepo setting.")
    }
}
