# Development

## Prerequisites

- Flutter 3.44+ stable with Windows desktop enabled (`flutter doctor` must show Visual Studio ✓)
- Visual Studio 2022/2026 with *Desktop development with C++*
- Python 3 (only for regenerating the icon)

## Run / build

```powershell
flutter pub get
flutter analyze                     # the verification step used for this project
flutter run -d windows              # debug
flutter build windows --release     # production build → build\windows\x64\runner\Release\
```

The one‑click launcher `Claude Usage Monitor.cmd` wraps build + start/stop for non‑developers.

## Dependencies (pubspec.yaml)

| Package | Purpose |
| --- | --- |
| window_manager | frameless/transparent/always‑on‑top window, drag, bounds |
| screen_retriever | primary display geometry |
| tray_manager | tray icon + context menu |
| launch_at_startup | Start with Windows (HKCU Run key) |
| local_notifier | Windows toast notifications |
| flutter_secure_storage | encrypted secret storage |
| shared_preferences | preferences |
| http | Anthropic API calls |
| provider | state management |
| intl, path, url_launcher, package_info_plus | formatting, paths, links, version |

## Project conventions

- **No colour or duration literals in widgets** — use `context.colors` / `context.motion`.
- **Every displayed value is nullable at the model level.** If a source does not provide it, leave it
  null and set `unavailableReason`; never derive or guess.
- **Services do I/O, widgets never do.** New sources go in `services/` and are merged in
  `repositories/usage_repository.dart`.
- Per‑second work is limited to the `clock` `ValueNotifier` and the widgets that listen to it.
- All Claude‑file access goes through `core/services/app_paths.dart`.

## Adding a data source

1. Create `services/<name>_service.dart` returning `LimitWindow`s (with `source`, `observedAt`) or a
   dedicated model.
2. Merge it in `UsageRepository.fetch` (freshest observation wins; keep last‑known on failure).
3. Extend `_unavailableReason` so the UI can explain absence.
4. Add the source label to `DataSource` and document it in `CLAUDE_USAGE_DATA.md`.

## Icon

`tools/make_icon.py` renders the spark mark into a multi‑size ICO and writes both
`assets/icons/app_icon.ico` (tray) and `windows/runner/resources/app_icon.ico` (window/exe). Regenerate
both together.

## Status‑line bridge

The PowerShell template lives in `services/statusline_bridge_service.dart`. After changing it, users
must click *Uninstall* then *Install* in Settings to rewrite the script.

## Testing

Pure logic lives in `core/utils/usage_math.dart`, `core/utils/format_utils.dart`,
`models/api_rate_limits.dart` (header parsing), `models/status_line_data.dart` and
`services/oauth_usage_service.dart` (`_parse`) — all free of platform dependencies so they can be unit
tested with plain `flutter test` when tests are added. Suggested edge cases: 0 %, 1 %, 50 %, 80 %,
90 %, 99 %, 100 %, missing limit, missing reset, null body, network failure.
