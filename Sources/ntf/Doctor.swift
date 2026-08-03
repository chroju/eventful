import Foundation
import UserNotifications

enum Doctor {
    static func run() {
        print("eventful doctor")
        print("===============")

        // Bundle / executable resolution
        let argv0 = CommandLine.arguments[0]
        let resolved = (try? FileManager.default.destinationOfSymbolicLink(atPath: argv0))
            .map { " -> \($0)" } ?? ""
        print("invoked as:      \(argv0)\(resolved)")
        print("executable:      \(Bundle.main.executablePath ?? "nil")")
        print("bundle path:     \(Bundle.main.bundlePath)")
        print("bundle id:       \(Bundle.main.bundleIdentifier ?? "nil")")

        let inBundle = Bundle.main.bundleIdentifier == Sender.bundleID
        if !inBundle {
            print("STATUS:          NG — not running inside Eventful.app.")
            print("                 Run scripts/build.sh and invoke via the build/ntf wrapper")
            print("                 (a plain symlink to the binary breaks bundle resolution)")
        }

        // Code signature summary
        print("")
        print("codesign:")
        let target = inBundle ? Bundle.main.bundlePath : argv0
        let sign = shell("/usr/bin/codesign", ["-dv", target])
        for line in sign.split(separator: "\n")
        where line.hasPrefix("Identifier=") || line.hasPrefix("Authority=")
            || line.hasPrefix("Signature=") || line.hasPrefix("TeamIdentifier=")
        {
            print("  \(line)")
        }
        if sign.isEmpty {
            print("  (no signature information)")
        }

        // Authorization status
        print("")
        if inBundle {
            let status = Sender.currentSettings().authorizationStatus
            print("authorization:   \(describe(status))")
            if status == .denied {
                print("                 Enable manually: System Settings > Notifications > Eventful")
            } else if status == .notDetermined {
                print("                 Run `ntf setup` to request permission")
            }
        } else {
            print("authorization:   (skipped — not in bundle)")
        }

        // Paths
        print("")
        print("spool dir:       \(Spool.dir.path)")
        print("expired spools:  \(Spool.expiredCount())")
        print("log file:        \(Log.file.path)")
        print("")
        print("execute contract: commands run via /bin/sh -c in the bare GUI session")
        print("environment. Use full paths; inline env vars as `FOO=bar /path/to/cmd`.")
    }

    static func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    /// Runs a helper binary and returns combined stdout+stderr.
    static func shell(_ path: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        guard (try? task.run()) != nil else { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
