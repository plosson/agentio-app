import Foundation
import Testing
@testable import CompanionUI

struct CompanionSettingsTests {
    let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
    var settings: CompanionSettings { CompanionSettings(defaults: defaults) }

    @Test func theFormIsTheDefault() {
        #expect(settings.setupMode == .form)
    }

    @Test func aChosenModeIsKept() {
        settings.setupMode = .terminal
        #expect(CompanionSettings(defaults: defaults).setupMode == .terminal)
        settings.setupMode = .form
        #expect(CompanionSettings(defaults: defaults).setupMode == .form)
    }

    @Test func anUnknownStoredValueIsTheForm() {
        for stored: Any in ["Terminal", "pty", "", 1, true] {
            defaults.set(stored, forKey: CompanionSettings.setupModeKey)
            #expect(settings.setupMode == .form, "stored: \(stored)")
        }
    }

    @Test func theSettingsWindowAndTheModelUseTheSameKey() {
        // SettingsView stores through @AppStorage(CompanionSettings.setupModeKey) as the raw value.
        defaults.set(SetupMode.terminal.rawValue, forKey: CompanionSettings.setupModeKey)
        #expect(settings.setupMode == .terminal)
    }
}
