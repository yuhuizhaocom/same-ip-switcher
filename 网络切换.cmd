@echo off
rem Green portable launcher: works from any folder.
rem Runs the switch-network.ps1 in the SAME folder with admin rights.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File \"%~dp0switch-network.ps1\"' -Verb RunAs"