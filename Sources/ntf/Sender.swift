import Foundation
import UserNotifications

struct NtfError: Error, CustomStringConvertible {
    var description: String
    init(_ message: String) { description = message }
}

enum Sender {
    static let bundleID = "com.github.chroju.eventful"

    /// The UserNotifications framework requires an app bundle. Detect
    /// out-of-bundle execution before touching any UN API — otherwise the
    /// process crashes with "bundleProxyForCurrentProcess is nil".
    static func ensureBundle() throws {
        guard Bundle.main.bundleIdentifier == bundleID else {
            throw NtfError(
                "not running inside Eventful.app bundle "
                    + "(bundle id: \(Bundle.main.bundleIdentifier ?? "nil")). "
                    + "Run scripts/build.sh and invoke via the build/ntf wrapper "
                    + "(a plain symlink to the binary breaks bundle resolution)")
        }
    }

    static func currentSettings() -> UNNotificationSettings {
        let center = UNUserNotificationCenter.current()
        var result: UNNotificationSettings!
        let sem = DispatchSemaphore(value: 0)
        center.getNotificationSettings { s in
            result = s
            sem.signal()
        }
        sem.wait()
        return result
    }

    /// Regular send. Only checks the authorization status; never prompts.
    /// Prompting is the responsibility of `ntf setup`.
    static func send(
        title: String, body: String?, subtitle: String?, sound: Bool,
        id: String?, activate: String?, open: String?, execute: String?,
        timeoutSec: Int
    ) throws {
        try ensureBundle()

        switch currentSettings().authorizationStatus {
        case .authorized, .provisional:
            break
        case .notDetermined:
            throw NtfError("notifications not authorized yet. Run `ntf setup` first")
        case .denied:
            throw NtfError(
                "notifications are denied. "
                    + "Enable manually: System Settings > Notifications > Eventful")
        @unknown default:
            throw NtfError("unknown notification authorization status")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if let body { content.body = body }
        if let subtitle { content.subtitle = subtitle }
        if sound { content.sound = .default }

        if activate != nil || open != nil || execute != nil {
            let action = SpoolAction(
                v: 1,
                createdAt: Date(),
                ttlSec: Spool.defaultTTLSec,
                activate: activate,
                open: open,
                execute: execute.map {
                    .init(cmd: $0, cwd: FileManager.default.currentDirectoryPath)
                },
                timeoutSec: timeoutSec)
            let ref = try Spool.save(action)
            content.userInfo = ["v": 1, "ref": ref]
        }

        try post(content: content, identifier: id ?? UUID().uuidString)
        Spool.gc()
    }

    /// Posts one notification and waits for completion. The follow-up
    /// failure notification from Runner reuses this path.
    static func post(content: UNMutableNotificationContent, identifier: String) throws {
        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: nil)
        var addError: Error?
        let sem = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request) { error in
            addError = error
            sem.signal()
        }
        sem.wait()
        if let addError {
            throw NtfError("failed to post notification: \(addError.localizedDescription)")
        }
    }

    /// Action-less plain notification, used for Runner failure reports.
    /// Carries no execute payload, so it cannot loop.
    static func postSimple(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        do {
            try post(content: content, identifier: UUID().uuidString)
        } catch {
            Log.write("follow-up notification failed: \(error)")
        }
    }

    static func remove(id: String?, all: Bool) throws {
        try ensureBundle()
        let center = UNUserNotificationCenter.current()
        if all {
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
        } else if let id {
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }
        // The remove APIs have no completion handler. Exiting immediately can
        // kill the process before they take effect, so make one round-trip
        // call to synchronize.
        _ = deliveredNotifications()
    }

    static func deliveredNotifications() -> [UNNotification] {
        var result: [UNNotification] = []
        let sem = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().getDeliveredNotifications { list in
            result = list
            sem.signal()
        }
        sem.wait()
        return result
    }

    static func list(json: Bool) throws {
        try ensureBundle()
        let delivered = deliveredNotifications()
        if json {
            let items = delivered.map { n -> [String: String] in
                let c = n.request.content
                return [
                    "id": n.request.identifier,
                    "title": c.title,
                    "subtitle": c.subtitle,
                    "body": c.body,
                    "date": ISO8601DateFormatter().string(from: n.date),
                ]
            }
            let data = try JSONSerialization.data(
                withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
        } else {
            if delivered.isEmpty {
                print("no delivered notifications")
                return
            }
            for n in delivered {
                let c = n.request.content
                print("\(n.request.identifier)\t\(c.title)\t\(c.body)")
            }
        }
    }
}
