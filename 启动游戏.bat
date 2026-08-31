@echo off
rem Launch "REAL RACING" local server + browser (Windows, zero dependency).
rem All friendly messages live in start-game.ps1 (UTF-8 with BOM).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-game.ps1" %*
