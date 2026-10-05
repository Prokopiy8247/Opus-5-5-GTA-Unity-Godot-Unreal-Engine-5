@echo off
setlocal
set "PROJECT=%~dp0Unreal_Opus5_5_GTA.uproject"
if not exist "%PROJECT%" (
  echo Project file was not found.
  pause
  exit /b 1
)
start "" "%PROJECT%"
if errorlevel 1 (
  echo Unreal Engine 5.8 is not associated with .uproject files.
  echo Install Unreal Engine 5.8 through Epic Games Launcher, then try again.
  pause
  exit /b 1
)
