import AppKit
import Foundation
import Testing
import WebKit
@testable import CompanionUI

struct BridgeCallTests {
    func menu(_ entries: Any) -> BridgeCall? { BridgeCall(message: ["method": "contextMenu", "args": [entries]]) }

    @Test func aContextMenuIsItsItemsAndSeparators() {
        #expect(menu([["id": "test", "title": "Test"], "-", ["id": "delete-2", "title": "Delete “kite/a b”…"]])
                == .contextMenu([.item(id: "test", title: "Test"), .separator, .item(id: "delete-2", title: "Delete “kite/a b”…")]))
    }

    @Test func aContextMenuRejectsAnythingOdd() {
        let item: [String: Any] = ["id": "test", "title": "Test"]
        let bad: [Any] = [
            [Any](), ["-"], ["-", "-"], "Test", [item, "+"], [item, NSNull()], [item, 42],
            [["id": "test"]], [["title": "Test"]], [["id": "test", "title": "Test", "extra": true]],
            [["id": "", "title": "Test"]], [["id": "Test", "title": "Test"]], [["id": "1test", "title": "Test"]],
            [["id": "te st", "title": "Test"]], [["id": String(repeating: "a", count: 33), "title": "Test"]],
            [["id": "test", "title": ""]], [["id": "test", "title": "   "]], [["id": "test", "title": String(repeating: "a", count: 81)]],
            [["id": "test", "title": "Test\nmore"]], [["id": "test", "title": "Te\u{0}st"]], [["id": 1, "title": "Test"]],
            [item, item],  // the same id twice
            (Array(repeating: "-", count: 10) as [Any]) + (0..<20).map { ["id": "i\($0)", "title": "Item"] as Any },  // 30 entries
        ]
        for entries in bad {
            #expect(menu(entries) == nil, "entries: \(entries)")
        }
        #expect(BridgeCall(message: ["method": "contextMenu", "args": [[item], [item]]]) == nil)
        #expect(BridgeCall(message: ["method": "contextMenu", "args": [Any]()]) == nil)
    }

    @Test func acceptsTheFiveCalls() {
        #expect(BridgeCall(message: ["method": "addProfile", "args": ["gmail"]]) == .addProfile(service: "gmail", displayName: nil))
        #expect(BridgeCall(message: ["method": "addProfile", "args": ["gmail", "Gmail"]]) == .addProfile(service: "gmail", displayName: "Gmail"))
        #expect(BridgeCall(message: ["method": "reauth", "args": ["gmail"]]) == .reauth(service: "gmail", name: nil, displayName: nil))
        #expect(BridgeCall(message: ["method": "reauth", "args": ["gmail", "work"]]) == .reauth(service: "gmail", name: "work", displayName: nil))
        #expect(BridgeCall(message: ["method": "reauth", "args": ["gmail", "work", "Gmail"]]) == .reauth(service: "gmail", name: "work", displayName: "Gmail"))
        #expect(BridgeCall(message: ["method": "openTerminal", "args": [Any]()]) == .openTerminal)
        #expect(BridgeCall(message: ["method": "dragWindow", "args": [Any]()]) == .dragWindow)
        #expect(BridgeCall(message: ["method": "signInAgain", "args": [Any]()]) == .signInAgain)
    }

    @Test func rejectsEverythingElse() {
        let bad: [Any] = [
            "addProfile", ["method": "addProfile"], ["method": "addProfile", "args": "gmail"],
            ["method": "addProfile", "args": [Any]()], ["method": "addProfile", "args": [42]],
            ["method": "addProfile", "args": [""]], ["method": "addProfile", "args": ["a", "b", "c"]],
            ["method": "reauth", "args": ["gmail", NSNull()]],
            ["method": "reauth", "args": ["gmail", "work", "Gmail", "x"]], ["method": "reauth", "args": ["gmail", "work", ""]],
            ["method": "reauth", "args": ["gmail", "work", 42]], ["method": "openTerminal", "args": ["x"]],
            ["method": "dragWindow", "args": ["x"]], ["method": "dragWindow"], ["method": "DragWindow", "args": [Any]()],
            ["method": "signInAgain", "args": ["https://evil.example"]], ["method": "signInAgain"],
            ["method": "exec", "args": ["rm -rf /"]], ["method": "__proto__", "args": [Any]()],
        ]
        for body in bad {
            #expect(BridgeCall(message: body) == nil, "body: \(body)")
        }
    }
}

