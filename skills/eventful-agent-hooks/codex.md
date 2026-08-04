# Codex CLI wiring

Codex has a single external-notify mechanism: the `notify` program in
`~/.codex/config.toml`. It fires on **turn completion only** — there is no
approval/permission event, so Codex gets a completion notification but no
"needs attention" one.

Unlike Claude Code and Gemini CLI, the payload is **not stdin**: Codex
appends one JSON string as the final argv argument. With `sh -c`, that
argument lands in `$1`. The JSON uses kebab-case keys:

```json
{"type":"agent-turn-complete","thread-id":"...","turn-id":"...","cwd":"...","input-messages":["..."],"last-assistant-message":"..."}
```

Add to `~/.codex/config.toml` (top-level key). Substitute `<NTF>` and
`<BUNDLE_ID>`:

```toml
notify = ["/bin/sh", "-c", "p=$1; <NTF> send --title 'Codex' --subtitle \"$(basename \"$(printf %s \"$p\" | jq -r '.cwd // \"-\"')\")\" --body \"$(printf %s \"$p\" | jq -r '(.[\"last-assistant-message\"] // \"Turn complete\") | .[0:120]')\" --id \"codex-$(printf %s \"$p\" | jq -r '.[\"thread-id\"] // \"default\"')\" --activate <BUNDLE_ID> >/dev/null 2>&1; exit 0", "ntf-notify"]
```

Codex-specific notes:

- The trailing `"ntf-notify"` is `$0` for `sh -c`; the JSON Codex appends
  after it becomes `$1`.
- `--id codex-<thread-id>` gives the same per-session replacement as the
  other agents.
- The body shows the first 120 chars of the last assistant message, so the
  banner says *what* finished, not just that something did.
- No `--sound`: this is a completion event (shared sound policy). Add it if
  the user wants audible completions.
- There is no per-hook timeout setting; the `; exit 0` failure isolation
  still applies.

Verification — pass the payload as an argument instead of piping:

```console
$ sh -c '<the script part between the quotes>' ntf-notify '{"type":"agent-turn-complete","thread-id":"test","cwd":"/tmp","last-assistant-message":"hook test"}'
$ ntf list        # expect: codex-test  Codex  hook test
$ ntf remove codex-test
```
