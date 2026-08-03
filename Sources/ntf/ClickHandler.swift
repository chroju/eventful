import AppKit
import Foundation
import UserNotifications

/// Click mode: when a notification is clicked, the OS relaunches
/// Eventful.app with no arguments and delivers didReceive(response).
/// The delegate must be set before NSApp.run(), as early as possible —
/// a late delegate misses the response entirely.
/// Shared response handling: resolve the spool ref and run the actions.
/// Used by both click mode and setup (whose still-running process receives
/// the response instead of a freshly launched instance).
enum ResponseHandler {
    /// Returns false when any action failed; stale/ref-less responses are
    /// treated as success (silently ignored).
    static func process(_ response: UNNotificationResponse) -> Bool {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            Log.write("click: non-default action, ignoring")
            return true
        }

        let userInfo = response.notification.request.content.userInfo
        guard let ref = userInfo["ref"] as? String else {
            Log.write("click: no ref in userInfo (action-less notification)")
            return true
        }
        guard let action = Spool.resolve(ref: ref) else {
            // Stale-click protection: missing or expired → silently do nothing.
            Log.write("click: spool miss/expired: \(ref)")
            return true
        }
        Spool.delete(ref: ref)

        var ok = true
        if let bundleID = action.activate {
            ok = Activator.activate(bundleID: bundleID) && ok
        }
        if let urlString = action.open {
            if let url = URL(string: urlString) {
                Log.write("click: open \(urlString)")
                ok = NSWorkspace.shared.open(url) && ok
            } else {
                Log.write("click: invalid open URL: \(urlString)")
                ok = false
            }
        }
        if let exec = action.execute {
            ok = Runner.run(cmd: exec.cmd, cwd: exec.cwd, timeoutSec: action.timeoutSec) && ok
        }
        Log.write("click: done ok=\(ok)")
        return ok
    }
}

final class ClickDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Exiting inside didReceive loses responses: rapid clicks on several
    /// notifications get delivered to the already-running instance, so the
    /// process must linger a bit after each one instead of exiting
    /// immediately (verified: an immediate exit dropped the second of three
    /// quick clicks).
    private var exitWork: DispatchWorkItem?
    private var exitCode: Int32 = 0

    func scheduleExit(after seconds: TimeInterval) {
        exitWork?.cancel()
        let work = DispatchWorkItem { [self] in
            Log.write("click: idle, exiting \(exitCode)")
            exit(exitCode)
        }
        exitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// If nothing arrives shortly after launch, assume a human simply typed
    /// `ntf` and bail out. Cancelled by the first response.
    func scheduleInitialTimeout(seconds: TimeInterval) {
        let work = DispatchWorkItem {
            Log.write("click: no response within \(Int(seconds))s, exiting")
            FileHandle.standardError.write(
                Data("eventful: no notification response. Try `ntf --help`\n".utf8))
            exit(64)
        }
        exitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void
    ) {
        exitWork?.cancel()  // keep the pending exit from firing mid-handling
        Log.write("click: received response action=\(response.actionIdentifier)")
        DispatchQueue.main.async { [self] in
            defer {
                completion()
                scheduleExit(after: 3)
            }
            if !ResponseHandler.process(response) { exitCode = 1 }
        }
    }
}

enum Activator {
    static func activate(bundleID: String) -> Bool {
        Log.write("click: activate \(bundleID)")
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            Log.write("click: app not found for bundle id \(bundleID)")
            return false
        }
        var ok = true
        let sem = DispatchSemaphore(value: 0)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error {
                Log.write("click: activate failed: \(error)")
                ok = false
            }
            sem.signal()
        }
        // The completion handler may need the main run loop, so pump it
        // instead of blocking on the semaphore.
        while sem.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return ok
    }
}

// UNUserNotificationCenter.delegate is weak; a function-local delegate gets
// released by ARC right after the assignment (its last use), silently dropping
// the response. Hold it in a global so it lives for the whole process.
private let clickDelegate = ClickDelegate()

func runClickMode() -> Never {
    // A bare-binary, argument-less invocation (e.g. a human typing `ntf`
    // outside the bundle) must not touch UN APIs — they would crash.
    guard Bundle.main.bundleIdentifier == Sender.bundleID else {
        FileHandle.standardError.write(
            Data("eventful: no notification response. Try `ntf --help`\n".utf8))
        exit(64)
    }

    Log.write("click: mode start")
    UNUserNotificationCenter.current().delegate = clickDelegate  // before NSApp.run()

    let app = NSApplication.shared
    clickDelegate.scheduleInitialTimeout(seconds: 5)
    app.run()
    exit(0)
}
