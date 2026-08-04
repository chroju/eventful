---
name: eventful-claude-code-hooks
description: Wire Claude Code hooks to native macOS notifications via the ntf CLI, so the user is notified when Claude Code needs approval/input or finishes responding. Use when asked to set up Claude Code notifications, or to be alerted when an agent is waiting.
---

# Claude Code notifications via ntf

Two hooks cover the agent-waiting workflow:

- **Notification** — fires when Claude Code needs permission or input.
- **Stop** — fires when Claude Code finishes responding.

Both send through `ntf` with the same `--id claude-<session_id>`, so within a
session a "needs approval" banner is *replaced* by the later "finished" one
instead of stacking.

## Steps

1. **Preflight.** Resolve the absolute ntf path and verify it works — hook
   commands must not rely on PATH:

   ```console
   $ NTF=$(command -v ntf || echo "$HOME/bin/ntf")
   $ "$NTF" doctor
   $ command -v jq   # required by the hook commands; brew install jq if missing
   ```

   If doctor reports problems, run the eventful-setup skill first.

2. **Pick the click action.** Clicking the notification should focus the
   user's terminal: use `--activate <bundle-id>`. Detect via `$TERM_PROGRAM`
   or ask the user, then confirm the id with
   `osascript -e 'id of app "<Name>"'`. Common ids:

   | Terminal | Bundle id |
   |---|---|
   | Ghostty | `com.mitchellh.ghostty` |
   | iTerm2 | `com.googlecode.iterm2` |
   | Terminal.app | `com.apple.Terminal` |
   | WezTerm | `com.github.wez.wezterm` |
   | kitty | `net.kovidgoyal.kitty` |
   | VS Code | `com.microsoft.VSCode` |

3. **Merge the hooks into `~/.claude/settings.json`** (create the file if
   missing; use a project's `.claude/settings.json` instead if the user wants
   this per-project). Do not clobber existing hooks — append to any existing
   `Notification`/`Stop` arrays, and skip entries that already contain
   `ntf send`. Substitute `<NTF>` and `<BUNDLE_ID>`:

   ```json
   {
     "hooks": {
       "Notification": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "p=$(cat); <NTF> send --title 'Claude Code' --subtitle \"$(basename \"$(printf %s \"$p\" | jq -r '.cwd // \"-\"')\")\" --body \"$(printf %s \"$p\" | jq -r '.message // \"Waiting for input\"')\" --id \"claude-$(printf %s \"$p\" | jq -r .session_id)\" --sound --activate <BUNDLE_ID> || true"
             }
           ]
         }
       ],
       "Stop": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "p=$(cat); <NTF> send --title 'Claude Code' --subtitle \"$(basename \"$(printf %s \"$p\" | jq -r '.cwd // \"-\"')\")\" --body 'Finished' --id \"claude-$(printf %s \"$p\" | jq -r .session_id)\" --sound --activate <BUNDLE_ID> || true"
             }
           ]
         }
       ]
     }
   }
   ```

   Notes on the shape of these commands:

   - Hook input arrives as JSON on stdin; commands run under `sh`, so they
     are POSIX (no `<<<`).
   - The trailing `|| true` is deliberate: a broken ntf install must never
     block or spam Claude Code with hook errors.
   - The subtitle is the basename of the session's cwd, which tells the user
     *which* project is asking when several sessions run in parallel.

4. **Verify without waiting for a real event** — pipe a fake payload through
   the exact command string (replace placeholders first):

   ```console
   $ printf '%s' '{"session_id":"test","cwd":"/tmp","message":"hook test"}' | sh -c '<the Notification command>'
   $ ntf list        # expect: claude-test  Claude Code  hook test
   $ ntf remove claude-test
   ```

   A banner should have appeared; clicking it should focus the terminal.

5. **Tell the user:** hook config is snapshotted at session start, so already
   running Claude Code sessions won't notify — new sessions will. Hooks can
   be reviewed in-session with `/hooks`. If the per-response Stop
   notification is too chatty, remove the `Stop` entry and keep only
   `Notification`.
