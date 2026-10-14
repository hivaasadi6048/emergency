@echo off
chcp 65001 >nul
title Emergency - Stop Servers
echo Stopping Django...
taskkill /FI "WINDOWTITLE eq Django :8001" /T /F >nul 2>&1
for /f "tokens=5" %%p in ('netstat -ano ^| findstr :8001 ^| findstr LISTENING') do taskkill /PID %%p /F >nul 2>&1
echo Stopping PostgreSQL...
"G:\Emergency\backend\.localdb\bin\pg_ctl.exe" -D "G:\Emergency\backend\.localdb\data" stop
echo Done.
pause
