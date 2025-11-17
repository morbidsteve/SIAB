@echo off
REM SIAB Provisioner Launcher for Windows

REM Check if Python is available
python --version >nul 2>&1
if errorlevel 1 (
    echo Python is required but not installed.
    echo Please install Python from https://www.python.org/downloads/
    echo Make sure to check "Add Python to PATH" during installation.
    pause
    exit /b 1
)

REM Get the directory where this script is located
set DIR=%~dp0

REM Run the GUI
python "%DIR%siab-provisioner-gui.py"

pause
