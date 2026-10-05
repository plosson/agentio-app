import Foundation
import Testing
@testable import AgentioKit

private func event(_ json: String) throws -> CliEvent { try #require(try parseEvent(json)) }

struct ProfileSetupTests {
    @Test func readsTheNeedsOfASetup() throws {
        let needs = try #require(SetupNeeds(event: try event(#"{"v":1,"event":"needs","service":"kite","auth":"device-code","inputs":[{"id":"url","label":"Kite server URL","kind":"url","help":"For example https://kite.example.com"},{"id":"site","label":"Site","kind":"choice","required":false,"default":"a","choices":[{"value":"a","label":"A"}]}]}"#)))
        #expect(needs.auth == .deviceCode)
        #expect(needs.inputs == [
            SetupInput(id: "url", label: "Kite server URL", kind: .url, required: true, defaultValue: nil, help: "For example https://kite.example.com", choices: []),
            SetupInput(id: "site", label: "Site", kind: .choice, required: false, defaultValue: "a", help: nil, choices: [SetupChoice(value: "a", label: "A")]),
        ])
        #expect(try #require(SetupNeeds(event: try event(#"{"v":1,"event":"needs","inputs":[],"auth":"browser"}"#))).inputs.isEmpty)
    }

    @Test func refusesNeedsItCannotRead() throws {
        for json in [
            #"{"v":1,"event":"needs","inputs":[],"auth":"telepathy"}"#,
            #"{"v":1,"event":"needs","inputs":[{"id":"x","label":"X","kind":"hologram"}],"auth":"none"}"#,
            #"{"v":1,"event":"needs","inputs":[{"id":"","label":"X","kind":"text"}],"auth":"none"}"#,
            #"{"v":1,"event":"needs","inputs":[{"id":"x","label":"X","kind":"choice"}],"auth":"none"}"#,
            #"{"v":1,"event":"needs","inputs":[{"id":"x","label":"X","kind":"choice","choices":[{"value":1,"label":"A"}]}],"auth":"none"}"#,
            #"{"v":1,"event":"needs","inputs":[{"id":"x","label":"X","kind":"text","required":"no"}],"auth":"none"}"#,
            #"{"v":1,"event":"needs","inputs":"url","auth":"none"}"#,
            #"{"v":1,"event":"needs","auth":"none"}"#,
        ] {
            #expect(SetupNeeds(event: try event(json)) == nil, "json: \(json)")
        }
    }

    @Test func readsTheEventsOfARun() throws {
        #expect(try setupEvent(try event(#"{"v":1,"event":"code","userCode":"AB-12","verificationUrl":"https://kite.example.com/auth/device?code=AB-12","expiresIn":600}"#))
                == .code(userCode: "AB-12", url: URL(string: "https://kite.example.com/auth/device?code=AB-12")!))
        #expect(try setupEvent(try event(#"{"v":1,"event":"open","url":"https://accounts.google.com/o/oauth2/v2/auth?x=1"}"#))
                == .open(URL(string: "https://accounts.google.com/o/oauth2/v2/auth?x=1")!))
        #expect(try setupEvent(try event(#"{"v":1,"event":"ask","id":"site","label":"Jira site","kind":"choice","choices":[{"value":"c1","label":"Acme"}]}"#))
                == .ask(SetupInput(id: "site", label: "Jira site", kind: .choice, required: true, defaultValue: nil, help: nil, choices: [SetupChoice(value: "c1", label: "Acme")])))
        #expect(try setupEvent(try event(#"{"v":1,"event":"added","service":"gmail","profile":"a@b.c","readOnly":false}"#)) == .added(profile: "a@b.c"))
        // Other events are not steps of the sheet.
        #expect(try setupEvent(try event(#"{"v":1,"event":"error","code":"AUTH_FAILED","message":"x"}"#)) == nil)
    }

    @Test func neverOpensAnAddressThatIsNotAWebPage() throws {
        for url in ["file:///etc/passwd", "javascript:alert(1)", "x-apple.systempreferences:", "https://", "not a url", "ftp://example.com"] {
            #expect(try setupEvent(try event(#"{"v":1,"event":"open","url":"\#(url)"}"#)) == nil, "url: \(url)")
            #expect(try setupEvent(try event(#"{"v":1,"event":"code","userCode":"A","verificationUrl":"\#(url)"}"#)) == nil, "url: \(url)")
        }
    }

    @Test func aQuestionItCannotShowStopsTheRun() throws {
        #expect(throws: unreadableSetup) { try setupEvent(try event(#"{"v":1,"event":"ask","id":"x","label":"X","kind":"hologram"}"#)) }
        #expect(throws: unreadableSetup) { try setupEvent(try event(#"{"v":1,"event":"added"}"#)) }
    }
}

/// Setup events and their order, across threads.
final class SetupLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [SetupEvent] = []
    func add(_ event: SetupEvent) { lock.withLock { entries.append(event) } }
    var events: [SetupEvent] { lock.withLock { entries } }
}

