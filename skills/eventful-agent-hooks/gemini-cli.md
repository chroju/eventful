# Gemini CLI wiring

Two hooks cover the agent-waiting workflow:

- **Notification** — fires on system alerts (currently
  `notification_type: "ToolPermission"`, i.e. the agent needs permission).
- **AfterAgent** — fires once per turn after the final response (the
  turn-complete signal; there is no separate `Stop` event).

Hook input arrives as JSON on stdin; every event carries `session_id` and
`cwd`, and Notification adds `message`.

Merge into `~/.gemini/settings.json`. Substitute `<NTF>` and `<BUNDLE_ID>`:

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "name": "ntf-notify",
            "command": "p=$(cat); <NTF> send --title 'Gemini CLI' --subtitle \"$(basename \"$(printf %s \"$p\" | jq -r '.cwd // \"-\"')\")\" --body \"$(printf %s \"$p\" | jq -r '.message // \"Waiting for input\"')\" --id \"gemini-$(printf %s \"$p\" | jq -r .session_id)\" --sound --activate <BUNDLE_ID> >/dev/null 2>&1; exit 0",
            "timeout": 10000
          }
        ]
      }
    ],
    "AfterAgent": [
      {
        "hooks": [
          {
            "type": "command",
            "name": "ntf-turn-complete",
            "command": "p=$(cat); <NTF> send --title 'Gemini CLI' --subtitle \"$(basename \"$(printf %s \"$p\" | jq -r '.cwd // \"-\"')\")\" --body 'Finished' --id \"gemini-$(printf %s \"$p\" | jq -r .session_id)\" --activate <BUNDLE_ID> >/dev/null 2>&1; exit 0",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
```

Gemini-specific notes — the shared failure-isolation rules are *load-bearing*
here, not just hygiene:

- `"timeout"` is in **milliseconds** (default 60000), unlike Claude Code.
- An `AfterAgent` hook exiting 2 **rejects the response and forces a retry
  turn**; other non-zero exits surface a warning. `; exit 0` prevents both.
- Gemini parses hook stdout as JSON and requires silence otherwise —
  `>/dev/null 2>&1` keeps ntf's output from being misread as a hook
  directive.

Verification (per the shared rules):

```console
$ printf '%s' '{"session_id":"test","cwd":"/tmp","message":"hook test"}' | sh -c '<the Notification command>'
$ ntf list        # expect: gemini-test  Gemini CLI  hook test
$ ntf remove gemini-test
```
