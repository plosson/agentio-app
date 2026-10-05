import Foundation
import os
import WebKit

/// A call from the hub page's `window.agentioCompanion` (spec Option A).
public enum BridgeCall: Equatable, Sendable {
    case addProfile(service: String)
    case reauth(service: String, name: String?)
    case openTerminal

    /// The message `bridgeScript` posts, `{ method, args }`; nil for anything else.
    public init?(message body: Any) {
        guard let message = body as? [String: Any],
              let method = message["method"] as? String,
              let args = message["args"] as? [Any] else { return nil }
        let strings = args.compactMap { $0 as? String }
        guard strings.count == args.count, strings.allSatisfy({ !$0.isEmpty }) else { return nil }
        switch (method, strings.count) {
        case ("addProfile", 1): self = .addProfile(service: strings[0])
        case ("reauth", 1): self = .reauth(service: strings[0], name: nil)
        case ("reauth", 2): self = .reauth(service: strings[0], name: strings[1])
        case ("openTerminal", 0): self = .openTerminal
        default: return nil
        }
    }
}

/// The name the bridge's messages arrive under.
let bridgeHandlerName = "agentioCompanion"

/// Defines `window.agentioCompanion` in the hub page. Each method returns
/// the promise of the handler's reply. Keep this surface narrow: no shell,
/// tokens, or passphrase APIs.
let bridgeScript = """
(() => {
  const call = (method, args) =>
    window.webkit.messageHandlers.\(bridgeHandlerName).postMessage({ method, args });
  Object.defineProperty(window, "agentioCompanion", {
    value: Object.freeze({
      present: true,
      addProfile: (service) => call("addProfile", [service]),
      reauth: (service, name) => call("reauth", name == null ? [service] : [service, name]),
      openTerminal: () => call("openTerminal", []),
    }),
  });
})();
"""

/// Receives the bridge's messages; replies with an error for malformed calls
/// and for calls from frames other than the main one.
final class BridgeHandler: NSObject, WKScriptMessageHandlerWithReply {
    private let onCall: @MainActor (BridgeCall) -> Void

    init(onCall: @escaping @MainActor (BridgeCall) -> Void) {
        self.onCall = onCall
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard message.frameInfo.isMainFrame, let call = BridgeCall(message: message.body) else {
            return replyHandler(nil, "Invalid agentioCompanion call")
        }
        onCall(call)
        replyHandler(nil, nil)
    }
}

/// Add the bridge to a web view's configuration, for the page's own scripts.
@MainActor func installBridge(in controller: WKUserContentController, handler: BridgeHandler) {
    controller.addUserScript(WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true, in: .page))
    controller.addScriptMessageHandler(handler, contentWorld: .page, name: bridgeHandlerName)
}

private let bridgeLog = Logger(subsystem: "com.plosson.agentio-companion", category: "bridge")

/// The bridge's actions. Stubs until the terminal (S7) exists.
@MainActor func performBridgeCall(_ call: BridgeCall) {
    switch call {
    case .addProfile(let service):
        bridgeLog.notice("[bridge stub] addProfile(\(service, privacy: .public)) — PTY later")
    case .reauth(let service, let name):
        bridgeLog.notice("[bridge stub] reauth(\(service, privacy: .public), \(name ?? "nil", privacy: .public)) — PTY later")
    case .openTerminal:
        bridgeLog.notice("[bridge stub] openTerminal() — PTY later")
    }
}
