<h1>
  <img src="icon/png/icon_128x128.png" alt="" width="32" height="32" align="top">
  eventful
</h1>

A notification CLI for macOS built on the UserNotifications framework, whose
core feature is running a command on notification click **without losing the
context of the moment the notification was posted** (the working directory is
captured at post time and restored at click time).

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
         [--image <PATH>]         # attach an image (png/jpg/gif, up to 10MB)
         [--activate <BUNDLE_ID>] # click: activate an app
         [--open <URL>]           # click: open a URL
         [--execute <CMD>]        # click: run a command (see contract below)
         [--timeout <SEC>]        # execute timeout, default 30
         [--wait]                 # block until interaction; print JSON result
         [--buttons <A,B,..>]     # action buttons (requires --wait)
         [--reply]                # text-input reply action (requires --wait)
         [--wait-timeout <SEC>]   # --wait timeout, default 300; 0 = forever
ntf run [options] -- <CMD...>     # run a command, notify when it finishes
ntf remove <GROUP_ID> | ntf remove --all
ntf list [--json]
ntf setup                         # permission prompt + click-path verification
ntf doctor                        # diagnostics
```

activate / open / execute can be combined; they run in that order.

### `ntf run`

Wraps a foreground command and posts a notification when it finishes, with
success/failure and duration in the body (`✓ done · 12s` / `✗ exit 2 · 1m 03s`):

```console
$ ntf run swift build
$ ntf run --sound --activate com.mitchellh.ghostty -- make test
```

- stdio is inherited (interactive commands work) and there is no timeout;
  `ntf run` exits with the wrapped command's exit code.
- The command is an argv array resolved via `/usr/bin/env` — no shell. For
  shell-isms, wrap explicitly: `ntf run sh -c 'a && b'`.
- All `send` options except `--body` pass through (the body is the status
  line). `--title` defaults to the command name.
- Bundle and permission are checked *before* the command runs, so a
  misconfigured setup fails immediately instead of after a long build.

### Synchronous mode (`--wait`)

Blocks until the user interacts with the notification, then prints the
result as one line of JSON to stdout — a human-in-the-loop primitive for
agents (e.g. answer an approval prompt from the notification banner):

```console
$ result=$(ntf send --wait --title "Deploy to prod?" --buttons "Approve,Deny")
$ echo "$result"
{"action":"button","button":"Approve","index":0}
```

| Interaction | stdout | exit code |
|---|---|---|
| body clicked | `{"action":"clicked"}` | 0 |
| button pressed | `{"action":"button","button":"<label>","index":<n>}` | 0 |
| reply sent (`--reply`) | `{"action":"reply","text":"<input>"}` | 0 |
| dismissed (the X button) | `{"action":"dismissed"}` | 2 |
| timeout (default 300s) | `{"action":"timeout"}` | 124 |

- `--wait` excludes `--activate`/`--open`/`--execute`: the caller consumes
  the result instead of the click running an action.
- On timeout the notification is removed. Ctrl-C / SIGTERM also remove it
  and exit with 128+signal, no JSON.
- Buttons show on hover over the banner (under "Options" with a reply
  action), and in Notification Center.
- If the waiting process dies while the notification is still visible
  (logout, `kill -9`), the leftover notification is inert: any interaction
  with it silently does nothing.

### `--image`

Shown as a thumbnail on the banner and full size when the notification is
expanded. png / jpg / gif only, up to 10MB; local paths only.

The framework moves an attached file into its own store rather than copying
it, so `ntf` attaches a temporary copy — the file you pass is left untouched.

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

## Development

```console
$ scripts/test.sh    # swift test (with Command Line Tools workarounds)
```

Unit tests cover the spool (persistence, TTL, GC, permissions), the runner
(exit codes, stderr capture, timeout kill, cwd handling), and CLI parsing.
The notification-facing paths (post, click delivery) require a signed app
bundle and a human click, so they are verified with `ntf setup` instead.

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
