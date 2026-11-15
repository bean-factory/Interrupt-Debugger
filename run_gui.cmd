@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Create the Python environment first. See README.md.
    pause
    exit /b 1
)
".venv\Scripts\python.exe" -c "import paramiko" >nul 2>&1
if errorlevel 1 (
    echo Installing the SSH connection dependency...
    ".venv\Scripts\python.exe" -m pip install paramiko==3.5.1
    if errorlevel 1 (
        pause
        exit /b 1
    )
)
".venv\Scripts\python.exe" tools\run_demo.py %*
if errorlevel 1 (
    pause
    exit /b 1
)
exit /b 0
