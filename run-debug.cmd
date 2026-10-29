@echo off
setlocal
set "GAME_ROOT=%~dp0"
set "GODOT_EXE=%GAME_ROOT%.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" set "GODOT_EXE=D:\a_my_vibe_coding\codex_work\xiuxian-world\.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT_EXE%" (
  echo Godot 4.7.2 is required.
  pause
  exit /b 1
)
start "" "%GODOT_EXE%" --path "%GAME_ROOT%." --log-file "%GAME_ROOT%evidence\debug-play.log" res://ui/main.tscn
exit /b 0
