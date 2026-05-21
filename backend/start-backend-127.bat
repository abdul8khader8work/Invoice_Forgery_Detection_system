@echo off
title BACKEND - ALL INTERFACES FOR ALL PLATFORMS
echo ========================================
echo   STARTING BACKEND FOR ALL PLATFORMS
echo ========================================
echo.

cd /d "D:\Projects\invoice_forgery_system\backend"

echo Killing any existing backend processes...
taskkill /f /im uvicorn.exe 2>nul
taskkill /f /im python.exe 2>nul
timeout /t 2 /nobreak >nul

echo Activating virtual environment...
call venv\Scripts\activate

echo.
echo Starting backend on 0.0.0.0:8000...
echo Accessible from:
echo   - Web/Desktop: http://localhost:8000
echo   - Mobile: http://10.236.207.92:8000
echo   - Network: http://[YOUR_IP]:8000
echo.
echo KEEP THIS WINDOW OPEN!
echo ========================================

uvicorn main:app --host 0.0.0.0 --port 8000 --reload

pause
