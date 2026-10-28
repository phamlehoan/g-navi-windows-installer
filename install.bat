@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set RC=%ERRORLEVEL%
if not defined GNAVI_NOPAUSE pause
exit /b %RC%
