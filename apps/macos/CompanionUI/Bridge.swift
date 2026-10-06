import Foundation
import os
import WebKit

/// A call from the hub page's `window.agentioCompanion` (spec Option A).
public enum BridgeCall: Equatable, Sendable {
    case addProfile(service: String, displayName: String?)
    case reauth(service: String, name: String?, displayName: String?)
    case openTerminal
    /// Move the window with the mouse: the page calls it on a mouse-down in
    /// an empty part of its headers (WKWebView ignores `app-region: drag`).
    case dragWindow
    /// Sign in to the hub again, for a key that may manage profiles.
    case signInAgain
    /// The items of the menu WebKit opens for the right-click under way, in place of its own;
    /// the reply is the chosen item's id, or null. The page must not cancel the event.
    case contextMenu([MenuEntry])

    public enum MenuEntry: Equatable, Sendable {
        case item(id: String, title: String)
        case separator
    }

    /// The message `bridgeScript` posts, `{ method, args }`; nil for anything else.
    public init?(message body: Any) {
        guard let message = body as? [String: Any],
              let method = message["method"] as? String,
              let args = message["args"] as? [Any] else { return nil }
        if method == "contextMenu" {
            guard args.count == 1, let entries = Self.menuEntries(args[0]) else { return nil }
            self = .contextMenu(entries)
            return
        }
        let strings = args.compactMap { $0 as? String }
        guard strings.count == args.count, strings.allSatisfy({ !$0.isEmpty }) else { return nil }
        switch (method, strings.count) {
        case ("addProfile", 1): self = .addProfile(service: strings[0], displayName: nil)
        case ("addProfile", 2): self = .addProfile(service: strings[0], displayName: strings[1])
        case ("reauth", 1): self = .reauth(service: strings[0], name: nil, displayName: nil)
        case ("reauth", 2): self = .reauth(service: strings[0], name: strings[1], displayName: nil)
        case ("reauth", 3): self = .reauth(service: strings[0], name: strings[1], displayName: strings[2])
        case ("openTerminal", 0): self = .openTerminal
        case ("dragWindow", 0): self = .dragWindow
        case ("signInAgain", 0): self = .signInAgain
        default: return nil
        }
    }

    /// 1 to 20 entries, at least one item: `"-"` or `{ id, title }` with exactly those keys,
    /// a unique id like `delete-profile`, and a title of 1 to 80 characters on one line.
    private static func menuEntries(_ value: Any) -> [MenuEntry]? {
        guard let raw = value as? [Any], (1...20).contains(raw.count) else { return nil }
        var ids = Set<String>()
        var entries: [MenuEntry] = []
        for entry in raw {
            if entry as? String == "-" {
                entries.append(.separator)
                continue
            }
            guard let fields = entry as? [String: Any], Set(fields.keys) == ["id", "title"],
                  let id = fields["id"] as? String, id.wholeMatch(of: /[a-z][a-z0-9-]{0,31}/) != nil,
                  let title = fields["title"] as? String, (1...80).contains(title.count),
                  !title.trimmingCharacters(in: .whitespaces).isEmpty,
                  !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  ids.insert(id).inserted else { return nil }
            entries.append(.item(id: id, title: title))
        }
        return ids.isEmpty ? nil : entries
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
      reauth: (service, name, displayName) => call("reauth", name == null ? [service] : displayName == null ? [service, name] : [service, name, displayName]),
      openTerminal: () => call("openTerminal", []),
      dragWindow: () => call("dragWindow", []),
      signInAgain: () => call("signInAgain", []),
      contextMenu: (items) => call("contextMenu", [items]),
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
    private let onCall: @MainActor (BridgeCall, @escaping @MainActor (String?) -> Void) -> Void

    /// `hubURL` is the hub page; only pages from its origin may call. `onCall` gets the call and
    /// the way to answer it, once.
    init(hubURL: URL, onCall: @escaping @MainActor (BridgeCall, @escaping @MainActor (String?) -> Void) -> Void) {
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
        onCall(call) { replyHandler($0, nil) }
    }
}

/// Add the bridge to a web view's configuration, for the page's own scripts.
@MainActor func installBridge(in controller: WKUserContentController, canManageProfiles: Bool?, handler: BridgeHandler) {
    controller.addUserScript(WKUserScript(source: bridgeScript(canManageProfiles: canManageProfiles), injectionTime: .atDocumentStart,
                                          forMainFrameOnly: true, in: .page))
    controller.addScriptMessageHandler(handler, contentWorld: .page, name: bridgeHandlerName)
}

private let bridgeLog = Logger(subsystem: "com.plosson.agentio-companion", category: "bridge")

/// The script that tells the hub page a profile was added. The detail is JSON, so any name is safe;
/// without a name (a terminal add) it is null, and the page shows its profile list.
func profilesChangedScript(_ notice: PageNotice) -> String {
    // Each value is a JSON string literal (it escapes `/`, so `</script>` is inert); the key order is fixed.
    func literal(_ text: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }
    let profile = notice.profile.map(literal) ?? "null"
    return "window.dispatchEvent(new CustomEvent('agentio:profiles-changed', { detail: { service: \(literal(notice.service)), profile: \(profile) } }));"
}

/// The bridge's actions, for the page in `webView`; `reply` answers the page, once.
/// The terminal action is a stub until the terminal (S7) exists.
@MainActor func performBridgeCall(_ call: BridgeCall, in webView: HubWebView?, signInAgain: () -> Void,
                                  addProfile: (String, String?) -> Void, reauth: (String, String?, String?) -> Void,
                                  reply: @escaping @MainActor (String?) -> Void = { _ in }) {
    switch call {
    case .contextMenu(let entries):
        guard let webView else { return reply(nil) }
        return webView.offerMenu(entries, reply: reply)
    case .addProfile(let service, let displayName):
        addProfile(service, displayName)
    case .reauth(let service, let name, let displayName):
        reauth(service, name, displayName)
    case .openTerminal:
        bridgeLog.notice("[bridge stub] openTerminal() — PTY later")
    case .dragWindow:
        webView?.dragWindow()
    case .signInAgain:
        signInAgain()
    }
    reply(nil)
}
