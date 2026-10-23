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

echo -^> Downloading DropDial for Windows via curl...
curl -fL --progress-bar "https://dropdial.app/download/win" -o "%TEMP_ZIP%"
if errorlevel 1 (
    echo -^> Trying fallback release endpoint...
    curl -fL --progress-bar "https://github.com/Nithin1138/lotus/releases/download/v1.0.1.6/DropDial-Windows-x64.zip" -o "%TEMP_ZIP%"
)

if not exist "%TEMP_ZIP%" (
    echo [ERROR] Download failed. Please check your internet connection and try again.
    exit /b 1
)

echo -^> Extracting application files...
tar -xf "%TEMP_ZIP%" -C "%TEMP_DIR%" >nul 2>&1
if errorlevel 1 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Expand-Archive -LiteralPath '%TEMP_ZIP%' -DestinationPath '%TEMP_DIR%' -Force"
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
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $d = [IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'DropDial.lnk'); $s = $ws.CreateShortcut($d); $s.TargetPath = '%EXE_PATH%'; $s.WorkingDirectory = '%INSTALL_DIR%'; $s.Save(); $sm = [IO.Path]::Combine([Environment]::GetFolderPath('Programs'), 'DropDial.lnk'); $s2 = $ws.CreateShortcut($sm); $s2.TargetPath = '%EXE_PATH%'; $s2.WorkingDirectory = '%INSTALL_DIR%'; $s2.Save()"

echo -^> Launching DropDial...
start "" "%EXE_PATH%"

echo.
echo   ==================================================================
echo     DropDial installed successfully and is now running!
echo   ==================================================================
echo.

endlocal
