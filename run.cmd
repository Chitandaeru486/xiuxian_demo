@echo off
setlocal
set "S1_ROOT=%~dp0"
set "S1_ENGINE=%S1_ROOT%.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%S1_ENGINE%" set "S1_ENGINE=%S1_ROOT%..\xiuxian-world\.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%S1_ENGINE%" set "S1_ENGINE=D:\a_my_vibe_coding\codex_work\xiuxian-world\.tools\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%S1_ENGINE%" (
  echo Godot 4.7.2 is required. See README.md.
  pause
  exit /b 1
)
start "" "%S1_ENGINE%" --path "%S1_ROOT%." --log-file "%S1_ROOT%evidence\play.log"
exit /b 0
