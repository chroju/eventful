import Foundation
import UserNotifications

/// `ntf setup`: idempotent, interactive first-run flow.
/// Assumes the binary already runs from inside a built Eventful.app
/// (building/signing is scripts/build.sh's job). Requests notification
/// permission — the only place that ever prompts — then fires a test
/// notification whose click touches a marker file, and waits for it.
enum Setup {
    static let certName = "eventful-selfsigned"

    static func run() throws {
        try Sender.ensureBundle()

        // 1. Certificate check (informational: build.sh falls back to ad-hoc)
        let certFound = Doctor.shell(
            "/usr/bin/security", ["find-certificate", "-c", certName]
        ).contains("keychain")
        if certFound {
            print("[1/4] certificate '\(certName)': found")
        } else {
            print("[1/4] certificate '\(certName)': NOT found")
            print("      Ad-hoc signing changes binary identity on every rebuild and can")
            print("      destabilize notification permission. Run scripts/make-cert.sh,")
            print("      then scripts/build.sh again.")
        }

        // 2. Signature summary (-dvv: Authority= lines only appear at verbosity 2)
        let sign = Doctor.shell("/usr/bin/codesign", ["-dvv", Bundle.main.bundlePath])
        let authority = sign.split(separator: "\n")
            .first { $0.hasPrefix("Authority=") } ?? "Authority=(ad-hoc or unsigned)"
        print("[2/4] signature: \(authority)")

        // 3. Authorization prompt (setup is the only path that prompts)
        let status = Sender.currentSettings().authorizationStatus
        switch status {
        case .authorized, .provisional:
            print("[3/4] notification permission: already granted")
        case .denied:
            throw NtfError(
                "notification permission is denied and cannot be re-prompted. "
                    + "Enable manually: System Settings > Notifications > Eventful")
        case .notDetermined:
            print("[3/4] requesting notification permission — check for the prompt...")
            var granted = false
            var reqError: Error?
            let sem = DispatchSemaphore(value: 0)
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound]
            ) { ok, error in
                granted = ok
                reqError = error
                sem.signal()
            }
            sem.wait()
            if let reqError {
                throw NtfError("authorization request failed: \(reqError.localizedDescription)")
            }
            guard granted else {
                throw NtfError(
                    "permission was not granted. To change your mind later: "
                        + "System Settings > Notifications > Eventful")
            }
            print("      granted")
        @unknown default:
            throw NtfError("unknown authorization status")
        }

        // 4. Test notification: click runs touch on a marker file, proving the
        //    whole click → spool → Runner path works.
        let marker = NSTemporaryDirectory() + "eventful-click-ok"
        try? FileManager.default.removeItem(atPath: marker)
        try Sender.send(
            title: "Eventful setup complete",
            body: "Click me to test the click-to-execute path",
            subtitle: nil,
            sound: false,
            id: "eventful-setup-test",
            activate: nil,
            open: nil,
            execute: "/usr/bin/touch \(marker)",
            timeoutSec: 30)
        print("[4/4] test notification posted. Click it within 60 seconds...")

        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: marker) {
                try? FileManager.default.removeItem(atPath: marker)
                print("")
                print("OK: click path verified. Setup complete.")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        print("")
        print("NOTE: the notification was not clicked within 60s.")
        print("You can still verify later: click it and check that")
        print("\(marker) appears (see also \(Log.file.path)).")
    }
}
