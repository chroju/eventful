import Foundation

/// Runs a foreground command for `ntf run`: stdio is inherited (the wrapped
/// command owns the tty), there is no timeout, and the child's exit code is
/// mirrored. Deliberately NOT Runner.execute — that is the click-time path
/// (captured output, timeout kill, no tty) and shares no requirements.
enum Wrap {
    struct WrapResult {
        var exitCode: Int32 = 0
        var durationSec: Double = 0
        var launchErrorDescription: String?

        var ok: Bool { launchErrorDescription == nil && exitCode == 0 }
    }

    /// Pure process execution with no notification side effects. The command
    /// is an argv array launched via /usr/bin/env (PATH lookup, no shell
    /// quoting pitfalls); shell-isms need an explicit `sh -c '...'`.
    static func execute(command: [String]) -> WrapResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = command
        // stdio deliberately untouched: the child inherits the tty.

        let start = DispatchTime.now()
        do {
            try task.run()
        } catch {
            return WrapResult(launchErrorDescription: error.localizedDescription)
        }
        task.waitUntilExit()

        var result = WrapResult()
        result.durationSec =
            Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
        if task.terminationReason == .uncaughtSignal {
            // Shell convention for signal deaths: 128 + signal number.
            result.exitCode = 128 + task.terminationStatus
        } else {
            result.exitCode = task.terminationStatus
        }
        return result
    }

    /// Banner-sized duration: "12s", "1m 03s", "1h 02m".
    static func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s" }
        if s < 3600 { return String(format: "%dm %02ds", s / 60, s % 60) }
        return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60)
    }

    /// Body of the completion notification.
    static func summary(_ result: WrapResult) -> String {
        let dur = formatDuration(result.durationSec)
        return result.exitCode == 0 ? "✓ done · \(dur)" : "✗ exit \(result.exitCode) · \(dur)"
    }
}
