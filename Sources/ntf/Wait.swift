import AppKit
import CryptoKit
import Foundation
import UserNotifications

/// `ntf send --wait`: synchronous mode. The posting process stays alive,
/// owns the UN delegate itself (no relaunch path), and blocks until the
/// user interacts with the notification — click, action button, text-input
/// reply, or dismiss — then prints one line of JSON to stdout and exits.
///
/// Exit codes: 0 for click/button/reply, 2 for dismiss, 124 for timeout
/// (mirroring timeout(1)).
///
/// If the waiting process dies while the notification is still visible
/// (logout, kill -9), the leftover notification is inert: a button press
/// relaunches the app in click mode, which ignores non-default actions,
/// and a body click carries no spool ref, so both silently do nothing.
enum Wait {
    struct Config {
        var title: String
        var body: String?
        var subtitle: String?
        var sound: Bool
        var id: String?
        var image: String?
        var buttons: [String]
        var reply: Bool
        var timeoutSec: Int  // 0 = wait forever
    }

    enum Outcome: Equatable {
        case clicked
        case button(index: Int, label: String)
        case reply(text: String)
        case dismissed
        case timeout
    }

    static let buttonActionPrefix = "eventful.button."
    static let replyActionID = "eventful.reply"

    // MARK: - Pure parts (covered by tests)

    /// Parses the --buttons value: comma-separated labels, whitespace-trimmed.
    static func parseButtons(_ raw: String) throws -> [String] {
        let labels = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !labels.isEmpty, !labels.contains("") else {
            throw NtfError("--buttons must be a comma-separated list of non-empty labels")
        }
        return labels
    }

    /// Categories registered via setNotificationCategories persist in the
    /// notification store per app, so the id is derived from the button
    /// config: identical configs share one entry, and the set of stored
    /// categories stays bounded by the number of distinct configs (no
    /// per-invocation cleanup needed).
    static func categoryID(buttons: [String], reply: Bool) -> String {
        var seed = buttons.joined(separator: "\u{1f}")
        if reply { seed += "\u{1f}reply" }
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "eventful.wait.\(hex)"
    }

