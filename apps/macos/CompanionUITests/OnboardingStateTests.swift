@testable import AgentioKit
import Foundation
import Testing
@testable import CompanionUI

@MainActor
struct OnboardingStateTests {
    let backend = FakeBackend()
    let settings = CompanionSettings(defaults: UserDefaults(suiteName: "tests-\(UUID().uuidString)")!)
    let model: CompanionModel

    init() {
        model = CompanionModel(backend: backend, settings: settings, allowLocalHTTP: false,
                               deviceName: "AgentIO Companion on mac", openURL: { _ in }, copy: { _ in })
    }

    private var screen: String { onboardingState(of: model).screen }

    /// Sign in to h.example until the code shows (the sign-in is left running).
    private func signInUntilCode() async -> Task<Void, Never> {
        backend.loginCode = code
        let task = Task { await model.signIn(url: "h.example", remember: true) }
        await eventually { model.loginCode != nil }
        return task
    }

    // MARK: Screens

    @Test func theScreenWaitsWhileTheVaultIsRead() {
        #expect(screen == "loading")
    }

    @Test func aFreshAppShowsWelcome() async {
        await model.start()
        let state = onboardingState(of: model)
        #expect(state.screen == "welcome")
        #expect(state.vault == nil)
        #expect(state.busy == nil)
        #expect(state.error == nil)
    }

