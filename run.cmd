@echo off
setlocal
set "GAME_ROOT=%~dp0"
set "GODOT_EXE=%GAME_ROOT%.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 portable is missing.
  echo See README.md for setup instructions.
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%GAME_ROOT%." --log-file "%GAME_ROOT%evidence\play.log"
exit /b 0
