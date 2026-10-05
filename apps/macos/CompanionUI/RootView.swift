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
                VaultWebView(url: page)
                    .ignoresSafeArea()
                    .frame(minWidth: 1100, minHeight: 760)
            } else {
                OnboardingView(model: model)
                    .frame(minWidth: 480, minHeight: 560)
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
