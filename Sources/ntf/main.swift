import Foundation

// Line-buffer stdout even when redirected, so progress messages (e.g. from
// `ntf setup`) appear as they happen instead of all at exit.
setvbuf(stdout, nil, _IOLBF, 0)

// Mode selection: any CLI argument means post mode (subcommands handled by
// ArgumentParser). No arguments means the OS relaunched us for a notification
// click — enter click mode and wait for the response delivery.
if CommandLine.arguments.count > 1 {
    Ntf.main()
} else {
    runClickMode()
}
