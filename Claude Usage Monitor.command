#!/bin/sh
# Claude Usage Monitor - macOS launcher, the counterpart of the .cmd on Windows.
#
# Double-click it in Finder (Terminal opens). The very first time, macOS needs
# permission to run it:   chmod +x "Claude Usage Monitor.command"
cd "$(dirname "$0")" || exit 1

APP="build/macos/Build/Products/Release/claude_usage_monitor.app"
PROC="claude_usage_monitor"
DIR="$HOME/Library/Application Support/ClaudeUsageMonitor"

running() { pgrep -x "$PROC" >/dev/null 2>&1; }

# Stop the monitor. Drops a "quit" marker the app watches for, so it shuts down
# cleanly and removes its own menu-bar icon; a forced kill strands it. Falls
# back to pkill only if it will not go. Returns 1 when nothing was running.
stop_monitor() {
  running || return 1
  mkdir -p "$DIR" 2>/dev/null
  printf 'stop' > "$DIR/quit" 2>/dev/null
  i=0
  while [ "$i" -lt 8 ]; do
    sleep 1
    running || return 0
    i=$((i + 1))
  done
  pkill -x "$PROC" >/dev/null 2>&1
  return 0
}

# Rebuild when the Dart code is newer than the built app, or nothing is built.
needs_build() {
  [ -d "$APP" ] || return 0
  [ -n "$(find lib pubspec.yaml -newer "$APP" -print -quit 2>/dev/null)" ]
}

build_app() {
  if ! command -v flutter >/dev/null 2>&1; then
    echo
    echo "  Flutter was not found on PATH. Install Flutter with macOS desktop"
    echo "  support and try again."
    echo
    return 1
  fi
  echo
  echo "  Building the app. This takes a few minutes..."
  echo
  flutter build macos --release || return 1
  [ -d "$APP" ]
}

while :; do
  clear
  echo
  echo "  Claude Usage Monitor"
  echo "  ===================="
  echo
  if running; then echo "  Status: ON  (running)"; else echo "  Status: OFF"; fi
  echo
  echo "  [1] Turn ON   - start the monitor at the right edge of your screen"
  echo "  [2] Turn OFF  - stop the monitor"
  echo "  [3] Rebuild   - rebuild after code changes, then start"
  echo "  [4] Exit"
  echo
  printf "  Choose 1, 2, 3 or 4: "
  read -r choice
  case "$choice" in
    1)
      if running; then
        echo
        echo "  The monitor is already running. Look at the right edge of your"
        echo "  screen, or the menu-bar icon."
        sleep 3
        continue
      fi
      if needs_build; then
        stop_monitor >/dev/null 2>&1
        build_app || { echo; printf "  Press return to continue: "; read -r _; continue; }
      fi
      open -a "$PWD/$APP" --args --from-launcher
      echo
      echo "  Monitor started. It sits at the right edge of your screen; the"
      echo "  menu-bar icon has Show / Hide / Quit."
      sleep 3
      exit 0
      ;;
    2)
      if stop_monitor; then echo; echo "  Monitor stopped."; else echo; echo "  The monitor was not running."; fi
      sleep 2
      exit 0
      ;;
    3)
      stop_monitor >/dev/null 2>&1
      build_app || { echo; printf "  Press return to continue: "; read -r _; continue; }
      open -a "$PWD/$APP" --args --from-launcher
      echo
      echo "  Monitor rebuilt and started."
      sleep 3
      exit 0
      ;;
    4) exit 0 ;;
    *) ;;
  esac
done
