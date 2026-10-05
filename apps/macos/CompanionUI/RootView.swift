import SwiftUI

/// The app window: the app's own screens, or the bar above a hub page.
public struct RootView: View {
    let model: CompanionModel

    public init(model: CompanionModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let page = model.vaultPage {
                VStack(spacing: 0) {
                    VaultBar(model: model)
                    Divider()
                    VaultWebView(url: page)
                }
                .frame(minWidth: 1100, minHeight: 760)
            } else {
                OnboardingView(model: model)
                    .frame(minWidth: 480, minHeight: 560)
            }
        }
        .background(Theme.bg)
        .navigationTitle(model.windowTitle)
        .task { await model.start() }
    }
}

/// The bar above the hub's page ("approving" and S6).
struct VaultBar: View {
    let model: CompanionModel

    var body: some View {
        HStack(spacing: 12) {
            if model.screen == .approving {
                Text("Approve code ") + Text(model.loginCode?.userCode ?? "").font(Theme.mono)
                    + Text(" below · waiting for approval…")
                Spacer()
                Button("Cancel") { model.cancelLogin() }
            } else {
                Text("AgentIO Companion · ") + Text(model.vaultPage?.host() ?? "").font(Theme.mono)
                Spacer()
                Button("Switch vault") { perform(model.switchVault) }
            }
        }
        .font(Theme.body)
        .padding(.horizontal, 16)
        .frame(height: Theme.vaultBarHeight)
        .background(Theme.bg)
    }
}
