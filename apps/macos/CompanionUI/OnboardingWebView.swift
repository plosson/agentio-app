import AppKit
import SwiftUI
import WebKit

/// The onboarding page, rendering `state`; its actions go to `model`.
struct OnboardingWebView: NSViewRepresentable {
    let state: OnboardingState
    let model: CompanionModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> HubWebView {
        context.coordinator.makeWebView(state: state)
    }

    func updateNSView(_ webView: HubWebView, context: Context) {
        context.coordinator.update(state)
    }

    static func dismantleNSView(_ webView: HubWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: CompanionModel
        private weak var webView: HubWebView?
        /// The latest state asked for; `didFinish` renders it.
        private var state: OnboardingState?
        private var lastRendered: OnboardingState?
        private var loaded = false

        init(model: CompanionModel) {
            self.model = model
        }

        /// The web view with the bundled page loading. It stays hidden until the
        /// first render, so the window's background shows meanwhile (no white flash).
        func makeWebView(state: OnboardingState) -> HubWebView {
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.add(
                OnboardingMessageHandler(pageURL: onboardingPageURL) { [weak self] action in
                    guard let self else { return }
                    // Qualified: NSObject has its own perform(_:).
                    CompanionUI.perform(action, on: self.model, webView: self.webView)
                },
                contentWorld: .page, name: "agentioOnboarding")
            let webView = HubWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.isHidden = true
            self.webView = webView
            self.state = state
            webView.loadFileURL(onboardingPageURL, allowingReadAccessTo: onboardingPageURL.deletingLastPathComponent())
            return webView
        }

        func update(_ state: OnboardingState) {
            self.state = state
            render()
        }

        /// Push the latest state, once the page has loaded and only when it changed.
        private func render() {
            guard loaded, let webView, let state, state != lastRendered else { return }
            lastRendered = state
            webView.evaluateJavaScript(renderScript(state)) { [weak webView] _, _ in
                webView?.isHidden = false
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            lastRendered = nil
            render()
        }

        /// Only the bundled page itself loads; every other navigation is cancelled.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(allowsNavigation(to: action.request.url, page: onboardingPageURL) ? .allow : .cancel)
        }

        /// The page opens no windows: its one link goes through `openWebsite`.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}

/// Whether `url` is the bundled page `page`, a fragment aside.
func allowsNavigation(to url: URL?, page: URL) -> Bool {
    guard let url else { return false }
    return withoutFragment(url) == withoutFragment(page)
}

private func withoutFragment(_ url: URL) -> URL {
    var parts = URLComponents(url: url.standardizedFileURL, resolvingAgainstBaseURL: false)
    parts?.fragment = nil
    return parts?.url ?? url.standardizedFileURL
}

/// Receives the page's messages: only from the main frame of the bundled page.
final class OnboardingMessageHandler: NSObject, WKScriptMessageHandler {
    private let pageURL: URL
    private let onAction: @MainActor (OnboardingAction) -> Void

    init(pageURL: URL, onAction: @escaping @MainActor (OnboardingAction) -> Void) {
        self.pageURL = pageURL
        self.onAction = onAction
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              allowsNavigation(to: message.frameInfo.request.url, page: pageURL),
              let action = OnboardingAction(message: message.body) else { return }
        MainActor.assumeIsolated { onAction(action) }
    }
}
