import Foundation
import os
import WebKit

/// A call from the hub page's `window.agentioCompanion` (spec Option A).
public enum BridgeCall: Equatable, Sendable {
    case addProfile(service: String, displayName: String?)
    case reauth(service: String, name: String?)
    case openTerminal
    /// Move the window with the mouse: the page calls it on a mouse-down in
    /// an empty part of its headers (WKWebView ignores `app-region: drag`).
    case dragWindow
    /// Sign in to the hub again, for a key that may manage profiles.
    case signInAgain

    /// The message `bridgeScript` posts, `{ method, args }`; nil for anything else.
    public init?(message body: Any) {
        guard let message = body as? [String: Any],
              let method = message["method"] as? String,
              let args = message["args"] as? [Any] else { return nil }
        let strings = args.compactMap { $0 as? String }
        guard strings.count == args.count, strings.allSatisfy({ !$0.isEmpty }) else { return nil }
        switch (method, strings.count) {
        case ("addProfile", 1): self = .addProfile(service: strings[0], displayName: nil)
        case ("addProfile", 2): self = .addProfile(service: strings[0], displayName: strings[1])
        case ("reauth", 1): self = .reauth(service: strings[0], name: nil)
        case ("reauth", 2): self = .reauth(service: strings[0], name: strings[1])
        case ("openTerminal", 0): self = .openTerminal
        case ("dragWindow", 0): self = .dragWindow
        case ("signInAgain", 0): self = .signInAgain
        default: return nil
        }
    }
}

/// The name the bridge's messages arrive under.
let bridgeHandlerName = "agentioCompanion"

/// Defines `window.agentioCompanion` in the hub page. Each method returns
/// the promise of the handler's reply. `canManageProfiles` is there only
/// when the app knows the key's right. Keep this surface narrow: no shell,
/// tokens, or passphrase APIs.
func bridgeScript(canManageProfiles: Bool?) -> String {
    """
(() => {
  const call = (method, args) =>
    window.webkit.messageHandlers.\(bridgeHandlerName).postMessage({ method, args });
  const right = \(canManageProfiles.map(String.init) ?? "null");
  Object.defineProperty(window, "agentioCompanion", {
    value: Object.freeze({
      present: true,
      ...(right === null ? {} : { canManageProfiles: right }),
      addProfile: (service, displayName) => call("addProfile", displayName == null ? [service] : [service, displayName]),
      reauth: (service, name) => call("reauth", name == null ? [service] : [service, name]),
      openTerminal: () => call("openTerminal", []),
      dragWindow: () => call("dragWindow", []),
      signInAgain: () => call("signInAgain", []),
    }),
  });
})();
"""
}

/// Scheme, host and port of an origin, with the default port filled in.
private struct Origin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
        self.init(scheme: scheme, host: host, port: url.port ?? 0)
    }

    @MainActor init(securityOrigin: WKSecurityOrigin) {
        self.init(scheme: securityOrigin.protocol.lowercased(), host: securityOrigin.host.lowercased(),
                  port: securityOrigin.port)
    }

    private init(scheme: String, host: String, port: Int) {
        self.scheme = scheme
        self.host = host
        self.port = port != 0 ? port : (scheme == "https" ? 443 : scheme == "http" ? 80 : 0)
    }
}

/// Receives the bridge's messages; replies with an error for malformed calls,
/// for calls from frames other than the main one, and for calls from pages
/// that are not from the hub's origin.
final class BridgeHandler: NSObject, WKScriptMessageHandlerWithReply {
    private let allowedOrigin: Origin?
    private let onCall: @MainActor (BridgeCall) -> Void

    /// `hubURL` is the hub page; only pages from its origin may call.
    init(hubURL: URL, onCall: @escaping @MainActor (BridgeCall) -> Void) {
        self.allowedOrigin = Origin(url: hubURL)
        self.onCall = onCall
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        // WebKit delivers script messages on the main thread.
        let fromHub = MainActor.assumeIsolated {
            message.frameInfo.isMainFrame
                && Origin(securityOrigin: message.frameInfo.securityOrigin) == allowedOrigin
        }
        guard fromHub, allowedOrigin != nil,
              let call = BridgeCall(message: message.body) else {
            return replyHandler(nil, "Invalid agentioCompanion call")
        }
        onCall(call)
        replyHandler(nil, nil)
    }
}

/// Add the bridge to a web view's configuration, for the page's own scripts.
@MainActor func installBridge(in controller: WKUserContentController, canManageProfiles: Bool?, handler: BridgeHandler) {
    controller.addUserScript(WKUserScript(source: bridgeScript(canManageProfiles: canManageProfiles), injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true, in: .page))
    controller.addScriptMessageHandler(handler, contentWorld: .page, name: bridgeHandlerName)
}

private let bridgeLog = Logger(subsystem: "com.plosson.agentio-companion", category: "bridge")

/// The script that tells the hub page a profile was added. The detail is JSON, so any name is safe.
func profilesChangedScript(_ notice: PageNotice) -> String {
    // Each value is a JSON string literal (it escapes `/`, so `</script>` is inert); the key order is fixed.
    func literal(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
    return "window.dispatchEvent(new CustomEvent('agentio:profiles-changed', { detail: { service: \(literal(notice.service)), profile: \(literal(notice.profile)) } }));"
}

/// The bridge's actions, for the page in `webView`. The terminal action
/// is a stub until the terminal (S7) exists.
@MainActor func performBridgeCall(_ call: BridgeCall, in webView: HubWebView?, signInAgain: () -> Void,
                                  addProfile: (String, String?) -> Void, reauth: (String, String?) -> Void) {
    switch call {
    case .addProfile(let service, let displayName):
        addProfile(service, displayName)
    case .reauth(let service, let name):
        reauth(service, name)
    case .openTerminal:
        bridgeLog.notice("[bridge stub] openTerminal() — PTY later")
    case .dragWindow:
        webView?.dragWindow()
    case .signInAgain:
        signInAgain()
    }
}
