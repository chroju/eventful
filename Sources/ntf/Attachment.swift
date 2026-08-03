import Foundation
import UserNotifications

/// Builds the image attachment for `ntf send --image`.
///
/// The framework MOVES the attached file into its own store rather than
/// copying it, so attaching the user's path directly would delete their
/// file. Everything here works on a throwaway copy in a temp directory.
///
/// Split like Runner: `stage` is the pure validate-and-copy part that tests
/// exercise, `makeImage` wraps it in the UserNotifications type, which
/// cannot be constructed outside an app bundle.
enum Attachment {
    /// Extensions the notification UI can actually render. The framework
    /// rejects anything else at attachment-construction time anyway; the
    /// explicit check just turns that into a readable error.
    static let allowedExtensions = ["png", "jpg", "jpeg", "gif"]

    /// The framework caps image attachments at 10 MB and silently drops
    /// oversized ones, so reject them here with an explanation instead.
    static let maxBytes = 10 * 1024 * 1024

    /// Validates the image and copies it into a fresh staging directory,
    /// returning the copy's URL. The copy — not the user's file — is what
    /// gets moved into the system store.
    static func stage(path: String) throws -> URL {
        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL

        let ext = source.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw NtfError(
                "unsupported image type '\(source.lastPathComponent)'. "
                    + "Supported: \(allowedExtensions.joined(separator: ", "))")
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir), !isDir.boolValue else {
            throw NtfError("image not found: \(source.path)")
        }

        let size = (try? fm.attributesOfItem(atPath: source.path))?[.size] as? Int
        if let size, size > maxBytes {
            throw NtfError(
                "image is \(size / 1024 / 1024) MB, over the \(maxBytes / 1024 / 1024) MB limit: "
                    + source.path)
        }

        // Per-call subdirectory: the attachment keeps the original filename,
        // so a flat temp dir would collide between concurrent sends.
        let stagingDir = fm.temporaryDirectory
            .appendingPathComponent("eventful-attach-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let copy = stagingDir.appendingPathComponent(source.lastPathComponent)
        do {
            try fm.copyItem(at: source, to: copy)
        } catch {
            try? fm.removeItem(at: stagingDir)
            throw NtfError("failed to read image \(source.path): \(error.localizedDescription)")
        }
        return copy
    }

    /// Stages the image and wraps the copy in an attachment. On failure the
    /// staging directory is removed rather than left behind.
    static func makeImage(path: String) throws -> UNNotificationAttachment {
        let copy = try stage(path: path)
        do {
            return try UNNotificationAttachment(identifier: "", url: copy, options: nil)
        } catch {
            try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
            throw NtfError("failed to attach image \(path): \(error.localizedDescription)")
        }
    }
}
