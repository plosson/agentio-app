import Foundation
import Testing
@testable import AgentioKit

struct HubURLTests {
    @Test func keepsSchemeHostAndPortOnly() throws {
        #expect(try normalizeHubBase("  https://Vault.Example.com/ui/?x=1#y  ", allowLocalHTTP: false) == "https://vault.example.com")
        #expect(try normalizeHubBase("https://vault.example.com:8443///", allowLocalHTTP: false) == "https://vault.example.com:8443")
        #expect(try normalizeHubBase("HTTPS://vault.example.com:443", allowLocalHTTP: false) == "https://vault.example.com")
        #expect(try normalizeHubBase("https://user:pw@vault.example.com", allowLocalHTTP: false) == "https://vault.example.com")
    }

    @Test func emptyInputSaysSo() {
        for raw in ["", "   ", "///", "\n"] {
            #expect(throws: AgentioError("Vault URL is empty"), "raw: \(raw)") { try normalizeHubBase(raw, allowLocalHTTP: false) }
        }
    }

    @Test func rejectsWhatIsNotAnHttpsHub() {
        for raw in ["vault.example.com", "https://", "ftp://vault.example.com", "http://vault.example.com", "javascript:alert(1)", "https:// spaced.example.com"] {
            #expect(throws: AgentioError.self, "raw: \(raw)") { try normalizeHubBase(raw, allowLocalHTTP: false) }
        }
    }

    @Test func localHttpOnlyWhenAllowedAndOnlyForLoopbackNames() throws {
        #expect(throws: AgentioError.self) { try normalizeHubBase("http://localhost:7890", allowLocalHTTP: false) }
        #expect(try normalizeHubBase("http://localhost:7890", allowLocalHTTP: true) == "http://localhost:7890")
        #expect(try normalizeHubBase("http://127.0.0.1:80", allowLocalHTTP: true) == "http://127.0.0.1")
        for raw in ["http://localhost.evil.example", "http://127.0.0.1.nip.io", "http://10.0.0.1"] {
            #expect(throws: AgentioError.self, "raw: \(raw)") { try normalizeHubBase(raw, allowLocalHTTP: true) }
        }
    }
}

/// A loader that answers `body` with `status`, and records the request.
final class FakeLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    let status: Int
    let body: String

    init(status: Int = 200, body: String) {
        self.status = status
        self.body = body
    }

    var urls: [URL?] { lock.withLock { requests.map(\.url) } }

    @Sendable func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { requests.append(request) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

struct HubVersionTests {
    @Test func readsTheVersionFromHealth() async throws {
        let loader = FakeLoader(body: #"{"status":"ok","timestamp":1,"uptime":2,"locked":true,"version":"3.13.0"}"#)
        #expect(try await hubVersion("https://h.example:8443", load: loader.load) == CliVersion("3.13.0"))
        #expect(loader.urls == [URL(string: "https://h.example:8443/health")])
    }

    @Test func aHubWithoutAVersionMustBeUpdated() async {
        for body in [#"{"status":"ok","locked":true}"#, #"{"status":"ok","version":3.13}"#, #"{"status":"ok","version":"latest"}"#] {
            await #expect(throws: AgentioError("The vault hub at https://h.example does not report its version. Update it to the latest agentio."),
                          "body: \(body)") {
                try await hubVersion("https://h.example", load: FakeLoader(body: body).load)
            }
        }
    }

    @Test func whatIsNotAHealthyHubIsSaidSo() async {
        let answers = [(200, "<html>Welcome</html>"), (200, #"{"status":"starting","version":"3.13.0"}"#), (200, "[]"),
                       (404, #"{"status":"ok","version":"3.13.0"}"#), (502, "Bad Gateway")]
        for (status, body) in answers {
            await #expect(throws: AgentioError("https://h.example is not an AgentIO vault hub"), "\(status) \(body)") {
                try await hubVersion("https://h.example", load: FakeLoader(status: status, body: body).load)
            }
        }
    }

    @Test func anUnreachableHubNamesTheCause() async {
        let error = URLError(.cannotFindHost)
        await #expect(throws: AgentioError("Cannot reach the vault hub at https://nowhere.example: \(error.localizedDescription)")) {
            try await hubVersion("https://nowhere.example") { _ in throw error }
        }
    }
}
