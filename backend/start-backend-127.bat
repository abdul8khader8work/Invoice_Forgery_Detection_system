@echo off
title BACKEND - 127.0.0.1 FOR FLUTTER
echo ========================================
echo   STARTING BACKEND FOR FLUTTER WEB
echo ========================================
echo.

cd /d "D:\Projects\invoice_forgery_system\backend"

echo Killing any existing backend processes...
taskkill /f /im uvicorn.exe 2>nul
timeout /t 2 /nobreak >nul

echo Activating virtual environment...
call venv\Scripts\activate

echo.
echo Starting backend on 127.0.0.1:8000...
echo Flutter Web will connect to this address!
echo.
echo KEEP THIS WINDOW OPEN!
echo ========================================

uvicorn main:app --host 127.0.0.1 --port 8000 --reload

pause
