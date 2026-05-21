@echo off
title INVOICE FORGERY DETECTION - START ALL SERVICES
echo ========================================
echo   INVOICE FORGERY DETECTION SYSTEM
echo   Starting Backend and Frontend
echo ========================================
echo.

cd /d "D:\Projects\invoice_forgery_system"

echo Step 1: Starting Backend Server...
echo.

start "Backend Server" cmd /k "cd backend && start-backend-127.bat"

echo Waiting for backend to start (10 seconds)...
timeout /t 10 /nobreak >nul

echo.
echo Step 2: Starting Frontend Application...
echo.

start "Frontend App" cmd /k "cd frontend && flutter run"

echo.
echo ========================================
echo   BOTH SERVICES STARTED!
echo ========================================
echo.
echo Backend: Running on 0.0.0.0:8000
echo Frontend: Running in Flutter
echo.
echo Access URLs:
echo   - Web/Desktop: http://localhost:8000
echo   - Mobile: http://10.236.207.92:8000
echo.
echo Keep both windows open for the system to work!
echo Press any key to exit this launcher (services will continue running)
pause
