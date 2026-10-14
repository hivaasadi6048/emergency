@echo off
chcp 65001 >nul
title Emergency - Servers
echo ============================================
echo  Emergency Backend - Local Stack
echo ============================================

echo [1/3] PostgreSQL (port 5433)...
"G:\Emergency\backend\.localdb\bin\pg_ctl.exe" -D "G:\Emergency\backend\.localdb\data" -o "-p 5433" -l "G:\Emergency\backend\.localdb\postgres.log" start
timeout /t 2 /nobreak >nul

echo [2/3] Django (port 8001) in new window...
start "Django :8001" cmd /k "cd /d G:\Emergency\backend && G:\Emergency\backend\.venv\Scripts\python.exe manage.py runserver 0.0.0.0:8001 --noreload"
timeout /t 6 /nobreak >nul

echo [3/3] adb reverse (phone must be connected)...
"C:\Users\ZHIRO\AppData\Local\Android\Sdk\platform-tools\adb.exe" reverse tcp:8001 tcp:8001

echo.
curl -s -o nul -w "  Django health: HTTP %%{http_code}  (401 = OK)\n" --max-time 8 http://127.0.0.1:8001/api/v1/users/me
echo.
echo ============================================
echo  DONE. Keep the "Django :8001" window OPEN.
echo  (adb reverse resets if you unplug the phone:
echo   re-run this file, or just run step 3 again)
echo ============================================
pause
