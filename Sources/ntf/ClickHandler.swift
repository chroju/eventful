import AppKit
import Foundation
import UserNotifications

/// Click mode: when a notification is clicked, the OS relaunches
/// Eventful.app with no arguments and delivers didReceive(response).
/// The delegate must be set before NSApp.run(), as early as possible —
/// a late delegate misses the response entirely.
final class ClickDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void
    ) {
        defer { completion() }
        Log.write("click: received response action=\(response.actionIdentifier)")

        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            Log.write("click: non-default action, ignoring")
            exit(0)
        }

        let userInfo = response.notification.request.content.userInfo
        guard let ref = userInfo["ref"] as? String else {
            Log.write("click: no ref in userInfo (action-less notification)")
            exit(0)
        }
        guard let action = Spool.resolve(ref: ref) else {
            // Stale-click protection: missing or expired → silently do nothing.
            Log.write("click: spool miss/expired: \(ref)")
            exit(0)
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
        exit(ok ? 0 : 1)
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

func runClickMode() -> Never {
    // A bare-binary, argument-less invocation (e.g. a human typing `ntf`
    // outside the bundle) must not touch UN APIs — they would crash.
    guard Bundle.main.bundleIdentifier == Sender.bundleID else {
        FileHandle.standardError.write(
            Data("eventful: no notification response. Try `ntf --help`\n".utf8))
        exit(64)
    }

    Log.write("click: mode start")
    let delegate = ClickDelegate()
    UNUserNotificationCenter.current().delegate = delegate  // before NSApp.run()

    let app = NSApplication.shared
    // If nothing arrives within 5s, assume a human simply typed `ntf`.
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
        Log.write("click: no response within 5s, exiting")
        FileHandle.standardError.write(
            Data("eventful: no notification response. Try `ntf --help`\n".utf8))
        exit(64)
    }
    app.run()
    exit(0)
}
