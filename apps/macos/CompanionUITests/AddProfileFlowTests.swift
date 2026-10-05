@testable import AgentioKit
import Foundation
import Testing
@testable import CompanionUI

let urlInput = SetupInput(id: "url", label: "Kite server URL", kind: .url, required: true, defaultValue: nil, help: nil, choices: [])
let siteInput = SetupInput(id: "site", label: "Jira site", kind: .choice, required: true, defaultValue: nil, help: nil, choices: [SetupChoice(value: "c1", label: "Acme")])

@MainActor
struct AddProfileFlowTests {
    let backend = FakeBackend()

    func flow(_ added: @escaping @MainActor (String, String) -> Void = { _, _ in }, opened: OpenLog = OpenLog()) -> AddProfileFlow {
        AddProfileFlow(service: "kite", displayName: "Kite", backend: backend, openURL: opened.add, onAdded: added)
    }

    @Test func aServiceThisAgentioCannotSetUpIsUnsupported() async {
        backend.describeResult = .success(nil)
        let flow = flow()
        await flow.start()
        #expect(flow.step == .unsupported)
        #expect(backend.startedAdds.isEmpty)
    }

    @Test func aDescribeFailureIsShown() async {
        backend.describeResult = .failure(AgentioError("This key may not manage profiles"))
        let flow = flow()
        await flow.start()
        #expect(flow.step == .failed("This key may not manage profiles"))
    }

    @Test func theFormNeedsEveryRequiredValueAndSendsOnlyNonBlankOnes() async {
        backend.describeResult = .success(SetupNeeds(inputs: [urlInput, SetupInput(id: "note", label: "Note", kind: .text, required: false, defaultValue: nil, help: nil, choices: [])], auth: .deviceCode))
        let flow = flow()
        await flow.start()
        #expect(flow.step == .form(SetupNeeds(inputs: [urlInput, SetupInput(id: "note", label: "Note", kind: .text, required: false, defaultValue: nil, help: nil, choices: [])], auth: .deviceCode)))
        #expect(!flow.canSubmit)
        flow.submit()
        #expect(backend.startedAdds.isEmpty)
        flow.values["url"] = "   "
        #expect(!flow.canSubmit)
        flow.values["url"] = "kite.example.com"
        flow.values["note"] = "  "
        flow.readOnly = true
        #expect(flow.canSubmit)
        flow.submit()
        #expect(flow.step == .working(.deviceCode))
        #expect(backend.startedAdds == ["kite|url=kite.example.com|true"])
    }

    @Test func eventsBecomeSteps_andTheAddEndsOnce() async throws {
        let log = OpenLog()
        var added: [String] = []
        let flow = flow({ added.append("\($0)/\($1)") }, opened: log)
        await flow.start()
        flow.submit()
        let run = try #require(backend.addRuns.first)
        run.emit(.code(userCode: "AB-12", url: URL(string: "https://kite.example.com/d")!))
        await eventually { flow.step == .code(userCode: "AB-12", url: URL(string: "https://kite.example.com/d")!) }
        run.emit(.open(URL(string: "https://kite.example.com/d")!))
        await eventually { log.urls == [URL(string: "https://kite.example.com/d")!] }
        #expect(flow.step == .code(userCode: "AB-12", url: URL(string: "https://kite.example.com/d")!))
        run.emit(.ask(siteInput))
        await eventually { flow.step == .asking(siteInput) }
        #expect(!flow.canSubmit)
        flow.answer = "c1"
        flow.sendAnswer()
        #expect(run.answers == ["site=c1"])
        run.finish(.success("pa@example.com"))
        await eventually { flow.step == .added(profile: "pa@example.com") }
        #expect(added == ["kite/pa@example.com"])
        flow.reopen()
        #expect(log.urls.count == 2)
    }

    @Test func aFailedAddIsShown() async throws {
        let flow = flow()
        await flow.start()
        flow.submit()
        try #require(backend.addRuns.first).finish(.failure(AgentioError("Google OAuth error: access_denied")))
        await eventually { flow.step == .failed("Google OAuth error: access_denied") }
    }

    @Test func cancellingStopsTheRunAndNothingIsAddedOrShownAfter() async throws {
        var added = 0
        let flow = flow({ _, _ in added += 1 })
        await flow.start()
        flow.submit()
        let run = try #require(backend.addRuns.first)
        flow.cancel()
        #expect(run.cancelled)
        run.finish(.success("late@example.com"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(added == 0)
        #expect(flow.step != .failed("Adding the profile was cancelled"))
    }
}

/// Addresses the flow asked to open, on the main actor.
@MainActor final class OpenLog {
    var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}
