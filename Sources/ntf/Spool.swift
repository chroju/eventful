import Foundation

/// Action payload to run on notification click. userInfo carries only a
/// reference (ref); the payload lives in this spool file so it never sits
/// in plaintext inside the OS notification store.
struct SpoolAction: Codable {
    struct Execute: Codable {
        var cmd: String
        var cwd: String
    }

    var v: Int
    var createdAt: Date
    var ttlSec: Int
    var activate: String?
    var open: String?
    var execute: Execute?
    var timeoutSec: Int

    enum CodingKeys: String, CodingKey {
        case v
        case createdAt = "created_at"
        case ttlSec = "ttl_sec"
        case activate
        case open
        case execute
        case timeoutSec = "timeout_sec"
    }

    var isExpired: Bool {
        Date() > createdAt.addingTimeInterval(TimeInterval(ttlSec))
    }
}

enum Spool {
    static let defaultTTLSec = 86_400

    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/eventful/spool", isDirectory: true)

    private static func fileURL(ref: String) -> URL {
        dir.appendingPathComponent("\(ref).json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Persists an action and returns the ref to embed in userInfo.
    /// Directory 0700, file 0600.
    static func save(_ action: SpoolAction) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let ref = UUID().uuidString
        let url = fileURL(ref: ref)
        try encoder.encode(action).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return ref
    }

    /// Resolves a ref. Missing, corrupt, or expired files yield nil; the
    /// caller silently does nothing (protects against stale-notification clicks).
    static func resolve(ref: String) -> SpoolAction? {
        guard let data = try? Data(contentsOf: fileURL(ref: ref)),
              let action = try? decoder.decode(SpoolAction.self, from: data)
        else { return nil }
        guard !action.isExpired else { return nil }
        return action
    }

    static func delete(ref: String) {
        try? FileManager.default.removeItem(at: fileURL(ref: ref))
    }

    /// Removes expired or corrupt spool files. Called opportunistically
    /// from `ntf send`.
    static func gc() {
        for url in listFiles() {
            guard let data = try? Data(contentsOf: url),
                  let action = try? decoder.decode(SpoolAction.self, from: data)
            else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            if action.isExpired {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// For doctor: number of expired spool entries.
    static func expiredCount() -> Int {
        listFiles().reduce(0) { count, url in
            guard let data = try? Data(contentsOf: url),
                  let action = try? decoder.decode(SpoolAction.self, from: data)
            else { return count + 1 }
            return action.isExpired ? count + 1 : count
        }
    }

    private static func listFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
    }
}
