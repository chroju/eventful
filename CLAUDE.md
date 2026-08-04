# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

macOS notification CLI. Product name `eventful`, binary `ntf`, bundle id
`com.github.chroju.eventful`. Swift package (swift-tools-version 6.0, language
mode v5), single dependency: swift-argument-parser (exact pin — it is an
application, so reproducibility beats auto-drift; Dependabot handles updates).

Not distributed: build from source with self-signing only. Targets the
developer's own macOS version.

## Commands

```console
$ scripts/build.sh          # swift build -c release + assemble/sign/register Eventful.app
$ scripts/test.sh           # swift test (Command Line Tools workarounds)
$ scripts/test.sh --filter SpoolTests            # one suite
$ scripts/test.sh --filter SpoolTests/gcRemovesExpiredAndCorruptKeepsLive   # one test
$ scripts/make-cert.sh      # one-time: self-signed code-signing certificate
$ ntf doctor                # runtime diagnostics: signature, permission, paths
$ ntf setup                 # interactive: permission prompt + click-path verification
```

`scripts/test.sh` exists because with Command Line Tools only (no Xcode),
Testing.framework sits outside the default search paths and the
Foundation/Testing cross-import overlay fails to resolve. Plain `swift test`
works in CI (`.github/workflows/test.yaml`, macos-latest) but may not locally.

`scripts/build.sh` must be re-run after any source change before manual
verification — the installed `~/bin/ntf` points at `build/ntf`, which execs the
binary inside the built app bundle.

## Architecture

### One-shot relaunch, two modes

No daemon. `Sources/ntf/main.swift` selects the mode by argument count:

- **post mode** (any argument): ArgumentParser subcommands in `CLI.swift` →
  `Sender.send` posts the notification, `Spool.save` persists the click action,
  process exits.
- **click mode** (no arguments): the OS relaunched `Eventful.app` because the
  user clicked. `runClickMode()` installs `ClickDelegate` and runs
  `NSApplication`, waiting for `didReceive(response:)`.

`ResponseHandler.process` is the shared click path for both click mode and
`ntf setup` (setup's own process holds the live notification-service
connection, so responses land there instead of relaunching the app).

Constraints that are easy to break and hard to debug:

- The `UNUserNotificationCenter` delegate must be assigned before
  `NSApp.run()`, and held in a global — the property is weak, and a
  function-local delegate is released by ARC immediately, silently dropping
  responses.
- Do not exit inside `didReceive`. Rapid clicks are delivered to the
  already-running instance; `ClickDelegate.scheduleExit(after:)` lingers 3s
  after each response.
- Any UserNotifications API call outside the app bundle crashes
  (`bundleProxyForCurrentProcess is nil`). Guard with `Sender.ensureBundle()`
  (post mode) or the bundle-id check in `runClickMode()` first.
- A plain symlink to the binary breaks `NSBundle` resolution. `build.sh`
  generates `build/ntf` as an exec wrapper for this reason.

### Spool (the click payload)

`userInfo` is stored in plaintext in the OS notification store, so it carries
only `{"v": 1, "ref": "<uuid>"}`. The real action lives in
`~/Library/Application Support/eventful/spool/<uuid>.json` (dir 0700, file
0600, 24h TTL). `Spool.dir` is a `var` so tests can redirect it to a temp
directory — those suites are `.serialized` for that reason.

Missing, corrupt, or expired refs resolve to `nil` and the click silently does
nothing (stale-notification protection). `Spool.gc()` runs opportunistically
from `ntf send`.

The on-disk JSON uses snake_case (`created_at`, `ttl_sec`, `timeout_sec`) via
explicit `CodingKeys`, with ISO8601 dates. `SpoolTests.decodesPlannedWireFormat`
pins this format — changing it breaks in-flight notifications from before the
change.

### `--execute` contract (settled decisions, do not "fix")

- Always `/bin/sh -c <CMD>`.
- The cwd at `ntf send` time is captured and restored at click time; a missing
  cwd falls back to home.
- **Environment variables are deliberately not saved or restored.** Click-time
  execution gets the bare GUI session environment. Commands need full paths and
  inlined env vars (`FOO=bar /opt/homebrew/bin/cmd`).
- Failure (non-zero exit, timeout, launch error) posts a follow-up
  action-less notification via `Sender.postSimple` — action-less so it cannot
  loop. Success is silent.
