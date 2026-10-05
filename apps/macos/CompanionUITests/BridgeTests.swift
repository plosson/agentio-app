import Foundation
import Testing
import WebKit
@testable import CompanionUI

struct BridgeCallTests {
    @Test func acceptsTheFiveCalls() {
        #expect(BridgeCall(message: ["method": "addProfile", "args": ["gmail"]]) == .addProfile(service: "gmail"))
        #expect(BridgeCall(message: ["method": "reauth", "args": ["gmail"]]) == .reauth(service: "gmail", name: nil))
        #expect(BridgeCall(message: ["method": "reauth", "args": ["gmail", "work"]]) == .reauth(service: "gmail", name: "work"))
        #expect(BridgeCall(message: ["method": "openTerminal", "args": [Any]()]) == .openTerminal)
        #expect(BridgeCall(message: ["method": "dragWindow", "args": [Any]()]) == .dragWindow)
        #expect(BridgeCall(message: ["method": "signInAgain", "args": [Any]()]) == .signInAgain)
    }

    @Test func rejectsEverythingElse() {
        let bad: [Any] = [
            "addProfile", ["method": "addProfile"], ["method": "addProfile", "args": "gmail"],
            ["method": "addProfile", "args": [Any]()], ["method": "addProfile", "args": [42]],
            ["method": "addProfile", "args": [""]], ["method": "addProfile", "args": ["a", "b"]],
            ["method": "reauth", "args": ["gmail", NSNull()]], ["method": "openTerminal", "args": ["x"]],
            ["method": "dragWindow", "args": ["x"]], ["method": "dragWindow"], ["method": "DragWindow", "args": [Any]()],
            ["method": "signInAgain", "args": ["https://evil.example"]], ["method": "signInAgain"],
            ["method": "exec", "args": ["rm -rf /"]], ["method": "__proto__", "args": [Any]()],
        ]
        for body in bad {
            #expect(BridgeCall(message: body) == nil, "body: \(body)")
        }
    }
}

/// Calls the bridge received, on the main actor.
@MainActor final class CallLog {
    var calls: [BridgeCall] = []
}

