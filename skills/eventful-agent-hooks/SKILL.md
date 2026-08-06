---
name: eventful-agent-hooks
description: Wires coding agents' hook/notify mechanisms (Claude Code, Gemini CLI, Codex CLI) to native macOS notifications via the ntf CLI, notifying the user when an agent needs approval/input or finishes responding. Use when the user asks to set up desktop notifications for a coding agent, or to be alerted when an agent is waiting.
license: MIT
---

# Coding-agent notifications via ntf

Wire an agent's hook/notify mechanism to `ntf send` so the user gets a native
macOS banner when the agent needs attention or finishes. Shared design first,
then the per-agent wiring:

- **Claude Code** — Notification + Stop hooks (stdin JSON), plus an optional
  `PermissionRequest` hook that answers the approval from the notification
  itself: see [claude-code.md](claude-code.md)
- **Gemini CLI** — Notification + AfterAgent hooks (stdin JSON):
  see [gemini-cli.md](gemini-cli.md)
- **Codex CLI** — `notify` program (JSON as final argv; turn-complete only):
  see [codex.md](codex.md)

## Preflight (all agents)

Resolve the absolute ntf path and verify it works — hook commands must not
rely on PATH:

```console
$ NTF=$(command -v ntf || echo "$HOME/bin/ntf")
$ "$NTF" doctor
$ command -v jq   # required by the hook commands; brew install jq if missing
```

If doctor reports problems, run the eventful-setup skill first.

## Click action (all agents)

Clicking the notification should focus the user's terminal: use
`--activate <bundle-id>`. Detect via `$TERM_PROGRAM` or ask the user, then
confirm the id with `osascript -e 'id of app "<Name>"'`. Common ids:

| Terminal | Bundle id |
|---|---|
| Ghostty | `com.mitchellh.ghostty` |
| iTerm2 | `com.googlecode.iterm2` |
| Terminal.app | `com.apple.Terminal` |
| WezTerm | `com.github.wez.wezterm` |
| kitty | `net.kovidgoyal.kitty` |
| VS Code | `com.microsoft.VSCode` |

## Shared design rules (all agents)

Apply these to every hook command; the per-agent files follow them:

- **Session replacement**: use `--id <agent>-<session id>` so later events
  from one session replace the earlier banner instead of stacking, and
  sessions from different agents never collide.
- **Parallel-session identification**: subtitle = basename of the session's
  cwd, so the user can tell *which* project is asking.
- **Sound policy**: `--sound` only on needs-attention events; per-response
  completion events stay silent so they are not chatty.
- **Failure isolation**: a broken ntf install must never disrupt the agent.
  End every hook command with `>/dev/null 2>&1; exit 0` (a non-zero exit or
  stray output means block/retry/warning in these agents' hook protocols),
  and set a short hook timeout where the agent supports one.
- **Merge, don't clobber**: append to existing hook config; skip entries
  that already contain `ntf send`.
- **Verify without waiting for a real event**: pipe (or pass) a fake payload
  through the exact configured command string, check `ntf list`, then
  `ntf remove` the test id. Rerun with the ntf path replaced by a
  nonexistent one and confirm the exit status is still 0.

After wiring, tell the user: agents read hook config at session start, so
already-running sessions won't notify — new sessions will.
