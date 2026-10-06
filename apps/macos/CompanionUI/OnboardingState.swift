import AgentioKit
import Foundation

/// What the onboarding page shows; pushed as JSON to window.agentioOnboarding.render.
struct OnboardingState: Encodable, Equatable {
    /// "loading" | "welcome" | "back" | "hub" | "local" | "ready" | "failed" | "approve" | "done"
    var screen: String
    /// For "back": the vault this app already uses.
    var vault: Vault?
    var download: Download
    /// The remembered hub address, to prefill the field (without "https://").
    var hubAddress: String
    var rememberAddress: Bool
    var hubCheck: Check
    /// The sign-in code, "WDJB-MJHT"; nil while the hub is asked for one.
    var code: String?
    var copiedLink: Bool
    var finished: Finished?
    /// The running step's message, shown on the main button; nil when idle.
    var busy: String?
    var error: String?

    struct Vault: Encodable, Equatable { var kind: String; var hub: String? }          // kind: "remote" | "local"
    struct Download: Encodable, Equatable { var phase: String; var percent: Int; var log: [String] }
    struct Check: Encodable, Equatable { var state: String; var hub: String?; var version: String? }
    struct Finished: Encodable, Equatable { var kind: String; var hub: String? }      // kind: "remote" | "local"
}

/// The bundled onboarding page.
let onboardingPageURL: URL = {
    final class Token {}
    guard let url = Bundle(for: Token.self).url(forResource: "onboarding", withExtension: "html") else {
        fatalError("onboarding.html is missing from CompanionUI's resources")
    }
    return url
}()

/// A hub address as the page shows it: without a leading "https://".
private func bareHub(_ hub: String) -> String {
    hub.hasPrefix("https://") ? String(hub.dropFirst("https://".count)) : hub
}

/// The page's state for `model`'s current screen and steps.
@MainActor func onboardingState(of model: CompanionModel) -> OnboardingState {
    let screen: String
    var vault: OnboardingState.Vault?
    switch model.screen {
    case .mode:
        switch model.vault {
        case nil: screen = "loading"
        case .some(.none): screen = "welcome"
        case .some(.remote(let hub, _)):
            screen = "back"
            vault = .init(kind: "remote", hub: bareHub(hub))
        case .some(.local):
            screen = "back"
            vault = .init(kind: "local", hub: nil)
        }
    case .hubURL: screen = "hub"
    case .local: screen = "local"
    case .installing: screen = model.download.phase == .failed ? "failed" : "ready"
    case .login: screen = "approve"
    case .done: screen = "done"
    case .approving, .vault: screen = "loading"
    }

    let check: OnboardingState.Check
    switch model.hubCheck {
    case .idle: check = .init(state: "idle", hub: nil, version: nil)
    case .checking(let hub): check = .init(state: "checking", hub: bareHub(hub), version: nil)
    case .found(let hub, let version): check = .init(state: "found", hub: bareHub(hub), version: version)
    case .invalid: check = .init(state: "invalid", hub: nil, version: nil)
    case .unreachable(let hub): check = .init(state: "unreachable", hub: bareHub(hub), version: nil)
    case .tooOld(let hub, let version): check = .init(state: "tooOld", hub: bareHub(hub), version: version)
    }

    let finished: OnboardingState.Finished?
    switch model.finished {
    case nil: finished = nil
    case .some(.signedIn(let hub)): finished = .init(kind: "remote", hub: bareHub(hub))
    case .some(.createdLocal): finished = .init(kind: "local", hub: nil)
    }

    return OnboardingState(
        screen: screen, vault: vault,
        download: .init(phase: model.download.phase.rawValue, percent: model.download.percent, log: model.download.log),
        hubAddress: bareHub(model.hubURL), rememberAddress: model.rememberURL, hubCheck: check,
        code: model.loginCode?.userCode, copiedLink: model.copiedLink, finished: finished,
        busy: model.busy, error: model.error)
}

/// The script that renders `state`: JSON, so any text in it is inert.
func renderScript(_ state: OnboardingState) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]  // slashes stay escaped: `</script>` cannot appear
    let data = (try? encoder.encode(state)) ?? Data("null".utf8)
    // U+2028 and U+2029 end a line in older JavaScript engines; spell them out.
    let json = String(decoding: data, as: UTF8.self)
        .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    return "window.agentioOnboarding && window.agentioOnboarding.render(\(json));"
}

