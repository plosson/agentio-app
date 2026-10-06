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
                      handler: BridgeHandler(hubURL: url) { [weak coordinator] call, reply in
            performBridgeCall(call, in: coordinator?.webView, signInAgain: signInAgain, addProfile: addProfile,
                              reauth: reauth, reply: reply)
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
    /// The page's items for the right-click under way, until WebKit opens its menu.
    private var offeredMenu: (entries: [BridgeCall.MenuEntry], reply: @MainActor (String?) -> Void)?
    /// Answers the page once the menu with its items closes.
    private var menuPicker: MenuPicker?

    /// The page's right-click handler offers its items before WebKit opens the menu for the
    /// same click (both come in order from the page), so `willOpenMenu` shows them instead.
    /// A newer offer ends an older one, unanswered.
    func offerMenu(_ entries: [BridgeCall.MenuEntry], reply: @escaping @MainActor (String?) -> Void) {
        offeredMenu?.reply(nil)
        offeredMenu = (entries, reply)
    }

    /// The right-click menu: the page's items when it offered some, or else no browser
    /// items (links, images, sharing, reloading).
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        // A menu still waiting for its answer has closed by now.
        menuPicker?.finish()
        menuPicker = nil
        guard let offered = offeredMenu else { return keepTextItems(in: menu, inspect: isInspectable) }
        offeredMenu = nil
        let picker = MenuPicker(reply: offered.reply)
        menuPicker = picker
        menu.removeAllItems()
        for entry in offered.entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .item(let id, let title):
                let item = NSMenuItem(title: title, action: #selector(MenuPicker.pick(_:)), keyEquivalent: "")
                item.target = picker
                item.representedObject = id
                menu.addItem(item)
            }
        }
        tidySeparators(in: menu)
    }

    /// A menu closed without a choice answers null; a chosen item's action may come just after, so wait one turn.
    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        guard let picker = menuPicker else { return }
        menuPicker = nil
        DispatchQueue.main.async { picker.finish() }
    }

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

/// Keep only the items that edit or read text, and Inspect Element when `inspect`.
/// WebKit's own identifiers decide for its items; Cut is not one of them, so its action counts.
func keepTextItems(in menu: NSMenu, inspect: Bool) {
    let prefix = "WKMenuItemIdentifier"
    let kept = Set((["Copy", "Paste", "LookUp", "Translate", "SpellingMenu"] + (inspect ? ["InspectElement"] : [])).map { prefix + $0 })
    for item in menu.items where !item.isSeparatorItem {
        let id = item.identifier?.rawValue ?? ""
        let keep = id.hasPrefix(prefix) ? kept.contains(id) : item.action == #selector(NSText.cut(_:))
        if !keep { menu.removeItem(item) }
    }
    tidySeparators(in: menu)
}

/// Answers the page with the item chosen in its menu, or null: once.
@MainActor private final class MenuPicker: NSObject {
    private var reply: (@MainActor (String?) -> Void)?

    init(reply: @escaping @MainActor (String?) -> Void) { self.reply = reply }

    @objc func pick(_ sender: NSMenuItem) { answer(sender.representedObject as? String) }
    func finish() { answer(nil) }

    private func answer(_ id: String?) {
        let reply = reply
        self.reply = nil
        reply?(id)
    }
}

/// No separator first, last, or next to another.
private func tidySeparators(in menu: NSMenu) {
    var previousIsSeparator = true
    for item in menu.items {
        if item.isSeparatorItem && previousIsSeparator { menu.removeItem(item) } else { previousIsSeparator = item.isSeparatorItem }
    }
    if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
}
