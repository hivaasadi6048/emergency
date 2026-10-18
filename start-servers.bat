@echo off
chcp 65001 >nul
title Emergency - Servers
echo ============================================
echo  Emergency Backend - Local Stack
echo ============================================

set PG=G:\Emergency\backend\.localdb\bin\pg_ctl.exe
set PGDATA=G:\Emergency\backend\.localdb\data
set PGLOG=G:\Emergency\backend\.localdb\server.log
set PY=G:\Emergency\backend\.venv\Scripts\python.exe
set ADB=C:\Users\ZHIRO\AppData\Local\Android\Sdk\platform-tools\adb.exe

echo [1/6] PostgreSQL (port 5433)...
del "%PGLOG%" 2>nul
"%PG%" -D "%PGDATA%" status 2>nul | findstr "running" >nul
if errorlevel 1 (
    "%PG%" -D "%PGDATA%" -o "-p 5433" -l "%PGLOG%" start
) else (
    echo   already running - skip
)
timeout /t 3 /nobreak >nul
"%PG%" -D "%PGDATA%" status | findstr "running" >nul
if errorlevel 1 (
    echo   [ERROR] PostgreSQL did NOT start. Log:
    type "%PGLOG%" 2>nul
    pause
    exit /b 1
)

echo [2/6] ensure database emergency_dev...
cd /d G:\Emergency\backend
"%PY%" ensure_dev_db.py

echo [3/6] migrate...
"%PY%" manage.py migrate --noinput

echo [4/6] Django :8001...
netstat -ano | findstr ":8001" | findstr "LISTENING" >nul
if errorlevel 1 (
    start "Django :8001" cmd /k "cd /d G:\Emergency\backend && G:\Emergency\backend\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8001 --noreload"
    timeout /t 7 /nobreak >nul
) else (
    echo   already listening - skip
)

echo [5/6] phone tunnel...
"%ADB%" reverse tcp:8001 tcp:8001 2>nul

echo [6/6] health check...
curl -s -o nul -w "  Django health: HTTP %%{http_code}  (401 = OK)\n" --max-time 10 http://127.0.0.1:8001/api/v1/users/me

echo.
echo ============================================
echo  401 = ALL GOOD. Keep "Django :8001" open.
echo ============================================
pause
