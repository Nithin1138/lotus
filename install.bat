@echo off
setlocal EnableDelayedExpansion

echo.
echo   ==================================================================
echo                     DropDial for Windows Installer
echo            Drag. Drop. Convert. - Universal Desktop Actions
echo   ==================================================================
echo.

set "INSTALL_DIR=%LOCALAPPDATA%\Programs\DropDial"
set "EXE_PATH=%INSTALL_DIR%\DropDial.exe"
set "TEMP_ZIP=%TEMP%\DropDial-Setup-%RANDOM%.zip"
set "TEMP_DIR=%TEMP%\DropDial-Extract-%RANDOM%"

echo -^> Installation destination: %INSTALL_DIR%

:: Stop any running instance
taskkill /F /IM DropDial.exe >nul 2>&1

:: Create directories
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

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

:: 2. Locate tar.exe (standard PATH or default Windows System32)
set "TAR_CMD="
where tar.exe >nul 2>&1
if not errorlevel 1 (
    set "TAR_CMD=tar.exe"
) else if exist "%SystemRoot%\System32\tar.exe" (
    set "TAR_CMD=%SystemRoot%\System32\tar.exe"
) else if exist "%WINDIR%\System32\tar.exe" (
    set "TAR_CMD=%WINDIR%\System32\tar.exe"
)

:: 3. Locate powershell.exe (standard system locations first to avoid PATH issues)
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

echo -^> Downloading DropDial for Windows...
if defined CURL_CMD (
    "%CURL_CMD%" -fL --progress-bar "https://github.com/Nithin1138/lotus/releases/download/v1.0.1.7/DropDial-Windows-x64.zip" -o "%TEMP_ZIP%"
    if errorlevel 1 (
        echo -^> Trying fallback release endpoint...
        "%CURL_CMD%" -fL --progress-bar "https://dropdial.app/download/win" -o "%TEMP_ZIP%"
    )
)

if not exist "%TEMP_ZIP%" (
    if defined PS_CMD (
        echo -^> Downloading via PowerShell...
        "%PS_CMD%" -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13; try { (New-Object System.Net.WebClient).DownloadFile('https://github.com/Nithin1138/lotus/releases/download/v1.0.1.7/DropDial-Windows-x64.zip', '%TEMP_ZIP%') } catch { (New-Object System.Net.WebClient).DownloadFile('https://dropdial.app/download/win', '%TEMP_ZIP%') }"
    )
)

if not exist "%TEMP_ZIP%" (
    echo [ERROR] Download failed. Please check your internet connection or download DropDial-Setup.exe directly from https://dropdial.app
    exit /b 1
)

echo -^> Extracting application files...
if defined TAR_CMD (
    "%TAR_CMD%" -xf "%TEMP_ZIP%" -C "%TEMP_DIR%" >nul 2>&1
)

set "FOUND_EXE=0"
if exist "%TEMP_DIR%\DropDial.exe" set "FOUND_EXE=1"
for /d %%D in ("%TEMP_DIR%\*") do (
    if exist "%%D\DropDial.exe" set "FOUND_EXE=1"
)

if "%FOUND_EXE%"=="0" (
    if defined PS_CMD (
        "%PS_CMD%" -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%TEMP_ZIP%' -DestinationPath '%TEMP_DIR%' -Force"
    )
)

:: Move files from extracted folder into INSTALL_DIR
if exist "%TEMP_DIR%\DropDial.exe" (
    xcopy /E /Y /Q "%TEMP_DIR%\*" "%INSTALL_DIR%\" >nul
) else (
    for /d %%D in ("%TEMP_DIR%\*") do (
        if exist "%%D\DropDial.exe" (
            xcopy /E /Y /Q "%%D\*" "%INSTALL_DIR%\" >nul
        )
    )
)

:: Clean up temporary files
del /f /q "%TEMP_ZIP%" >nul 2>&1
rmdir /s /q "%TEMP_DIR%" >nul 2>&1

echo -^> Creating desktop and start menu shortcuts...
if defined PS_CMD (
    "%PS_CMD%" -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $d = [IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'DropDial.lnk'); $s = $ws.CreateShortcut($d); $s.TargetPath = '%EXE_PATH%'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Save(); $sm = [IO.Path]::Combine([Environment]::GetFolderPath('Programs'), 'DropDial.lnk'); $s2 = $ws.CreateShortcut($sm); $s2.TargetPath = '%EXE_PATH%'; $s2.WorkingDirectory = '%INSTALL_DIR%'; $s2.Save()" >nul 2>&1
) else (
    echo Set oWS = WScript.CreateObject("WScript.Shell") > "%TEMP%\shortcut.vbs"
    echo sLinkFile = oWS.SpecialFolders("Desktop") ^& "\DropDial.lnk" >> "%TEMP%\shortcut.vbs"
    echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%TEMP%\shortcut.vbs"
    echo oLink.TargetPath = "%EXE_PATH%" >> "%TEMP%\shortcut.vbs"
    echo oLink.WorkingDirectory = "%INSTALL_DIR%" >> "%TEMP%\shortcut.vbs"
    echo oLink.Save >> "%TEMP%\shortcut.vbs"
    cscript //nologo "%TEMP%\shortcut.vbs" >nul 2>&1
    del /f /q "%TEMP%\shortcut.vbs" >nul 2>&1
)

echo -^> Launching DropDial...
start "" "%EXE_PATH%"

echo.
echo   ==================================================================
echo     DropDial installed successfully and is now running!
echo   ==================================================================
echo.

endlocal