@MainActor
struct BridgeScriptTests {
    /// A web view with the bridge, showing `html`.
    func page(_ html: String, log: CallLog, baseURL: String = "https://h.example/ui",
              canManageProfiles: Bool? = nil) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        installBridge(in: configuration.userContentController, canManageProfiles: canManageProfiles,
                      handler: BridgeHandler(hubURL: URL(string: "https://h.example/ui")!) { log.calls.append($0) })
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(html, baseURL: URL(string: baseURL))
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while webView.isLoading || webView.url == nil {
            guard clock.now < deadline else { throw AgentioTestTimeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
        return webView
    }

    @Test func pageSeesThePresentFlagAndCallsResolve() async throws {
        let log = CallLog()
        let webView = try await page("<html><body>hub</body></html>", log: log)
        let present = try await webView.callAsyncJavaScript("return window.agentioCompanion.present === true", contentWorld: .page)
        #expect(present as? Bool == true)
        _ = try await webView.callAsyncJavaScript(
            "await window.agentioCompanion.addProfile('gmail'); await window.agentioCompanion.reauth('gmail', null); await window.agentioCompanion.openTerminal(); await window.agentioCompanion.dragWindow(); await window.agentioCompanion.signInAgain(); return 1",
            contentWorld: .page)
        #expect(log.calls == [.addProfile(service: "gmail"), .reauth(service: "gmail", name: nil), .openTerminal, .dragWindow, .signInAgain])
    }

    @Test func malformedCallsRejectAndDoNothing() async throws {
        let log = CallLog()
        let webView = try await page("<html><body>hub</body></html>", log: log)
        let outcome = try await webView.callAsyncJavaScript(
            "try { await window.agentioCompanion.addProfile(42); return 'resolved' } catch (e) { return 'rejected' }",
            contentWorld: .page)
        #expect(outcome as? String == "rejected")
        #expect(log.calls.isEmpty)
    }

    /// The page is shown from `baseURL`, while the handler only trusts https://h.example.
    func outcomeOfCall(from baseURL: String) async throws -> (String?, [BridgeCall]) {
        let log = CallLog()
        let webView = try await page("<html><body>hub</body></html>", log: log, baseURL: baseURL)
        let outcome = try await webView.callAsyncJavaScript(
            "try { await window.agentioCompanion.openTerminal(); return 'resolved' } catch (e) { return 'rejected' }",
            contentWorld: .page)
        return (outcome as? String, log.calls)
    }

    @Test(arguments: [(Optional(true), "true"), (false, "false"), (nil, "absent")])
    func pageSeesTheKeysManagingRightOnlyWhenKnown(right: Bool?, seen: String) async throws {
        let webView = try await page("<html><body>hub</body></html>", log: CallLog(), canManageProfiles: right)
        let result = try await webView.callAsyncJavaScript(
            "return 'canManageProfiles' in window.agentioCompanion ? String(window.agentioCompanion.canManageProfiles) : 'absent'",
            contentWorld: .page)
        #expect(result as? String == seen)
    }

    @Test func thePageCannotChangeTheManagingRight() async throws {
        let webView = try await page("<html><body>hub</body></html>", log: CallLog(), canManageProfiles: false)
        let result = try await webView.callAsyncJavaScript(
            "'use strict'; try { window.agentioCompanion.canManageProfiles = true } catch (e) {} ; return window.agentioCompanion.canManageProfiles",
            contentWorld: .page)
        #expect(result as? Bool == false)
    }

    @Test func aPageFromAnotherHostCannotSignInAgain() async throws {
        let log = CallLog()
        let webView = try await page("<html><body>hub</body></html>", log: log, baseURL: "https://evil.example/ui", canManageProfiles: false)
        let outcome = try await webView.callAsyncJavaScript(
            "try { await window.agentioCompanion.signInAgain(); return 'resolved' } catch (e) { return 'rejected' }",
            contentWorld: .page)
        #expect(outcome as? String == "rejected")
        #expect(log.calls.isEmpty)
    }

    @Test func aPageFromAnotherHostCannotDragTheWindow() async throws {
        let log = CallLog()
        let webView = try await page("<html><body>hub</body></html>", log: log, baseURL: "https://evil.example/ui")
        let outcome = try await webView.callAsyncJavaScript(
            "try { await window.agentioCompanion.dragWindow(); return 'resolved' } catch (e) { return 'rejected' }",
            contentWorld: .page)
        #expect(outcome as? String == "rejected")
        #expect(log.calls.isEmpty)
    }

    @Test func aPageFromAnotherHostIsRejected() async throws {
        let (outcome, calls) = try await outcomeOfCall(from: "https://evil.example/ui")
        #expect(outcome == "rejected")
        #expect(calls.isEmpty)
    }

    @Test func aPageFromAnotherPortIsRejected() async throws {
        let (outcome, calls) = try await outcomeOfCall(from: "https://h.example:8443/ui")
        #expect(outcome == "rejected")
        #expect(calls.isEmpty)
    }

    @Test func aPageFromAnotherSchemeIsRejected() async throws {
        let (outcome, calls) = try await outcomeOfCall(from: "http://h.example/ui")
        #expect(outcome == "rejected")
        #expect(calls.isEmpty)
    }

    @Test func thePageCannotReplaceTheBridge() async throws {
        let log = CallLog()
        let webView = try await page("<html><body>hub</body></html>", log: log)
        let result = try await webView.callAsyncJavaScript(
            "try { window.agentioCompanion = { present: false } } catch (e) {} ; return window.agentioCompanion.present",
            contentWorld: .page)
        #expect(result as? Bool == true)
    }

    @Test func framesDoNotGetTheBridge() async throws {
        let log = CallLog()
        let webView = try await page("<html><body><iframe srcdoc='<p>x</p>'></iframe></body></html>", log: log)
        try await Task.sleep(for: .milliseconds(200))
        let result = try await webView.callAsyncJavaScript(
            "return typeof document.querySelector('iframe').contentWindow.agentioCompanion", contentWorld: .page)
        #expect(result as? String == "undefined")
    }
}

struct AgentioTestTimeout: Error {}
