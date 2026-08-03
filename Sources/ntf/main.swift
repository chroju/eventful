import Foundation

// Mode selection: any CLI argument means post mode (subcommands handled by
// ArgumentParser). No arguments means the OS relaunched us for a notification
// click — enter click mode and wait for the response delivery.
if CommandLine.arguments.count > 1 {
    Ntf.main()
} else {
    runClickMode()
}
