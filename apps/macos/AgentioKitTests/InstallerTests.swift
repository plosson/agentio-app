import Foundation
import Testing
@testable import AgentioKit

/// Progress reports, collected across threads.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [InstallProgress] = []
    func add(_ progress: InstallProgress) { lock.withLock { stored.append(progress) } }
    var all: [InstallProgress] { lock.withLock { stored } }
}

struct InstallerLineTests {
    @Test func readsPercentFromCurlProgressBars() {
        #expect(installProgress(fromLine: "######                 42.5%") == .percent(42.5))
        #expect(installProgress(fromLine: "100%") == .percent(100))
    }

    @Test func barsWithoutPercentAndBlankLinesAreIgnored() {
        for line in ["###", "##O#-#", "  ", "", "=-=-"] {
            #expect(installProgress(fromLine: line) == nil, "line: \(line)")
        }
    }

    @Test func otherLinesAreLabels() {
        #expect(installProgress(fromLine: "  Installing agentio 3.2.2  ") == .label("Installing agentio 3.2.2"))
        #expect(installProgress(fromLine: "50% done") == .label("50% done"))
    }
}

struct CliVersionTests {
    @Test func comparesByNumberNotByText() throws {
        let ordered = ["3.2.2-beta.2", "3.2.2-beta.10", "3.2.2", "3.2.10", "3.9.9", "3.10.0", "10.0.0"]
        let versions = try ordered.map { try #require(CliVersion($0)) }
        for (a, b) in zip(versions, versions.dropFirst()) { #expect(a < b, "\(a) < \(b)") }
        #expect(CliVersion("3.12.2") == CliVersion("v3.12.2"))
    }

    @Test func readsTheFirstVersionInTheText() {
        #expect(CliVersion("agentio 3.12.2\n")?.description == "3.12.2")
        #expect(CliVersion("v3.13.0-rc.1 (build 4.5.6)")?.description == "3.13.0-rc.1")
    }

    @Test func textWithoutThreeNumbersIsNoVersion() {
        for text in ["", "3.12", "latest", "3.x.2", "v", "99999999999999999999.0.0"] {
            #expect(CliVersion(text) == nil, "text: \(text)")
        }
    }

    @Test func aCliMeetsTheMinimumOnlyWithAReadableVersion() {
        let minimum = CliVersion("3.12.2")!
        for (printed, meets) in [("3.12.2", true), ("agentio v3.13.0", true), ("3.12.1", false), ("3.12.2-beta.1", false), ("unknown", false)] {
            #expect(CliInfo(path: URL(filePath: "/a"), version: printed).isAtLeast(minimum) == meets, "printed: \(printed)")
        }
    }
}

struct InstallTests {
    /// A fake installer that records its arguments and environment, then
    /// writes an agentio that prints `version`.
    func fakeInstaller(version: String = "3.12.2", extra: String = "") -> String {
        """
        echo "$@" > "$2/../installer-args"
        env > "$2/../installer-env"
        printf '##########    42.5%%\\r'
        echo 'Installing agentio'
        \(extra)
        printf '#!/bin/sh\\necho \(version)\\n' > "$2/agentio"
        chmod +x "$2/agentio"
        """
    }

    @Test func installsTheLatestIntoTheAppsBinDir() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url), baseEnvironment: plainEnv)
        let log = ProgressLog()
        let info = try await cli.install(atLeast: CliVersion("3.12.2")!, fetchScript: { Data(fakeInstaller().utf8) }, onProgress: log.add)
        #expect(info == CliInfo(path: cli.location.binPath, version: "3.12.2"))
        #expect(dir.read("installer-args") == "--install-dir \(cli.location.binDir.path) --no-modify-path\n")
        #expect(log.all.contains(.percent(42.5)))
        #expect(log.all.contains(.label("Installing agentio")))
        let homeMode = try FileManager.default.attributesOfItem(atPath: cli.location.homeDir.path)[.posixPermissions] as? Int
        #expect(homeMode == 0o700)
    }

    @Test func aLatestReleaseOlderThanTheHubIsRefused() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url), baseEnvironment: plainEnv)
        await #expect(throws: AgentioError("The latest agentio release is 3.12.2, but this vault needs 3.13.0-dev.4 or later")) {
            try await cli.install(atLeast: CliVersion("3.13.0-dev.4")!, fetchScript: { Data(fakeInstaller().utf8) }) { _ in }
        }
    }

    @Test func installerRunsWithoutTheUsersAgentioSettings() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url),
                             baseEnvironment: ["PATH": "/usr/bin:/bin", "AGENTIO_VERSION": "9.9.9", "FORCE_COLOR": "1"])
        _ = try await cli.install(atLeast: minimumCliVersion, fetchScript: { Data(fakeInstaller().utf8) }) { _ in }
        let env = try #require(dir.read("installer-env"))
        #expect(!env.contains("AGENTIO_VERSION"))
        #expect(!env.contains("FORCE_COLOR"))
        #expect(env.contains("NO_COLOR=1"))
    }

    @Test func worksWithTheMinimalEnvironmentOfAnAppStartedFromFinder() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url),
                             baseEnvironment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let info = try await cli.install(atLeast: minimumCliVersion, fetchScript: { Data(fakeInstaller().utf8) }) { _ in }
        #expect(info.version == "3.12.2")
    }

    @Test func failureNamesTheExitCodeAndTheLastFiveLines() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url), baseEnvironment: plainEnv)
        let script = "for i in 1 2 3 4 5 6 7; do echo \"line $i\"; done; echo '#####  10%'; exit 6"
        await #expect(throws: AgentioError("The installer exited with code 6: line 3 · line 4 · line 5 · line 6 · line 7", exitCode: 6)) {
            try await cli.install(atLeast: minimumCliVersion, fetchScript: { Data(script.utf8) }) { _ in }
        }
    }

    @Test func successWithoutAWorkingBinaryIsAFailure() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url), baseEnvironment: plainEnv)
        await #expect(throws: AgentioError("The installer finished, but agentio could not be run")) {
            try await cli.install(atLeast: minimumCliVersion, fetchScript: { Data("echo done".utf8) }) { _ in }
        }
    }

    @Test func aFailedDownloadRunsNothing() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = AgentioCLI(location: CliLocation(root: dir.url), baseEnvironment: plainEnv)
        await #expect(throws: AgentioError("Could not download the installer (HTTP 503)")) {
            try await cli.install(atLeast: minimumCliVersion, fetchScript: { throw AgentioError("Could not download the installer (HTTP 503)") }) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: cli.location.binPath.path))
    }
}
