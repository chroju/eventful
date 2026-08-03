import Foundation

/// Runs an execute action: always `/bin/sh -c <CMD>`, restoring the cwd
/// captured at post time. Environment variables are deliberately NOT saved
/// or restored (settled decision): click-time execution gets the bare GUI
/// session environment, so commands must use full paths and inline env vars.
enum Runner {
    struct RunResult {
        var exitCode: Int32 = 0
        var timedOut = false
        var stderrTail = ""
        var launchErrorDescription: String?

        var ok: Bool { launchErrorDescription == nil && !timedOut && exitCode == 0 }
    }

    /// Pure process execution with no notification side effects.
    static func execute(cmd: String, cwd: String, timeoutSec: Int) -> RunResult {
        Log.write("runner: start cmd=\(cmd) cwd=\(cwd) timeout=\(timeoutSec)s")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", cmd]
        if FileManager.default.fileExists(atPath: cwd) {
            task.currentDirectoryURL = URL(fileURLWithPath: cwd)
        } else {
            Log.write("runner: cwd missing (\(cwd)), falling back to home")
            task.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }

        let stderrPipe = Pipe()
        task.standardError = stderrPipe
        task.standardOutput = FileHandle.nullDevice

        // Drain stderr in the background: a full pipe would deadlock waitUntilExit.
        var stderrData = Data()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global().async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        do {
            try task.run()
        } catch {
            Log.write("runner: failed to launch: \(error)")
            return RunResult(launchErrorDescription: error.localizedDescription)
        }

        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global().async {
            task.waitUntilExit()
            waitGroup.leave()
        }

        var result = RunResult()
        if waitGroup.wait(timeout: .now() + .seconds(timeoutSec)) == .timedOut {
            result.timedOut = true
            Log.write("runner: timeout after \(timeoutSec)s, terminating")
            task.terminate()
            if waitGroup.wait(timeout: .now() + .seconds(3)) == .timedOut {
                Log.write("runner: SIGKILL")
                kill(task.processIdentifier, SIGKILL)
                waitGroup.wait()
            }
        }
        readGroup.wait()

        result.exitCode = task.terminationStatus
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        result.stderrTail = stderrText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last.map(String.init) ?? ""
        return result
    }

    /// Click-path entry point: executes, and posts a follow-up notification
    /// on failure. Success is silent.
    static func run(cmd: String, cwd: String, timeoutSec: Int) -> Bool {
        let result = execute(cmd: cmd, cwd: cwd, timeoutSec: timeoutSec)

        if let launchError = result.launchErrorDescription {
            Sender.postSimple(title: "✗ command failed to launch", body: launchError)
            return false
        }
        if result.timedOut {
            Log.write("runner: killed by timeout. stderr tail: \(result.stderrTail)")
            Sender.postSimple(
                title: "✗ command timed out (\(timeoutSec)s)",
                body: result.stderrTail.isEmpty ? cmd : result.stderrTail)
            return false
        }
        if result.exitCode != 0 {
            Log.write("runner: exit \(result.exitCode). stderr tail: \(result.stderrTail)")
            Sender.postSimple(
                title: "✗ command failed (exit \(result.exitCode))",
                body: result.stderrTail.isEmpty ? cmd : result.stderrTail)
            return false
        }
        Log.write("runner: success")
        return true
    }
}
