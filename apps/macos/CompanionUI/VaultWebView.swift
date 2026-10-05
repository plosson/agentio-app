import AppKit
import SwiftUI
import WebKit

/// The hub's page, with the narrow bridge. Links that open new windows go
/// to the browser.
struct VaultWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        installBridge(in: configuration.userContentController, handler: BridgeHandler(hubURL: url, onCall: performBridgeCall))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        context.coordinator.loaded = url
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loaded != url else { return }
        context.coordinator.loaded = url
        webView.load(URLRequest(url: url))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    final class Coordinator: NSObject, WKUIDelegate {
        var loaded: URL?

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
