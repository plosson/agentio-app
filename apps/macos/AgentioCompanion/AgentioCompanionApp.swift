import SwiftUI

@main
struct AgentioCompanionApp: App {
    var body: some Scene {
        Window("AgentIO Companion", id: "main") {
            // Replaced by the onboarding screens in Task 8.
            Text("AgentIO Companion")
                .frame(minWidth: 480, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
