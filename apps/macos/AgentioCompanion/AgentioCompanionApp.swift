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
        Window("AgentIO", id: "main") {
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
            deviceName: "AgentIO on \(ProcessInfo.processInfo.hostName)"
        )
    }()

    /// Before any window: drop the old "AgentIO Companion.app" name, and start again from the new one if this copy moved.
    /// A moved copy exits at once: its window would look for its resources at the old path, and crash.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard case .renamed(let app) = OldAppName.tidy(bundle: Bundle.main.bundleURL,
                                                       bundleID: Bundle.main.bundleIdentifier ?? "") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let launched = DispatchSemaphore(value: 0)
        // The handler runs on another queue, so waiting here does not block it.
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, _ in launched.signal() }
        _ = launched.wait(timeout: .now() + 10)
        exit(0)
    }

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
