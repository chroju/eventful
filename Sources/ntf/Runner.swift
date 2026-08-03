import Foundation

/// Runs an execute action: always `/bin/sh -c <CMD>`, restoring the cwd
/// captured at post time. Environment variables are deliberately NOT saved
/// or restored (settled decision): click-time execution gets the bare GUI
/// session environment, so commands must use full paths and inline env vars.
enum Runner {
    static func run(cmd: String, cwd: String, timeoutSec: Int) -> Bool {
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
            Sender.postSimple(
                title: "✗ command failed to launch",
                body: error.localizedDescription)
            return false
        }

        let waitGroup = DispatchGroup()
        waitGroup.enter()
        DispatchQueue.global().async {
            task.waitUntilExit()
            waitGroup.leave()
        }

        var timedOut = false
        if waitGroup.wait(timeout: .now() + .seconds(timeoutSec)) == .timedOut {
            timedOut = true
            Log.write("runner: timeout after \(timeoutSec)s, terminating")
            task.terminate()
            if waitGroup.wait(timeout: .now() + .seconds(3)) == .timedOut {
                Log.write("runner: SIGKILL")
                kill(task.processIdentifier, SIGKILL)
                waitGroup.wait()
            }
        }
        readGroup.wait()

        let exitCode = task.terminationStatus
        let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
        let stderrTail = stderrText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .last.map(String.init) ?? ""

        if timedOut {
            Log.write("runner: killed by timeout. stderr tail: \(stderrTail)")
            Sender.postSimple(
                title: "✗ command timed out (\(timeoutSec)s)",
                body: stderrTail.isEmpty ? cmd : stderrTail)
            return false
        }
        if exitCode != 0 {
            Log.write("runner: exit \(exitCode). stderr tail: \(stderrTail)")
            Sender.postSimple(
                title: "✗ command failed (exit \(exitCode))",
                body: stderrTail.isEmpty ? cmd : stderrTail)
            return false
        }
        Log.write("runner: success")
        return true
    }
}
