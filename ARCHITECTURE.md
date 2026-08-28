# Architecture

Flutter (Dart 3.12) Windows desktop app. Single frameless, transparent, always‑on‑top window docked to
the top of the primary display; a system‑tray icon keeps it running in the background.

```
lib/
├── main.dart                    composition root: builds services, controllers, window, tray; runApp
├── app/
│   ├── app.dart                 MaterialApp (light/dark/system)
│   ├── motion_scope.dart        context.motion → AppMotion honouring the animation toggle
│   └── theme/                   app_colors (semantic tokens + status colours), app_theme,
│                                app_motion (durations/curves), app_dimens (spacing/radius)
├── core/
│   ├── constants/app_constants.dart
│   ├── errors/app_error.dart    typed errors; messages are credential‑sanitised
│   ├── services/app_paths.dart  every on‑disk path the app touches
│   └── utils/                   usage_math (thresholds, %), format_utils (countdowns, masking)
├── models/                      immutable data: LimitWindow, UsageSnapshot, ApiRateLimits,
│                                ApiUsageReport, CliStatus, StatusLineData, AppSettings, ConnectionStatus
├── services/
│   ├── claude_cli_service.dart          detect CLI, read config metadata, read status‑line file
│   ├── statusline_bridge_service.dart   install/uninstall the status‑line bridge and the SessionStart
│   │                                    "open with Claude Code" hook (only writer to settings.json)
│   ├── oauth_usage_service.dart         opt‑in usage endpoint client (throttled, back‑off)
│   ├── anthropic_api_service.dart       Messages probe (headers) + Admin usage/cost/rate‑limit APIs
│   ├── settings_service.dart            SharedPreferences (prefs) + flutter_secure_storage (secrets)
│   ├── notification_service.dart        toasts with once‑per‑window de‑dup (persisted)
│   ├── refresh_service.dart             the two periodic timers
│   ├── window_service.dart              window_manager + screen_retriever geometry
│   ├── tray_service.dart                tray_manager icon + menu
│   └── startup_service.dart             launch_at_startup (HKCU Run key / macOS login item)
├── repositories/usage_repository.dart   merges sources → UsageSnapshot, computes ConnectionStatus
├── features/
│   ├── dashboard/   usage_controller (refresh + 1 s clock), edge_tab, limits_panel, dashboard_page
│   ├── settings/    settings_controller, settings_page
│   └── shell/       shell_controller (3 states), edge_shell (the morphing glass), app_shell
└── widgets/         glass_panel, usage_bar, usage_card, api_card, animated_number, countdown,
                     status_indicator, claude_mark, app_icon_button, app_button, section_header, setting_row
```

## Data flow

```
 Claude Code ──statusLine cmd──▶ bridge.ps1 ──▶ %LOCALAPPDATA%\ClaudeUsageMonitor\statusline.json
                                                              │
 ~/.claude/.credentials.json (metadata / opt‑in token) ───────┤
 api.anthropic.com  /api/oauth/usage (opt‑in) ────────────────┤
 api.anthropic.com  /v1/messages (1‑token probe → headers) ───┼──▶ UsageRepository.fetch()
 api.anthropic.com  /v1/organizations/* (Admin key) ──────────┘          │
                                                                          ▼
                       UsageController.snapshot (ChangeNotifier) ◀── UsageSnapshot
                                │                    │
                    NotificationService.evaluate     UI (CompactBar / DashboardPage)
```

`UsageRepository` never estimates: each `LimitWindow` carries `usedPercentage?`, `resetsAt?`,
`observedAt?`, `source` and an `unavailableReason`. The freshest observation per window wins;
last‑known values are retained and flagged stale by the UI.

## Refresh model

| Cadence | What | Cost |
| --- | --- | --- |
| Data refresh (10 s–5 m, or manual) | read status‑line file, settings metadata; usage endpoint if enabled (≥60 s floor) | local I/O, at most one HTTPS GET/min |
| API probe (1 m–30 m, or manual) | one `max_tokens: 1` Messages request; Admin reports | one tiny paid request |
| Clock (1 s) | `ValueNotifier<DateTime>` consumed **only** by countdown/relative‑time widgets; runs only while the window is visible | none |
| Reset | when a window's `resets_at` passes: notify once, refresh 3 s later | one data refresh |