struct ProfileAddTests {
    @Test func describesASetup() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo "$@" > "$HOME/args"; echo '{"v":1,"event":"needs","service":"kite","inputs":[],"auth":"browser"}'"#)
        #expect(try await cli.describeSetup("kite") == SetupNeeds(inputs: [], auth: .browser))
        #expect(dir.read("home/args") == "kite profile add --describe --json\n")
    }

    @Test func aServiceThatCannotDoItIsNotSupportedHere() async throws {
        for script in [
            #"echo '{"v":1,"event":"error","code":"INVALID_PARAMS","message":"gcal cannot be set up with --json yet","suggestion":"Run: agentio gcal profile add"}'; exit 1"#,
            #"echo "error: unknown option '--describe'" >&2; exit 1"#,
        ] {
            let dir = try TempDir(); defer { dir.cleanUp() }
            #expect(try await fakeCli(dir, script).describeSetup("gcal") == nil, "script: \(script)")
        }
    }

    @Test func otherDescribeFailuresAreErrors() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"echo '{"v":1,"event":"error","code":"PERMISSION_DENIED","message":"This key may not manage profiles"}'; exit 2"#)
        await #expect(throws: AgentioError("This key may not manage profiles", code: "PERMISSION_DENIED", exitCode: 2)) { try await cli.describeSetup("kite") }
        let bad = try fakeCli(dir, #"echo '{"v":1,"event":"needs","inputs":[],"auth":"telepathy"}'"#)
        await #expect(throws: unreadableSetup) { try await bad.describeSetup("kite") }
    }

    @Test func aServiceIdThatIsNotOneIsRefusedBeforeAnythingRuns() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"touch "$HOME/ran""#)
        for id in ["--help", "", "Gmail", "gmail;rm", "../x", "a b", "-x"] {
            await #expect(throws: AgentioError.self, "id: \(id)") { try await cli.describeSetup(id) }
            #expect(throws: AgentioError.self, "id: \(id)") { try cli.startProfileAdd(id, values: [:], readOnly: false) { _ in } }
        }
        #expect(dir.read("home/ran") == nil)
    }

    @Test func anAddSendsItsValuesOnStdinAndEndsWithTheProfile() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, """
        echo "$@" > "$HOME/args"; read -r values; echo "$values" > "$HOME/values"
        echo '{"v":1,"event":"open","url":"https://accounts.google.com/x"}'
        echo '{"v":1,"event":"added","service":"gmail","profile":"a@b.c","readOnly":true}'
        """)
        let log = SetupLog()
        let run = try cli.startProfileAdd("gmail", values: ["url": "https://k.example", "apiKey": "s3cr\"et"], readOnly: true, onEvent: log.add)
        #expect(try await run.finished() == "a@b.c")
        #expect(log.events == [.open(URL(string: "https://accounts.google.com/x")!), .added(profile: "a@b.c")])
        #expect(dir.read("home/args") == "gmail profile add --json --input - --read-only\n")
        // Secrets never appear in the arguments, only on stdin, as one JSON line.
        #expect(dir.read("home/values") == #"{"apiKey":"s3cr\"et","url":"https:\/\/k.example"}"# + "\n")
    }

    @Test func anAnswerReachesTheQuestion() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, """
        read values
        echo '{"v":1,"event":"ask","id":"site","label":"Jira site","kind":"choice","choices":[{"value":"c1","label":"Acme"}]}'
        read answer; echo "$answer" > "$HOME/answer"
        echo '{"v":1,"event":"added","service":"jira","profile":"acme","readOnly":false}'
        """)
        let log = SetupLog()
        let run = try cli.startProfileAdd("jira", values: [:], readOnly: false, onEvent: log.add)
        let clock = ContinuousClock(); let deadline = clock.now + .seconds(5)
        while log.events.isEmpty, clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        run.answer(id: "site", value: "c1")
        #expect(try await run.finished() == "acme")
        #expect(dir.read("home/answer") == #"{"id":"site","value":"c1"}"# + "\n")
    }

    @Test func aFailureIsTheErrorEventOrStderr() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let failing = try fakeCli(dir, #"read v; echo '{"v":1,"event":"error","code":"AUTH_FAILED","message":"Google OAuth error: access_denied","suggestion":"Run the command again"}'; exit 2"#)
        await #expect(throws: AgentioError("Google OAuth error: access_denied", code: "AUTH_FAILED", suggestion: "Run the command again", exitCode: 2)) {
            try await failing.startProfileAdd("gmail", values: [:], readOnly: false) { _ in }.finished()
        }
        // A crash with no event and no `added` is a failure too, never a success.
        let crashing = try fakeCli(dir, #"read v; echo "boom" >&2; exit 1"#)
        await #expect(throws: AgentioError.self) { try await crashing.startProfileAdd("gmail", values: [:], readOnly: false) { _ in }.finished() }
    }

    @Test func cancellingStopsTheRunAndSaysSo() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"read v; echo $$ > "$HOME/pid"; exec sleep 30"#)
        let run = try cli.startProfileAdd("gmail", values: [:], readOnly: false) { _ in }
        let clock = ContinuousClock(); let deadline = clock.now + .seconds(5)
        while dir.read("home/pid") == nil, clock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        run.cancel()
        await #expect(throws: AgentioError("Adding the profile was cancelled", exitCode: nil)) { try await run.finished() }
    }

    @Test func aQuestionTheAppCannotShowStopsTheRun() async throws {
        let dir = try TempDir(); defer { dir.cleanUp() }
        let cli = try fakeCli(dir, #"read v; echo '{"v":1,"event":"ask","id":"x","label":"X","kind":"hologram"}'; exec sleep 30"#)
        await #expect(throws: unreadableSetup) { try await cli.startProfileAdd("gmail", values: [:], readOnly: false) { _ in }.finished() }
    }
}