    /// Maps a response's actionIdentifier to an outcome. Returns nil for
    /// identifiers that don't belong to this notification's config
    /// (keep waiting rather than mis-reporting).
    static func outcome(
        actionIdentifier: String, userText: String?, buttons: [String]
    ) -> Outcome? {
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier: return .clicked
        case UNNotificationDismissActionIdentifier: return .dismissed
        case replyActionID: return .reply(text: userText ?? "")
        default:
            guard actionIdentifier.hasPrefix(buttonActionPrefix),
                let index = Int(actionIdentifier.dropFirst(buttonActionPrefix.count)),
                buttons.indices.contains(index)
            else { return nil }
            return .button(index: index, label: buttons[index])
        }
    }

    private struct ResultPayload: Encodable {
        var action: String
        var button: String?
        var index: Int?
        var text: String?
    }

    static func jsonLine(for outcome: Outcome) -> String {
        let payload: ResultPayload
        switch outcome {
        case .clicked: payload = .init(action: "clicked")
        case .button(let index, let label):
            payload = .init(action: "button", button: label, index: index)
        case .reply(let text): payload = .init(action: "reply", text: text)
        case .dismissed: payload = .init(action: "dismissed")
        case .timeout: payload = .init(action: "timeout")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(data: try! encoder.encode(payload), encoding: .utf8)!
    }

    static func exitCode(for outcome: Outcome) -> Int32 {
        switch outcome {
        case .clicked, .button, .reply: return 0
        case .dismissed: return 2
        case .timeout: return 124
        }
    }

    // MARK: - Runtime (needs the app bundle; verified via `ntf setup` flow)

    static func run(_ config: Config) throws -> Never {
        try Sender.ensureBundle()
        try Sender.ensureAuthorized()

        let content = UNMutableNotificationContent()
        content.title = config.title
        if let body = config.body { content.body = body }
        if let subtitle = config.subtitle { content.subtitle = subtitle }
        if config.sound { content.sound = .default }
        if let image = config.image {
            content.attachments = [try Attachment.makeImage(path: image)]
        }
        content.categoryIdentifier = registerCategory(
            buttons: config.buttons, reply: config.reply)

        let requestID = config.id ?? UUID().uuidString

        // Delegate before posting, same rule as click mode: this process
        // holds the live notification-service connection, so responses are
        // delivered here — a late delegate misses them.
        waitDelegate.requestID = requestID
        waitDelegate.buttons = config.buttons
        UNUserNotificationCenter.current().delegate = waitDelegate

        try Sender.post(content: content, identifier: requestID)
        Log.write("wait: posted \(requestID), timeout=\(config.timeoutSec)s")

        installSignalHandlers(requestID: requestID)
        if config.timeoutSec > 0 {
            // Wall clock, not uptime: "answer within N seconds" should keep
            // counting across system sleep.
            DispatchQueue.main.asyncAfter(
                wallDeadline: .now() + .seconds(config.timeoutSec)
            ) {
                finish(.timeout, requestID: requestID)
            }
        }
        NSApplication.shared.run()
        exit(70)  // unreachable: finish() is the only way out
    }

    private static var finished = false

    /// Single exit point; runs on the main queue. The guard drops duplicate
    /// events (e.g. a response racing the timeout).
    static func finish(_ outcome: Outcome, requestID: String) {
        guard !finished else { return }
        finished = true
        if outcome == .timeout { removeNotification(requestID) }
        Log.write("wait: outcome \(outcome)")
        print(jsonLine(for: outcome))
        exit(exitCode(for: outcome))
    }

    /// Registers the category (buttons + optional text-input reply) and
    /// returns its id. customDismissAction is required even with no buttons:
    /// without it, dismiss events are not delivered at all.
    private static func registerCategory(buttons: [String], reply: Bool) -> String {
        var actions: [UNNotificationAction] = buttons.enumerated().map { index, label in
            UNNotificationAction(
                identifier: buttonActionPrefix + String(index), title: label, options: [])
        }
        if reply {
            actions.append(
                UNTextInputNotificationAction(
                    identifier: replyActionID, title: "Reply", options: [],
                    textInputButtonTitle: "Send", textInputPlaceholder: ""))
        }
        let category = UNNotificationCategory(
            identifier: categoryID(buttons: buttons, reply: reply),
            actions: actions, intentIdentifiers: [],
            options: [.customDismissAction])

        // Union with the existing set: setNotificationCategories replaces
        // wholesale, and a concurrent `ntf send --wait` may have registered
        // a different config.
        let center = UNUserNotificationCenter.current()
        var existing: Set<UNNotificationCategory> = []
        let sem = DispatchSemaphore(value: 0)
        center.getNotificationCategories { cats in
            existing = cats
            sem.signal()
        }
        sem.wait()
        existing.insert(category)
        center.setNotificationCategories(existing)
        return category.identifier
    }

    private static func removeNotification(_ requestID: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])
        center.removeDeliveredNotifications(withIdentifiers: [requestID])
        // The remove APIs have no completion handler; one round-trip call
        // synchronizes before exit (same trick as Sender.remove).
        _ = Sender.deliveredNotifications()
    }

    private static var signalSources: [DispatchSourceSignal] = []

    /// SIGINT/SIGTERM (Ctrl-C, logout) clean up the still-visible
    /// notification so a stale banner doesn't outlive the waiter, then exit
    /// 128+signal with no JSON on stdout.
    private static func installSignalHandlers(requestID: String) {
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                Log.write("wait: signal \(sig), removing notification and exiting")
                removeNotification(requestID)
                exit(128 + sig)
            }
            source.resume()
            signalSources.append(source)
        }
    }
}

/// Held in a global: UNUserNotificationCenter.delegate is weak and a local
/// delegate would be released immediately (same constraint as ClickDelegate).
private let waitDelegate = WaitDelegate()

private final class WaitDelegate: NSObject, UNUserNotificationCenterDelegate {
    var requestID = ""
    var buttons: [String] = []

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void
    ) {
        DispatchQueue.main.async {
            defer { completion() }
            guard response.notification.request.identifier == self.requestID else {
                // While this process lives it holds the notification-service
                // connection, so clicks on OTHER eventful notifications land
                // here instead of relaunching the app. Handle them exactly
                // as click mode would, and keep waiting for ours.
                Log.write("wait: response for other notification, delegating")
                _ = ResponseHandler.process(response)
                return
            }
            let text = (response as? UNTextInputNotificationResponse)?.userText
            guard
                let outcome = Wait.outcome(
                    actionIdentifier: response.actionIdentifier,
                    userText: text, buttons: self.buttons)
            else {
                Log.write("wait: unknown action \(response.actionIdentifier), ignoring")
                return
            }
            Wait.finish(outcome, requestID: self.requestID)
        }
    }
}
