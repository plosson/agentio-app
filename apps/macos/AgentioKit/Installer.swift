import Foundation

/// The oldest agentio whose `--json` output this app reads (agentio#92).
/// A hub can require a newer one; see `hubVersion`.
public let minimumCliVersion = CliVersion("3.3.0")!

/// The oldest hub the app signs in to: it understands `login --scope` (agentio#125).
public let minimumHubVersion = CliVersion("3.14.0")!

/// What the app's key asks for: use and change every profile, and add,
/// rename and remove them.
public let loginScopes = ["profiles:write", "profiles:manage"]

/// The official installer, as documented at https://houlahop.com/agentio/#install.
public let installScriptURL = URL(string: "https://houlahop.com/agentio/install")!

/// An x.y.z version, compared by number ("3.10.0" > "3.9.9"). A pre-release
/// ("3.13.0-beta.1") comes before its release.
public struct CliVersion: Comparable, Sendable, CustomStringConvertible {
    let numbers: [Int]
    let preRelease: String?

    /// The first x.y.z in `text`, so "v3.2.2" and "agentio 3.2.2" work too.
    public init?(_ text: String) {
        guard let match = text.firstMatch(of: /(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.\-]+))?/),
              let major = Int(match.1), let minor = Int(match.2), let patch = Int(match.3) else { return nil }
        numbers = [major, minor, patch]
        preRelease = match.4.map(String.init)
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".") + (preRelease.map { "-\($0)" } ?? "")
    }

    public static func < (a: CliVersion, b: CliVersion) -> Bool {
        if a.numbers != b.numbers { return a.numbers.lexicographicallyPrecedes(b.numbers) }
        switch (a.preRelease, b.preRelease) {
        case (nil, _): return false
        case (_, nil): return true
        case (let x?, let y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }
}

/// What the installer is doing: a line it printed, or its download percent.
public enum InstallProgress: Sendable, Equatable {
    case label(String)
    case percent(Double)
    /// The installer finished; the installed agentio is being run.
    case checking
}

/// One installer output line: nil for blank lines and for curl's
/// `--progress-bar` redraws without a percent ("###", its "##O#-#" spinner).
func installProgress(fromLine raw: String) -> InstallProgress? {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if line.isEmpty { return nil }
    if let bar = line.wholeMatch(of: /[#=O\-\s]*(?:(\d+(?:\.\d+)?)%)?/) {
        return bar.1.flatMap { Double($0) }.map { .percent($0) }
    }
    return .label(line)
}

extension CliInfo {
    /// False too when the version cannot be read.
    public func isAtLeast(_ minimum: CliVersion) -> Bool {
        CliVersion(version).map { $0 >= minimum } ?? false
    }
}

extension AgentioCLI {
    /// Install (or replace) the latest CLI in the app's own bin dir with the
    /// official installer, and check it is at least `minimum`. Never touches
    /// PATH, shell rc files or other installs.
    public func install(
        atLeast minimum: CliVersion,
        fetchScript: @Sendable () async throws -> Data = fetchOfficialInstaller,
        onProgress: @escaping @Sendable (InstallProgress) -> Void
    ) async throws -> CliInfo {
        if let dev { throw dev.cannotInstall(atLeast: minimum) }
        let files = FileManager.default
        try files.createDirectory(at: location.binDir, withIntermediateDirectories: true)
        try files.createDirectory(at: location.homeDir, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        let tmpDir = files.temporaryDirectory.appending(path: "agentio-install-\(UUID().uuidString)",
                                                        directoryHint: .isDirectory)
        try files.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: tmpDir) }

        onProgress(.label("Downloading installer from \(installScriptURL.absoluteString)…"))
        let script = tmpDir.appending(path: "install", directoryHint: .notDirectory)
        try await fetchScript().write(to: script)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let tail = TailLines(limit: 5)
        let args = [script.path, "--install-dir", location.binDir.path, "--no-modify-path"]
        let result = try await run(URL(filePath: "/bin/sh"), args,
                                   RunOptions(environment: isolatedEnv(baseEnvironment), timeout: .seconds(5 * 60)) { line, _ in
            guard let progress = installProgress(fromLine: line) else { return }
            if case .label(let text) = progress { tail.add(text) }
            onProgress(progress)
        })
        if result.exitCode != 0 {
            let reason = result.exitCode.map { "exited with code \($0)" } ?? "was stopped"
            let lines = tail.lines
            throw AgentioError("The installer \(reason)\(lines.isEmpty ? "" : ": " + lines.joined(separator: " · "))",
                               exitCode: result.exitCode)
        }
        onProgress(.checking)
        guard let cli = await detect() else {
            throw AgentioError("The installer finished, but agentio could not be run")
        }
        guard cli.isAtLeast(minimum) else {
            throw AgentioError("The latest agentio release is \(cli.version), but this vault needs \(minimum) or later")
        }
        return cli
    }
}

/// What `agentio update --check --json` says about the app's CLI.
public struct CliUpdate: Sendable, Equatable {
    public let current: String
    public let latest: String
    public let updateAvailable: Bool
}

extension AgentioCLI {
    /// Ask the CLI whether a newer release exists; it asks GitHub. Throws when
    /// it cannot say: no network, or an agentio without `update --check --json`.
    public func checkUpdate() async throws -> CliUpdate {
        let result = try await execute(["update", "--check", "--json"], timeout: .seconds(30))
        guard result.exitCode == 0, let event = result.events.last(where: { $0.name == "version" }),
              let current = event.string("current"), let latest = event.string("latest"),
              let available = event.bool("updateAvailable") else {
            throw failure(result, fallback: "agentio could not check for updates")
        }
        return CliUpdate(current: current, latest: latest, updateAvailable: available)
    }
}

/// Download the official installer script.
@Sendable public func fetchOfficialInstaller() async throws -> Data {
    let request = URLRequest(url: installScriptURL, timeoutInterval: 30)
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
        throw AgentioError("Could not download the installer (HTTP \(status))")
    }
    return data
}

/// The last `limit` lines added, for error messages.
private final class TailLines: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var stored: [String] = []

    init(limit: Int) { self.limit = limit }

    func add(_ line: String) {
        lock.withLock {
            stored.append(line)
            if stored.count > limit { stored.removeFirst() }
        }
    }

    var lines: [String] { lock.withLock { stored } }
}
