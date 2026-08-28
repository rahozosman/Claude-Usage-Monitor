# Security

> **Paths on this page** use the Windows locations. On macOS the app's own folder is
> `~/Library/Application Support/ClaudeUsageMonitor/` instead of `%LOCALAPPDATA%\ClaudeUsageMonitor\`;
> `~/.claude` is the same on both.

## Credentials

| Secret | Where it lives | How it is used |
| --- | --- | --- |
| Anthropic API key | OS‑encrypted secure storage (`flutter_secure_storage`: DPAPI on Windows, Keychain on macOS) **or** `ANTHROPIC_API_KEY` env var (read‑only) | `x-api-key` header on the 1‑token probe |
| Admin API key | secure storage **or** `ANTHROPIC_ADMIN_KEY` | Admin usage/cost/rate‑limit GETs |
| Claude Code OAuth token | **not stored by this app.** Read from `~/.claude/.credentials.json` into memory only when the opt‑in usage endpoint is enabled, for the duration of one request | `Authorization: Bearer` on `/api/oauth/usage` |

Rules enforced in code:

- No key is ever hard‑coded, written to SharedPreferences, logged, or included in an error string
  (`AppError._sanitize` redacts `sk-ant-…` and `Bearer …` patterns from API messages before display).
- The Settings screen shows keys masked (`sk-ant-…7f3a`), the entry field is obscured, and keys from
  environment variables are marked read‑only.
- Keys are sent only to `https://api.anthropic.com`. No telemetry, no third‑party servers.
- The `.gitignore` excludes `.env*`, `*.key`, `*.pem`, `secrets/`, `credentials.json` and similar.
- If secure storage is unavailable the app says so and falls back to environment variables — it
  never silently downgrades to plain‑text storage.

## What the app reads

- `%USERPROFILE%\.claude\settings.json` (or `CLAUDE_CONFIG_DIR`): only `statusLine.command`.
- `%USERPROFILE%\.claude\.credentials.json`: `subscriptionType`, `rateLimitTier`, `expiresAt`
  (and `accessToken` only for the opt‑in endpoint, in memory).
- `%LOCALAPPDATA%\ClaudeUsageMonitor\statusline.json`: JSON produced by the bridge.
- `claude --version` output.

## What the app writes

- `%LOCALAPPDATA%\ClaudeUsageMonitor\` — bridge script, bridge config, settings backups.
- `%USERPROFILE%\.claude\settings.json` — **only** the `statusLine` key and the `SessionStart` hook,
  **always** after copying the file to
  `%LOCALAPPDATA%\ClaudeUsageMonitor\backups\settings.json.<timestamp>.bak`. Files that fail to parse
  are never modified, and uninstall restores the previous `statusLine` value.

  Both edits happen when you use the switches in Settings → Claude Code, and the bridge additionally
  installs itself **once, on first launch**, so limits work without any setup. That auto-install is
  one-shot: it is recorded in `bridgeAutoInstallDone` and never repeated, so removing the bridge
  yourself is respected and it is not reinstalled behind you. It is skipped entirely when `~/.claude`
  does not exist. All four writers (bridge install/uninstall, hook install/uninstall) are queued
  through a single serializer, so two of them can never read-modify-write the file at the same time
  and lose each other's changes.
- App preferences via SharedPreferences (no secrets).
- Start at login, when that setting is on: a per‑user `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
  entry on Windows, a per‑user login item on macOS. Neither needs administrator rights.

## macOS: no App Sandbox

The macOS build deliberately runs **outside the App Sandbox**. Its whole purpose is to read
`~/.claude` (settings, credential metadata, transcripts) and to write the one `statusLine` key and the
`SessionStart` hook back — a sandboxed app cannot reach another application's support directory, so
sandboxing it would leave nothing but the API section working. The trade‑off is deliberate and worth
knowing: the app has normal user‑level file access, exactly like the Windows build. That also means it
cannot ship through the Mac App Store, which requires the sandbox.

## Network

- HTTPS only, 20 s timeouts, no redirects followed to other hosts.
- `User-Agent: ClaudeUsageMonitor/1.0 (Windows)` as Anthropic recommends for integrations.
- Usage endpoint calls are throttled (≥60 s) and back off on 429; API probes default to every 5 min.

## Threat notes

- The bridge script runs with your user rights — PowerShell `-ExecutionPolicy Bypass -File` on Windows,
  `/bin/sh` on macOS
  (needed because Claude Code invokes it non‑interactively). It reads stdin, writes one JSON file and
  forwards stdin to your previous status line. Review it at
  `%LOCALAPPDATA%\ClaudeUsageMonitor\bridge\statusline-bridge.ps1`.
- Anyone with access to your Windows user profile can already read `~/.claude/.credentials.json`;
  this app does not widen that exposure.

## Reporting

Open an issue in the project repository (if configured in Settings → About) or contact the developer.
