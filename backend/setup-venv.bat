@echo off
echo Setting up Python Virtual Environment...
echo.

:: Create virtual environment if it doesn't exist
if not exist "venv" (
    echo Creating virtual environment...
    python -m venv venv
) else (
    echo Virtual environment already exists.
)

:: Activate virtual environment
echo Activating virtual environment...
call venv\Scripts\activate

:: Install requirements
echo Installing Python dependencies...
pip install -r requirements.txt

echo.
echo ✅ Virtual environment setup complete!
echo Backend is ready to start.
pause
