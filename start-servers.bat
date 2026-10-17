@echo off
chcp 65001 >nul
title Emergency - Servers
echo ============================================
echo  Emergency Backend - Local Stack (self-healing)
echo ============================================

set PG=G:\Emergency\backend\.localdb\bin\pg_ctl.exe
set PGDATA=G:\Emergency\backend\.localdb\data
set PY=G:\Emergency\backend\.venv\Scripts\python.exe
set ADB=C:\Users\ZHIRO\AppData\Local\Android\Sdk\platform-tools\adb.exe

echo [1/5] PostgreSQL...
"%PG%" -D "%PGDATA%" status 2>nul | find "running" >nul
if errorlevel 1 (
    "%PG%" -D "%PGDATA%" -o "-p 5433" -l "G:\Emergency\backend\.localdb\pg2.log" start
) else (
    echo   already running - skip
)
timeout /t 2 /nobreak >nul

echo [2/5] ensure database emergency_dev...
"%PY%" -c "import psycopg; c=psycopg.connect('host=127.0.0.1 port=5433 dbname=postgres user=postgres', autocommit=True); exec('try:\n c.execute('CREATE DATABASE emergency_dev')\n print('  created')\nexcept Exception as e:\n print('  exists')')"

echo [3/5] migrate...
cd /d G:\Emergency\backend
"%PY%" manage.py migrate --noinput 2>&1 | find /c "Applying" >nul && echo   done

echo [4/5] Django :8001...
netstat -ano | findstr ":8001" | findstr "LISTENING" >nul
if errorlevel 1 (
    start "Django :8001" cmd /k "cd /d G:\Emergency\backend && G:\Emergency\backend\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8001 --noreload"
    timeout /t 6 /nobreak >nul
) else (
    echo   already listening - skip
)

echo [5/5] phone tunnel + health...
"%ADB%" reverse tcp:8001 tcp:8001 2>nul
curl -s -o nul -w "  Django health: HTTP %%{http_code}  ^(401 = OK^)\n" --max-time 8 http://127.0.0.1:8001/api/v1/users/me

echo.
echo ============================================
echo  If health shows 401 = ALL GOOD.
echo  Keep the "Django :8001" window OPEN.
echo ============================================
pause
