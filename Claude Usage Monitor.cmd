@echo off
setlocal
title Claude Usage Monitor
cd /d "%~dp0"
set "EXE=%~dp0build\windows\x64\runner\Release\claude_usage_monitor.exe"

:menu
cls
echo.
echo   Claude Usage Monitor
echo   ====================
echo.
tasklist /fi "imagename eq claude_usage_monitor.exe" 2>nul | find /i "claude_usage_monitor.exe" >nul
if errorlevel 1 (echo   Status: OFF) else (echo   Status: ON  ^(running^))
echo.
echo   [1] Turn ON   - start the monitor at the top of your screen
echo   [2] Turn OFF  - stop the monitor
echo   [3] Rebuild  - rebuild after code changes, then start
echo   [4] Exit
echo.
choice /c 1234 /n /m "  Choose 1, 2, 3 or 4: "
if errorlevel 4 goto :eof
if errorlevel 3 goto rebuild
if errorlevel 2 goto off
if errorlevel 1 goto on
goto menu

:on
set "NEEDBUILD=0"
if not exist "%EXE%" set "NEEDBUILD=1"
if "%NEEDBUILD%"=="0" call :is_stale && set "NEEDBUILD=1"
if "%NEEDBUILD%"=="0" (
  tasklist /fi "imagename eq claude_usage_monitor.exe" 2>nul | find /i "claude_usage_monitor.exe" >nul
  if not errorlevel 1 (
    echo.
    echo   The monitor is already running and up to date. Look for the tab at the right edge or the tray icon.
    timeout /t 3 >nul
    goto menu
  )
)
if "%NEEDBUILD%"=="1" (
  rem Stale copies of the old build must go before the new one starts.
  call :stop
  echo.
  if exist "%EXE%" (
    echo   The code is newer than the last build. Rebuilding so you get the latest version...
  ) else (
    echo   First run: building the app. This takes a few minutes...
  )
  echo.
  where flutter >nul 2>&1
  if errorlevel 1 (
    echo   Flutter was not found on PATH. Install Flutter ^(with Windows desktop support^) and try again.
    echo.
    pause
    goto menu
  )
  call flutter build windows --release
  if not exist "%EXE%" (
    echo.
    echo   Build failed. Read the messages above, or see TROUBLESHOOTING.md.
    echo.
    pause
    goto menu
  )
)
start "" "%EXE%"
echo.
echo   Monitor started. It sits at the top of your screen; the tray icon has Show / Hide / Quit.
timeout /t 3 >nul
goto :eof

:rebuild
call :stop
where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Flutter was not found on PATH.
  pause
  goto menu
)
echo.
echo   Rebuilding the app. This takes a few minutes...
echo.
call flutter build windows --release
if not exist "%EXE%" (
  echo.
  echo   Build failed. Read the messages above, or see TROUBLESHOOTING.md.
  pause
  goto menu
)
start "" "%EXE%"
echo.
echo   Monitor rebuilt and started.
timeout /t 3 >nul
goto :eof

:off
call :stop
if errorlevel 1 (
  echo.
  echo   The monitor was not running.
) else (
  echo.
  echo   Monitor stopped.
)
timeout /t 2 >nul
goto :eof
:: ---------------------------------------------------------------------------
:: Returns 0 (true) when any source file under lib\ or pubspec.yaml is newer
:: than the last build, i.e. "Turn ON" would otherwise start stale code.
:: The Dart code ships in data\app.so - the exe itself is only relinked when
:: native code changes, so its timestamp says nothing about a rebuild.
:is_stale
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$built = Get-Item -LiteralPath (Join-Path (Split-Path -Parent $env:EXE) 'data\app.so') -ErrorAction SilentlyContinue;" ^
  "if (-not $built) { $built = Get-Item -LiteralPath $env:EXE -ErrorAction Stop };" ^
  "$src = Get-ChildItem -LiteralPath 'lib' -Recurse -File -ErrorAction SilentlyContinue;" ^
  "$src += Get-Item -LiteralPath 'pubspec.yaml' -ErrorAction SilentlyContinue;" ^
  "$newest = ($src | Measure-Object -Property LastWriteTime -Maximum).Maximum;" ^
  "if ($newest -gt $built.LastWriteTime) { exit 0 } else { exit 1 }" >nul 2>&1
exit /b %errorlevel%

:: ---------------------------------------------------------------------------
:: Stop the monitor. Drops a "quit" marker the app watches for, so it shuts
:: down cleanly and removes its own tray icon; a forced kill leaves a dead
:: icon behind in the notification area. Falls back to /f only if it will not
:: go. Returns 1 when nothing was running.
:stop
tasklist /fi "imagename eq claude_usage_monitor.exe" 2>nul | find /i "claude_usage_monitor.exe" >nul
if errorlevel 1 exit /b 1
if not exist "%LOCALAPPDATA%\ClaudeUsageMonitor" mkdir "%LOCALAPPDATA%\ClaudeUsageMonitor" >nul 2>&1
echo stop> "%LOCALAPPDATA%\ClaudeUsageMonitor\quit"
for /l %%i in (1,1,8) do (
  timeout /t 1 >nul
  tasklist /fi "imagename eq claude_usage_monitor.exe" 2>nul | find /i "claude_usage_monitor.exe" >nul
  if errorlevel 1 exit /b 0
)
taskkill /im claude_usage_monitor.exe /f >nul 2>&1
exit /b 0
