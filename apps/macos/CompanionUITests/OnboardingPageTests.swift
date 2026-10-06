import Foundation
import Testing
import WebKit
@testable import CompanionUI

/// Every message the onboarding page posts, as the app would read it (nil: refused).
@MainActor final class PageMessages: NSObject, WKScriptMessageHandler {
    var actions: [OnboardingAction?] = []
    var marks = 0

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.body as? String == "test-mark" { return marks += 1 }
        actions.append(OnboardingAction(message: message.body))
    }
}

/// A state with idle defaults, for `screen`.
func state(_ screen: String, _ change: (inout OnboardingState) -> Void = { _ in }) -> OnboardingState {
    var state = OnboardingState(
        screen: screen, vault: nil, download: .init(phase: "idle", percent: 0, log: []),
        hubAddress: "", rememberAddress: true, hubCheck: .init(state: "idle", hub: nil, version: nil),
        code: nil, copiedLink: false, finished: nil, busy: nil, error: nil)
    change(&state)
    return state
}

let hostile = #"<img src=x onerror="window.pwned=1">"#

@MainActor
struct OnboardingPageTests {
    let messages = PageMessages()
    let webView: WKWebView

    init() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(messages, name: "agentioOnboarding")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 640), configuration: configuration)
        webView.loadFileURL(onboardingPageURL, allowingReadAccessTo: onboardingPageURL.deletingLastPathComponent())
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while webView.isLoading || webView.url == nil {
            guard clock.now < deadline else { throw AgentioTestTimeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func render(_ state: OnboardingState) async throws {
        _ = try await webView.callAsyncJavaScript(renderScript(state), contentWorld: .page)
    }

    func js(_ body: String) async throws -> Any? {
        try await webView.callAsyncJavaScript(body, contentWorld: .page)
    }

    func string(_ expression: String) async throws -> String? {
        try await js("return \(expression)") as? String
    }

    func bool(_ expression: String) async throws -> Bool? {
        try await js("return \(expression)") as? Bool
    }

    func int(_ expression: String) async throws -> Int? {
        (try await js("return \(expression)") as? NSNumber)?.intValue
    }

    /// The messages `script` makes the page post (and nothing else), in order.
    func sent(by script: String) async throws -> [OnboardingAction?] {
        let before = messages.actions.count
        let marks = messages.marks
        _ = try await js(script + "; window.webkit.messageHandlers.agentioOnboarding.postMessage('test-mark')")
        try await waitFor { messages.marks > marks }
        return Array(messages.actions[before...])
    }

    /// Waits (bounded) until `condition` holds.
    func waitFor(seconds: Int = 3, _ condition: () async throws -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(seconds)
        while try await !condition() {
            guard clock.now < deadline else { throw AgentioTestTimeout() }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Screens

    @Test func eachScreenShowsAloneAndAsked() async throws {
        let screens = ["loading", "welcome", "back", "hub", "local", "ready", "failed", "approve", "done"]
        for name in screens + screens.reversed() {
            try await render(state(name))
            #expect(try await int("document.querySelectorAll('.screen.on').length") == 1, "\(name)")
            #expect(try await string("document.querySelector('.screen.on').dataset.screen") == name)
        }
    }

    @Test func anUnknownScreenOrNoStateBreaksNothing() async throws {
        try await render(state("welcome"))
        _ = try await js("window.agentioOnboarding.render({screen: 'nope'}); window.agentioOnboarding.render(null); window.agentioOnboarding.render({})")
        try await render(state("hub"))
        #expect(try await string("document.querySelector('.screen.on').dataset.screen") == "hub")
    }

    @Test func thePageCannotBeReplaced() async throws {
        let replaced = try await bool("(() => { try { window.agentioOnboarding.render = null } catch (e) {} ; return typeof window.agentioOnboarding.render === 'function' })()")
        #expect(replaced == true)
    }

    // MARK: Untrusted text stays text (Review Focus 2)

    @Test func anErrorShowsAsTextAndRunsNothing() async throws {
        let images = try await int("document.querySelectorAll('img').length")
        try await render(state("hub") { $0.error = hostile })
        #expect(try await string("document.querySelector('.screen.on .banner').textContent") == hostile)
        #expect(try await bool("document.querySelector('.screen.on .banner').hidden") == false)
        #expect(try await int("document.querySelectorAll('img').length") == images)
        #expect(try await string("typeof window.pwned") == "undefined")

        try await render(state("hub"))
        #expect(try await bool("document.querySelector('.screen.on .banner').hidden") == true)
    }

    @Test func aHubAddressShowsAsTextAndRunsNothing() async throws {
        let images = try await int("document.querySelectorAll('img').length")
        for check in ["found", "unreachable", "tooOld"] {
            try await render(state("hub") { $0.hubCheck = .init(state: check, hub: hostile, version: hostile) })
            let line = try await string("document.getElementById('hubCheck').textContent")
            #expect(line?.contains(hostile) == true, "\(check): \(line ?? "nil")")
        }
        try await render(state("back") { $0.vault = .init(kind: "remote", hub: hostile) })
        #expect(try await string("document.querySelector('.screen.on .where').textContent") == hostile)
        try await render(state("done") { $0.finished = .init(kind: "remote", hub: hostile) })
        #expect(try await string("document.querySelector('.screen.on .where').textContent") == hostile)
        #expect(try await int("document.querySelectorAll('img').length") == images)
        #expect(try await string("typeof window.pwned") == "undefined")
    }

    @Test func aLogLineShowsAsTextAndRunsNothing() async throws {
        let images = try await int("document.querySelectorAll('img').length")
        let log = ["Downloading…", hostile, "</pre><script>window.pwned=1</script>"]
        try await render(state("ready") { $0.download = .init(phase: "downloading", percent: 10, log: log) })
        #expect(try await string("document.getElementById('readyLog').textContent") == log.joined(separator: "\n"))
        #expect(try await int("document.getElementById('readyLog').children.length") == 0)
        try await render(state("failed") { $0.download = .init(phase: "failed", percent: 10, log: log) })
        #expect(try await string("document.getElementById('failedLog').textContent") == log.joined(separator: "\n"))
        #expect(try await int("document.querySelectorAll('img').length") == images)
        #expect(try await string("typeof window.pwned") == "undefined")
    }

    @Test func aHostileCodeShowsAsText() async throws {
        let images = try await int("document.querySelectorAll('img').length")
        try await render(state("approve") { $0.code = "<img src=x onerror=\"window.pwned=1\">" })
        #expect(try await int("document.querySelectorAll('img').length") == images)
        #expect(try await string("typeof window.pwned") == "undefined")
    }

    // MARK: Render many times, nothing reset (Review Focus 1)

    @Test func progressDoesNotResetWhatTheUserTypes() async throws {
        try await render(state("hub"))
        _ = try await js("const f = document.getElementById('hubInput'); f.value = 'team.example'; f.focus()")
        for percent in 0..<50 {
            try await render(state("hub") { $0.download = .init(phase: "downloading", percent: percent, log: ["line \(percent)"]) })
        }
        #expect(try await string("document.getElementById('hubInput').value") == "team.example")
        #expect(try await bool("document.activeElement === document.getElementById('hubInput')") == true)
        #expect(try await int("document.querySelectorAll('#confetti i').length") == 0)
        #expect(try await string("document.getElementById('confetti').dataset.runs || '0'") == "0")
        #expect(try await string("document.getElementById('pillText').textContent") == "Getting AgentIO ready… 49%")
    }

    @Test func progressDoesNotClearThePassphrases() async throws {
        try await render(state("local"))
        _ = try await js("document.getElementById('pass1').value = 'correct horse'; document.getElementById('pass2').value = 'correct'; document.getElementById('pass2').focus()")
        for percent in 0..<20 {
            try await render(state("local") { $0.download = .init(phase: "downloading", percent: percent, log: []) })
        }
        #expect(try await string("document.getElementById('pass1').value") == "correct horse")
        #expect(try await string("document.getElementById('pass2').value") == "correct")
        #expect(try await bool("document.activeElement === document.getElementById('pass2')") == true)
    }

    @Test func theDoneEntryRunsOncePerEntry() async throws {
        try await render(state("done") { $0.finished = .init(kind: "remote", hub: "h.example") })
        try await render(state("done") { $0.finished = .init(kind: "remote", hub: "h.example") })
        #expect(try await string("document.getElementById('confetti').dataset.runs") == "1")
        #expect(try await int("document.querySelectorAll('#confetti i').length") ?? 0 > 0)
        try await render(state("welcome"))
        try await render(state("done") { $0.finished = .init(kind: "local") })
        #expect(try await string("document.getElementById('confetti').dataset.runs") == "2")
    }

    @Test func theHubEntryFillsAndChecksOnlyOnce() async throws {
        #expect(try await sent(by: "").isEmpty)
        try await render(state("hub") { $0.hubAddress = "team.example"; $0.rememberAddress = false })
        try await waitFor { messages.actions.count >= 1 }
        #expect(messages.actions == [.checkHub("team.example")])
        #expect(try await string("document.getElementById('hubInput').value") == "team.example")
        #expect(try await bool("document.getElementById('hubRemember').checked") == false)
        #expect(try await bool("document.activeElement === document.getElementById('hubInput')") == true)
        // Later renders neither refill, recheck nor reset the checkbox.
        _ = try await js("document.getElementById('hubInput').value = ''; document.getElementById('hubRemember').checked = true")
        let again = try await sent(by: "") + (try await renderAndCollect(state("hub") { $0.hubAddress = "other.example"; $0.rememberAddress = false }))
        #expect(again.isEmpty)
        #expect(try await string("document.getElementById('hubInput').value") == "")
        #expect(try await bool("document.getElementById('hubRemember').checked") == true)
    }

    @Test func theHubEntryWithoutAnAddressSendsNothing() async throws {
        #expect(try await renderAndCollect(state("hub")).isEmpty)
    }

    /// Renders `state` and returns what the page posted while doing so.
    func renderAndCollect(_ state: OnboardingState) async throws -> [OnboardingAction?] {
        try await sent(by: renderScript(state))
    }

    // MARK: Actions

    @Test func theWelcomeCardsChooseThenContinue() async throws {
        try await render(state("welcome"))
        #expect(try await sent(by: "document.getElementById('welcomeNext').click()").isEmpty)
        #expect(try await sent(by: "document.querySelector('[data-choice=hub]').click()").isEmpty)
        #expect(try await string("document.querySelector('[data-choice=hub]').getAttribute('aria-checked')") == "true")
        #expect(try await sent(by: "document.getElementById('welcomeNext').click()") == [.chooseHub])
        #expect(try await sent(by: "document.querySelector('[data-choice=local]').click(); document.getElementById('welcomeNext').click()") == [.chooseLocal])
        #expect(try await string("document.querySelector('[data-choice=hub]').getAttribute('aria-checked')") == "false")
    }

    @Test func connectWaitsForTheTypedHubToBeFound() async throws {
        try await render(state("hub"))
        _ = try await js("const f = document.getElementById('hubInput'); f.value = 'team.example'")
        let click = "document.getElementById('hubNext').click()"
        #expect(try await bool("document.getElementById('hubNext').disabled") == true)
        #expect(try await sent(by: click).isEmpty)

        for check in [OnboardingState.Check(state: "checking", hub: "team.example", version: nil),
                      .init(state: "found", hub: "other.example", version: "3.17.0"),
                      .init(state: "unreachable", hub: "team.example", version: nil),
                      .init(state: "tooOld", hub: "team.example", version: "3.1.0"),
                      .init(state: "invalid", hub: nil, version: nil),
                      .init(state: "found", hub: nil, version: nil)] {
            try await render(state("hub") { $0.hubCheck = check })
            #expect(try await sent(by: click).isEmpty, "\(check)")
        }

        try await render(state("hub") { $0.hubCheck = .init(state: "found", hub: "team.example", version: "3.17.0") })
        #expect(try await bool("document.getElementById('hubNext').disabled") == false)
        #expect(try await string("document.getElementById('hubCheck').textContent") == "✓ Found it: team.example")
        #expect(try await sent(by: click) == [.signIn(address: "team.example", remember: true)])
        #expect(try await sent(by: "document.getElementById('hubRemember').click(); " + click) == [.signIn(address: "team.example", remember: false)])

        // Typing something else disables it at once, before any new check.
        _ = try await js("const f = document.getElementById('hubInput'); f.value = 'team.example.org'; f.dispatchEvent(new Event('input'))")
        #expect(try await bool("document.getElementById('hubNext').disabled") == true)
    }

    @Test func connectAcceptsTheSameHubTypedDifferently() async throws {
        try await render(state("hub") { $0.hubCheck = .init(state: "found", hub: "team.example", version: "3.17.0") })
        _ = try await js("document.getElementById('hubInput').value = ' Team.Example/ '; document.getElementById('hubInput').dispatchEvent(new Event('input'))")
        #expect(try await bool("document.getElementById('hubNext').disabled") == false)
    }

    @Test func typingChecksOnceAfterAPauseWithoutTheScheme() async throws {
        try await render(state("hub"))
        _ = try await js("""
            const f = document.getElementById('hubInput');
            for (const v of ['t', 'te', 'https://team.example']) { f.value = v; f.dispatchEvent(new Event('input')) }
            """)
        #expect(try await string("document.getElementById('hubInput').value") == "team.example")
        try await waitFor { messages.actions.count >= 1 }
        #expect(try await sent(by: "") == [])
        #expect(messages.actions == [.checkHub("team.example")])
    }

    @Test func theHubCheckLineFollowsTheState() async throws {
        let lines: [(OnboardingState.Check, String)] = [
            (.init(state: "idle", hub: nil, version: nil), ""),
            (.init(state: "checking", hub: "h.example", version: nil), "Looking for your hub…"),
            (.init(state: "found", hub: "h.example", version: "3.17.0"), "✓ Found it: h.example"),
            (.init(state: "invalid", hub: nil, version: nil), "That doesn’t look like a web address yet."),
            (.init(state: "unreachable", hub: "h.example", version: nil), "No AgentIO hub answers at h.example. Check the address?"),
            (.init(state: "tooOld", hub: "h.example", version: "3.1.0"), "This hub runs AgentIO 3.1.0. It needs 3.14 or later for this app."),
        ]
        for (check, line) in lines {
            try await render(state("hub") { $0.hubCheck = check })
            #expect(try await string("document.getElementById('hubCheck').textContent") == line, "\(check.state)")
        }
    }

    @Test func busyDisablesTheMainButtonAndSaysWhy() async throws {
        try await render(state("hub") { $0.hubCheck = .init(state: "found", hub: "team.example", version: "3.17.0") })
        _ = try await js("document.getElementById('hubInput').value = 'team.example'; document.getElementById('hubInput').dispatchEvent(new Event('input'))")
        try await render(state("hub") { $0.hubCheck = .init(state: "found", hub: "team.example", version: "3.17.0"); $0.busy = "Checking the hub…" })
        #expect(try await bool("document.getElementById('hubNext').disabled") == true)
        #expect(try await string("document.getElementById('hubNext').textContent.trim()") == "Checking the hub…")
        #expect(try await bool("!document.querySelector('#hubNext .spinner').hidden") == true)
        #expect(try await sent(by: "document.getElementById('hubNext').click()").filter { $0 != .checkHub("team.example") }.isEmpty)

        try await render(state("hub") { $0.hubCheck = .init(state: "found", hub: "team.example", version: "3.17.0") })
        #expect(try await string("document.getElementById('hubNext').textContent.trim()") == "Connect")
        #expect(try await bool("document.getElementById('hubNext').disabled") == false)

        try await render(state("back") { $0.vault = .init(kind: "local"); $0.busy = "Starting the local vault…" })
        #expect(try await string("document.getElementById('backOpen').textContent.trim()") == "Starting the local vault…")
        #expect(try await sent(by: "document.getElementById('backOpen').click()").isEmpty)
    }

    @Test func createMyVaultSendsBothFieldsThenClearsThem() async throws {
        try await render(state("local"))
        let fill = { (a: String, b: String) in
            "for (const [id, v] of [['pass1', '\(a)'], ['pass2', '\(b)']]) { const f = document.getElementById(id); f.value = v; f.dispatchEvent(new Event('input')) }"
        }
        let click = "document.getElementById('localNext').click()"
        _ = try await js(fill("short", "short"))
        #expect(try await sent(by: click).isEmpty)
        _ = try await js(fill("correct horse", "correct horsf"))
        #expect(try await sent(by: click).isEmpty)
        #expect(try await string("document.getElementById('matchHint').textContent") == "They don’t match yet")
        _ = try await js(fill("correct horse", "correct horse"))
        #expect(try await sent(by: click) == [.createVault(passphrase: "correct horse", again: "correct horse")])
        #expect(try await string("document.getElementById('pass1').value + '|' + document.getElementById('pass2').value") == "|")
        #expect(try await bool("document.getElementById('localNext').disabled") == true)
        #expect(try await sent(by: click).isEmpty)
    }

    @Test func leavingTheLocalScreenForgetsThePassphrase() async throws {
        try await render(state("local"))
        _ = try await js("document.getElementById('pass1').value = 'correct horse'; document.getElementById('pass2').value = 'correct horse'")
        try await render(state("welcome"))
        #expect(try await string("document.getElementById('pass1').value + '|' + document.getElementById('pass2').value") == "|")
    }

    @Test func theBackButtonsGoBack() async throws {
        for (screen, id) in [("hub", "hubBack"), ("local", "localBack"), ("failed", "failedBack")] {
            try await render(state(screen))
            #expect(try await sent(by: "document.getElementById('\(id)').click()") == [.back], "\(screen)")
        }
    }

    @Test func welcomeBackOpensTheVaultOrAnother() async throws {
        try await render(state("back") { $0.vault = .init(kind: "remote", hub: "h.example") })
        #expect(try await string("document.querySelector('.screen.on .where').textContent") == "h.example")
        #expect(try await string("document.getElementById('backOther').textContent") == "Use a different hub")
        #expect(try await sent(by: "document.getElementById('backOpen').click()") == [.openExistingVault])
        #expect(try await sent(by: "document.getElementById('backOther').click()") == [.useAnotherVault])

        try await render(state("back") { $0.vault = .init(kind: "local") })
        #expect(try await string("document.querySelector('.screen.on .where').textContent") == "On this Mac")
        #expect(try await string("document.getElementById('backOther').textContent") == "Connect to a hub instead")
    }

    @Test func tryAgainRetriesTheDownload() async throws {
        try await render(state("failed") { $0.download = .init(phase: "failed", percent: 30, log: ["curl: (56)"]) })
        #expect(try await sent(by: "document.getElementById('retry').click()") == [.retryDownload])
    }

    @Test func theApproveScreenShowsTheCodeAndItsActions() async throws {
        try await render(state("approve") { $0.code = "WDJB-MJHT" })
        #expect(try await string("[...document.querySelectorAll('#code span')].map(s => s.className === 'gap' ? '-' : s.textContent).join('')") == "WDJB-MJHT")
        #expect(try await string("document.getElementById('copied').textContent") == "")
        #expect(try await sent(by: "document.getElementById('approveNow').click()") == [.openApproval])
        #expect(try await sent(by: "document.getElementById('copyLink').click()") == [.copyApprovalLink])
        #expect(try await sent(by: "document.getElementById('cancel').click()") == [.cancelSignIn])

        try await render(state("approve") { $0.code = "WDJB-MJHT"; $0.copiedLink = true })
        #expect(try await string("document.getElementById('copied').textContent") == "Link copied. Send it to the hub’s owner; this page continues on its own once they approve.")
    }

    @Test func approveWithoutACodeWaitsForOne() async throws {
        try await render(state("approve") { $0.code = "WDJB-MJHT" })
        try await render(state("approve"))
        #expect(try await int("document.querySelectorAll('#code span:not(.gap)').length") == 8)
        #expect(try await string("[...document.querySelectorAll('#code span:not(.gap)')].map(s => s.textContent).join('')") == "")
        #expect(try await string("document.getElementById('waitText').textContent") == "Asking the hub for a code…")
        #expect(try await bool("document.getElementById('approveNow').disabled && document.getElementById('copyLink').disabled") == true)
        #expect(try await sent(by: "document.getElementById('approveNow').click(); document.getElementById('copyLink').click()").isEmpty)
        #expect(try await sent(by: "document.getElementById('cancel').click()") == [.cancelSignIn])
    }

    @Test func doneOpensTheVault() async throws {
        try await render(state("done") { $0.finished = .init(kind: "local") })
        #expect(try await string("document.getElementById('doneTitle').textContent") == "Your vault is ready!")
        #expect(try await bool("document.getElementById('doneWhere').hidden") == true)
        #expect(try await sent(by: "document.getElementById('doneOpen').click()") == [.openVault])
        try await render(state("welcome"))
        try await render(state("done") { $0.finished = .init(kind: "remote", hub: "h.example") })
        #expect(try await string("document.getElementById('doneTitle').textContent") == "You’re all set!")
        #expect(try await bool("document.getElementById('doneWhere').hidden") == false)
    }

    @Test func theWebsiteLinkIsAnActionNotANavigation() async throws {
        try await render(state("hub"))
        let url = webView.url
        #expect(try await sent(by: "document.getElementById('website').click()") == [.openWebsite])
        #expect(webView.url == url)
    }

    @Test func dragsStartOnlyFromEmptyAreas() async throws {
        try await render(state("welcome"))
        let down = { (selector: String) in
            "document.querySelector('\(selector)').dispatchEvent(new MouseEvent('mousedown', { bubbles: true, button: 0 }))"
        }
        #expect(try await sent(by: down(".screen.on h1")) == [.dragWindow])
        for selector in ["#welcomeNext", "[data-choice=hub] b", "#welcomeNext .label"] {
            #expect(try await sent(by: down(selector)).isEmpty, "\(selector)")
        }
        try await render(state("hub"))
        for selector in ["#hubInput", "#hubRemember", ".toggle", "#website"] {
            #expect(try await sent(by: down(selector)).isEmpty, "\(selector)")
        }
        try await render(state("ready"))
        #expect(try await sent(by: down(".screen.on summary")).isEmpty)
    }

    // MARK: Download

    @Test func theReadyStepsFollowThePhase() async throws {
        let rows: [(String, Int, [String], String)] = [
            ("downloading", 42, ["now", "", ""], "42%"),
            ("settingUp", 90, ["done", "now", ""], ""),
            ("checking", 95, ["done", "done", "now"], ""),
            ("ready", 100, ["done", "done", "done"], ""),
        ]
        for (phase, percent, steps, amount) in rows {
            try await render(state("ready") { $0.download = .init(phase: phase, percent: percent, log: []) })
            #expect(try await string("[...document.querySelectorAll('#steps li')].map(l => l.className).join(',')") == steps.joined(separator: ","), "\(phase)")
            #expect(try await string("document.getElementById('amount').textContent") == amount, "\(phase)")
        }
        #expect(try await bool("document.getElementById('readyVault').classList.contains('open')") == true)
        #expect(try await string("document.getElementById('readyTitle').textContent") == "Ready!")
    }

    @Test func thePillShowsTheBackgroundDownload() async throws {
        try await render(state("welcome"))
        #expect(try await bool("document.getElementById('pill').classList.contains('hide')") == true)
        try await render(state("welcome") { $0.download = .init(phase: "failed", percent: 30, log: []) })
        #expect(try await bool("document.getElementById('pill').classList.contains('hide')") == false)
        #expect(try await string("document.getElementById('pillText').textContent") == "Couldn’t get AgentIO. It will try again when you continue.")
        #expect(try await bool("document.getElementById('pill').classList.contains('failed')") == true)
        try await render(state("local") { $0.download = .init(phase: "ready", percent: 100, log: []) })
        #expect(try await string("document.getElementById('pillText').textContent") == "AgentIO is ready")
        try await render(state("hub") { $0.download = .init(phase: "settingUp", percent: 90, log: []) })
        #expect(try await string("document.getElementById('pillText').textContent") == "Getting AgentIO ready… 90%")
        try await render(state("ready") { $0.download = .init(phase: "settingUp", percent: 90, log: []) })
        #expect(try await bool("document.getElementById('pill').classList.contains('hide')") == true)
    }

    // MARK: No network

    @Test func thePageLoadsNothingFromOutside() async throws {
        #expect(try await int("document.querySelectorAll('script[src], link, iframe, object, embed').length") == 0)
        #expect(try await int("document.querySelectorAll('img[src^=\"http\"]').length") == 0)
        #expect(try await string("document.querySelector('meta[http-equiv=\"Content-Security-Policy\"]').content")
            == "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:")
        #expect(try await int("[...document.querySelectorAll('[href], [src]')].filter(e => /^(https?:)?\\/\\//.test(e.getAttribute('href') || e.getAttribute('src'))).length") == 0)
    }
}
