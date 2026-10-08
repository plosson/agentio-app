@testable import AgentioKit
import AppKit
import Foundation
import Testing
@testable import CompanionUI

@MainActor
struct TerminalFlowTests {
    let backend = FakeBackend()
    let added = AddedLog()

    func flow(_ service: String = "gcal") -> TerminalFlow {
        TerminalFlow(service: service, displayName: "Google Calendar", backend: backend, onDone: added.add)
    }

    func reauth(_ service: String = "gcal", profile: String = "work") -> TerminalFlow {
        TerminalFlow(service: service, displayName: "Google Calendar", purpose: .reauth(profile: profile), backend: backend,
                     onDone: added.add)
    }

    @Test func nothingRunsBeforeStart() {
        let flow = flow()
        #expect(flow.step == .ready)
        #expect(backend.terminalAdds.isEmpty)
    }

    @Test func startRunsTheCommandWithTheReadOnlyChoice() throws {
        let flow = flow()
        flow.readOnly = true
        flow.start()
        guard case .running(let command) = flow.step else { Issue.record("not running: \(flow.step)"); return }
        #expect(command.arguments == ["gcal", "profile", "add", "--read-only"])
        #expect(backend.terminalAdds == ["gcal|true"])
    }

    @Test func startTwiceRunsOnce() {
        let flow = flow()
        flow.start()
        flow.start()
        #expect(backend.terminalAdds.count == 1)
    }

    @Test func startAfterCancelRunsNothing() {
        let flow = flow()
        flow.cancel()
        flow.start()
        #expect(flow.step == .ready)
        #expect(backend.terminalAdds.isEmpty)
    }

    @Test func aRefusedServiceFailsWithoutRunning() {
        let flow = flow("../x")
        flow.start()
        #expect(flow.step == .failed("Not a service: ../x"))
        #expect(added.services.isEmpty)
    }

    @Test func exitZeroSucceedsAndTellsThePage() {
        let flow = flow()
        flow.start()
        flow.exited(0)
        #expect(flow.step == .succeeded)
        #expect(added.services == ["gcal"])
    }

    @Test func aNonZeroExitOrASignalEndsWithoutTellingThePage() {
        for code: Int32? in [1, 2, 130, nil] {
            let flow = flow()
            flow.start()
            flow.exited(code)
            #expect(flow.step == .ended(exitCode: code), "code: \(String(describing: code))")
        }
        #expect(added.services.isEmpty)
    }

    @Test func anExitAfterCancelChangesNothing() {
        let flow = flow()
        flow.start()
        flow.cancel()
        flow.exited(0)
        #expect(flow.isCancelled)
        #expect(added.services.isEmpty)
        #expect(flow.step != .succeeded)
    }

    @Test func anExitBeforeStartOrASecondExitIsIgnored() {
        let early = flow()
        early.exited(0)
        #expect(early.step == .ready)
        let twice = flow()
        twice.start()
        twice.exited(1)
        twice.exited(0)
        #expect(twice.step == .ended(exitCode: 1))
        #expect(added.services.isEmpty)
    }

    // MARK: Signing in again

    @Test func aSignInAgainRunsAtOnceWithoutAReadOnlyChoice() throws {
        let flow = reauth()
        guard case .running(let command) = flow.step else { Issue.record("not running: \(flow.step)"); return }
        #expect(command.arguments == ["profile", "reauth", "gcal", "work"])
        #expect(backend.terminalReauths == ["gcal|work"])
        #expect(backend.terminalAdds.isEmpty)
        // Its Read-only flag is the profile's own: the choice changes nothing, and start does not run it again.
        flow.readOnly = true
        flow.start()
        #expect(backend.terminalReauths == ["gcal|work"])
    }

    @Test func aSignedInProfileTellsThePageItsName() {
        let flow = reauth(profile: "pa@example.com")
        flow.exited(0)
        #expect(flow.step == .succeeded)
        #expect(added.services == ["gcal|pa@example.com"])
    }

    @Test func aFailedSignInAgainTellsThePageNothing() {
        for code: Int32? in [1, nil] {
            let flow = reauth()
            flow.exited(code)
            #expect(flow.step == .ended(exitCode: code))
        }
        #expect(added.services.isEmpty)
    }

    @Test func aSignInAgainOfARefusedServiceFailsWithoutRunning() {
        let flow = reauth("--json")
        #expect(flow.step == .failed("Not a service: --json"))
        flow.exited(0)
        #expect(added.services.isEmpty)
    }
}

@MainActor final class AddedLog {
    /// "service", or "service|profile" for a sign-in again.
    private(set) var services: [String] = []
    func add(_ service: String, _ profile: String?) { services.append(profile.map { "\(service)|\($0)" } ?? service) }
}

@MainActor
struct TerminalFlowStopTests {
    let backend = FakeBackend()

    func flow() -> TerminalFlow {
        TerminalFlow(service: "gcal", displayName: "Google Calendar", backend: backend, onDone: { _, _ in })
    }

    @Test func cancelStopsTheAttachedProcessOnce() {
        let flow = flow()
        var stops = 0
        flow.start()
        flow.attach { stops += 1 }
        #expect(stops == 0)
        flow.cancel()
        flow.cancel()
        #expect(stops == 1)
    }

    @Test func aProcessAttachedAfterCancelIsStoppedAtOnce() {
        let flow = flow()
        var stops = 0
        flow.start()
        flow.cancel()
        flow.attach { stops += 1 }
        #expect(stops == 1)
    }
}

struct ThemeResolvedTests {
    func hex(_ color: NSColor) -> UInt32 {
        UInt32((color.redComponent * 255).rounded()) << 16 | UInt32((color.greenComponent * 255).rounded()) << 8
            | UInt32((color.blueComponent * 255).rounded())
    }

    @Test func aTokenResolvesToItsLightOrDarkValueWhateverTheCurrentAppearance() {
        for current in [NSAppearance.Name.aqua, .darkAqua] {
            NSAppearance(named: current)!.performAsCurrentDrawingAppearance {
                #expect(hex(Theme.resolved(Theme.bg, dark: false)) == 0xF5F5F7, "current: \(current.rawValue)")
                #expect(hex(Theme.resolved(Theme.bg, dark: true)) == 0x1C1C1E, "current: \(current.rawValue)")
                #expect(hex(Theme.resolved(Theme.text, dark: true)) == 0xF5F5F7, "current: \(current.rawValue)")
            }
        }
    }
}
