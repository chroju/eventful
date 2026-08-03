import Foundation
import Testing

@testable import ntf

/// Only `stage` is covered: `makeImage` constructs a
/// UNNotificationAttachment, which requires an app bundle the test runner
/// does not have.
struct AttachmentTests {
    /// Writes `bytes` of content to a temp file with the given extension.
    private func makeFile(ext: String, bytes: Int = 8) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachtest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("shot.\(ext)")
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    @Test func stagesCopyAndLeavesOriginalInPlace() throws {
        let original = try makeFile(ext: "png")
        let staged = try Attachment.stage(path: original.path)

        // The whole point: the framework moves the staged file, so the
        // user's original must still be there afterwards.
        #expect(FileManager.default.fileExists(atPath: original.path))
        #expect(staged.path != original.path)
        #expect(try Data(contentsOf: staged) == Data(contentsOf: original))
        // The attachment shows the filename, so it must be preserved.
        #expect(staged.lastPathComponent == "shot.png")
    }

    @Test func stagesEachCallIntoItsOwnDirectory() throws {
        let original = try makeFile(ext: "png")
        let first = try Attachment.stage(path: original.path)
        let second = try Attachment.stage(path: original.path)
        // Same filename, so a shared staging dir would have collided.
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test(arguments: ["png", "jpg", "jpeg", "gif", "PNG", "JPG"])
    func acceptsSupportedExtensions(ext: String) throws {
        let file = try makeFile(ext: ext)
        #expect(throws: Never.self) { try Attachment.stage(path: file.path) }
    }

    @Test func rejectsUnsupportedExtension() throws {
        let file = try makeFile(ext: "pdf")
        #expect(throws: NtfError.self) { try Attachment.stage(path: file.path) }
    }

    @Test func rejectsMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).png")
        #expect(throws: NtfError.self) { try Attachment.stage(path: missing.path) }
    }

    @Test func rejectsDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachdir-\(UUID().uuidString).png", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(throws: NtfError.self) { try Attachment.stage(path: dir.path) }
    }

    @Test func rejectsOversizedImage() throws {
        let big = try makeFile(ext: "png", bytes: Attachment.maxBytes + 1)
        #expect(throws: NtfError.self) { try Attachment.stage(path: big.path) }
    }

    @Test func expandsTilde() throws {
        // A "~/..." path must resolve against the home directory. Without
        // expansion the literal path does not exist and stage() throws.
        let home = FileManager.default.homeDirectoryForCurrentUser
        let name = "eventful-tilde-\(UUID().uuidString).png"
        let file = home.appendingPathComponent(name)
        try Data(repeating: 0x41, count: 8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let staged = try Attachment.stage(path: "~/\(name)")
        #expect(staged.lastPathComponent == name)
    }
}
