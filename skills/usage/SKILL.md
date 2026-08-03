---
name: eventful-usage
description: Send macOS notifications with the ntf CLI (eventful), including click actions that activate an app, open a URL, or run a command. Use when asked to notify the user on macOS or to alert when a long-running task finishes.
---

# Sending notifications with ntf

```console
$ ntf send --title "Build finished" --body "All tests green"
```

Options:

- `--body <B>` / `--subtitle <S>` — additional text.
- `--sound` — play the default sound (silent by default).
- `--id <GROUP>` — re-sending with the same id replaces the previous
  notification instead of stacking a new one. Use for progress updates.
- `--image <PATH>` — attach an image (png/jpg/gif, up to 10MB): a thumbnail
  on the banner, full size when expanded. Useful for attaching a generated
  chart or screenshot. The file is copied, so the original is left in place.
- `--activate <BUNDLE_ID>` — clicking the notification activates the app
  (e.g. `com.mitchellh.ghostty`).
- `--open <URL>` — clicking opens the URL.
- `--execute <CMD>` — clicking runs the command. See the contract below.
- `--timeout <SEC>` — timeout for `--execute` (default 30).

activate / open / execute can be combined; they run in that order.

## The --execute contract (important)

- Runs as `/bin/sh -c <CMD>` in the directory where `ntf send` was invoked
  (cwd is captured and restored).
- **The click-time environment is the bare GUI session — no `.zshrc`, no
  custom PATH.** Always use full paths and inline env vars:

  ```console
  $ ntf send --title "Agent needs input" \
      --execute "FOO=bar /opt/homebrew/bin/herdr agent focus 3"
  ```

- Failures produce a follow-up notification (`✗ command failed (exit N)`)
  with the last stderr line; success is silent. Details:
  `~/Library/Logs/eventful/ntf.log`.
- Click actions expire after 24 hours; clicking an older notification
  silently does nothing.

## Other commands

```console
$ ntf list [--json]          # delivered notifications
$ ntf remove <GROUP_ID>      # remove one group
$ ntf remove --all           # remove everything
$ ntf doctor                 # diagnostics
```

If send fails with "not authorized", run `ntf setup` (see the
eventful-setup skill).
