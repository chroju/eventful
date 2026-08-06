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

## Answering the approval from the notification (`PermissionRequest`)

The hooks above only *tell* the user that Claude Code is waiting — the
answer still has to be typed in the terminal. `PermissionRequest` closes
that loop: it fires just before the approval prompt is shown and its JSON
output decides the outcome, so `ntf send --wait --buttons` can put the
answer on the notification itself.

Use `PermissionRequest`, not `PreToolUse`. `PreToolUse` fires on *every*
tool call — including ones already covered by `permissions.allow` — so it
would post a notification for every `ls`. `PermissionRequest` fires only
when an approval is actually needed.

This hook blocks the agent while the notification is up, so it needs a
script rather than a one-liner. Write it next to the notification hook and
substitute `<NTF>`:

```bash
#!/bin/bash
set -u
NTF=<NTF>
WAIT_SEC=240          # keep the settings.json timeout above this
INPUT=$(jq -c '.' 2>/dev/null) || INPUT='{}'

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""')

# Tools whose prompt is not a yes/no question cannot be answered from a
# notification. matcher has no negation, so filter here.
case "$TOOL" in AskUserQuestion) exit 0 ;; esac

SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""')
DETAIL=$(printf '%s' "$INPUT" | jq -r '
  (.tool_input // {}) | (.command // .file_path // .url // "") | tostring')
BODY=$([ -n "$DETAIL" ] && echo "${TOOL}: ${DETAIL}" || echo "${TOOL:-approval needed}")

RESULT=$("$NTF" send --title "Approve?" \
  --subtitle "$(basename "$(printf '%s' "$INPUT" | jq -r '.cwd // "-"')")" \
  --body "$BODY" --id "claude-approve-${SESSION_ID:-unknown}" --sound \
  --buttons "Allow,Deny" --wait --wait-timeout "$WAIT_SEC" 2>/dev/null) || RESULT=""

# Anything other than a button press (timeout, dismiss, body click, broken
# ntf) returns no decision, and Claude Code falls back to the terminal
# prompt. Never auto-allow.
[ "$(printf '%s' "$RESULT" | jq -r '.action // ""')" = "button" ] || exit 0

[ "$(printf '%s' "$RESULT" | jq -r '.index')" = "0" ] \
  && DECISION='{"behavior":"allow"}' \
  || DECISION='{"behavior":"deny","message":"Denied from the notification"}'

jq -nc --argjson d "$DECISION" \
  '{hookSpecificOutput:{hookEventName:"PermissionRequest",decision:$d}}'
```

Register it with a timeout longer than `WAIT_SEC`, or the hook is killed
before the user can answer:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "hooks": [
          { "type": "command", "command": "<SCRIPT>", "timeout": 300 }
        ]
      }
    ]
  }
}
```

Notes specific to this hook:

- The body must say *what* is being approved (`Bash: git push origin main`),
  otherwise the user is pressing Allow blind.
- `permissions.deny` still blocks, and `permissions.ask` entries still
  prompt, even when the hook answers `allow` — the hook cannot widen the
  configured policy.
- Buttons appear on hover over the banner and in Notification Center; the
  notification has to be reachable for the whole `WAIT_SEC` window.

Verification:

```console
$ printf '%s' '{"session_id":"t","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"git push"}}' | <SCRIPT>
# press Allow  -> {"hookSpecificOutput":{...,"decision":{"behavior":"allow"}}}
# press Deny   -> ...{"behavior":"deny",...}
$ printf '%s' '{"tool_name":"AskUserQuestion"}' | <SCRIPT>   # no notification, no output
$ printf '%s' '{"session_id":"t","cwd":"/tmp"}' | HOME=/nonexistent <SCRIPT>   # no output, exit 0
```
