import Foundation
import Testing

@testable import ntf

// Only Wrap.execute and the pure formatters are exercised here; the
// notification side of `ntf run` lives in Sender, which needs an app bundle.
//
// .serialized for the same reason as RunnerTests: concurrent Process spawns
// hang on GitHub Actions macOS runners under default parallelism.
@Suite(.serialized)
struct WrapTests {
    @Test func successExitZero() {
        let result = Wrap.execute(command: ["true"])
        #expect(result.ok)
        #expect(result.exitCode == 0)
    }

    @Test func exitCodeMirrored() {
        let result = Wrap.execute(command: ["sh", "-c", "exit 7"])
        #expect(!result.ok)
        #expect(result.exitCode == 7)
    }

    @Test func missingCommandExits127() {
        // /usr/bin/env launches fine and reports the missing command as 127,
        // so this is an exit-code case, not a launch error.
        let result = Wrap.execute(command: ["ntf-test-no-such-command-\(UUID().uuidString)"])
        #expect(result.launchErrorDescription == nil)
        #expect(result.exitCode == 127)
    }

    @Test func signalDeathMapsTo128PlusSigno() {
        let result = Wrap.execute(command: ["sh", "-c", "kill -TERM $$"])
        #expect(result.exitCode == 128 + SIGTERM)
    }

    @Test func durationIsMeasured() {
        let result = Wrap.execute(command: ["sleep", "0.2"])
        #expect(result.durationSec >= 0.15)
        #expect(result.durationSec < 5)
    }

    @Test func formatDuration() {
        #expect(Wrap.formatDuration(0.4) == "0s")
        #expect(Wrap.formatDuration(12) == "12s")
        #expect(Wrap.formatDuration(63) == "1m 03s")
        #expect(Wrap.formatDuration(3725) == "1h 02m")
    }

    @Test func summaryReportsStatusAndDuration() {
        #expect(Wrap.summary(.init(exitCode: 0, durationSec: 12)) == "✓ done · 12s")
        #expect(Wrap.summary(.init(exitCode: 2, durationSec: 63)) == "✗ exit 2 · 1m 03s")
    }
}
