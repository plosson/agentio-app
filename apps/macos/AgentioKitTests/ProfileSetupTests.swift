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
