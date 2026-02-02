@echo off
SETLOCAL EnableDelayedExpansion

echo ====================================================
echo  Allben Kitchen Manager Windows Deployment Script
echo ====================================================

:: 1. Flutter Build
echo [1/5] Building Flutter Windows application...
cd admin_console
call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter build failed.
    pause
    exit /b %ERRORLEVEL%
)
cd ..

:: 2. Prepare Release Directory
set "RELEASE_ROOT=admin_console\build\windows\x64\runner\Release"
set "ASSETS_DIR=%RELEASE_ROOT%\python_assets"
set "PYTHON_SOURCE=python_packetSnip"

echo [2/5] Cleaning and preparing asset directory...
if exist "%ASSETS_DIR%" rmdir /s /q "%ASSETS_DIR%"
mkdir "%ASSETS_DIR%"

:: 3. Prepare Python Environment
echo [3/5] Setting up Python environment...
:: OPTION A: Using system python to create a venv (Fallback)
:: OPTION B: Copying a pre-downloaded embedded python (Recommended for portability)

set "PYTHON_EMBED_DIR=%ASSETS_DIR%\python"
set "PYTHON_SOURCE_RUNTIME=python_runtime"

echo [3/5] Setting up Embedded Python environment...
if exist "%PYTHON_SOURCE_RUNTIME%" (
    echo [INFO] Copying Embedded Python from %PYTHON_SOURCE_RUNTIME%...
    xcopy "%PYTHON_SOURCE_RUNTIME%" "%PYTHON_EMBED_DIR%" /E /I /Y
    
    if exist "%PYTHON_EMBED_DIR%\python.exe" (
        echo [VERIFY] python.exe exists in %PYTHON_EMBED_DIR%.
    ) else (
        echo [ERROR] python.exe NOT found in %PYTHON_EMBED_DIR%!
        pause
        exit /b 1
    )
) else (
    echo [ERROR] %PYTHON_SOURCE_RUNTIME% folder not found!
    pause
    exit /b 1
)

:: 4. Copy Sniffer Scripts
echo [4/5] Copying sniffer scripts...
copy "%PYTHON_SOURCE%\main.py" "%ASSETS_DIR%\"
copy "%PYTHON_SOURCE%\requirements.txt" "%ASSETS_DIR%\"

:: 5. Final Packaging (Inno Setup)
echo [5/5] Generating final installer (Allben_Setup_v2.0.exe)...
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" innoSetup\setup_script.iss
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Inno Setup build failed.
    pause
    exit /b %ERRORLEVEL%
)

echo.
echo ====================================================
echo  FULL DEPLOYMENT SUCCESSFUL!
echo  Installer: %CD%\Allben_Setup_v2.0.exe
echo ====================================================
pause