- `Runner.execute` is the pure process-running part with no notification side
  effects; `Runner.run` wraps it with the failure notification. Tests only
  exercise `execute`, since `run` touches UserNotifications.

### `ntf run` wrapper

`Wrap.execute` is deliberately separate from `Runner.execute` despite both
spawning processes — their requirements share nothing: run mode inherits stdio
(the child owns the tty), has no timeout, and mirrors the exit code
(128+signal for signal deaths); click mode captures stderr, kills on timeout,
and has no tty. Do not merge them.

The command is an argv array launched via `/usr/bin/env` (PATH lookup, no
shell) — shell-isms require an explicit `sh -c '...'`. `--body` is
intentionally absent from `run`: the body is always the generated status line.
The bundle/authorization precheck runs *before* the wrapped command so a
broken setup fails in seconds, not after a long build. `captureForPassthrough`
keeps the `--` terminator itself in the captured array; `validate()` strips it.

### `--image` attachment

`UNNotificationAttachment` **moves** the file into the system store instead of
copying it, so attaching the user's path directly would delete their file.
`Attachment.stage` always copies to a per-call temp directory first and the
copy is what gets attached. The per-call subdirectory matters: the attachment
keeps the original filename, so a shared staging directory would collide
between concurrent sends.

Split like Runner: `Attachment.stage` is the pure validate-and-copy part that
tests exercise; `Attachment.makeImage` wraps it in the UserNotifications type,
which cannot be constructed outside an app bundle.

Note the ordering in `Sender.send`: the authorization check runs before image
validation, so an unauthorized `ntf send --image <bad-path>` reports the
permission error, not the image error.

### Permission

`ntf setup` is the only code path that ever calls `requestAuthorization`.
`ntf send` only checks the status and errors out with instructions. `denied`
cannot be re-prompted programmatically — the user must use System Settings.

### Signing

`build.sh` prefers the `eventful-selfsigned` certificate and falls back to
ad-hoc with a warning. Ad-hoc signing changes binary identity on every rebuild,
which resets notification permission (permission is tied to bundle id +
signature). If notifications stop working right after a rebuild, this is why.

`build.sh` also runs `lsregister -f`; skipping it can mean no notifications at
all, or a stale cached icon/name.

### App icon

`icon/eventful.iconset` is the source of truth; `build.sh` runs `iconutil` on it
to produce `Contents/Resources/Eventful.icns`, so no binary `.icns` is committed.
Iconset members already use the `@2x` suffix `iconutil` requires — do not rename
them. The icns must be written before `codesign`, which seals bundle contents.

A changed icon may not show up until `lsregister -f` re-registers the bundle
(build.sh does this) and the icon cache catches up.

## Deployment target

`Package.swift` pins `.macOS("14")` as a compile/lint floor for CI (whose SDK
lags the developer's macOS). The real minimum is `LSMinimumSystemVersion` in
`Resources/Info.plist`. These two are intentionally different — do not
"reconcile" them.

## Testing scope

Unit tests cover Spool (persistence, TTL, GC, permissions), Runner (exit codes,
stderr tail, timeout kill, cwd), Wrap (exit code mirroring, signal mapping,
duration, summary formatting), Attachment (staging copy, type/size/existence
validation), and CLI parsing. Notification-facing paths
(posting, click delivery) need a signed bundle and a human click, so they are
verified with `ntf setup`, not tests.

`RunnerTests` and `WrapTests` are `.serialized`: concurrent `Process` spawns
hang indefinitely on GitHub Actions macOS runners under swift-testing's default
parallelism (not reproducible locally).

## Debugging

Click-mode processes have no tty. Everything goes to
`~/Library/Logs/eventful/ntf.log` via `Log.write`. Add logging there rather than
printing when touching the click path.

## Skills

`skills/eventful-setup/`, `skills/eventful-usage/`, and
`skills/eventful-agent-hooks/` are user-facing Agent Skills shipped by this
repo — the install/repair flow, the send-notification usage guide, and the
coding-agent (Claude Code / Gemini CLI / Codex) hooks wiring guide. Keep them
in sync when CLI flags or the setup steps change. Skill directory names must
match the frontmatter `name` (`gh skill publish --dry-run` validates this).
