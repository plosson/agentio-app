@testable import AgentioKit
import Foundation
import Testing
@testable import CompanionUI

@MainActor
struct TerminalFlowTests {
    let backend = FakeBackend()
    let added = AddedLog()

    func flow(_ service: String = "gcal") -> TerminalFlow {
        TerminalFlow(service: service, displayName: "Google Calendar", backend: backend, onAdded: added.add)
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
}

@MainActor final class AddedLog {
    private(set) var services: [String] = []
    func add(_ service: String) { services.append(service) }
}

@MainActor
struct TerminalFlowStopTests {
    let backend = FakeBackend()

    func flow() -> TerminalFlow {
        TerminalFlow(service: "gcal", displayName: "Google Calendar", backend: backend, onAdded: { _ in })
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
