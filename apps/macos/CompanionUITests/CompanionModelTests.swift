@testable import AgentioKit
import Foundation
import Testing
@testable import CompanionUI

@MainActor
struct CompanionModelTests {
    let backend = FakeBackend()
    let settings = CompanionSettings(defaults: UserDefaults(suiteName: "tests-\(UUID().uuidString)")!)
    let model: CompanionModel

    init() {
        model = CompanionModel(backend: backend, settings: settings, allowLocalHTTP: false,
                               deviceName: "AgentIO Companion on mac", openURL: { _ in })
    }

    // MARK: Adding a profile

    @Test func addProfileNeedsAnOpenRemoteVaultWhoseKeyMayManageProfiles() async {
        model.addProfile(service: "kite", displayName: "Kite")
        #expect(model.addFlow == nil)
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: false))
        await model.openRemoteVault()
        model.addProfile(service: "kite", displayName: "Kite")
        #expect(model.addFlow == nil)
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.switchVault()
        await model.openRemoteVault()
        model.addProfile(service: "kite", displayName: "Kite")
        #expect(model.addFlow?.service == "kite")
        // One at a time: a second call while the sheet is open is ignored.
        let first = model.addFlow
        model.addProfile(service: "gmail", displayName: "Gmail")
        #expect(model.addFlow === first)
    }

    @Test func anAddedProfileIsANoticeForThePage() async throws {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.addProfile(service: "kite", displayName: nil)
        #expect(model.addFlow?.displayName == "kite")
        await eventually { model.addFlow?.step == .form(SetupNeeds(inputs: [], auth: .browser)) }
        model.addFlow?.submit()
        try #require(backend.addRuns.first).finish(.success("pa@example.com"))
        await eventually { model.pageNotice?.profile == "pa@example.com" }
        #expect(model.pageNotice?.service == "kite")
    }

    @Test func switchingVaultCancelsAnAddAndClosesTheSheet() async throws {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.addProfile(service: "kite", displayName: "Kite")
        await eventually { model.addFlow?.step == .form(SetupNeeds(inputs: [], auth: .browser)) }
        model.addFlow?.submit()
        let run = try #require(backend.addRuns.first)
        await model.switchVault()
        #expect(run.cancelled)
        #expect(model.addFlow == nil)
        #expect(model.pageNotice == nil)
    }

    @Test func quittingDuringAnAddCancelsItAndClosesTheSheet() async throws {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.addProfile(service: "kite", displayName: "Kite")
        await eventually { model.addFlow?.step == .form(SetupNeeds(inputs: [], auth: .browser)) }
        model.addFlow?.submit()
        let run = try #require(backend.addRuns.first)
        await model.shutdown()
        #expect(run.cancelled)
        #expect(model.addFlow == nil)
    }

    @Test func closingTheSheetWhileItLoadsStopsTheDescribe() async throws {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        backend.describeGated = true
        await model.openRemoteVault()
        model.addProfile(service: "kite", displayName: "Kite")
        let flow = try #require(model.addFlow)
        #expect(flow.step == .loading)
        try await Task.sleep(for: .milliseconds(50)) // the describe is now waiting on the gate
        model.closeAddFlow()
        backend.describeGated = false
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.addFlow == nil)
        #expect(flow.step != .form(SetupNeeds(inputs: [], auth: .browser)))
        #expect(backend.startedAdds.isEmpty)
    }

    // MARK: Signing a profile in again

    @Test func reauthNeedsAnOpenRemoteVaultWhoseKeyMayManageProfiles() async {
        model.reauthProfile(service: "gmail", profile: "work")
        #expect(model.addFlow == nil)
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: false))
        await model.openRemoteVault()
        model.reauthProfile(service: "gmail", profile: "work")
        #expect(model.addFlow == nil)
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: nil))
        await model.switchVault()
        await model.openRemoteVault()
        model.reauthProfile(service: "gmail", profile: "work")
        #expect(model.addFlow == nil)
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.switchVault()
        await model.openRemoteVault()
        model.reauthProfile(service: "gmail", profile: "work")
        #expect(model.addFlow?.service == "gmail")
        #expect(model.addFlow?.purpose == .reauth(profile: "work"))
        #expect(model.addFlow?.step == .confirm)
        #expect(model.addFlow?.displayName == "gmail")
    }

    @Test func reauthNamesTheServiceAsThePageShowsIt() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.reauthProfile(service: "gmail", profile: "x", displayName: "Gmail")
        #expect(model.addFlow?.displayName == "Gmail")
    }

    @Test func reauthOnALocalVaultDoesNothing() async {
        await model.openLocalVault()
        #expect(model.screen == .vault)
        model.reauthProfile(service: "gmail", profile: "work")
        #expect(model.addFlow == nil)
    }

    @Test(arguments: ["", "-x", "--json", "a\nb", String(repeating: "a", count: 201)])
    func reauthRefusesANameThatIsNotOne(_ name: String) async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.reauthProfile(service: "gmail", profile: name)
        #expect(model.addFlow == nil)
    }

    @Test func oneSheetAtATimeAcrossAddAndReauth() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.addProfile(service: "kite", displayName: "Kite")
        let add = model.addFlow
        model.reauthProfile(service: "gmail", profile: "work")
        #expect(model.addFlow === add)
        model.closeAddFlow()
        model.reauthProfile(service: "gmail", profile: "work")
        let reauth = model.addFlow
        #expect(reauth?.purpose == .reauth(profile: "work"))
        model.addProfile(service: "kite", displayName: "Kite")
        model.reauthProfile(service: "gmail", profile: "other")
        #expect(model.addFlow === reauth)
    }

    @Test func aSignInAgainIsANoticeForThePage() async throws {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.reauthProfile(service: "gmail", profile: "work")
        model.addFlow?.submit()
        #expect(backend.startedReauths == ["gmail|work"])
        try #require(backend.addRuns.first).finish(.success("work"))
        await eventually { model.pageNotice?.profile == "work" }
        #expect(model.pageNotice?.service == "gmail")
    }

    @Test func switchingVaultCancelsASignInAgain() async throws {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: true))
        await model.openRemoteVault()
        model.reauthProfile(service: "gmail", profile: "work")
        model.addFlow?.submit()
        let run = try #require(backend.addRuns.first)
        await model.switchVault()
        #expect(run.cancelled)
        #expect(model.addFlow == nil)
        #expect(model.pageNotice == nil)
    }

    // MARK: CLI

    @Test func aFreshAppShowsTheChoiceAndStartsTheDownload() async {
        backend.detected = nil
        await model.start()
        #expect(model.screen == .mode)
        #expect(model.vault == VaultState.none)
        await eventually { model.download.phase == .ready }
        #expect(backend.installs == [minimumCliVersion])
    }

    @Test(arguments: ["3.12.2", "4.0.0"])
    func aCliAtOrAboveTheMinimumIsNotDownloadedAtLaunch(version: String) async {
        backend.detected = CliInfo(path: URL(filePath: "/x"), version: version)
        await model.start()
        #expect(backend.installs.isEmpty)
        #expect(model.download.phase == .idle)
    }

    @Test(arguments: ["3.2.2", "3.3.0-beta.1", "garbage"])
    func aCliBelowTheMinimumOrUnreadableIsReplacedAtLaunch(version: String) async {
        backend.detected = CliInfo(path: URL(filePath: "/x"), version: version)
        await model.start()
        await eventually { model.download.phase == .ready }
        #expect(backend.installs == [minimumCliVersion])
    }

    @Test func progressFillsTheThreeStepsInOrder() async {
        backend.detected = nil
        backend.installEvents = (0..<200).map { .percent(Double($0) / 2) } + [.percent(100), .label("Installing"), .checking]
        await model.start()
        await eventually { model.download.phase == .ready }
        #expect(model.download.percent == 100)
        #expect(model.download.log.last == "agentio 3.14.0 is ready")
        #expect(model.download.log.contains("Installing"))
    }

    @Test(arguments: [(-10.0, 0), (0, 0), (42.5, 38), (99.9, 90), (250, 90)])
    func downloadPercentFillsZeroToNinety(percent: Double, shown: Int) async {
        backend.detected = nil
        backend.installEvents = [.percent(percent)]
        backend.installResult = .failure(AgentioError("stop here"))
        await model.start()
        await eventually { model.download.phase == .failed }
        #expect(model.download.percent == shown)
    }

    @Test func theLogKeepsTheLastFiftyLines() async {
        backend.detected = nil
        backend.installEvents = (1...80).map { .label("line \($0)") }
        await model.start()
        await eventually { model.download.phase == .ready }
        #expect(model.download.log.count == 50)
        #expect(model.download.log.first == "line 32")
    }

    @Test func choosingKeepItOnThisMacNeedsNoCliYet() async {
        backend.detected = nil
        backend.installGate = true            // hold the launch download open
        await model.start()
        model.goLocal()
        #expect(model.screen == .local)
        await eventually { backend.installs.count == 1 }  // the launch download only
        backend.openInstallGate()
    }

    @Test func creatingAVaultWaitsForTheRunningDownloadInsteadOfStartingAnother() async {
        backend.detected = nil
        backend.installGate = true
        await model.start()
        model.goLocal()
        let create = Task { await model.createLocalVault(passphrase: "correct horse", again: "correct horse") }
        await eventually { model.screen == .installing }
        backend.detected = installed           // what the finished install leaves behind
        backend.openInstallGate()
        await create.value
        #expect(backend.installs.count == 1)
        #expect(backend.passphrases == ["correct horse"])
    }

    @Test func aFailedDownloadStaysOnItsScreenAndTryAgainGoesBack() async {
        backend.detected = nil
        backend.installResult = .failure(AgentioError("The installer exited with code 1: no network"))
        await model.start()
        await eventually { model.download.phase == .failed }
        model.goLocal()
        await model.createLocalVault(passphrase: "correct horse", again: "correct horse")
        #expect(backend.installs.count == 2)  // a new install, not the old failure awaited again
        #expect(model.screen == .installing)
        #expect(model.download.phase == .failed)
        #expect(model.error == "The installer exited with code 1: no network")
        #expect(backend.passphrases.isEmpty)
        backend.installResult = .success(installed)
        model.retryDownload()
        #expect(model.screen == .local)
        #expect(model.error == nil)
        await eventually { model.download.phase == .ready }
    }

    @Test func retryDoesNothingUnlessTheDownloadFailed() async {
        backend.detected = nil
        backend.installGate = true
        backend.installEvents = [.label("working")]
        await model.start()
        await eventually { model.download.log == ["working"] }
        model.retryDownload()
        #expect(model.download.log == ["working"])
        #expect(model.download.phase == .downloading)
        #expect(backend.installs.count == 1)
        backend.openInstallGate()
        await eventually { model.download.phase == .ready }
    }

    @Test func startingTwiceWhileTheDownloadRunsInstallsOnce() async {
        backend.detected = nil
        backend.installGate = true
        await model.start()
        await eventually { backend.installs.count == 1 }
        await model.start()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(backend.installs.count == 1)
        backend.openInstallGate()
        await eventually { model.download.phase == .ready }
    }

    @Test func aFailedSignInAgainDownloadTriesAgainOnTheHubAddress() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: false))
        await model.openRemoteVault()
        #expect(model.screen == .vault)
        backend.hubVersionResult = .success(CliVersion("3.20.0")!)
        backend.installResult = .failure(AgentioError("no network"))
        await model.signInAgain()
        #expect(model.screen == .installing)
        #expect(model.download.phase == .failed)
        backend.installResult = .success(CliInfo(path: URL(filePath: "/app/bin/agentio"), version: "3.20.0"))
        model.retryDownload()
        #expect(model.screen == .hubURL)
        await eventually { model.download.phase == .ready }
    }

    @Test func aHubNeedingANewerCliThanTheLaunchDownloadGetsOneMoreInstall() async {
        backend.detected = nil
        await model.start()
        await eventually { model.download.phase == .ready }
        backend.detected = CliInfo(path: URL(filePath: "/x"), version: "3.14.0")
        backend.hubVersionResult = .success(CliVersion("3.20.0")!)
        backend.installResult = .failure(AgentioError("The latest agentio release is 3.17.0, but this vault needs 3.20.0 or later"))
        model.goRemote()
        await model.signIn(url: "https://h.example", remember: false)
        #expect(backend.installs == [minimumCliVersion, CliVersion("3.20.0")!])
        #expect(model.screen == .installing)
        #expect(model.download.phase == .failed)
    }

    @Test func unreadableVaultStateShowsTheChoiceAndTheError() async {
        backend.vaultStateResult = .failure(AgentioError("agentio status did not print JSON"))
        await model.enterMode()
        #expect(model.screen == .mode)
        #expect(model.vault == VaultState.none)
        #expect(model.error == "agentio status did not print JSON")
    }

    // MARK: Remote vault

    @Test func invalidHubURLNeverStartsASignIn() async {
        model.goRemote()
        await model.signIn(url: "http://vault.example.com", remember: true)
        #expect(model.screen == .hubURL)
        #expect(model.error == "Vault URL must be HTTPS (http://localhost allowed in dev)")
        #expect(backend.hubChecks.isEmpty)
        #expect(backend.logins.isEmpty)
    }

    @Test func signInBringsTheCliUpToTheHubFirst() async {
        backend.hubVersionResult = .success(CliVersion("3.15.0")!)
        backend.installResult = .success(CliInfo(path: URL(filePath: "/app/bin/agentio"), version: "3.15.1"))
        model.goRemote()
        let signIn = Task { await model.signIn(url: "https://h.example", remember: false) }
        await eventually { backend.logins.count == 1 }
        #expect(backend.hubChecks == ["https://h.example"])
        #expect(backend.installs == [CliVersion("3.15.0")!])
        #expect(model.screen == .login)
        #expect(model.busy == nil)
        model.cancelLogin()
        await signIn.value
    }

    @Test(arguments: ["3.13.1", "3.0.0", "3.14.0-beta.1"])
    func aHubTooOldForScopedSignInIsRefusedBeforeAnything(version: String) async {
        backend.hubVersionResult = .success(CliVersion(version)!)
        backend.detected = CliInfo(path: URL(filePath: "/x"), version: "3.2.2")
        model.goRemote()
        await model.signIn(url: "https://h.example", remember: false)
        #expect(model.screen == .hubURL)
        #expect(model.error == "The vault hub at https://h.example runs agentio \(version). Signing in from this app needs agentio 3.14.0 or later on the hub.")
        #expect(backend.installs.isEmpty)
        #expect(backend.logins.isEmpty)
        #expect(model.busy == nil)
    }

    @Test func aHubThatCannotBeCheckedIsNeitherInstalledForNorSignedInTo() async {
        backend.hubVersionResult = .failure(AgentioError("The vault hub at https://h.example does not report its version. Update it to the latest agentio."))
        model.goRemote()
        await model.signIn(url: "https://h.example", remember: true)
        #expect(model.screen == .hubURL)
        #expect(model.error == "The vault hub at https://h.example does not report its version. Update it to the latest agentio.")
        #expect(model.busy == nil)
        #expect(backend.installs.isEmpty)
        #expect(backend.logins.isEmpty)
    }

    @Test func signInShowsTheCodeThenTheHubPage() async {
        backend.loginCode = code
        model.goRemote()
        let signIn = Task { await model.signIn(url: "https://H.example/ui/", remember: false) }
        await eventually { model.loginCode == code }
        #expect(model.screen == .login)
        #expect(backend.logins == ["https://h.example|AgentIO Companion on mac"])
        model.openApproval()
        #expect(model.screen == .approving)
        #expect(model.vaultPage == code.verifyURL)
        backend.finishLogin(.success(()))
        await signIn.value
        #expect(model.screen == .done)
        #expect(model.finished == .signedIn(hub: "https://h.example"))
        #expect(model.vaultPage == nil)
        model.openVault()
        #expect(model.screen == .vault)
        #expect(model.finished == nil)
        #expect(model.vaultPage == URL(string: "https://h.example/ui"))
        #expect(model.loginCode == nil)
        #expect(model.rememberURL == false)
        #expect(model.windowTitle == "AgentIO Companion — h.example")
    }

    @Test func signInAgainFromTheHubPageSkipsTheCelebration() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: false))
        await model.openRemoteVault()
        backend.loginCode = code
        let again = Task { await model.signInAgain() }
        await eventually { model.loginCode == code }
        backend.finishLogin(.success(()))
        await again.value
        #expect(model.screen == .vault)
        #expect(model.finished == nil)
    }

    @Test func openVaultDoesNothingOutsideTheDoneScreen() async {
        model.openVault()
        #expect(model.vaultPage == nil)
        #expect(model.screen == .mode)
    }

    @Test func copyingTheLinkCopiesTheApprovalAddressAndResetsWithANewCode() async {
        var copied: [String] = []
        let model = CompanionModel(backend: backend, settings: settings, allowLocalHTTP: false, deviceName: "d",
                                   openURL: { _ in }, copy: { copied.append($0) })
        model.copyApprovalLink()
        #expect(copied.isEmpty)            // no code yet
        backend.loginCode = code
        model.goRemote()
        let signIn = Task { await model.signIn(url: "https://h.example", remember: false) }
        await eventually { model.loginCode == code }
        model.copyApprovalLink()
        #expect(copied == [code.verifyURL.absoluteString])
        #expect(model.copiedLink)
        model.cancelLogin()
        await signIn.value
        #expect(!model.copiedLink)
    }

    @Test func reopeningAnExistingLocalVaultSkipsTheCelebration() async {
        backend.vaultStateResult = .success(.local)
        await model.start()
        await model.openLocalVault()
        #expect(model.screen == .vault)
        #expect(model.finished == nil)
    }

    @Test func openingTheWebsiteOpensAgentioCom() {
        var opened: [URL] = []
        let model = CompanionModel(backend: backend, settings: settings, allowLocalHTTP: false, deviceName: "d",
                                   openURL: { opened.append($0) })
        model.openWebsite()
        #expect(opened == [URL(string: "https://agentio.com")!])
    }

    @Test func rememberedHubURLIsSavedOnlyWhenAsked() async {
        let signIn = Task { await model.signIn(url: "https://H.example/ui", remember: true) }
        await eventually { backend.logins.count == 1 }
        #expect(settings.rememberedHubURL == "https://h.example")
        model.cancelLogin()
        await signIn.value
        let forget = Task { await model.signIn(url: "https://other.example", remember: false) }
        await eventually { backend.logins.count == 2 }
        #expect(settings.rememberedHubURL == nil)
        model.cancelLogin()
        await forget.value
    }

    @Test func aRememberedHubURLIsPrefilledOnLaunch() {
        settings.rememberedHubURL = "https://h.example"
        let relaunched = CompanionModel(backend: backend, settings: settings, allowLocalHTTP: false, deviceName: "d")
        #expect(relaunched.hubURL == "https://h.example")
    }

    @Test func anInvalidURLIsNotRemembered() async {
        settings.rememberedHubURL = "https://h.example"
        await model.signIn(url: "not a url", remember: true)
        #expect(settings.rememberedHubURL == "https://h.example")
    }

    @Test func failedSignInDropsTheApprovalPageAndGoesBackToTheURL() async {
        backend.loginCode = code
        let signIn = Task { await model.signIn(url: "https://h.example", remember: true) }
        await eventually { model.loginCode != nil }
        model.openApproval()
        backend.finishLogin(.failure(AgentioError("The code expired", code: "CODE_EXPIRED")))
        await signIn.value
        #expect(model.screen == .hubURL)
        #expect(model.vaultPage == nil)
        #expect(model.error == "The code expired")
    }

    @Test func cancellingFromTheApprovalPageGoesBackToTheURL() async {
        backend.loginCode = code
        let signIn = Task { await model.signIn(url: "https://h.example", remember: true) }
        await eventually { model.loginCode != nil }
        model.openApproval()
        model.cancelLogin()
        await signIn.value
        #expect(model.screen == .hubURL)
        #expect(model.vaultPage == nil)
        #expect(model.error == "Sign-in was cancelled")
    }

    @Test func approvalWithoutACodeIsRefused() async {
        let signIn = Task { await model.signIn(url: "https://h.example", remember: true) }
        await eventually { backend.logins.count == 1 }
        model.openApproval()
        #expect(model.vaultPage == nil)
        #expect(model.error == "There is no sign-in code to approve")
        model.cancelLogin()
        await signIn.value
    }

    @Test func aReplacedSignInChangesNothingWhenItEnds() async {
        let first = Task { await model.signIn(url: "https://old.example", remember: true) }
        await eventually { backend.logins.count == 1 }
        backend.loginCode = code
        let second = Task { await model.signIn(url: "https://h.example", remember: true) }
        await first.value
        await eventually { model.loginCode == code }
        #expect(model.screen == .login)
        #expect(model.error == nil)
        backend.finishLogin(.success(()))
        await second.value
        #expect(model.finished == .signedIn(hub: "https://h.example"))
        model.openVault()
        #expect(model.vaultPage == URL(string: "https://h.example/ui"))
    }

    @Test func openRemoteVaultNeedsARemoteSignIn() async {
        backend.vaultStateResult = .success(.local)
        await model.openRemoteVault()
        #expect(model.vaultPage == nil)
        #expect(model.error == "This app is not signed in to a vault hub")
        #expect(backend.hubChecks.isEmpty)
        backend.vaultStateResult = .success(.remote(hub: "https://h.example"))
        await model.openRemoteVault()
        #expect(model.vaultPage == URL(string: "https://h.example/ui"))
        #expect(model.error == nil)
    }

    @Test func reopeningAnUpdatedHubUpdatesTheCliFirst() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example"))
        backend.hubVersionResult = .success(CliVersion("3.15.0")!)
        backend.installResult = .success(CliInfo(path: URL(filePath: "/app/bin/agentio"), version: "3.15.0"))
        await model.enterMode()
        await model.openRemoteVault()
        #expect(backend.installs == [CliVersion("3.15.0")!])
        #expect(model.vaultPage == URL(string: "https://h.example/ui"))
        #expect(model.busy == nil)
    }

    @Test func anOlderReachableHubStillOpensAnExistingSignIn() async {
        // Only a new sign-in needs 3.14.0: a key the app already holds keeps working.
        backend.vaultStateResult = .success(.remote(hub: "https://h.example"))
        backend.hubVersionResult = .success(CliVersion("3.13.1")!)
        await model.openRemoteVault()
        #expect(model.vaultPage == URL(string: "https://h.example/ui"))
        #expect(model.error == nil)
    }

    @Test(arguments: [Optional(true), false, nil])
    func theVaultCarriesTheKeysManagingRight(right: Bool?) async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: right))
        await model.openRemoteVault()
        #expect(model.canManageProfiles == right)
    }

    @Test func aNewSignInTakesTheRightTheHubGave() async {
        backend.loginRight = false
        let signIn = Task { await model.signIn(url: "https://h.example", remember: false) }
        await eventually { backend.logins.count == 1 }
        backend.finishLogin(.success(()))
        await signIn.value
        #expect(model.screen == .done)
        #expect(model.canManageProfiles == false)
    }

    @Test func aLocalVaultHasNoManagingRightToShow() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: false))
        await model.openRemoteVault()
        await model.switchVault()
        await model.openLocalVault()
        #expect(model.vaultPage == URL(string: "http://127.0.0.1:63168/ui"))
        #expect(model.canManageProfiles == nil)
    }

    @Test(arguments: [true, false])
    func signInAgainLeavesThePageAndSignsInToTheSameHub(remembered: Bool) async {
        settings.rememberedHubURL = remembered ? "https://h.example" : nil
        backend.vaultStateResult = .success(.remote(hub: "https://h.example", canManageProfiles: false))
        backend.loginCode = code
        await model.openRemoteVault()
        let again = Task { await model.signInAgain() }
        await eventually { model.loginCode == code }
        #expect(model.vaultPage == nil)
        #expect(model.screen == .login)
        #expect(backend.logins == ["https://h.example|AgentIO Companion on mac"])
        // The remembered URL is left as it was.
        #expect(settings.rememberedHubURL == (remembered ? "https://h.example" : nil))
        backend.finishLogin(.success(()))
        await again.value
        #expect(model.screen == .vault)
        #expect(model.vaultPage == URL(string: "https://h.example/ui"))
        #expect(model.canManageProfiles == true)
    }

    @Test func signInAgainWithoutAnOpenRemoteVaultDoesNothing() async {
        await model.signInAgain()
        #expect(backend.logins.isEmpty)
        #expect(backend.hubChecks.isEmpty)
        await model.openLocalVault()
        await model.signInAgain()
        #expect(backend.logins.isEmpty)
        #expect(model.vaultPage == URL(string: "http://127.0.0.1:63168/ui"))
    }

    @Test func anUnreachableHubKeepsTheVaultClosed() async {
        backend.vaultStateResult = .success(.remote(hub: "https://h.example"))
        backend.hubVersionResult = .failure(AgentioError("Cannot reach the vault hub at https://h.example: offline"))
        await model.enterMode()
        await model.openRemoteVault()
        #expect(model.screen == .mode)
        #expect(model.vaultPage == nil)
        #expect(model.busy == nil)
        #expect(model.error == "Cannot reach the vault hub at https://h.example: offline")
    }

    // MARK: Hub check

    @Test func blankIsIdleAndNoNetwork() async {
        await model.checkHub("   ")
        #expect(model.hubCheck == .idle)
        #expect(backend.hubChecks.isEmpty)
    }

    @Test(arguments: ["ftp://h.example", "https://", "http://h.example"])
    func anAddressTheAppRefusesIsInvalidAndNeverFetched(raw: String) async {
        await model.checkHub(raw)
        #expect(model.hubCheck == .invalid)
        #expect(backend.hubChecks.isEmpty)
    }

    @Test func aHubIsFoundByItsNormalisedAddress() async {
        backend.hubVersionResult = .success(CliVersion("3.17.0")!)
        await model.checkHub("H.example/ui/")
        #expect(model.hubCheck == .found(hub: "https://h.example", version: "3.17.0"))
    }

    @Test func anOldHubIsTooOld() async {
        backend.hubVersionResult = .success(CliVersion("3.13.9")!)
        await model.checkHub("h.example")
        #expect(model.hubCheck == .tooOld(hub: "https://h.example", version: "3.13.9"))
    }

    @Test func noAnswerIsUnreachable() async {
        backend.hubVersionResult = .failure(AgentioError("offline"))
        await model.checkHub("h.example")
        #expect(model.hubCheck == .unreachable(hub: "https://h.example"))
    }

    @Test func theLastAddressTypedWinsEvenWhenAnOlderAnswerArrivesLast() async {
        backend.hubVersionGates = ["https://a.example"]
        let a = Task { await model.checkHub("a.example") }
        await eventually { model.hubCheck == .checking(hub: "https://a.example") }
        await model.checkHub("b.example")
        #expect(model.hubCheck == .found(hub: "https://b.example", version: "3.14.0"))
        backend.openHubVersionGate("https://a.example")
        await a.value
        #expect(model.hubCheck == .found(hub: "https://b.example", version: "3.14.0"))
    }

    @Test func clearingTheFieldWhileACheckRunsLeavesItIdle() async {
        backend.hubVersionGates = ["https://a.example"]
        let a = Task { await model.checkHub("a.example") }
        await eventually { model.hubCheck == .checking(hub: "https://a.example") }
        await model.checkHub("")
        backend.openHubVersionGate("https://a.example")
        await a.value
        #expect(model.hubCheck == .idle)
    }

    @Test func anInvalidAddressWhileACheckRunsIsNotOverwrittenByTheOldAnswer() async {
        backend.hubVersionGates = ["https://a.example"]
        let a = Task { await model.checkHub("a.example") }
        await eventually { model.hubCheck == .checking(hub: "https://a.example") }
        await model.checkHub("ftp://a.example")
        backend.openHubVersionGate("https://a.example")
        await a.value
        #expect(model.hubCheck == .invalid)
    }

    @Test func goingToTheHubScreenForgetsAnOldCheck() async {
        await model.checkHub("h.example")
        model.goRemote()
        #expect(model.hubCheck == .idle)
    }

    @Test func aCheckStillRunningWhenTheHubScreenOpensChangesNothing() async {
        backend.hubVersionGates = ["https://a.example"]
        let a = Task { await model.checkHub("a.example") }
        await eventually { model.hubCheck == .checking(hub: "https://a.example") }
        model.goRemote()
        backend.openHubVersionGate("https://a.example")
        await a.value
        #expect(model.hubCheck == .idle)
    }

    // MARK: Local vault

    @Test(arguments: [("1234567", "1234567", "The passphrase needs at least 8 characters"),
                      ("12345678", "12345679", "The two passphrases are different"),
                      ("", "", "The passphrase needs at least 8 characters")])
    func badPassphrasesNeverReachTheCli(passphrase: String, again: String, message: String) async {
        model.goLocal()
        await model.createLocalVault(passphrase: passphrase, again: again)
        #expect(model.error == message)
        #expect(backend.passphrases.isEmpty)
        #expect(model.screen == .local)
    }

    @Test func createLocalVaultStartsTheDaemonAndShowsItsPage() async {
        model.goLocal()
        await model.createLocalVault(passphrase: "correct horse", again: "correct horse")
        #expect(backend.passphrases == ["correct horse"])
        #expect(backend.daemons.count == 1)
        #expect(model.screen == .done)
        #expect(model.finished == .createdLocal)
        #expect(model.vaultPage == nil)
        model.openVault()
        #expect(model.vaultPage == URL(string: "http://127.0.0.1:63168/ui"))
        #expect(model.screen == .vault)
        #expect(model.busy == nil)
    }

    @Test func failedVaultCreationStartsNoDaemon() async {
        backend.initVaultResult = .failure(AgentioError("A vault already exists", code: "VAULT_EXISTS"))
        model.goLocal()
        await model.createLocalVault(passphrase: "correct horse", again: "correct horse")
        #expect(model.error == "A vault already exists")
        #expect(model.busy == nil)
        #expect(backend.daemons.isEmpty)
        #expect(model.screen == .local)
    }

    @Test func reopeningTheLocalVaultReusesTheRunningDaemon() async {
        await model.openLocalVault()
        await model.switchVault()
        #expect(model.vaultPage == nil)
        #expect(model.screen == .mode)
        await model.openLocalVault()
        #expect(backend.daemons.count == 1)
    }

    @Test func aDaemonThatExitedIsStartedAgain() async throws {
        await model.openLocalVault()
        backend.daemons[0].crash()
        // The exit is noticed asynchronously; reopen until a new one starts.
        for _ in 0..<100 where backend.daemons.count < 2 {
            await model.switchVault()
            await model.openLocalVault()
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(backend.daemons.count == 2)
    }

    @Test func daemonStartFailureIsShownAndNothingOpens() async {
        backend.daemonError = AgentioError("The agentio daemon did not start in time")
        await model.enterMode()
        await model.openLocalVault()
        #expect(model.vaultPage == nil)
        #expect(model.busy == nil)
        #expect(model.error == "The agentio daemon did not start in time")
    }

    @Test func aLocalVaultThatNeededTheDownloadReturnsToItsScreenWhenTheDaemonFails() async {
        backend.vaultStateResult = .success(.local)
        await model.start()
        backend.detected = nil
        backend.daemonError = AgentioError("The agentio daemon did not start in time")
        await model.openLocalVault()
        #expect(backend.installs.count == 1)
        #expect(model.screen == .mode)
        #expect(model.error == "The agentio daemon did not start in time")
        #expect(model.busy == nil)
    }

    @Test func aCliThatIsStillTooOldAfterTheInstallFailsTheDownloadOnce() async {
        backend.detected = CliInfo(path: URL(filePath: "/app/bin/agentio"), version: "3.14.0")
        backend.hubVersionResult = .success(CliVersion("3.20.0")!)
        await model.signIn(url: "https://h.example", remember: false)
        #expect(backend.installs.count == 1)  // it started the install itself: no second one at the same minimum
        #expect(model.download.phase == .failed)
        #expect(model.screen == .installing)
        #expect(model.error == "agentio 3.20.0 or later could not be installed")
    }

    @Test func aDownloadAHigherStepWaitedForIsInstalledOnceMoreWhenItAimedTooLow() async {
        backend.detected = nil
        backend.installGate = true
        await model.start()
        backend.hubVersionResult = .success(CliVersion("3.20.0")!)
        let signIn = Task { await model.signIn(url: "https://h.example", remember: false) }
        await eventually { model.screen == .installing }
        backend.openInstallGate()
        await eventually { backend.installs.count == 2 }
        #expect(backend.installs.last == CliVersion("3.20.0")!)
        signIn.cancel()
        await model.shutdown()
    }

    @Test func quittingDuringTheDownloadCancelsIt() async {
        backend.detected = nil
        backend.installGate = true
        await model.start()
        await eventually { backend.installs.count == 1 }
        #expect(model.download.phase == .downloading)
        await model.shutdown()
        await eventually { model.download.phase == .failed }  // the gated fake install stops only when cancelled
        backend.openInstallGate()
    }

    // MARK: Quitting

    @Test func shutdownStopsTheDaemonAndAbandonsTheSignIn() async {
        await model.openLocalVault()
        await model.switchVault()
        let signIn = Task { await model.signIn(url: "https://h.example", remember: true) }
        await eventually { backend.logins.count == 1 }
        await model.shutdown()
        await signIn.value
        #expect(backend.daemons[0].stopped)
        // The abandoned sign-in does not move the screen or show an error.
        #expect(model.screen == .login)
        #expect(model.error == nil)
    }
}