Overlapping refreshes are coalesced (a refresh requested while one is running is queued once).

## State management

`provider` with three `ChangeNotifier`s:

- `SettingsController` — `AppSettings` + masked secret metadata + Start‑with‑Windows state
- `UsageController` — snapshot, refreshing flags, clock, reset handling
- `ShellController` — window mode/page/visibility, tray sync, drag, quit

Services are plain classes created once in `main.dart` and injected; widgets never touch I/O.

## Window & geometry

The window is **docked to the right edge of the work area** and is only ever as large as the current
state needs, so the rest of the desktop stays clickable.

- `window_manager`: frameless, transparent, hidden title bar, skip taskbar, prevent-close,
  always-on-top toggle, `startDragging` from the tab and the panel header.
- `screen_retriever`: work area in logical px. `WindowService._dock()` sets
  `x = workRight − windowWidth` for every state, so the glass is always flush with the screen border;
  the vertical centre (`anchorCenterY`) is remembered across states and after a drag. A drag that
  pulls the window off the edge snaps it back on `onWindowMoved`.
- Three sizes (`WindowMode`): **tab** 20 × 76 → **limits** 296 × 236 → **home** 560 × 660, each plus a
  transparent `shadowPad` margin on the left/top/bottom for the glass shadow (the right side stays
  flush). Home is capped to the work area.
- `ShellStage { collapsed, limits, home }` in `ShellController` is the single source of UI truth.
  **Growing** applies the window bounds first so the glass has room to expand into; **shrinking**
  plays the exit animation inside the current bounds and only then pulls the window in.
- `EdgeShell` is one `GlassPanel` whose width, height and corner radius are interpolated across the
  three stops, so collapsing from Home travels *through* the panel width on its way back to the edge.
  Only the outgoing and incoming contents are built and cross-faded (`ShellController.previousStage`),
  so a state the surface passes over never flashes, and a page is never laid out at a size it was not
  designed for. Only the left corners are rounded — the glass always reads as attached.
- Durations: 240 ms tab → limits, 380 ms limits → home, 200 ms collapse, all on the ease-out curve.
  `WindowCaptionBar` gives Home its Windows-style ─ (collapse to tab) and × (close) buttons;
  `AppScrollView` is plain `Scrollable` scrolling with a hover scrollbar.

## Collapse on click-outside

`WindowService` forwards `onWindowBlur` (emitted natively from `WM_NCACTIVATE`, before the frameless
early-return) to `ShellController.handleFocusLost()`. That waits 200 ms and re-checks
`windowManager.isFocused()` before collapsing, so a transient blur — a native menu opening, the window
moving itself — does not shrink the app; only a real click elsewhere does. Guarded by
`AppSettings.collapseOnClickOutside` (default on), the window being visible, the stage not already
being the collapsed tab, and no shrink in flight. Clicks inside the window never blur it, so working in the bar
or dashboard leaves it open.

## Platform support

One codebase, two targets, every difference behind a `Platform.is…` branch: app-data location
(`%LOCALAPPDATA%` vs `~/Library/Application Support`), the bridge and launch-hook scripts (`.ps1` vs
`.sh`), the process check (`tasklist` vs `ps -A -o comm=`), the tray image (`.ico` beside the exe vs
`.png` inside `App.framework/Resources`), the login-item target (the executable vs the `.app` bundle),
and the CLI locator (`where` vs `which`).

Two constraints that are easy to break:

- `.gitattributes` pins **LF** on `.sh`/`.command` and **CRLF** on `.cmd`/`.ps1`. The app writes shell
  scripts out of Dart string templates, so a CRLF checkout would emit a `statusline-bridge.sh` that
  `/bin/sh` rejects with an unhelpful error. A `_shellSafe()` guard backs this up at runtime.
- The macOS bridge reads the previous status line from a plain-text `bridge/forward` file rather than
  parsing JSON: `sh` has no dependable JSON parser and macOS ships no guaranteed `python3`.

> **The macOS build has never been compiled or run.** It was written entirely from Windows;
> `flutter analyze` is clean and the generated `sh` bridge was executed under Git Bash, but Xcode
> compilation, signing, Keychain, tray and window behaviour on a real Mac are all untested.

## Lifecycle

The app follows Claude Code rather than running all day.

