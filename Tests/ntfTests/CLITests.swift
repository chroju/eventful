import Testing

@testable import ntf

struct CLITests {
    @Test func sendDefaults() throws {
        let send = try Send.parse(["--title", "hello"])
        #expect(send.title == "hello")
        #expect(send.body == nil)
        #expect(send.sound == false)
        #expect(send.id == nil)
        #expect(send.timeout == 30)
    }

    @Test func sendParsesAllOptions() throws {
        let send = try Send.parse([
            "--title", "t", "--body", "b", "--subtitle", "s", "--sound",
            "--id", "g", "--activate", "com.example.app",
            "--open", "https://example.com", "--execute", "/usr/bin/true",
            "--timeout", "5",
        ])
        #expect(send.body == "b")
        #expect(send.subtitle == "s")
        #expect(send.sound == true)
        #expect(send.id == "g")
        #expect(send.activate == "com.example.app")
        #expect(send.open == "https://example.com")
        #expect(send.execute == "/usr/bin/true")
        #expect(send.timeout == 5)
    }

    @Test func removeRequiresGroupIDOrAll() {
        #expect(throws: (any Error).self) { try Remove.parse([]) }
        #expect(throws: (any Error).self) { try Remove.parse(["x", "--all"]) }
        #expect(throws: Never.self) { try Remove.parse(["x"]) }
        #expect(throws: Never.self) { try Remove.parse(["--all"]) }
    }
}
