import AgentioKit
import AppKit
import SwiftUI

/// Adding one profile, or signing one in again, over the hub page.
struct AddProfileSheet: View {
    @Bindable var flow: AddProfileFlow
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(Theme.title)
            content
        }
        .font(Theme.body)
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }

    private var title: String {
        flow.purpose == .add ? "Add \(flow.displayName)" : "Sign in again to \(flow.displayName)"
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case .confirm:
            if case .reauth(let profile) = flow.purpose {
                Text(profile).font(Theme.mono).textSelection(.enabled)
            }
            Explanation("Your browser opens to sign in again.")
            buttons(primary: ("Continue", flow.submit))
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
            buttons(primary: nil)
        case .unsupported:
            Explanation("This version of agentio can't add \(flow.displayName) from the app yet. Add it from a terminal for now:")
            command("agentio \(flow.service) profile add")
            buttons(primary: nil, cancel: "Close")
        case .form(let needs):
            if let line = authLine(needs.auth) { Explanation(line) }
            ForEach(needs.inputs) { input in field(input, text: binding(for: input.id)) }
            Toggle("Read-only: agents can read, not change anything", isOn: $flow.readOnly)
            buttons(primary: ("Continue", flow.submit))
        case .working(let auth):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(auth == .none && flow.purpose == .add ? "Checking…" : "Waiting for you in the browser…").foregroundStyle(Theme.textSecondary)
            }
            if flow.lastOpened != nil { Button("Open the page again", action: flow.reopen).buttonStyle(LinkButtonStyle()) }
            buttons(primary: nil)
        case .code(let code, _):
            Explanation("Check that the page in your browser shows this code, then approve.")
            Text(code).font(Theme.monoDisplay).textSelection(.enabled)
            if flow.lastOpened != nil { Button("Open the page again", action: flow.reopen).buttonStyle(LinkButtonStyle()) }
            buttons(primary: nil)
        case .asking(let input):
            field(input, text: $flow.answer)
            buttons(primary: ("Continue", flow.sendAnswer))
        case .added(let profile):
            Label(flow.purpose == .add ? "\(flow.displayName) added as \(profile)" : "Signed in again as \(profile)",
                  systemImage: "checkmark.circle.fill").foregroundStyle(Theme.text)
            buttons(primary: ("Done", close), cancel: nil)
        case .failed(let text):
            Text(text).foregroundStyle(Theme.danger).textSelection(.enabled)
            buttons(primary: nil, cancel: "Close")
        }
    }

    private func authLine(_ auth: SetupAuth) -> String? {
        switch auth {
        case .browser: "A \(flow.displayName) sign-in opens in your browser. Approve it, then come back here."
        case .browserCode: "Your browser opens \(flow.displayName). After you approve, it shows a code to paste here."
        case .deviceCode: "Your browser opens a page with a code. Check it matches the one shown here, then approve."
        case .pairing: "You'll link your account by scanning a code."
        case .none: nil
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(get: { flow.values[id] ?? "" }, set: { flow.values[id] = $0 })
    }

    @ViewBuilder private func field(_ input: SetupInput, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(input.label).font(Theme.caption).foregroundStyle(Theme.textSecondary)
            switch input.kind {
            case .secret: SecureField("", text: text).textFieldStyle(.roundedBorder)
            case .choice:
                Picker("", selection: text) {
                    Text("Choose…").tag("")
                    ForEach(input.choices, id: \.value) { Text($0.label).tag($0.value) }
                }
                .labelsHidden()
            default: TextField("", text: text).textFieldStyle(.roundedBorder)
            }
            if let help = input.help { Text(help).font(Theme.caption).foregroundStyle(Theme.textSecondary) }
        }
    }

    private func command(_ text: String) -> some View {
        HStack {
            Text(text).font(Theme.mono).textSelection(.enabled)
            Spacer()
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.bgElevated))
    }

    private func buttons(primary: (title: String, action: () -> Void)?, cancel: String? = "Cancel") -> some View {
        HStack {
            Spacer()
            if let cancel { Button(cancel, action: close).buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction) }
            if let primary {
                Button(primary.title, action: primary.action).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(!flow.canSubmit && primary.title == "Continue")
            }
        }
    }
}
