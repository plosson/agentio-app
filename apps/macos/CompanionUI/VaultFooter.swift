import SwiftUI

/// The bar under a vault page: which vault this is, a way to another one,
/// and which AgentIO the app runs.
struct VaultFooter: View {
    let footer: Footer
    let model: CompanionModel

    var body: some View {
        HStack(spacing: 10) {
            vault
            Spacer(minLength: 16)
            agentio
        }
        .font(Theme.caption)
        .foregroundStyle(Theme.textSecondary)
        .controlSize(.small)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Theme.bgElevated)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    @ViewBuilder private var vault: some View {
        switch footer.vault {
        case .hub(let host):
            Label(host, systemImage: "server.rack").foregroundStyle(Theme.text)
            Button("Switch Vault…") { perform(model.switchVault) }
        case .local:
            Label("Local vault on this Mac", systemImage: "laptopcomputer").foregroundStyle(Theme.text)
            Button("Switch Vault…") { perform(model.switchVault) }
        case .signingIn(let host):
            Label("Signing in to \(host)", systemImage: "person.badge.key").foregroundStyle(Theme.text)
            Button("Cancel Sign-in") { model.cancelLogin() }
        }
    }

    @ViewBuilder private var agentio: some View {
        switch footer.agentio {
        case .unknown:
            Text("AgentIO")
        case .version(let version):
            Text("AgentIO \(version)")
        case .upToDate(let version):
            Text("AgentIO \(version) · up to date")
        case .updateAvailable(let current, let latest):
            Text("AgentIO \(current)")
            Button("Update to \(latest)") { perform(model.updateAgentio) }
        case .updating(let percent):
            ProgressView(value: Double(percent), total: 100).frame(width: 80)
            Text("Updating AgentIO… \(percent)%").monospacedDigit()
        case .updateFailed(let current, _):
            Text("AgentIO \(current) · the update failed").foregroundStyle(Theme.danger)
            Button("Try Again") { perform(model.updateAgentio) }
        case .dev(let version, let folder):
            Text("AgentIO \(version ?? "") · dev · \(folder)")
                .lineLimit(1).truncationMode(.middle)
                .help("Runs AgentIO from \(folder). Change it in Settings.")
        }
    }
}
