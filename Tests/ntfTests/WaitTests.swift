import Testing
import UserNotifications

@testable import ntf

/// Pure parts of Wait only: button parsing, response→outcome mapping, JSON
/// shape, and exit codes. The runtime part (posting, delegate, run loop)
/// needs a signed bundle and a human, so it is verified manually.
struct WaitTests {
    // MARK: parseButtons

    @Test func parsesCommaSeparatedLabels() throws {
        #expect(try Wait.parseButtons("yes,no") == ["yes", "no"])
        #expect(try Wait.parseButtons("Approve") == ["Approve"])
        #expect(try Wait.parseButtons(" a , b , c ") == ["a", "b", "c"])
    }

    @Test func rejectsEmptyLabels() {
        #expect(throws: (any Error).self) { try Wait.parseButtons("") }
        #expect(throws: (any Error).self) { try Wait.parseButtons("yes,,no") }
        #expect(throws: (any Error).self) { try Wait.parseButtons("yes,") }
        #expect(throws: (any Error).self) { try Wait.parseButtons("  ") }
    }

    // MARK: outcome mapping

    @Test func mapsSystemActionIdentifiers() {
        #expect(
            Wait.outcome(
                actionIdentifier: UNNotificationDefaultActionIdentifier,
                userText: nil, buttons: []) == .clicked)
        #expect(
            Wait.outcome(
                actionIdentifier: UNNotificationDismissActionIdentifier,
                userText: nil, buttons: []) == .dismissed)
    }

    @Test func mapsButtonIdentifiersToLabels() {
        let buttons = ["Approve", "Deny"]
        #expect(
            Wait.outcome(actionIdentifier: "eventful.button.0", userText: nil, buttons: buttons)
                == .button(index: 0, label: "Approve"))
        #expect(
            Wait.outcome(actionIdentifier: "eventful.button.1", userText: nil, buttons: buttons)
                == .button(index: 1, label: "Deny"))
    }

    @Test func mapsReplyWithText() {
        #expect(
            Wait.outcome(actionIdentifier: "eventful.reply", userText: "hi", buttons: [])
                == .reply(text: "hi"))
        #expect(
            Wait.outcome(actionIdentifier: "eventful.reply", userText: nil, buttons: [])
                == .reply(text: ""))
    }

    @Test func unknownIdentifiersResolveToNil() {
        #expect(Wait.outcome(actionIdentifier: "eventful.button.5", userText: nil, buttons: ["a"]) == nil)
        #expect(Wait.outcome(actionIdentifier: "eventful.button.x", userText: nil, buttons: ["a"]) == nil)
        #expect(Wait.outcome(actionIdentifier: "something.else", userText: nil, buttons: ["a"]) == nil)
    }

    // MARK: JSON shape (pinned: this is the stdout contract)

    @Test func jsonShapeIsPinned() {
        #expect(Wait.jsonLine(for: .clicked) == #"{"action":"clicked"}"#)
        #expect(
            Wait.jsonLine(for: .button(index: 1, label: "Deny"))
                == #"{"action":"button","button":"Deny","index":1}"#)
        #expect(
            Wait.jsonLine(for: .reply(text: "ship it"))
                == #"{"action":"reply","text":"ship it"}"#)
        #expect(Wait.jsonLine(for: .dismissed) == #"{"action":"dismissed"}"#)
        #expect(Wait.jsonLine(for: .timeout) == #"{"action":"timeout"}"#)
    }

    // MARK: exit codes (pinned: shell contract)

    @Test func exitCodesArePinned() {
        #expect(Wait.exitCode(for: .clicked) == 0)
        #expect(Wait.exitCode(for: .button(index: 0, label: "a")) == 0)
        #expect(Wait.exitCode(for: .reply(text: "")) == 0)
        #expect(Wait.exitCode(for: .dismissed) == 2)
        #expect(Wait.exitCode(for: .timeout) == 124)
    }

    // MARK: category id

    @Test func categoryIDIsDeterministicPerConfig() {
        let a = Wait.categoryID(buttons: ["yes", "no"], reply: false)
        #expect(a == Wait.categoryID(buttons: ["yes", "no"], reply: false))
        #expect(a != Wait.categoryID(buttons: ["yes", "no"], reply: true))
        #expect(a != Wait.categoryID(buttons: ["no", "yes"], reply: false))
        #expect(a.hasPrefix("eventful.wait."))
    }
}
