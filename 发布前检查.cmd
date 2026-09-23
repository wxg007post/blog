@echo off
rem Pre-publish check launcher. Keep this file ASCII-only and CRLF.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0发布前检查.ps1"
echo.
pause
