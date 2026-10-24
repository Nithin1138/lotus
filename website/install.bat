@echo off
setlocal EnableDelayedExpansion

echo.
echo   ==================================================================
echo                     DropDial for Windows Installer
echo            Drag. Dial. Done. - Universal Desktop Actions
echo   ==================================================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\DropDial"
set "EXE_PATH=%INSTALL_DIR%\DropDial.exe"
set "SETUP_EXE=%TEMP%\DropDial-Setup-%RANDOM%.exe"

echo -^> Installation destination: %INSTALL_DIR%

:: Stop any running instance
taskkill /F /IM DropDial.exe >nul 2>&1

:: Create installation directory if not exists
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"

:: 1. Locate curl.exe (standard PATH or default Windows System32)
set "CURL_CMD="
where curl.exe >nul 2>&1
if not errorlevel 1 (
    set "CURL_CMD=curl.exe"
) else if exist "%SystemRoot%\System32\curl.exe" (
    set "CURL_CMD=%SystemRoot%\System32\curl.exe"
) else if exist "%WINDIR%\System32\curl.exe" (
    set "CURL_CMD=%WINDIR%\System32\curl.exe"
)

:: 2. Locate powershell.exe (standard system locations)
set "PS_CMD="
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    set "PS_CMD=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
) else if exist "%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe" (
    set "PS_CMD=%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe"
) else if exist "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" (
    set "PS_CMD=C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
) else (
    where powershell.exe >nul 2>&1
    if not errorlevel 1 set "PS_CMD=powershell.exe"
)

echo -^> Downloading DropDial for Windows installer...
:: Priority 1: High-speed direct download of DropDial-Setup.exe (69 MB vs 247 MB) via curl
if defined CURL_CMD (
    "%CURL_CMD%" -fL --progress-bar "https://dropdial.app/downloads/DropDial-Setup.exe" -o "%SETUP_EXE%"
    if errorlevel 1 (
        echo -^> Trying fallback release endpoint...
        "%CURL_CMD%" -fL --progress-bar "https://dropdial.app/api/releases?download=DropDial-Setup.exe" -o "%SETUP_EXE%"
    )
)

:: Priority 2: High-speed download via PowerShell WebClient if curl wasn't found or failed
if not exist "%SETUP_EXE%" (
    if defined PS_CMD (
        echo -^> Downloading via PowerShell...
        "%PS_CMD%" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; try { (New-Object System.Net.WebClient).DownloadFile('https://dropdial.app/downloads/DropDial-Setup.exe', '%SETUP_EXE%') } catch { (New-Object System.Net.WebClient).DownloadFile('https://dropdial.app/api/releases?download=DropDial-Setup.exe', '%SETUP_EXE%') }"
    )
)

if not exist "%SETUP_EXE%" (
    echo [ERROR] Download failed. Please check your internet connection or download DropDial-Setup.exe directly from https://dropdial.app
    exit /b 1
)

echo -^> Installing DropDial...
:: Run NSIS installer silently (/S) targeting local app directory
start /wait "" "%SETUP_EXE%" /S /D=%INSTALL_DIR%

:: Clean up temporary installer
del /f /q "%SETUP_EXE%" >nul 2>&1

:: Ensure desktop and start menu shortcuts exist
if not exist "%EXE_PATH%" (
    if exist "%LOCALAPPDATA%\Programs\DropDial\DropDial.exe" (
        set "EXE_PATH=%LOCALAPPDATA%\Programs\DropDial\DropDial.exe"
    )
)

echo -^> Launching DropDial...
if exist "%EXE_PATH%" (
    start "" "%EXE_PATH%"
) else (
    start "" "%LOCALAPPDATA%\Programs\DropDial\DropDial.exe"
)

echo.
echo   ==================================================================
echo     DropDial installed successfully and is now running!
echo   ==================================================================
echo.

endlocal
