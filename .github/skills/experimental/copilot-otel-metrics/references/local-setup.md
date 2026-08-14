---
description: "Procedure for enabling GitHub Copilot's OpenTelemetry export in the user's global VS Code settings, including the diff-and-confirm write and the manual alternative"
---

# Local setup: enable Copilot OTel export

## Intended Use

Read this before writing or advising on any `github.copilot.chat.otel.*` setting. It carries the settings inventory, the platform-specific file paths, the profile resolution pitfall that makes a careless write a silent no-op, the per-key upsert contract, and the paste-it-yourself alternative for a user who declines the assisted write.

## The settings

Seven settings exist in the build verified for this revision. Three of them turn export on; the remaining four tune it. Enumerate the live set before quoting this table, because it describes one build.

Verified against the GitHub Copilot Chat extension manifest, version 0.52.0, reading `contributes.configuration[].properties`.

| Setting                                           | Type    | Default                   | Sets what                                                              |
|---------------------------------------------------|---------|---------------------------|------------------------------------------------------------------------|
| `github.copilot.chat.otel.enabled`                | boolean | `false`                   | Master switch for trace, metric, and log emission                      |
| `github.copilot.chat.otel.exporterType`           | string  | `"otlp-http"`             | One of `otlp-grpc`, `otlp-http`, `console`, `file`                     |
| `github.copilot.chat.otel.otlpEndpoint`           | string  | `"http://localhost:4318"` | Where the data goes                                                    |
| `github.copilot.chat.otel.captureContent`         | boolean | `false`                   | Prompts, responses, system instructions, and tool definitions on spans |
| `github.copilot.chat.otel.maxAttributeSizeChars`  | integer | `0`                       | Truncation limit in characters; `0` disables truncation                |
| `github.copilot.chat.otel.outfile`                | string  | `""`                      | JSON-lines output path; setting it forces the `file` exporter          |
| `github.copilot.chat.otel.dbSpanExporter.enabled` | boolean | `false`                   | Local SQLite span exporter; turning it on turns OTel on                |

An earlier revision of this reference listed eleven settings, adding `protocol`, `headers`, `serviceName`, and `resourceAttributes`, verified against extension build `0.59.2026072702` where all eleven declared `scope: application`. Those four are **not declared in the build verified here**. Both observations are real, which is the point: the settings surface moves with the extension. Writing a key the installed build does not declare produces a setting that is silently inert, so confirm against the user's own build before offering any of them.

`headers` in particular is absent from **user settings** in this build. It is not absent from the product: the managed `telemetry` block carries a `headers` field, which is how a fleet authenticates to a collector. The two are different configuration surfaces delivered through different channels, so an operator who cannot find `headers` in their settings UI has not found a bug. See `org-distribution.md` for the managed surface and the consequence that headers reach the extension exporter and not the agent host.

None of these settings declares a `scope` in the verified manifest, which means they take VS Code's default `window` scope rather than `application`. Do not assert application scope without checking; see the profile section below for what that changes.

A minimal local setup writes three keys and leaves the rest at their defaults:

```json
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318"
}
```

Do not add `captureContent` to that block. Raise what it does, and what happens without it, before the user chooses; the position to take is in `SKILL.md`.

### Precedence

Enterprise policy beats environment variable beats user setting beats default. A user whose setting appears to be ignored is usually looking at a policy or a stray environment variable, not a failed write.

| Setting                 | Environment variable                    |
|-------------------------|-----------------------------------------|
| `enabled`               | `COPILOT_OTEL_ENABLED`                  |
| `captureContent`        | `COPILOT_OTEL_CAPTURE_CONTENT`          |
| `otlpEndpoint`          | `OTEL_EXPORTER_OTLP_ENDPOINT`           |
| `maxAttributeSizeChars` | `COPILOT_OTEL_MAX_ATTRIBUTE_SIZE_CHARS` |

`exporterType`, `outfile`, and `dbSpanExporter.enabled` declare no environment variable in the manifest inspected for this revision; they are set through user settings or enterprise policy. Confirm against the installed build before telling a user an environment variable will or will not apply, because this mapping moves with the extension.

The VS Code documentation renders "This setting is managed at the organization level. Contact your administrator to change it." next to these settings. That means the setting *can* be policy-managed, not that it *is*. Have the user run **Developer: Policy Diagnostics** from the command palette to find out which applies to them.

## Find the file that actually resolves

Which file resolves depends on the declared scope, and the scope is a property of the installed build rather than of this document. Check it before choosing a target file.

* **If a setting declares `scope: application`,** it lives only in the global `settings.json`, and that file resolves from the **default profile no matter which profile is active**. Writing into `User/profiles/<id>/settings.json` accomplishes nothing for that key, and it fails silently: no error, no warning, no telemetry.
* **If it declares no scope,** as every OTel key does in the verified manifest, it takes the default `window` scope and the active profile's `settings.json` does apply.

When unsure, write the global file: it is correct in both cases, because a window-scoped key still resolves there when no profile overrides it. Then have the user confirm the value took effect rather than assuming it did.

