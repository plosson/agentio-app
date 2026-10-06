import AgentioKit
import AppKit
import SwiftUI

/// The Settings window (⌘,).
public struct SettingsView: View {
    @AppStorage(CompanionSettings.setupModeKey) private var setupMode: SetupMode = .form
    @AppStorage(CompanionSettings.devAgentioRepoKey) private var devAgentioRepo = ""

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

            Divider().padding(.vertical, 8)

            LabeledContent("AgentIO") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(devAgentioRepo.isEmpty ? "The app's own" : (devAgentioRepo as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1).truncationMode(.middle)
                    HStack {
                        Button("Choose a Source Folder…", action: chooseSourceFolder)
                        if !devAgentioRepo.isEmpty {
                            Button("Use the App's Own") { devAgentioRepo = "" }
                        }
                    }
                }
            }
            if let repo = CompanionSettings().devAgentioRepo,
               !FileManager.default.fileExists(atPath: DevAgentio(repo: repo).entry.path) {
                Text("This folder has no src/index.ts.")
                    .font(Theme.caption).foregroundStyle(.red)
            }
            Text("For AgentIO developers: run AgentIO from its source folder with bun. The change applies the next time the app opens.")
                .font(Theme.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(width: 420)
    }

    private func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose an agentio source folder (the one with src/index.ts)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        devAgentioRepo = url.path
    }
}
