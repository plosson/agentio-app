import AgentioKit
import Foundation

/// What the onboarding needs from the app's CLI and the hub. AgentioCLI is
/// the real one; tests use a fake.
public protocol CompanionBackend: Sendable {
    func detectCli() async -> CliInfo?
    func installCli(atLeast minimum: CliVersion, onProgress: @escaping @Sendable (InstallProgress) -> Void) async throws -> CliInfo
    func hubVersion(_ hub: String) async throws -> CliVersion
    func vaultState() async throws -> VaultState
    func login(hub: String, name: String, onCode: @escaping @Sendable (LoginCode) -> Void) async throws
    func initVault(passphrase: String) async throws
    func startLocalDaemon() async throws -> any LocalDaemon
}

/// A local vault daemon this app started.
public protocol LocalDaemon: AnyObject, Sendable {
    var url: URL { get }
    func waitForExit() async
    func stop() async
}

extension DaemonHandle: LocalDaemon {}

extension AgentioCLI: CompanionBackend {
    public func detectCli() async -> CliInfo? { await detect() }

    public func installCli(atLeast minimum: CliVersion, onProgress: @escaping @Sendable (InstallProgress) -> Void) async throws -> CliInfo {
        try await install(atLeast: minimum, onProgress: onProgress)
    }

    public func hubVersion(_ hub: String) async throws -> CliVersion { try await AgentioKit.hubVersion(hub) }

    public func startLocalDaemon() async throws -> any LocalDaemon { try await startDaemon() }
}
