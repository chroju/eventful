# Claude Code wiring

Two hooks cover the agent-waiting workflow:

- **Notification** — fires when Claude Code needs permission or input.
- **Stop** — fires when Claude Code finishes responding.

Hook input arrives as JSON on stdin (`session_id`, `cwd`, `message`);
commands run under `sh`, so they are POSIX (no `<<<`).

Merge into `~/.claude/settings.json` (create the file if missing; use a
project's `.claude/settings.json` instead if the user wants this
per-project). Substitute `<NTF>` and `<BUNDLE_ID>`:

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "p=$(cat); <NTF> send --title 'Claude Code' --subtitle \"$(basename \"$(printf %s \"$p\" | jq -r '.cwd // \"-\"')\")\" --body \"$(printf %s \"$p\" | jq -r '.message // \"Waiting for input\"')\" --id \"claude-$(printf %s \"$p\" | jq -r .session_id)\" --sound --activate <BUNDLE_ID> >/dev/null 2>&1; exit 0",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "p=$(cat); <NTF> send --title 'Claude Code' --subtitle \"$(basename \"$(printf %s \"$p\" | jq -r '.cwd // \"-\"')\")\" --body 'Finished' --id \"claude-$(printf %s \"$p\" | jq -r .session_id)\" --activate <BUNDLE_ID> >/dev/null 2>&1; exit 0",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Claude Code-specific notes:

- `"timeout"` is in **seconds**; 10 cuts a hung ntf off well before the 60s
  default. A hook exiting 2 would block Claude Code — the `; exit 0` from the
  shared rules prevents that.
- Hooks can be reviewed in-session with `/hooks`.
- If the per-response Stop notification is too chatty, drop the `Stop` entry
  and keep only `Notification`.

Verification (per the shared rules):

```console
$ printf '%s' '{"session_id":"test","cwd":"/tmp","message":"hook test"}' | sh -c '<the Notification command>'
$ ntf list        # expect: claude-test  Claude Code  hook test
$ ntf remove claude-test
```
