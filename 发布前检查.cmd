@echo off
rem 双击本文件即可运行"发布前检查"。
rem 中文路径在 cmd 下容易乱码，所以先切到 UTF-8 代码页，再调用 PowerShell 脚本。
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0发布前检查.ps1"
echo.
pause
