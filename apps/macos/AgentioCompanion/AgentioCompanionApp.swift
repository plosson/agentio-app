import AgentioKit
import AppKit
import CompanionUI
import HoulahopUpdater
import SwiftUI

@main
struct AgentioCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var updater = Updater()

    var body: some Scene {
        Window("AgentIO Companion", id: "main") {
            RootView(model: appDelegate.model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 640)
        .commands {
            VaultCommands(model: appDelegate.model)
            CommandGroup(after: .appInfo) { CheckForUpdatesButton(updater: updater) }
        }
        Settings { SettingsView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: CompanionModel = {
        #if DEBUG
        let allowLocalHTTP = true
        #else
        let allowLocalHTTP = false
        #endif
        let settings = CompanionSettings()
        return CompanionModel(
            backend: AgentioCLI(location: .appDefault(), dev: settings.devAgentioRepo.map { DevAgentio(repo: $0) }),
            settings: settings,
            allowLocalHTTP: allowLocalHTTP,
            deviceName: "AgentIO Companion on \(ProcessInfo.processInfo.hostName)"
        )
    }()

    /// One window: closing it quits, like System Settings.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Stop the local daemon and any sign-in first, so they do not outlive the app.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
