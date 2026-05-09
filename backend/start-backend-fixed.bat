@echo off
title BACKEND SERVER - FIXED VERSION
echo ========================================
echo   INVOICE FORGERY DETECTION BACKEND
echo ========================================
echo.

cd /d "D:\Projects\invoice_forgery_system\backend"

echo Activating virtual environment...
call venv\Scripts\activate

echo.
echo Starting backend server on ALL interfaces...
echo This will allow Flutter to connect from any address
echo.
echo Server will be available at:
echo   - http://127.0.0.1:8000
echo   - http://localhost:8000  
echo   - http://0.0.0.0:8000
echo.
echo KEEP THIS WINDOW OPEN!
echo ========================================

uvicorn main:app --host 0.0.0.0 --port 8000 --reload

pause
