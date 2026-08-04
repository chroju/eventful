import ArgumentParser
import Foundation

struct Ntf: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ntf",
        abstract: "Notification CLI for macOS with click-to-execute support.",
        version: "0.1.0",
        subcommands: [
            Send.self, Run.self, Remove.self, List.self, SetupCommand.self,
            DoctorCommand.self,
        ]
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

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a command and post a notification when it finishes.",
        discussion: """
            The command runs with inherited stdio and no timeout; ntf exits \
            with the command's exit code. The notification body reports \
            success/failure and duration. Options for ntf must come before \
            the command (everything after the first non-option is the \
            command; use -- to be explicit).
            """)

    @Option(help: "Notification title. Defaults to the command name.")
    var title: String?

    @Option(help: "Notification subtitle.")
    var subtitle: String?

    @Flag(help: "Play the default sound (silent by default).")
    var sound = false

    @Option(help: "Group id. Re-sending with the same id replaces the existing notification.")
    var id: String?

    @Option(help: "Path to an image (png/jpg/gif, up to 10MB) to attach.")
    var image: String?

    @Option(help: "Bundle id of an app to activate on click.")
    var activate: String?

    @Option(help: "URL to open on click.")
    var open: String?

    @Option(help: "Command to run on click via /bin/sh -c (see `ntf send --help`).")
    var execute: String?

    @Option(help: "Timeout in seconds for --execute.")
    var timeout: Int = 30

    @Argument(
        parsing: .captureForPassthrough,
        help: "The command to run (argv; PATH lookup via /usr/bin/env).")
    var command: [String] = []

    mutating func validate() throws {
        // captureForPassthrough keeps the -- terminator itself in the array.
        if command.first == "--" { command.removeFirst() }
        if command.isEmpty { throw ValidationError("no command given") }
    }

    func run() throws {
        // Fail fast: check bundle + permission BEFORE the (possibly long)
        // command, not after — discovering a permission problem only when
        // the completion notification fails is the worst case.
        try Sender.ensureBundle()
        try Sender.ensureAuthorized()

        let result = Wrap.execute(command: command)
        if let launchError = result.launchErrorDescription {
            throw NtfError("failed to launch \(command[0]): \(launchError)")
        }

        try Sender.send(
            title: title ?? (command[0] as NSString).lastPathComponent,
            body: Wrap.summary(result), subtitle: subtitle, sound: sound,
            id: id, activate: activate, open: open, execute: execute,
            timeoutSec: timeout, image: image)

        throw ExitCode(result.exitCode)
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
