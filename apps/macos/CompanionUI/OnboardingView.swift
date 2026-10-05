import AgentioKit
import SwiftUI

/// The app's own screens, in a narrow centred column.
struct OnboardingView: View {
    let model: CompanionModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("AgentIO Companion")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                screen
                if let error = model.error {
                    Text(error)
                        .font(Theme.body)
                        .foregroundStyle(Theme.danger)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.dangerMuted))
                        .textSelection(.enabled)
                }
            }
            .frame(width: Theme.column)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .font(Theme.body)
        .foregroundStyle(Theme.text)
    }

    @ViewBuilder private var screen: some View {
        switch model.screen {
        case .mode: ModeScreen(model: model)
        case .installing: InstallingScreen(model: model)
        case .hubURL: HubURLScreen(model: model)
        case .login: LoginScreen(model: model)
        case .local: LocalVaultScreen(model: model)
        case .approving, .vault: EmptyView()
        }
    }
}

/// Run a model step from a button.
@MainActor func perform(_ step: @escaping @MainActor () async -> Void) {
    Task { await step() }
}

struct Heading: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(Theme.display) }
}

struct Explanation: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct StatusBox<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.bgElevated))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).stroke(Theme.border))
    }
}

/// The screen's actions, or the running step's message.
struct Actions<Content: View>: View {
    let busy: String?
    @ViewBuilder let content: Content
    var body: some View {
        if let busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(busy).font(Theme.mono).foregroundStyle(Theme.textSecondary)
            }
        } else {
            HStack(spacing: 12) { content }
        }
    }
}

// MARK: S2

struct InstallingScreen: View {
    let model: CompanionModel

    var body: some View {
        Heading("Setting up AgentIO CLI")
        Text(model.installLabel).font(Theme.mono).foregroundStyle(Theme.textSecondary).lineLimit(2)
        ProgressView(value: Double(model.installPercent), total: 100).tint(Theme.accent)
        Text("\(model.installPercent)%").font(Theme.mono).foregroundStyle(Theme.textSecondary)
    }
}

// MARK: Vault choice

struct ModeScreen: View {
    let model: CompanionModel

    var body: some View {
        switch model.vault {
        case nil:
            Heading("Choose a vault")
            Explanation("Checking this app’s vault…")
        case .remote(let hub):
            Heading("Your vault")
            StatusBox { Text("Signed in to ") + Text(hub).font(Theme.mono) }
            Actions(busy: model.busy) {
                Button("Open vault") { perform(model.openRemoteVault) }.buttonStyle(PrimaryButtonStyle())
                Button("Sign in to a different hub") { model.goRemote() }.buttonStyle(SecondaryButtonStyle())
            }
        case .local:
            Heading("Your vault")
            StatusBox { Text("A local vault is set up on this computer.") }
            Actions(busy: model.busy) {
                Button("Open local vault") { perform(model.openLocalVault) }.buttonStyle(PrimaryButtonStyle())
                Button("Connect to a remote vault instead") { model.goRemote() }.buttonStyle(SecondaryButtonStyle())
            }
            Text("Signing in to a hub makes this app use the hub instead of the local vault.")
                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
        case .none?:
            Heading("Welcome to AgentIO Companion")
            Explanation("A local vault keeps your credentials on this computer. A remote vault is a hub that you or your team already runs.")
            Explanation("The app installs its own copy of the AgentIO CLI, separate from any agentio you installed yourself, and keeps it up to date with your vault.")
            Actions(busy: model.busy) {
                Button("Create a local vault") { perform(model.goLocal) }.buttonStyle(PrimaryButtonStyle())
                Button("Connect to a remote vault") { model.goRemote() }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

struct LocalVaultScreen: View {
    let model: CompanionModel
    @State private var passphrase = ""
    @State private var again = ""

    var body: some View {
        Heading("Create a local vault")
        Explanation("Choose a passphrase of at least 8 characters. You need it each time you unlock the vault. It cannot be recovered if you lose it.")
        SecureField("Passphrase", text: $passphrase).textFieldStyle(.roundedBorder)
        SecureField("Passphrase again", text: $again).textFieldStyle(.roundedBorder)
        Actions(busy: model.busy) {
            Button("Create vault") {
                perform { await model.createLocalVault(passphrase: passphrase, again: again) }
            }
            .buttonStyle(PrimaryButtonStyle())
            Button("Back") { perform(model.enterMode) }.buttonStyle(LinkButtonStyle())
        }
    }
}

// MARK: Remote vault

struct HubURLScreen: View {
    let model: CompanionModel
    @State private var url = ""
    @State private var remember = true

    var body: some View {
        Heading("Connect to your vault")
        Explanation("Enter the HTTPS URL of your AgentIO vault hub. Self-hosted or commercially hosted — same step.")
        TextField("vault.example.com", text: $url)
            .textFieldStyle(.roundedBorder)
            .font(Theme.mono)
            .onSubmit(signIn)
        Toggle("Remember this URL", isOn: $remember)
        Actions(busy: model.busy) {
            Button("Sign in", action: signIn).buttonStyle(PrimaryButtonStyle())
            Button("Back") { perform(model.enterMode) }.buttonStyle(LinkButtonStyle())
            Link("Need a hosted vault? agentio.com", destination: URL(string: "https://agentio.com")!)
                .font(Theme.body).foregroundStyle(Theme.textSecondary)
        }
        .onAppear {
            url = model.hubURL
            remember = model.rememberURL
        }
    }

    private func signIn() {
        perform { await model.signIn(url: url, remember: remember) }
    }
}

struct LoginScreen: View {
    let model: CompanionModel

    var body: some View {
        Heading("Sign in to your vault")
        if let code = model.loginCode {
            Explanation("The hub’s owner must approve this computer with this code:")
            StatusBox { Text(code.userCode).font(Theme.monoDisplay).textSelection(.enabled) }
            Explanation("If you own the hub, open its approval page here. It asks for the hub’s passphrase, the one set on the hub itself. Then choose what this computer may use; to add services from here, allow it to manage profiles.")
            Explanation("Otherwise, send the owner this link and wait:")
            Text(code.verifyURL.absoluteString).font(Theme.mono).textSelection(.enabled)
            Actions(busy: nil) {
                Button("Open approval page") { model.openApproval() }.buttonStyle(PrimaryButtonStyle())
                Button("Cancel") { model.cancelLogin() }.buttonStyle(SecondaryButtonStyle())
            }
        } else {
            (Text("Asking ") + Text(model.hubURL).font(Theme.mono) + Text(" for a sign-in code…"))
                .foregroundStyle(Theme.textSecondary)
            Button("Cancel") { model.cancelLogin() }.buttonStyle(SecondaryButtonStyle())
        }
    }
}
