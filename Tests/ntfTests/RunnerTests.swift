import Foundation
import Testing

@testable import ntf

// Only Runner.execute is exercised here: Runner.run posts notifications via
// UserNotifications, which crashes outside an app bundle (i.e. in the test
// runner).
//
// .serialized: concurrent Process spawns from swift-testing's default
// parallelism hang indefinitely on GitHub Actions macOS runners (confirmed:
// every test here passes in well under a second individually or with
// --no-parallel, but the suite alone hangs for 5+ minutes under default
// parallel execution). Not reproducible locally; runner-sandbox-specific.
@Suite(.serialized)
struct RunnerTests {
    private func makeTempCwd() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntf-runner-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func successfulCommand() {
        let result = Runner.execute(cmd: "/usr/bin/true", cwd: "/tmp", timeoutSec: 5)
        #expect(result.ok)
        #expect(result.exitCode == 0)
        #expect(!result.timedOut)
    }

    @Test func nonZeroExitCodeIsReported() {
        let result = Runner.execute(cmd: "exit 7", cwd: "/tmp", timeoutSec: 5)
        #expect(!result.ok)
        #expect(result.exitCode == 7)
        #expect(!result.timedOut)
    }

    @Test func stderrTailIsLastLine() {
        let result = Runner.execute(
            cmd: "echo first >&2; echo last line >&2; exit 1",
            cwd: "/tmp", timeoutSec: 5)
        #expect(result.exitCode == 1)
        #expect(result.stderrTail == "last line")
    }

    @Test func timeoutKillsProcess() {
        let start = Date()
        let result = Runner.execute(cmd: "sleep 30", cwd: "/tmp", timeoutSec: 1)
        #expect(result.timedOut)
        #expect(!result.ok)
        // 1s timeout + terminate; must not wait for the full sleep
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func runsInGivenCwd() throws {
        let cwd = try makeTempCwd()
        let result = Runner.execute(cmd: "/usr/bin/touch marker", cwd: cwd.path, timeoutSec: 5)
        #expect(result.ok)
        #expect(FileManager.default.fileExists(
            atPath: cwd.appendingPathComponent("marker").path))
    }

    @Test func missingCwdFallsBackAndStillRuns() {
        let result = Runner.execute(
            cmd: "/usr/bin/true",
            cwd: "/nonexistent/path/\(UUID().uuidString)",
            timeoutSec: 5)
        #expect(result.ok)
    }
}
