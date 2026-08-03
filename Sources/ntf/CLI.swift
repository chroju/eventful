import ArgumentParser
import Foundation

struct Ntf: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ntf",
        abstract: "Notification CLI for macOS with click-to-execute support.",
        version: "0.1.0",
        subcommands: [Send.self, Remove.self, List.self, SetupCommand.self, DoctorCommand.self]
    )
}

struct Send: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Post a notification.")

    @Option(help: "Notification title.")
    var title: String

    @Option(help: "Notification body.")
    var body: String?

    @Option(help: "Notification subtitle.")
    var subtitle: String?

    @Flag(help: "Play the default sound (silent by default).")
    var sound = false

    @Option(help: "Group id. Re-sending with the same id replaces the existing notification.")
    var id: String?

    @Option(help: """
        Path to an image (png/jpg/gif, up to 10MB) to attach: a thumbnail on \
        the banner, full size when expanded. The file is copied, so the \
        original is left untouched.
        """)
    var image: String?

    @Option(help: "Bundle id of an app to activate on click.")
    var activate: String?

    @Option(help: "URL to open on click.")
    var open: String?

    @Option(help: """
        Command to run on click via /bin/sh -c, in the directory where \
        `ntf send` was invoked. The click-time environment is the bare GUI \
        session: use full paths and inline env vars (FOO=bar /path/to/cmd).
        """)
    var execute: String?

    @Option(help: "Timeout in seconds for --execute.")
    var timeout: Int = 30

    func run() throws {
        try Sender.send(
            title: title, body: body, subtitle: subtitle, sound: sound,
            id: id, activate: activate, open: open, execute: execute,
            timeoutSec: timeout, image: image)
    }
}

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove a delivered/pending notification by group id.")

    @Argument(help: "Group id to remove.")
    var groupID: String?

    @Flag(help: "Remove all notifications from eventful.")
    var all = false

    func validate() throws {
        if (groupID == nil) == !all {
            throw ValidationError("specify either <group-id> or --all")
        }
    }

    func run() throws {
        try Sender.remove(id: groupID, all: all)
    }
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List delivered notifications.")

    @Flag(help: "Output as JSON.")
    var json = false

    func run() throws {
        try Sender.list(json: json)
    }
}

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Request notification permission and verify the click path.")

    func run() throws {
        try Setup.run()
    }
}

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose signing, permission, and path issues.")

    func run() throws {
        Doctor.run()
    }
}
