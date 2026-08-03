# eventful

A notification CLI for macOS built on the UserNotifications framework, whose
core feature is running a command on notification click **without losing the
context of the moment the notification was posted** (the working directory is
captured at post time and restored at click time).

A modern replacement for terminal-notifier (which relies on the deprecated
NSUserNotification API and is effectively unmaintained). No CLI compatibility
with terminal-notifier is provided.

- Product name: `eventful` / binary: `ntf` / bundle id: `com.github.chroju.eventful`
- Not distributed. Build from source with self-signing only; no Homebrew.
- Targets the developer's own macOS version only (pinned in Package.swift).

## Architecture: one-shot relaunch

No daemon. One binary, two modes, selected by the presence of CLI arguments:

```
[post mode]   ntf send ... → post notification → save action to spool → exit
                                  ↓ (seconds to hours later, the user clicks)
[click mode]  the OS relaunches Eventful.app with no arguments
              → UNUserNotificationCenterDelegate.didReceive(response) fires
              → resolve the spool ref from userInfo → activate/open/execute → exit
```

The UserNotifications framework requires an app bundle, so the binary ships
inside `Eventful.app` and is invoked through a thin exec wrapper
(`build/ntf`). A plain symlink to the binary does **not** work — NSBundle
loses bundle resolution (verified on macOS 26).

## Install

```console
$ scripts/make-cert.sh   # one-time: create the self-signed certificate
$ scripts/build.sh       # build, assemble Eventful.app, sign, register
$ ln -sf "$(pwd)/build/ntf" ~/bin/ntf
$ ntf setup              # permission prompt + click-path test notification
```

`make-cert.sh` is optional but recommended: ad-hoc signing changes binary
identity on every rebuild, which can reset the notification permission. If
the script fails on your macOS version, create the certificate manually with
Keychain Access.app (Certificate Assistant > Create a Certificate..., name
`eventful-selfsigned`, type Code Signing) and re-run `scripts/build.sh`.

## Usage

```
ntf send --title <T> [--body <B>] [--subtitle <S>]
         [--sound]                # silent by default; flag enables default sound
         [--id <GROUP>]           # same id replaces the existing notification
         [--activate <BUNDLE_ID>] # click: activate an app
         [--open <URL>]           # click: open a URL
         [--execute <CMD>]        # click: run a command (see contract below)
         [--timeout <SEC>]        # execute timeout, default 30
ntf remove <GROUP_ID> | ntf remove --all
ntf list [--json]
ntf setup                         # permission prompt + click-path verification
ntf doctor                        # diagnostics
```

activate / open / execute can be combined; they run in that order.

### The `--execute` contract

- The command runs as `/bin/sh -c <CMD>`.
- The working directory from `ntf send` time is restored.
- **Environment variables are not preserved.** The click-time process runs in
  the bare GUI session environment — your `.zshrc` PATH is not there. Write
  commands with full paths, and inline any env vars:
  `FOO=bar /opt/homebrew/bin/mycmd`.
- On failure (non-zero exit or timeout) a follow-up notification appears:
  `✗ command failed (exit N)` with the last stderr line. Details go to the
  log file. Success is silent.

### Payload safety (spool)

Notification userInfo is persisted in plaintext in the OS notification store,
so it carries only a reference: `{"v": 1, "ref": "<uuid>"}`. The actual action
lives in `~/Library/Application Support/eventful/spool/<uuid>.json`
(directory 0700, files 0600) with a 24h TTL. A click on a stale notification
whose spool entry is missing or expired silently does nothing.

## Troubleshooting

Click-mode processes have no tty; everything is logged to
`~/Library/Logs/eventful/ntf.log`.

| Symptom | Likely cause |
|---|---|
| crash: bundleProxyForCurrentProcess is nil | running outside the bundle / symlinked binary (use the build/ntf wrapper) |
| no notification, no error | permission not granted or denied / lsregister missed / unsigned |
| click does nothing | spool expired / command not full-path (PATH issue) — check the log |
| notifications stopped after rebuild | ad-hoc signing changed identity → use make-cert.sh |
| stale icon or name | LaunchServices cache → `lsregister -f`, then `-kill -r -domain user` |

`ntf doctor` prints the signature, permission status, and relevant paths.