    @Test func anExistingRemoteVaultShowsBackWithItsHostOnly() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.start()
        let state = onboardingState(of: model)
        #expect(state.screen == "back")
        #expect(state.vault == .init(kind: "remote", hub: "h.example"))
    }

    @Test func anExistingLocalVaultShowsBack() async {
        backend.vaultStateResult = .success(.local)
        await model.start()
        let state = onboardingState(of: model)
        #expect(state.screen == "back")
        #expect(state.vault == .init(kind: "local", hub: nil))
    }

    @Test func theHubAndLocalScreens() async {
        await model.start()
        model.goRemote()
        #expect(screen == "hub")
        model.goLocal()
        #expect(screen == "local")
    }

    @Test func aRunningDownloadThatAButtonWaitsForShowsReady() async {
        backend.detected = nil
        backend.installGate = true
        backend.installEvents = [.percent(42)]
        await model.start()
        model.goLocal()
        let create = Task { await model.createLocalVault(passphrase: "correct horse", again: "correct horse") }
        await eventually { model.screen == .installing }
        let state = onboardingState(of: model)
        #expect(state.screen == "ready")
        #expect(state.download.phase == "downloading")
        #expect(state.download.percent == 42)
        backend.detected = installed
        backend.openInstallGate()
        await create.value
    }

    @Test func aFailedDownloadShowsFailedWithItsError() async {
        backend.detected = nil
        backend.installResult = .failure(AgentioError("no network"))
        await model.start()
        await eventually { model.download.phase == .failed }
        model.goLocal()
        await model.createLocalVault(passphrase: "correct horse", again: "correct horse")
        let state = onboardingState(of: model)
        #expect(state.screen == "failed")
        #expect(state.download.phase == "failed")
        #expect(state.error == "no network")
    }

    @Test func signingInShowsTheCodeThenApprovalThenAllSet() async {
        await model.start()
        model.goRemote()
        let sign = await signInUntilCode()
        let waiting = onboardingState(of: model)
        #expect(waiting.screen == "approve")
        #expect(waiting.code == "ABCD-1234")
        #expect(waiting.hubAddress == "h.example")
        #expect(waiting.rememberAddress)
        model.copyApprovalLink()
        #expect(onboardingState(of: model).copiedLink)
        model.openApproval()
        #expect(screen == "loading")  // the hub's own page is shown instead
        backend.finishLogin(.success(()))
        await sign.value
        let done = onboardingState(of: model)
        #expect(done.screen == "done")
        #expect(done.finished == .init(kind: "remote", hub: "h.example"))
        #expect(done.code == nil)
    }

    @Test func aNewLocalVaultEndsOnAllSetWithoutAHub() async {
        await model.start()
        model.goLocal()
        await model.createLocalVault(passphrase: "correct horse", again: "correct horse")
        let state = onboardingState(of: model)
        #expect(state.screen == "done")
        #expect(state.finished == .init(kind: "local", hub: nil))
    }

    @Test func theHubPageScreenIsLoading() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        #expect(model.screen == .vault)
        #expect(screen == "loading")
    }

    @Test func aBusyStepAndAnErrorAreShown() async {
        await model.start()
        model.goLocal()
        await model.createLocalVault(passphrase: "short", again: "short")
        #expect(onboardingState(of: model).error == "The passphrase needs at least 8 characters")
    }

    // MARK: Hub address and check

    @Test func theRememberedAddressDropsItsScheme() async {
        settings.rememberedHubURL = "https://h.example"
        let remembering = CompanionModel(backend: backend, settings: settings, allowLocalHTTP: false,
                                         deviceName: "d", openURL: { _ in })
        #expect(onboardingState(of: remembering).hubAddress == "h.example")
        #expect(onboardingState(of: model).hubAddress == "")
    }

    @Test func aFoundHubShowsWithoutItsScheme() async {
        await model.checkHub("h.example")
        let check = onboardingState(of: model).hubCheck
        #expect(check == .init(state: "found", hub: "h.example", version: "3.14.0"))
    }

    @Test func everyCheckCaseHasItsName() async {
        #expect(onboardingState(of: model).hubCheck == .init(state: "idle", hub: nil, version: nil))
        await model.checkHub("not a hub")
        #expect(onboardingState(of: model).hubCheck == .init(state: "invalid", hub: nil, version: nil))
        backend.hubVersionResult = .failure(AgentioError("down"))
        await model.checkHub("h.example")
        #expect(onboardingState(of: model).hubCheck == .init(state: "unreachable", hub: "h.example", version: nil))
        backend.hubVersionResult = .success(CliVersion("0.0.1")!)
        await model.checkHub("h.example")
        #expect(onboardingState(of: model).hubCheck == .init(state: "tooOld", hub: "h.example", version: "0.0.1"))
        backend.hubVersionResult = .success(CliVersion("3.14.0")!)
        backend.hubVersionGates = ["https://h.example"]
        let checking = Task { await model.checkHub("h.example") }
        await eventually { onboardingState(of: model).hubCheck.state == "checking" }
        #expect(onboardingState(of: model).hubCheck == .init(state: "checking", hub: "h.example", version: nil))
        backend.openHubVersionGate("https://h.example")
        await checking.value
    }

    // MARK: renderScript

    @Test func hostileTextStaysInertInTheScript() async throws {
        let hostile = "</script><img src=x onerror=alert(1)>\"\u{2028}"
        await model.start()
        model.goLocal()
        var state = onboardingState(of: model)
        state.error = hostile
        state.download.log = [hostile]
        let script = renderScript(state)
        let prefix = "window.agentioOnboarding && window.agentioOnboarding.render("
        #expect(script.hasPrefix(prefix))
        #expect(script.hasSuffix(");"))
        #expect(!script.contains("</script>"))
        let json = String(script.dropFirst(prefix.count).dropLast(2))
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(parsed["error"] as? String == hostile)
        #expect((parsed["download"] as? [String: Any])?["log"] as? [String] == [hostile])
        #expect(parsed["screen"] as? String == "local")
    }

    @Test func theStateKeysAreTheContract() async throws {
        await model.start()
        let script = renderScript(onboardingState(of: model))
        let json = String(script.dropFirst("window.agentioOnboarding && window.agentioOnboarding.render(".count).dropLast(2))
        let parsed = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(Set(parsed.keys).isSuperset(of: ["screen", "download", "hubAddress", "rememberAddress", "hubCheck", "copiedLink"]))
    }

    @Test func thePassphraseNeverReachesTheState() async {
        backend.detected = nil
        backend.installGate = true
        await model.start()
        model.goLocal()
        let secret = "correct-horse-battery"
        let create = Task { await model.createLocalVault(passphrase: secret, again: secret) }
        await eventually { model.screen == .installing }
        #expect(!renderScript(onboardingState(of: model)).contains(secret))
        backend.detected = installed
        backend.openInstallGate()
        await create.value
        #expect(!renderScript(onboardingState(of: model)).contains(secret))
        // A refused passphrase pair does not echo either value.
        model.goLocal()
        await model.createLocalVault(passphrase: secret, again: secret + "x")
        #expect(!renderScript(onboardingState(of: model)).contains(secret))
    }

    // MARK: Messages

    private func message(_ action: String, _ args: [Any] = []) -> [String: Any] { ["action": action, "args": args] }

    @Test func everyRowOfTheTableIsAccepted() {
        let none: [(String, OnboardingAction)] = [
            ("chooseHub", .chooseHub), ("chooseLocal", .chooseLocal), ("back", .back),
            ("cancelSignIn", .cancelSignIn), ("openApproval", .openApproval),
            ("copyApprovalLink", .copyApprovalLink), ("openVault", .openVault),
            ("openExistingVault", .openExistingVault), ("useAnotherVault", .useAnotherVault),
            ("retryDownload", .retryDownload), ("openWebsite", .openWebsite), ("dragWindow", .dragWindow),
        ]
        for (name, action) in none { #expect(OnboardingAction(message: message(name)) == action, "\(name)") }
        #expect(OnboardingAction(message: message("checkHub", ["h.example"])) == .checkHub("h.example"))
        #expect(OnboardingAction(message: message("checkHub", [""])) == .checkHub(""))
        #expect(OnboardingAction(message: message("signIn", ["h.example", true])) == .signIn(address: "h.example", remember: true))
        #expect(OnboardingAction(message: message("signIn", ["h.example", NSNumber(value: false)])) == .signIn(address: "h.example", remember: false))
        #expect(OnboardingAction(message: message("createVault", ["a", "b"])) == .createVault(passphrase: "a", again: "b"))
        #expect(OnboardingAction(message: message("createVault", ["", ""])) == .createVault(passphrase: "", again: ""))
    }

    @Test func malformedMessagesAreRefused() {
        #expect(OnboardingAction(message: ["action": "chooseHub"]) == nil)
        #expect(OnboardingAction(message: ["action": "chooseHub", "args": "none"]) == nil)
        #expect(OnboardingAction(message: ["action": "chooseHub", "args": [1]]) == nil)
        #expect(OnboardingAction(message: message("chooseHub", ["extra"])) == nil)
        #expect(OnboardingAction(message: message("checkHub")) == nil)
        #expect(OnboardingAction(message: message("checkHub", ["a", "b"])) == nil)
        #expect(OnboardingAction(message: message("checkHub", [1])) == nil)
        #expect(OnboardingAction(message: message("signIn", ["h.example", "true"])) == nil)
        #expect(OnboardingAction(message: message("signIn", ["h.example", NSNumber(value: 1)])) == nil)
        #expect(OnboardingAction(message: message("signIn", ["h.example", 0])) == nil)
        #expect(OnboardingAction(message: message("signIn", ["", true])) == nil)
        #expect(OnboardingAction(message: message("signIn", ["h.example"])) == nil)
        #expect(OnboardingAction(message: message("signIn", ["h.example", true, true])) == nil)
        #expect(OnboardingAction(message: message("createVault", ["a"])) == nil)
        #expect(OnboardingAction(message: message("createVault", ["a", 1])) == nil)
        #expect(OnboardingAction(message: message("createVault", ["a", "b", "c"])) == nil)
        #expect(OnboardingAction(message: message("launchMissiles")) == nil)
        #expect(OnboardingAction(message: message("ChooseHub")) == nil)
        #expect(OnboardingAction(message: message("")) == nil)
        #expect(OnboardingAction(message: ["action": 1, "args": []]) == nil)
        #expect(OnboardingAction(message: "chooseHub") == nil)
        #expect(OnboardingAction(message: ["chooseHub"]) == nil)
        #expect(OnboardingAction(message: ["action": "chooseHub", "args": [], "extra": 1]) == nil)
        #expect(OnboardingAction(message: ["method": "chooseHub", "args": []]) == nil)
    }

    // MARK: perform

    @Test func aStalePageCannotSkipSteps() async {
        await model.start()
        #expect(screen == "welcome")
        perform(.signIn(address: "h.example", remember: true), on: model, webView: nil)
        perform(.checkHub("h.example"), on: model, webView: nil)
        perform(.createVault(passphrase: "correct horse", again: "correct horse"), on: model, webView: nil)
        perform(.openVault, on: model, webView: nil)
        perform(.openApproval, on: model, webView: nil)
        perform(.copyApprovalLink, on: model, webView: nil)
        perform(.cancelSignIn, on: model, webView: nil)
        perform(.openExistingVault, on: model, webView: nil)
        perform(.useAnotherVault, on: model, webView: nil)
        perform(.retryDownload, on: model, webView: nil)
        perform(.back, on: model, webView: nil)
        await Task.yield()
        #expect(backend.logins.isEmpty)
        #expect(backend.hubChecks.isEmpty)
        #expect(backend.passphrases.isEmpty)
        #expect(backend.daemons.isEmpty)
        #expect(screen == "welcome")
    }

    @Test func openingAVaultFromWelcomeOpensNothing() async {
        await model.start()
        perform(.openVault, on: model, webView: nil)
        #expect(model.screen == .mode)
        #expect(model.vaultPage == nil)
    }

    @Test func theWelcomeButtonsMoveOn() async {
        await model.start()
        perform(.chooseHub, on: model, webView: nil)
        #expect(screen == "hub")
        perform(.chooseLocal, on: model, webView: nil)  // not on welcome any more
        #expect(screen == "hub")
        perform(.back, on: model, webView: nil)
        await eventually { screen == "welcome" }
        perform(.chooseLocal, on: model, webView: nil)
        #expect(screen == "local")
    }

    @Test func theHubScreenChecksAndSignsIn() async {
        await model.start()
        model.goRemote()
        perform(.checkHub("h.example"), on: model, webView: nil)
        await eventually { onboardingState(of: model).hubCheck.state == "found" }
        backend.loginCode = code
        perform(.signIn(address: "h.example", remember: false), on: model, webView: nil)
        await eventually { backend.logins.count == 1 }
        await eventually { screen == "approve" }
        perform(.cancelSignIn, on: model, webView: nil)
        await eventually { screen == "hub" || model.error != nil }
    }

    @Test func createVaultOnTheLocalScreenReachesTheBackend() async {
        await model.start()
        model.goLocal()
        perform(.createVault(passphrase: "correct horse", again: "correct horse"), on: model, webView: nil)
        await eventually { backend.passphrases == ["correct horse"] }
        await eventually { screen == "done" }
        perform(.openVault, on: model, webView: nil)
        #expect(model.screen == .vault)
    }

    @Test func openExistingVaultFollowsTheVaultKind() async {
        backend.vaultStateResult = .success(.local)
        await model.start()
        perform(.openExistingVault, on: model, webView: nil)
        await eventually { model.screen == .vault }
        #expect(backend.daemons.count == 1)
    }

    @Test func useAnotherVaultGoesToTheHubScreen() async {
        backend.vaultStateResult = .success(.local)
        await model.start()
        perform(.useAnotherVault, on: model, webView: nil)
        #expect(screen == "hub")
    }

    @Test func retryDownloadOnlyOnTheFailedScreen() async {
        backend.detected = nil
        backend.installResult = .failure(AgentioError("no network"))
        await model.start()
        await eventually { model.download.phase == .failed }
        model.goLocal()
        await model.createLocalVault(passphrase: "correct horse", again: "correct horse")
        #expect(screen == "failed")
        backend.installResult = .success(installed)
        perform(.retryDownload, on: model, webView: nil)
        #expect(screen == "local")
        await eventually { model.download.phase == .ready }
    }

    @Test func openWebsiteWorksOnAnyScreen() async {
        var opened: [URL] = []
        let m = CompanionModel(backend: backend, settings: settings, allowLocalHTTP: false,
                               deviceName: "d", openURL: { opened.append($0) }, copy: { _ in })
        #expect(onboardingState(of: m).screen == "loading")
        perform(.openWebsite, on: m, webView: nil)
        #expect(opened == [URL(string: "https://agentio.com")!])
        perform(.dragWindow, on: m, webView: nil)  // no web view: nothing happens
    }
}