@MainActor
struct BridgeActionTests {
    @Test func reauthReachesOnlyTheReauthAction() {
        var reauths: [String] = []
        var others = 0
        for call in [BridgeCall.reauth(service: "gmail", name: "work", displayName: "Gmail"), .reauth(service: "gmail", name: nil, displayName: nil)] {
            performBridgeCall(call, in: nil, signInAgain: { others += 1 }, addProfile: { _, _ in others += 1 },
                              reauth: { reauths.append("\($0)|\($1 ?? "nil")|\($2 ?? "nil")") })
        }
        #expect(reauths == ["gmail|work|Gmail", "gmail|nil|nil"])
        #expect(others == 0)
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
                      handler: BridgeHandler(hubURL: URL(string: "https://h.example/ui")!) { call, reply in
            log.calls.append(call)
            // A menu "picks" its last item, so the reply reaches the page.
            if case .contextMenu(let entries) = call, case .item(let id, _) = entries.last { return reply(id) }
            reply(nil)
        })
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
        let picked = try await webView.callAsyncJavaScript(
            "return await window.agentioCompanion.contextMenu([{ id: 'test', title: 'Test' }, '-', { id: 'rename', title: 'Rename…' }])",
            contentWorld: .page)
        #expect(picked as? String == "rename")
        _ = try await webView.callAsyncJavaScript(
            "await window.agentioCompanion.addProfile('gmail', 'Gmail'); await window.agentioCompanion.reauth('gmail', null); await window.agentioCompanion.reauth('gmail', 'a b', 'Gmail'); await window.agentioCompanion.openTerminal(); await window.agentioCompanion.dragWindow(); await window.agentioCompanion.signInAgain(); return 1",
            contentWorld: .page)
        #expect(log.calls == [.contextMenu([.item(id: "test", title: "Test"), .separator, .item(id: "rename", title: "Rename…")]),
                              .addProfile(service: "gmail", displayName: "Gmail"), .reauth(service: "gmail", name: nil, displayName: nil), .reauth(service: "gmail", name: "a b", displayName: "Gmail"), .openTerminal, .dragWindow, .signInAgain])
    }

    @Test func theProfilesChangedEventCarriesTheProfileUnharmed() async throws {
        let webView = try await page("<html><body><script>window.got = []; window.addEventListener('agentio:profiles-changed', (e) => window.got.push(e.detail));</script></body></html>", log: CallLog())
        let notice = PageNotice(id: UUID(), service: "gmail", profile: #"a"b'c</script><b>@x"#)
        _ = try await webView.evaluateJavaScript(profilesChangedScript(notice))
        let got = try await webView.callAsyncJavaScript("return JSON.stringify(window.got)", contentWorld: .page)
        #expect(got as? String == #"[{"service":"gmail","profile":"a\"b'c</script><b>@x"}]"#)
    }

    @Test func theProfilesChangedEventWithoutAProfileSendsNull() async throws {
        let webView = try await page("<html><body><script>window.got = []; window.addEventListener('agentio:profiles-changed', (e) => window.got.push(e.detail));</script></body></html>", log: CallLog())
        _ = try await webView.evaluateJavaScript(profilesChangedScript(PageNotice(id: UUID(), service: "gcal", profile: nil)))
        let got = try await webView.callAsyncJavaScript("return JSON.stringify(window.got)", contentWorld: .page)
        #expect(got as? String == #"[{"service":"gcal","profile":null}]"#)
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

@MainActor
struct ContextMenuTests {
    func item(_ title: String, id: String? = nil, action: Selector? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let id { item.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifier" + id) }
        return item
    }
    func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "—" : $0.title } }

    @Test func aLinkGetsNoMenu() {
        let menu = NSMenu()
        for entry in [item("Open Link", id: "OpenLink"), item("Open Link in New Window", id: "OpenLinkInNewWindow"),
                      item("Download Linked File", id: "DownloadLinkedFile"),
                      // Copies too, but it is a link item: its identifier decides, not its action.
                      item("Copy Link", id: "CopyLink", action: #selector(NSText.copy(_:))),
                      .separator(), item("Share…", id: "ShareMenu"), .separator(), item("Reload", id: "Reload")] {
            menu.addItem(entry)
        }
        keepTextItems(in: menu, inspect: false)
        #expect(menu.items.isEmpty)
    }

    @Test func aTextFieldKeepsItsEditingItemsWithTidySeparators() {
        let menu = NSMenu()
        for entry in [.separator(), item("Look Up “x”", id: "LookUp"), item("Translate “x”", id: "Translate"),
                      item("Search with Google", id: "SearchWeb"), .separator(), .separator(),
                      item("Cut", action: #selector(NSText.cut(_:))), item("Copy", id: "Copy"), item("Paste", id: "Paste"),
                      .separator(), item("Share…", id: "ShareMenu"), item("Services"), .separator(),
                      item("Spelling and Grammar", id: "SpellingMenu"), item("Writing Tools", id: "WritingTools"),
                      item("Inspect Element", id: "InspectElement"), .separator()] {
            menu.addItem(entry)
        }
        keepTextItems(in: menu, inspect: false)
        #expect(titles(menu) == ["Look Up “x”", "Translate “x”", "—", "Cut", "Copy", "Paste", "—", "Spelling and Grammar"])
    }

    func rightClick() -> NSEvent {
        NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    /// What WebKit opens on a link.
    func webKitMenu() -> NSMenu {
        let menu = NSMenu()
        for entry in [item("Open Link", id: "OpenLink"), item("Copy Link", id: "CopyLink"), item("Share…", id: "ShareMenu")] {
            menu.addItem(entry)
        }
        return menu
    }
    func choose(_ item: NSMenuItem) { _ = (item.target as? NSObject)?.perform(item.action, with: item) }

    @Test func theOfferedItemsReplaceWebKitsAndTheChosenIdIsTheAnswer() async {
        let view = HubWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var answers: [String?] = []
        view.offerMenu([.separator, .item(id: "test", title: "Test"), .separator, .separator,
                        .item(id: "delete", title: "Delete Profile…"), .separator]) { answers.append($0) }
        let menu = webKitMenu()
        view.willOpenMenu(menu, with: rightClick())
        #expect(titles(menu) == ["Test", "—", "Delete Profile…"])
        // AppKit sends the action as the menu closes; the answer is the item, once.
        view.didCloseMenu(menu, with: nil)
        choose(menu.items[2])
        try? await Task.sleep(for: .milliseconds(50))
        #expect(answers == ["delete"])
    }

    @Test func aMenuClosedWithoutAChoiceAnswersNullOnce() async {
        let view = HubWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var answers: [String?] = []
        view.offerMenu([.item(id: "test", title: "Test")]) { answers.append($0) }
        let menu = webKitMenu()
        view.willOpenMenu(menu, with: rightClick())
        view.didCloseMenu(menu, with: nil)
        try? await Task.sleep(for: .milliseconds(50))
        view.didCloseMenu(menu, with: nil)
        choose(menu.items[0])  // too late: already answered
        try? await Task.sleep(for: .milliseconds(50))
        #expect(answers == [nil])
    }

    @Test func aNewerOfferEndsTheOlderOneAndTheNextMenuIsCleanedAsUsual() {
        let view = HubWebView(frame: .zero, configuration: WKWebViewConfiguration())
        var answers: [String] = []
        view.offerMenu([.item(id: "old", title: "Old")]) { answers.append("old:\($0 ?? "nil")") }
        view.offerMenu([.item(id: "new", title: "New")]) { answers.append("new:\($0 ?? "nil")") }
        #expect(answers == ["old:nil"])
        let first = webKitMenu()
        view.willOpenMenu(first, with: rightClick())
        #expect(titles(first) == ["New"])
        // The offer was used: the next right-click, with none, gets WebKit's menu without its browser items.
        let second = webKitMenu()
        view.willOpenMenu(second, with: rightClick())
        #expect(second.items.isEmpty)
        // A new menu opening ends the previous one, unanswered.
        #expect(answers == ["old:nil", "new:nil"])
    }

    @Test func inspectElementStaysOnlyWhereThePageCanBeInspected() {
        let menu = NSMenu()
        menu.addItem(item("Reload", id: "Reload"))
        menu.addItem(.separator())
        menu.addItem(item("Inspect Element", id: "InspectElement"))
        keepTextItems(in: menu, inspect: true)
        #expect(titles(menu) == ["Inspect Element"])
    }
}
