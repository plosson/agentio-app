import AppKit
import SwiftUI
import WebKit

/// The hub's page, with the narrow bridge. Links that open new windows go
/// to the browser.
struct VaultWebView: NSViewRepresentable {
    let url: URL
    /// For the bridge; a change needs a new web view (the bridge is set when it is made).
    let canManageProfiles: Bool?
    /// The profile just added, for the page to hear; it never makes a new web view.
    let notice: PageNotice?
    let onSignInAgain: @MainActor () -> Void
    let onAddProfile: @MainActor (String, String?) -> Void
    let onReauth: @MainActor (String, String?, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HubWebView {
        let configuration = WKWebViewConfiguration()
        let coordinator = context.coordinator
        let signInAgain = onSignInAgain
        let addProfile = onAddProfile
        let reauth = onReauth
        installBridge(in: configuration.userContentController, canManageProfiles: canManageProfiles,
                      handler: BridgeHandler(hubURL: url) { [weak coordinator] call in
            performBridgeCall(call, in: coordinator?.webView, signInAgain: signInAgain, addProfile: addProfile,
                              reauth: reauth)
        })
        let webView = HubWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = coordinator
        coordinator.webView = webView
        coordinator.loaded = url
        // A page loaded after the add already has the profile.
        coordinator.lastNotice = notice?.id
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: HubWebView, context: Context) {
        if let notice, notice.id != context.coordinator.lastNotice {
            context.coordinator.lastNotice = notice.id
            webView.evaluateJavaScript(profilesChangedScript(notice))
        }
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        webView.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ webView: HubWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKUIDelegate {
        var loaded: URL?
        var lastNotice: UUID?
        weak var webView: HubWebView?

        /// window.open and target="_blank": http(s) links open in the browser.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased()) {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}

/// The web view under the transparent title bar, which the page can ask to
/// move the window.
final class HubWebView: WKWebView {
    /// The page's `dragWindow()` arrives a moment after its mouse-down, too
    /// late for `performDrag(with:)`, which then may not end on mouse-up. So
    /// the window follows the mouse here, while the button stays down.
    func dragWindow() {
        guard let window, CGEventSource.buttonState(.hidSystemState, button: .left) else { return }
        let start = NSEvent.mouseLocation
        let origin = window.frame.origin
        // The mouse-up can come before this loop starts; a held button and
        // the 50 ms wait end it then.
        while CGEventSource.buttonState(.hidSystemState, button: .left) {
            guard let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .leftMouseDown],
                                               until: Date(timeIntervalSinceNow: 0.05),
                                               inMode: .eventTracking, dequeue: true) else { continue }
            guard event.type == .leftMouseDragged else {
                // The page still gets its mouse-up, or the next press.
                NSApp.postEvent(event, atStart: true)
                return
            }
            let now = NSEvent.mouseLocation
            var frame = window.frame
            frame.origin = NSPoint(x: origin.x + now.x - start.x, y: origin.y + now.y - start.y)
            window.setFrameOrigin(window.constrainFrameRect(frame, to: window.screen).origin)
        }
    }
}

