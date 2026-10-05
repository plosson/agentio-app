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

    @Test func aDescribeFailureCarriesAgentiosSuggestion() async {
        backend.describeResult = .failure(AgentioError("Key rejected", code: "AUTH", suggestion: "Ask the hub admin for a new key"))
        let flow = flow()
        await flow.start()
        #expect(flow.step == .failed("Key rejected"))
        #expect(flow.failureSuggestion == "Ask the hub admin for a new key")
    }

    @Test func aRunFailureCarriesAgentiosSuggestion() async throws {
        let flow = flow()
        await flow.start()
        flow.submit()
        try #require(backend.addRuns.first).finish(.failure(AgentioError("No such profile", suggestion: "Add it again with: agentio kite profile add")))
        await eventually { flow.step == .failed("No such profile") }
        #expect(flow.failureSuggestion == "Add it again with: agentio kite profile add")
    }

    @Test func failuresWithoutASuggestionShowNone() async throws {
        backend.describeResult = .failure(AgentioError("plain"))
        let described = flow()
        await described.start()
        #expect(described.failureSuggestion == nil)

        backend.describeResult = .success(SetupNeeds(inputs: [], auth: .none))
        let run = flow()
        await run.start()
        run.submit()
        try #require(backend.addRuns.first).finish(.failure(AgentioError("plain")))
        await eventually { if case .failed = run.step { true } else { false } }
        #expect(run.failureSuggestion == nil)
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

@MainActor
struct ReauthFlowTests {
    let backend = FakeBackend()

    func flow(_ done: @escaping @MainActor (String, String) -> Void = { _, _ in }, opened: OpenLog = OpenLog()) -> AddProfileFlow {
        AddProfileFlow(service: "gmail", displayName: "gmail", purpose: .reauth(profile: "palosson@hex-rays.com"),
                       backend: backend, openURL: opened.add, onAdded: done)
    }

    @Test func startsAtTheConfirmationAndRunsNothingUntilContinue() async {
        backend.describeGated = true // a describe would hang the start
        let flow = flow()
        #expect(flow.step == .confirm)
        await flow.start()
        #expect(flow.step == .confirm)
        #expect(flow.canSubmit)
        #expect(backend.startedReauths.isEmpty)
        #expect(backend.startedAdds.isEmpty)
        // Neither an answer nor a form value starts anything at the confirmation.
        flow.sendAnswer()
        #expect(backend.addRuns.isEmpty)
    }

    @Test func continueStartsTheSignInAgainOnce() async {
        let flow = flow()
        await flow.start()
        flow.submit()
        #expect(flow.step == .working(.none))
        #expect(backend.startedReauths == ["gmail|palosson@hex-rays.com"])
        #expect(backend.startedAdds.isEmpty)
        // A second Continue (a double click) starts no second run.
        flow.submit()
        #expect(backend.startedReauths.count == 1)
    }

    @Test func eventsBecomeSteps_andTheSignInEndsOnce() async throws {
        let log = OpenLog()
        var done: [String] = []
        let flow = flow({ done.append("\($0)/\($1)") }, opened: log)
        await flow.start()
        flow.submit()
        let run = try #require(backend.addRuns.first)
        run.emit(.open(URL(string: "https://accounts.google.com/x")!))
        await eventually { log.urls == [URL(string: "https://accounts.google.com/x")!] }
        run.emit(.ask(siteInput))
        await eventually { flow.step == .asking(siteInput) }
        flow.answer = "c1"
        flow.sendAnswer()
        #expect(run.answers == ["site=c1"])
        #expect(flow.step == .working(.none))
        // The end event itself changes nothing; the run's end does.
        run.emit(.reauthed(profile: "palosson@hex-rays.com"))
        try await Task.sleep(for: .milliseconds(50))
        #expect(flow.step == .working(.none))
        run.finish(.success("palosson@hex-rays.com"))
        await eventually { flow.step == .added(profile: "palosson@hex-rays.com") }
        #expect(done == ["gmail/palosson@hex-rays.com"])
        flow.submit()
        #expect(backend.startedReauths.count == 1)
    }

    @Test func aFailedSignInIsShownAndNotifiesNothing() async throws {
        var done = 0
        let flow = flow({ _, _ in done += 1 })
        await flow.start()
        flow.submit()
        try #require(backend.addRuns.first).finish(.failure(AgentioError("gmail cannot be signed in again with --json yet")))
        await eventually { flow.step == .failed("gmail cannot be signed in again with --json yet") }
        #expect(done == 0)
    }

    @Test func cancellingStopsTheRunAndNothingHappensAfter() async throws {
        var done = 0
        let log = OpenLog()
        let flow = flow({ _, _ in done += 1 }, opened: log)
        await flow.start()
        flow.submit()
        let run = try #require(backend.addRuns.first)
        flow.cancel()
        #expect(run.cancelled)
        run.emit(.open(URL(string: "https://accounts.google.com/late")!))
        run.finish(.success("palosson@hex-rays.com"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(done == 0)
        #expect(log.urls.isEmpty)
        #expect(flow.step == .working(.none))
    }

    @Test func cancellingAtTheConfirmationStartsNothingLater() async {
        let flow = flow()
        flow.cancel()
        flow.submit()
        #expect(backend.addRuns.isEmpty)
    }
}

/// Addresses the flow asked to open, on the main actor.
@MainActor final class OpenLog {
    var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}
