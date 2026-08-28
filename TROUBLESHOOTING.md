# Troubleshooting

## The limits panel shows "—" / "Unavailable"

Click the edge tab to open the panel — the reason is spelled out under each limit. Typical causes:

| Reason shown | Fix |
| --- | --- |
| Claude Code is not installed | Install Claude Code and sign in; subscription limits only exist there |
| Not provided by Claude for API‑key sign‑in | You use `ANTHROPIC_API_KEY` in Claude Code. Rate limits are only sent for Claude.ai subscribers. Use the API section instead |
| Not signed in to Claude Code | Run `claude`, then `/login` |
| Install the Claude Code bridge in Settings | Settings → Claude Code → **Install** (or enable the usage endpoint) |
| Waiting for a Claude Code session | Start a Claude Code session and send one message; the first response delivers the limits |
| Claude Code sent no rate limits yet | Same as above; also check you are on Pro/Max/Team/Enterprise |
| Claude Code sign‑in expired | Open Claude Code once — it refreshes the token; this app never does |
| Usage endpoint rate limited | Wait; the app backs off automatically (≥5 min) |

## Data is marked "Stale"

The status‑line bridge only updates while a Claude Code session is producing responses. Either keep
a session open, or enable **Use Claude usage endpoint** (Settings → Claude Code) which polls without
a session.

## It shrinks back to the tab whenever I click somewhere else

That is deliberate: clicking outside the app collapses it straight back to the tiny edge tab, so it
never sits in your way. Turn it off in Settings → General → **Shrink when I click elsewhere**.
Clicking *inside* the panel or Home never collapses it.

## The edge tab disappeared

Right‑click the tray icon (✦ terracotta square) → **Show Dashboard**, or left‑click the icon to
toggle. Closing the window with the × button quits the app; use the tray menu's Hide to keep it
running invisibly.

## The tab is behind other windows, or in the wrong place

Settings → General → **Always on top**; full‑screen games and exclusive‑mode apps still cover it.
The tab is docked to the **right edge** and snaps back there if you drag it away — drag it up or down
to move it along the edge, and the position is remembered.

## The monitor closed itself

By design: it follows your Claude Code sessions. The `SessionStart` hook opens it when you start a
session, and it closes again once the **last** Claude Code session is gone, so it is not left running
all day. Turn it off in Settings → Claude Code → **Close with Claude Code**, and it will then stay up
until you close it yourself.

It will not close on you unexpectedly: it never exits until it has actually seen a session running
(so opening it on its own is safe), it needs two consecutive checks with nothing running (so closing
one session and opening the next does not count), and if the check itself fails it assumes a session
is still open rather than quitting. When it does exit it shuts down cleanly, so the tray icon goes
with it instead of being stranded.

### macOS: it does not close by itself

If you installed Claude Code through npm, its process is `node`, not `claude`, so the watcher cannot
recognise it and the monitor simply stays open. That is the safe direction — it will never close while
you are working — but you will need to quit it yourself.

## Only one copy runs

Launching the app again (Explorer, the launcher, "Start with Windows", or the Claude Code hook)
brings the existing copy forward instead of starting a second one.

## Nothing happens when I click "Install" (bridge)

- The message under the button explains failures. If `settings.json` cannot be parsed the app refuses
  to modify it — fix the JSON first (Claude Code's `claude doctor` helps).
- Verify afterwards: `~/.claude/settings.json` should contain
  `"statusLine": {"type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/<you>/AppData/Local/ClaudeUsageMonitor/bridge/statusline-bridge.ps1"}`.
- A backup of your previous file is in `%LOCALAPPDATA%\ClaudeUsageMonitor\backups`.

## My old status line vanished / shows nothing

The bridge forwards stdin to your previous command (saved in
`%LOCALAPPDATA%\ClaudeUsageMonitor\bridge\bridge-config.json` under `forward`). If that command needed
Git Bash and Git Bash is not on PATH, it cannot run — install Git for Windows or uninstall the bridge
to restore the original setting.

## API section says "Authentication failed"

The key is wrong, revoked, or is a workspace key used for Admin endpoints. Admin endpoints need an
Admin key (`sk-ant-admin…`) and an organisation account.

## API section says "Rate limited" (HTTP 429)

That is real data: your organisation is at a per‑minute limit. The headers and `retry-after` are
displayed. The probe itself is 1 token; lower the probe interval only if needed.

## "Request rejected" / HTTP 400 from the probe

Usually the probe model is not available to your organisation. Settings → API → **Probe model**.

## Notifications never appear

- Settings → Notifications → **Enable notifications**, then **Test**.
- Windows Settings → System → Notifications: allow *Claude Usage Monitor*, and check Focus Assist /
  Do Not Disturb.
- Each threshold fires only once per usage window by design.

## "Start with Windows" / "Start at login" does not stick

The entry records the **current** location of the app: a `HKCU\…\CurrentVersion\Run` value on Windows,
a login item pointing at the `.app` bundle on macOS. If you move or rebuild it somewhere else, toggle
the setting off and on again.

## Secure storage unavailable

Set `ANTHROPIC_API_KEY` / `ANTHROPIC_ADMIN_KEY` as user environment variables instead, then restart
the app.

## Build errors

- **macOS has never been compiled.** The macOS target was written from Windows: `flutter analyze` is
  clean, but no one has run `flutter build macos` on a Mac. Expect to fix Xcode, signing or entitlement
  issues on the first build there; the Windows build is the tested one.
- `flutter doctor` must show Visual Studio with the C++ workload (Windows) or Xcode (macOS).
- Spaces in the project path are fine; a very long path can hit MSBuild limits — move the folder
  closer to the drive root if `flutter build windows` fails with path errors.
- Delete `build/` and rerun after upgrading Flutter.

## Where things live

| Item | Path |
| --- | --- |
| Bridge script & config, backups, status‑line JSON | `%LOCALAPPDATA%\ClaudeUsageMonitor\` (macOS: `~/Library/Application Support/ClaudeUsageMonitor/`) |
| Claude Code config | `%USERPROFILE%\.claude\` (or `CLAUDE_CONFIG_DIR`) |
| Built app | `build\windows\x64\runner\Release\claude_usage_monitor.exe` (macOS: `build/macos/Build/Products/Release/`) |