| Platform | VS Code                                                 | VS Code Insiders                                                   |
|----------|---------------------------------------------------------|--------------------------------------------------------------------|
| macOS    | `~/Library/Application Support/Code/User/settings.json` | `~/Library/Application Support/Code - Insiders/User/settings.json` |
| Windows  | `%APPDATA%\Code\User\settings.json`                     | `%APPDATA%\Code - Insiders\User\settings.json`                     |
| Linux    | `~/.config/Code/User/settings.json`                     | `~/.config/Code - Insiders/User/settings.json`                     |

Confirm rather than infer. Have the user run **Preferences: Open Application Settings (JSON)** from the command palette; VS Code opens the exact file these settings resolve from. Ask which build they run before choosing a path, because a machine with both installed has both files and only one of them matters.

Stop and ask if the file cannot be identified with confidence. Do not write to a guessed path.

## The assisted write

Follow every step. Steps 1, 4, and 5 are what make this reversible and visible.

`examples/settings_upsert.py` implements this contract rather than describing it. Prefer it over an ad-hoc edit: it refuses any key outside the verified schema, rejects a type mismatch, an unsafe endpoint, an `outfile` and `otlp-*` combination, and any attempt to enable `captureContent`; it splices only the target value span, backs the file up, restores the backup if the result does not parse, and refuses to write if unrelated settings would change. Run it without `--apply` to get the diff for step 4.

```bash
python3 settings_upsert.py --settings <path> \
  --set github.copilot.chat.otel.enabled=true \
  --set github.copilot.chat.otel.exporterType=otlp-http \
  --set github.copilot.chat.otel.otlpEndpoint=http://localhost:4318
```

Its schema is frozen against one build and records which one. Re-verify against the installed extension before trusting it on a newer version.

The steps below remain the contract, whether the tool performs them or a hand edit does.

1. **Back up.** Copy the file alongside itself as `settings.json.bak-otel-<UTC timestamp>`, for example `settings.json.bak-otel-20260727T142530Z`. Tell the user the backup path and that restoring it is a file copy in the other direction. That path sits beside `settings.json`, outside the workspace; name it when asking for the write rather than treating it as a separate approval.
2. **Read the file as text.** If it does not exist or is empty, treat the content as `{}`. It is JSONC: it may contain `//` and `/* */` comments and trailing commas, all of which are legal and all of which the user wrote deliberately.
3. **Compute the change per key. Do not write yet.** Work out the exact edit without applying it, so step 4 has something to show.
   * For a key already present, the change replaces only its value span, leaving the key, its indentation, and any adjacent comment untouched.
   * For a key not present, it is collected and inserted immediately before the document's final `}`, matching the file's existing indentation and adding the separating comma to the previous last entry when one is needed.
   * Match keys at the document's top level only. `"github.copilot.chat.otel.enabled"` appearing inside a `[...]` override block or a nested object is a different key and is not a target.
   * **Never reserialize.** Reserializing the document destroys every comment and every formatting choice in a file the user owns.
4. **Show the exact diff and stop.** Present the computed change as a unified diff against the file on disk, and name the file path above it. Ask for approval. Do not fold this into a broader "shall I proceed" question that bundles other work.
5. **Apply the upsert**, exactly as shown in the approved diff and no more.
6. **Validate after writing.** Re-read the file and parse it with comments and trailing commas tolerated. If it does not parse, restore the backup immediately, tell the user it was restored, and hand them the manual block instead.
7. **Reload.** These settings are read at window startup. Have the user run **Developer: Reload Window**. A skipped reload is the single most common cause of an empty dashboard.

Every write gets its own diff and its own approval. An approval earlier in the session does not carry forward to the next key or the next value.

### Two caveats worth stating out loud

**Settings Sync.** If the user has Settings Sync on, a change to the global settings file propagates to their other machines. Whether a write made outside the running VS Code instance produces a sync conflict has not been confirmed, so say that it may and let the user decide whether to close VS Code first.

**Concurrent writes.** VS Code writes this file too. If the user changes a setting through the Settings UI while an assisted write is in flight, one of the two writes wins and the other is lost. The backup is the recovery path.

## The manual alternative

A user who declines the assisted write should lose nothing but keystrokes. Give them this, complete, without asking again:

> Run **Preferences: Open Application Settings (JSON)** from the command palette. Add these three keys inside the outermost `{ }`, keeping your existing keys and comments as they are. If a key is already there, change its value rather than adding a second copy.
>
> ```json
> "github.copilot.chat.otel.enabled": true,
> "github.copilot.chat.otel.exporterType": "otlp-http",
> "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318"
> ```
>
> Save, then run **Developer: Reload Window**.

Then point them at the verification reference, because a pasted block is exactly as unproven as a written one.

## Turning it off

Set `github.copilot.chat.otel.enabled` to `false` and reload the window. The other keys are inert while it is off, so there is no need to remove them. Data already in the store stays there until the store is cleared.

