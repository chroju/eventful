import Foundation
import Testing

@testable import ntf

/// Serialized: these tests redirect the shared Spool.dir to a temp directory.
@Suite(.serialized)
struct SpoolTests {
    private func useTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntf-spool-tests-\(UUID().uuidString)", isDirectory: true)
        Spool.dir = dir
        return dir
    }

    private func makeAction(
        ttlSec: Int = 3600,
        createdAt: Date = Date()
    ) -> SpoolAction {
        SpoolAction(
            v: 1,
            createdAt: createdAt,
            ttlSec: ttlSec,
            activate: "com.example.app",
            open: "https://example.com",
            execute: .init(cmd: "/usr/bin/true", cwd: "/tmp"),
            timeoutSec: 30)
    }

    @Test func saveAndResolveRoundtrip() throws {
        _ = try useTempDir()
        let ref = try Spool.save(makeAction())

        let resolved = try #require(Spool.resolve(ref: ref))
        #expect(resolved.v == 1)
        #expect(resolved.activate == "com.example.app")
        #expect(resolved.open == "https://example.com")
        #expect(resolved.execute?.cmd == "/usr/bin/true")
        #expect(resolved.execute?.cwd == "/tmp")
        #expect(resolved.timeoutSec == 30)
    }

    @Test func filePermissionsAreRestrictive() throws {
        let dir = try useTempDir()
        let ref = try Spool.save(makeAction())

        let fm = FileManager.default
        let dirPerms = try fm.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        let filePerms = try fm.attributesOfItem(
            atPath: dir.appendingPathComponent("\(ref).json").path)[.posixPermissions] as? Int
        #expect(dirPerms == 0o700)
        #expect(filePerms == 0o600)
    }

    @Test func missingRefResolvesToNil() throws {
        _ = try useTempDir()
        #expect(Spool.resolve(ref: UUID().uuidString) == nil)
    }

    @Test func expiredEntryResolvesToNil() throws {
        _ = try useTempDir()
        let ref = try Spool.save(
            makeAction(ttlSec: 60, createdAt: Date().addingTimeInterval(-120)))
        #expect(Spool.resolve(ref: ref) == nil)
    }

    @Test func deleteRemovesEntry() throws {
        _ = try useTempDir()
        let ref = try Spool.save(makeAction())
        Spool.delete(ref: ref)
        #expect(Spool.resolve(ref: ref) == nil)
    }

    @Test func gcRemovesExpiredAndCorruptKeepsLive() throws {
        let dir = try useTempDir()
        let liveRef = try Spool.save(makeAction())
        let expiredRef = try Spool.save(
            makeAction(ttlSec: 60, createdAt: Date().addingTimeInterval(-120)))
        let corruptURL = dir.appendingPathComponent("\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: corruptURL)

        #expect(Spool.expiredCount() == 2)  // expired + corrupt
        Spool.gc()

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(remaining == ["\(liveRef).json"])
        #expect(Spool.resolve(ref: expiredRef) == nil)
    }

    @Test func decodesPlannedWireFormat() throws {
        let json = """
            {
              "v": 1,
              "created_at": "2026-08-03T12:00:00+09:00",
              "ttl_sec": 86400,
              "activate": "com.mitchellh.ghostty",
              "open": null,
              "execute": { "cmd": "/opt/homebrew/bin/herdr agent focus 3", "cwd": "/tmp/work" },
              "timeout_sec": 30
            }
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let action = try decoder.decode(SpoolAction.self, from: Data(json.utf8))
        #expect(action.activate == "com.mitchellh.ghostty")
        #expect(action.open == nil)
        #expect(action.execute?.cwd == "/tmp/work")
        #expect(action.ttlSec == 86400)
    }
}
