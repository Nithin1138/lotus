# ==============================================================================
#  DropDial Universal Windows Installer
#  One-line install in PowerShell:
#    irm https://raw.githubusercontent.com/Nithin1138/lotus/main/install.ps1 | iex
# ==============================================================================

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  ╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                     DropDial for Windows                           ║" -ForegroundColor Cyan
Write-Host "  ║          Drag. Drop. Convert. • Universal Desktop Actions          ║" -ForegroundColor Cyan
Write-Host "  ╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# 1. Architecture check
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Error "DropDial requires a 64-bit version of Windows 10 or Windows 11."
    exit 1
}

# 2. Setup destinations
$installDir = Join-Path $env:LOCALAPPDATA "Programs\DropDial"
$exePath = Join-Path $installDir "DropDial.exe"
Write-Host "→ Installation target: $installDir" -ForegroundColor Gray

# 3. Terminate running DropDial instance if any
$running = Get-Process -Name "DropDial" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "→ Stopping running DropDial process..." -ForegroundColor Gray
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 700
}

# 4. Prepare install directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# 5. Resolve Release Asset URL
$downloadUrl = "https://dropdial.app/api/releases?download=DropDial-Windows-x64.zip"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $releaseInfo = Invoke-RestMethod -Uri "https://dropdial.app/api/releases/latest" -Headers @{ "User-Agent" = "DropDial-Installer" } -TimeoutSec 6 -ErrorAction SilentlyContinue
    if ($releaseInfo -and $releaseInfo.assets) {
        $winAsset = $releaseInfo.assets | Where-Object { 
            $_.name -like "*win*.zip" -or $_.name -like "*windows*.zip"
        } | Select-Object -First 1
        if ($winAsset) {
            $downloadUrl = $winAsset.browser_download_url
        }
    }
} catch {
    # Fallback to default endpoint
}

$tempZip = Join-Path $env:TEMP ("DropDial-Setup-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
$tempExtract = Join-Path $env:TEMP ("DropDial-Extract-" + [System.Guid]::NewGuid().ToString("N"))

Write-Host "→ Downloading DropDial for Windows..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Use WebClient for clean progress and reliability across Windows versions
$wc = New-Object System.Net.WebClient
$wc.Headers.Add("User-Agent", "DropDial-Installer")
$wc.DownloadFile($downloadUrl, $tempZip)
$wc.Dispose()

Write-Host "→ Extracting application files..." -ForegroundColor Cyan
Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force

# Locate DropDial folder or files
$sourceDir = if (Test-Path (Join-Path $tempExtract "DropDial\DropDial.exe")) {
    Join-Path $tempExtract "DropDial"
} elseif (Test-Path (Join-Path $tempExtract "DropDial.exe")) {
    $tempExtract
} else {
    $found = Get-ChildItem -Path $tempExtract -Recurse -Filter "DropDial.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { $found.DirectoryName } else { $tempExtract }
}

Write-Host "→ Installing application to $installDir..." -ForegroundColor Cyan
Copy-Item -Path "$sourceDir\*" -Destination $installDir -Recurse -Force

# Cleanup temp files
Remove-Item -Path $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item -Path $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

# 6. Create Shortcuts (Start Menu & Desktop)
Write-Host "→ Registering desktop & start menu shortcuts..." -ForegroundColor Gray
$wsh = New-Object -ComObject WScript.Shell

# Start Menu Shortcut
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$startMenuShortcut = Join-Path $startMenuDir "DropDial.lnk"
$shortcut = $wsh.CreateShortcut($startMenuShortcut)
$shortcut.TargetPath = $exePath
$shortcut.WorkingDirectory = $installDir
$shortcut.Description = "DropDial - Drag. Drop. Convert."
$shortcut.IconLocation = "$exePath,0"
$shortcut.Save()

# Desktop Shortcut
$desktopDir = [Environment]::GetFolderPath('Desktop')
$desktopShortcut = Join-Path $desktopDir "DropDial.lnk"
$dShortcut = $wsh.CreateShortcut($desktopShortcut)
$dShortcut.TargetPath = $exePath
$dShortcut.WorkingDirectory = $installDir
$dShortcut.Description = "DropDial - Drag. Drop. Convert."
$dShortcut.IconLocation = "$exePath,0"
$dShortcut.Save()

Write-Host ""
Write-Host "✓ DropDial installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Location : $installDir" -ForegroundColor Gray
Write-Host "  Shortcut : Desktop & Start Menu created" -ForegroundColor Gray
Write-Host ""

# 7. Launch DropDial
Write-Host "→ Launching DropDial..." -ForegroundColor Cyan
Start-Process -FilePath $exePath -WorkingDirectory $installDir

Write-Host ""
Write-Host "Controls & Shortcuts:" -ForegroundColor Yellow
Write-Host "  • Drag any file to summon the Radial Wheel"
Write-Host "  • Shift + Drag   : Conversion Wheel (Images, Videos, PDFs, Docs)"
Write-Host "  • Ctrl + Drag    : Actions Wheel (Shelf, Paths, Privacy metadata)"
Write-Host "  • F8 / F9 / F10  : Quick Tool Hotkeys"
Write-Host "  • System Tray    : DropDial is running in your taskbar tray"
Write-Host ""
Write-Host "Enjoy DropDial!" -ForegroundColor Green
Write-Host ""
