import Foundation

/// Click-mode processes have no tty, so all debugging and troubleshooting
/// relies on this file log.
enum Log {
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/eventful", isDirectory: true)
    static let file = dir.appendingPathComponent("ntf.log")

    static func write(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let pid = ProcessInfo.processInfo.processIdentifier
        let line = "\(ts) [\(pid)] \(message)\n"
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            if !fm.fileExists(atPath: file.path) {
                fm.createFile(atPath: file.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            FileHandle.standardError.write(Data("eventful: log write failed: \(error)\n".utf8))
        }
    }
}