- **One copy only**: on Windows a named mutex (`single_instance_lock.dart`) held for the process
  lifetime; on macOS the file lock is the guard, and the same warning applies there — the handle must
  be held in a static or it is collected and the lock silently released. A second launch — Explorer, the launcher, Start with Windows, or the `SessionStart` hook —
  drops a `wake` marker so the running copy comes forward, then exits before creating a window or a
  tray icon. (A `RandomAccessFile` lock was tried first and does not work: the handle was collected
  and the lock released seconds after startup.)
- **Opened** by the `SessionStart` hook the bridge installs, **closed** by
  `claude_session_watcher.dart`, which polls for the CLI every 15 s (`tasklist` on Windows,
  `ps -A -o comm=` on macOS, matching the process *name* and never the command line — this app's own
  path contains "claude") and calls
  `ShellController.quit()` — the same path as the tray's Quit, so the tray icon is removed rather
  than stranded. Gated by `AppSettings.quitWithClaude` (default on), live-updated from Settings.
- Three rules in that watcher are load-bearing and must not be simplified away: it never quits before
  it has *seen* a session running; it needs two consecutive empty polls, so the gap between closing
  one session and opening the next does not read as "all gone"; and a failed or timed-out `tasklist`
  returns "still open", so a transient failure is never mistaken for the user having finished.
  A `SessionEnd` hook cannot do this job — it does not run when a terminal is killed outright.

## Design system (macOS idiom)

- **Palette** (`AppColors`): macOS system colours — label tiers (`textPrimary/Secondary/Tertiary`),
  `fill`/`fillStrong`, `separator`, green/yellow/orange/red status. `accent` and `mark` are both
  Claude terracotta: every interactive accent (buttons, focus rings, selection, the pop-up badge)
  uses the brand colour rather than the system blue. Status colours stay reserved for meaning —
  comparison bars step terracotta down in opacity instead of borrowing green/amber.
- **Typography** (`AppTheme`): bundled Inter (SF‑like) at macOS sizes — 13 pt body, 11 pt secondary,
  tight tracking on titles, tabular figures for changing numbers.
- **Controls** (`widgets/mac_controls.dart`): `MacSwitch`, `MacPopupButton`, `MacSegmentedControl`,
  `MacGlyphButton`; `AppButton` is a macOS push button. Window chrome is Windows-style, not Apple:
  `widgets/window_caption.dart` (`WindowCaptionBar`, `CaptionButton`) gives Home a ─ (collapse to the
  edge tab) and × (close) pair, × turning `trafficRed` on hover.
- **Surfaces** (`GlassPanel`): translucent fill, 0.6 px hairline, top sheen, layered shadow; inset
  grouped cards at 10 pt radius. The edge widget rounds **only its left corners** (9 pt tab →
  14 pt panel → 16 pt Home) so the glass always reads as attached to the screen border.
  A childless `ColoredBox`/`DecoratedBox` takes `constraints.smallest`, so every bar fill is wrapped
  in `Positioned.fill` or given explicit dimensions — without that it silently paints nothing.
- **Scrolling** (`widgets/app_scroll_view.dart`): standard `Scrollable` physics with a scrollbar that
  appears on hover. An earlier custom wheel-animation scroller was removed — it broke scrolling.
- **Motion** (`AppMotion`): macOS ease‑out `Cubic(0.22,1,0.36,1)` for entrances, symmetric
  `Cubic(0.45,0,0.15,1)` for state changes, `settle` for values, a light `spring` for reveals.

## Theme system

`AppColors` is a `ThemeExtension` with semantic tokens (surface, border, text tiers, accent,
status normal/moderate/warning/critical/offline, connected). `context.colors.forStatus(...)` and
`forConnection(...)` map states to colours — no colour literals in widgets. `AppMotion` centralises
durations (micro 150 / component 280 / value 420 / large 520 / ambient 2400 ms) and curves; with
animations off every duration is zero.

## Error handling

`AppError(kind, message, detail, retryAfter)` with kinds: cliMissing, unauthenticated,
invalidCredentials, tokenExpired, network, rateLimited, malformed, api, unsupported, permission,
unknown. Network failures (socket/timeout/TLS) map to `network` → *Offline* with last‑known values.
Auth failures → *Sign‑in needed*. Everything else → the card shows the sanitised message; the app
never throws out of a refresh (`UsageController.refresh` catches and records).