/// A message from the onboarding page, `{ action, args }`, checked like BridgeCall.
enum OnboardingAction: Equatable {
    case chooseHub, chooseLocal, back
    case checkHub(String)
    case signIn(address: String, remember: Bool)
    case cancelSignIn, openApproval, copyApprovalLink
    case createVault(passphrase: String, again: String)
    case openVault, openExistingVault, useAnotherVault
    case retryDownload, openWebsite, dragWindow

    /// The message the page posts; nil for anything else.
    init?(message body: Any) {
        guard let message = body as? [String: Any], message.count == 2,
              let action = message["action"] as? String,
              let args = message["args"] as? [Any] else { return nil }
        switch (action, args.count) {
        case ("chooseHub", 0): self = .chooseHub
        case ("chooseLocal", 0): self = .chooseLocal
        case ("back", 0): self = .back
        case ("cancelSignIn", 0): self = .cancelSignIn
        case ("openApproval", 0): self = .openApproval
        case ("copyApprovalLink", 0): self = .copyApprovalLink
        case ("openVault", 0): self = .openVault
        case ("openExistingVault", 0): self = .openExistingVault
        case ("useAnotherVault", 0): self = .useAnotherVault
        case ("retryDownload", 0): self = .retryDownload
        case ("openWebsite", 0): self = .openWebsite
        case ("dragWindow", 0): self = .dragWindow
        case ("checkHub", 1):
            guard let address = args[0] as? String else { return nil }
            self = .checkHub(address)
        case ("signIn", 2):
            // A JSON `true` arrives as an NSNumber; `1` is one too, and is refused.
            guard let address = args[0] as? String, !address.isEmpty,
                  let flag = args[1] as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { return nil }
            self = .signIn(address: address, remember: flag.boolValue)
        case ("createVault", 2):
            guard let passphrase = args[0] as? String, let again = args[1] as? String else { return nil }
            self = .createVault(passphrase: passphrase, again: again)
        default: return nil
        }
    }

    /// The screens (see `OnboardingState.screen`) the action belongs to; nil for any.
    fileprivate var screens: Set<String>? {
        switch self {
        case .chooseHub, .chooseLocal: ["welcome"]
        case .checkHub, .signIn: ["hub"]
        case .cancelSignIn, .openApproval, .copyApprovalLink: ["approve"]
        case .createVault: ["local"]
        case .openVault: ["done"]
        case .openExistingVault, .useAnotherVault: ["back"]
        case .retryDownload: ["failed"]
        case .back: ["hub", "local", "failed"]
        case .openWebsite, .dragWindow: nil
        }
    }
}

extension OnboardingAction {
    /// Whether the action starts a step, which must not run twice or while another step runs.
    fileprivate var startsStep: Bool {
        switch self {
        case .chooseHub, .chooseLocal, .signIn, .createVault, .back, .openExistingVault, .useAnotherVault,
             .openVault, .retryDownload: true
        case .checkHub, .cancelSignIn, .openApproval, .copyApprovalLink, .openWebsite, .dragWindow: false
        }
    }

    /// Do what the page asked, on `model`; dragWindow moves `webView`'s window.
    /// An action that doesn't belong to the current screen does nothing, and a
    /// step-starting action does nothing while a step is running (`model.busy`).
    @MainActor func perform(on model: CompanionModel, webView: HubWebView?) {
        if let screens, !screens.contains(onboardingState(of: model).screen) { return }
        if startsStep, model.busy != nil { return }
        switch self {
        case .chooseHub, .useAnotherVault: model.goRemote()
        case .chooseLocal: model.goLocal()
        case .back: Task { await model.enterMode() }
        case .checkHub(let address): Task { await model.checkHub(address) }
        case .signIn(let address, let remember): Task { await model.signIn(url: address, remember: remember) }
        case .cancelSignIn: model.cancelLogin()
        case .openApproval: model.openApproval()
        case .copyApprovalLink: model.copyApprovalLink()
        case .createVault(let passphrase, let again):
            Task { await model.createLocalVault(passphrase: passphrase, again: again) }
        case .openVault: model.openVault()
        case .openExistingVault:
            switch model.vault {
            case .some(.remote): Task { await model.openRemoteVault() }
            case .some(.local): Task { await model.openLocalVault() }
            case .some(.none), nil: break
            }
        case .retryDownload: model.retryDownload()
        case .openWebsite: model.openWebsite()
        case .dragWindow: webView?.dragWindow()
        }
    }
}
