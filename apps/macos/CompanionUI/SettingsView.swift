import SwiftUI

/// The Settings window (⌘,).
public struct SettingsView: View {
    @AppStorage(CompanionSettings.setupModeKey) private var setupMode: SetupMode = .form

    public init() {}

    public var body: some View {
        Form {
            Picker("Setup mode", selection: $setupMode) {
                Text("Form").tag(SetupMode.form)
                Text("Terminal").tag(SetupMode.terminal)
            }
            .pickerStyle(.radioGroup)
            Text("How Add opens: the app's own form, or agentio's questions in a terminal.")
                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
