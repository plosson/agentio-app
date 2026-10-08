import Foundation
import Testing
@testable import CompanionUI

struct DevAgentioSettingTests {
    let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
    var settings: CompanionSettings { CompanionSettings(defaults: defaults) }

    @Test func unsetMeansTheAppsOwnAgentio() {
        #expect(settings.devAgentioRepo == nil)
    }

    @Test func anAbsolutePathOrOneInTheHomeFolderIsTheCheckout() {
        defaults.set("/src/my agentio/", forKey: CompanionSettings.devAgentioRepoKey)
        #expect(settings.devAgentioRepo?.path == "/src/my agentio")
        defaults.set(" ~/devel/agentio\n", forKey: CompanionSettings.devAgentioRepoKey)
        #expect(settings.devAgentioRepo?.path == FileManager.default.homeDirectoryForCurrentUser.path + "/devel/agentio")
    }

    @Test func anythingElseIsIgnored() {
        for stored: Any in ["", "   ", "devel/agentio", "./agentio", "~other/agentio", 1, true, ["/src/agentio"]] {
            defaults.set(stored, forKey: CompanionSettings.devAgentioRepoKey)
            #expect(settings.devAgentioRepo == nil, "stored: \(stored)")
        }
    }
}
