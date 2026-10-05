import Foundation

/// The hub's base URL ("https://host[:port]") from what the user typed.
/// Without a scheme ("vault.example.com") it assumes https://. HTTPS only;
/// `allowLocalHTTP` (debug builds) also accepts http://localhost and
/// http://127.0.0.1 when typed with http://.
public func normalizeHubBase(_ raw: String, allowLocalHTTP: Bool) throws -> String {
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // Before trailing slashes go: "https://" alone has a scheme, not a host.
    let typedScheme = trimmed.contains("://")
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    if trimmed.isEmpty { throw AgentioError("Vault URL is empty") }
    guard let parts = URLComponents(string: typedScheme ? trimmed : "https://" + trimmed),
          let scheme = parts.scheme?.lowercased(),
          let host = parts.host?.lowercased(), !host.isEmpty,
          // Without a scheme, "name@host" or "mailto:x@host" is not a hub address.
          typedScheme || (parts.user == nil && parts.password == nil) else {
        throw AgentioError("Invalid vault URL")
    }
    let isLocal = host == "localhost" || host == "127.0.0.1"
    guard scheme == "https" || (allowLocalHTTP && isLocal && scheme == "http") else {
        throw AgentioError("Vault URL must be HTTPS (http://localhost allowed in dev)")
    }
    let defaultPort = scheme == "https" ? 443 : 80
    let port = parts.port.flatMap { $0 == defaultPort ? nil : ":\($0)" } ?? ""
    return "\(scheme)://\(host)\(port)"
}

/// Fetches a URL; tests replace URLSession.
public typealias Loader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// The agentio version a hub runs, from its public `GET /health`. The
/// app's CLI must be at least that version to work with the hub.
public func hubVersion(_ hub: String, load: Loader = { try await URLSession.shared.data(for: $0) }) async throws -> CliVersion {
    guard let url = URL(string: "\(hub)/health") else { throw AgentioError("Invalid vault URL") }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let data: Data
    let response: URLResponse
    do {
        (data, response) = try await load(request)
    } catch {
        throw AgentioError("Cannot reach the vault hub at \(hub): \(error.localizedDescription)")
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status),
          let health = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          health["status"] as? String == "ok" else {
        throw AgentioError("\(hub) is not an AgentIO vault hub")
    }
    guard let version = (health["version"] as? String).flatMap(CliVersion.init) else {
        throw AgentioError("The vault hub at \(hub) does not report its version. Update it to the latest agentio.")
    }
    return version
}
