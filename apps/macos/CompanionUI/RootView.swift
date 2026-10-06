import SwiftUI

/// The app window: the app's own screens, or the hub's page up to the top
/// of the window, under the transparent title bar.
public struct RootView: View {
    let model: CompanionModel

    public init(model: CompanionModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let page = model.vaultPage {
                VStack(spacing: 0) {
                    VaultWebView(url: page, canManageProfiles: model.canManageProfiles, notice: model.pageNotice,
                                 onSignInAgain: { perform(model.signInAgain) },
                                 onAddProfile: { model.addProfile(service: $0, displayName: $1) },
                                 onReauth: { model.reauthProfile(service: $0, profile: $1 ?? "", displayName: $2) })
                        .id(model.canManageProfiles)
                        .ignoresSafeArea(edges: .top)
                    if let footer = model.footer { VaultFooter(footer: footer, model: model) }
                }
                .frame(minWidth: 1100, minHeight: 760)
                    .sheet(item: Binding(get: { model.addFlow }, set: { if $0 == nil { model.closeAddFlow() } })) { flow in
                        AddProfileSheet(flow: flow, close: model.closeAddFlow)
                    }
                    .sheet(item: Binding(get: { model.terminalFlow }, set: { if $0 == nil { model.closeTerminalFlow() } })) { flow in
                        TerminalSheet(flow: flow, close: model.closeTerminalFlow)
                    }
            } else {
                OnboardingWebView(state: onboardingState(of: model), model: model)
                    .ignoresSafeArea()
                    .frame(minWidth: 560, minHeight: 620)
            }
        }
        .background(Theme.bg, ignoresSafeAreaEdges: .all)
        .navigationTitle(model.windowTitle)
        .task { await model.start() }
    }
}

/// The Vault menu: the actions of the old bar above the hub's page.
public struct VaultCommands: Commands {
    let model: CompanionModel

    public init(model: CompanionModel) {
        self.model = model
    }

    public var body: some Commands {
        CommandMenu("Vault") {
            Button("Switch Vault…") { perform(model.switchVault) }
                .disabled(model.screen != .vault)
            Button("Cancel Sign-in") { model.cancelLogin() }
                .disabled(model.screen != .login && model.screen != .approving)
        }
    }
}

/// Run a model step from a button or menu item.
@MainActor func perform(_ step: @escaping @MainActor () async -> Void) {
    Task { await step() }
}
