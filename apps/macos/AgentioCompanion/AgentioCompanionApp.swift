import AgentioKit
import AppKit
import CompanionUI
import SwiftUI

@main
struct AgentioCompanionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("AgentIO Companion", id: "main") {
            RootView(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 560)
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
        return CompanionModel(
            backend: AgentioCLI(location: .appDefault()),
            settings: CompanionSettings(),
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
