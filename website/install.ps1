# ==============================================================================
#  DropDial Universal Windows Installer
#  One-line install in PowerShell:
#    irm https://dropdial.app/install.ps1 | iex
# ==============================================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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
$hasRuntime = (Test-Path (Join-Path $installDir "runtime\python\python.exe")) -and (Test-Path (Join-Path $installDir "runtime\ffmpeg\ffmpeg.exe"))
Write-Host "→ Installation target: $installDir" -ForegroundColor Gray

# 3. Terminate running DropDial instance if any
$running = Get-Process -Name "DropDial" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "→ Stopping running DropDial process..." -ForegroundColor Gray
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    $waitAttempts = 0
    while ((Get-Process -Name "DropDial" -ErrorAction SilentlyContinue) -and $waitAttempts -lt 20) {
        Start-Sleep -Milliseconds 250
        $waitAttempts++
    }
}

# 4. Prepare install directory
if (-not (Test-Path $installDir)) {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
}

# 5. Resolve Release Asset URL
$downloadUrl = "https://github.com/Nithin1138/lotus/releases/download/v1.0.1.6/DropDial-Windows-x64.zip"
$isLightweightUpdate = $false

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    $releaseInfo = $null
    try {
        $releaseInfo = Invoke-RestMethod -Uri "https://dropdial.app/api/releases/latest" -Headers @{ "User-Agent" = "DropDial-Installer" } -TimeoutSec 6 -ErrorAction SilentlyContinue
    } catch {}

    if (-not $releaseInfo -or -not $releaseInfo.assets) {
        try {
            $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/Nithin1138/lotus/releases/latest" -Headers @{ "User-Agent" = "DropDial-Installer" } -TimeoutSec 6 -ErrorAction SilentlyContinue
        } catch {}
    }

    if ($releaseInfo -and $releaseInfo.assets) {
        $updateAsset = $releaseInfo.assets | Where-Object { $_.name -like "*update*.zip" } | Select-Object -First 1
        $fullAsset = $releaseInfo.assets | Where-Object { 
            ($_.name -like "*win*.zip" -or $_.name -like "*windows*.zip") -and ($_.name -notlike "*update*")
        } | Select-Object -First 1

        if ($hasRuntime -and $updateAsset) {
            $downloadUrl = $updateAsset.browser_download_url
            $isLightweightUpdate = $true
        } elseif ($fullAsset) {
            $downloadUrl = $fullAsset.browser_download_url
        }
    }
} catch {
    # Fallback to default endpoint
}

$tempZip = Join-Path $env:TEMP ("DropDial-Setup-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
$tempExtract = Join-Path $env:TEMP ("DropDial-Extract-" + [System.Guid]::NewGuid().ToString("N"))

if ($isLightweightUpdate) {
    Write-Host "→ Existing runtime detected. Downloading fast application update (~15 MB)..." -ForegroundColor Cyan
} else {
    Write-Host "→ Downloading DropDial for Windows..." -ForegroundColor Cyan
}

function Download-DropDialFile {
    param(
        [string]$Url,
        [string]$OutPath
    )

    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Method = "GET"
        $req.UserAgent = "DropDial-Installer"
        $req.Timeout = 300000

        $resp = $req.GetResponse()
        $totalLength = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::Create($OutPath)

        $bufSize = 65536
        $buf = New-Object byte[] $bufSize
        $totalBytesRead = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $uiSw = [System.Diagnostics.Stopwatch]::StartNew()

        while (($bytesRead = $stream.Read($buf, 0, $bufSize)) -gt 0) {
            $fs.Write($buf, 0, $bytesRead)
            $totalBytesRead += $bytesRead

            if ($uiSw.ElapsedMilliseconds -ge 150 -or $totalBytesRead -eq $totalLength) {
                $uiSw.Restart()
                $elapsedSec = [Math]::Max(0.001, $sw.Elapsed.TotalSeconds)
                $speedMBs = ($totalBytesRead / 1MB) / $elapsedSec

                if ($totalLength -gt 0) {
                    $pct = [int](($totalBytesRead * 100) / $totalLength)
                    $barWidth = 22
                    $filled = [int](($pct * $barWidth) / 100)
                    $unfilled = $barWidth - $filled
                    $bar = ("=" * $filled) + (">" * [Math]::Min(1, $unfilled)) + (" " * [Math]::Max(0, $unfilled - 1))
                    $curMB = $totalBytesRead / 1MB
                    $totMB = $totalLength / 1MB
                    Write-Host -NoNewline ("`r  [{0}] {1,3}% ({2:N1} MB / {3:N1} MB) - {4:N1} MB/s   " -f $bar, $pct, $curMB, $totMB, $speedMBs)
                } else {
                    $curMB = $totalBytesRead / 1MB
                    Write-Host -NoNewline ("`r  Downloading: {0:N1} MB ({1:N1} MB/s)   " -f $curMB, $speedMBs)
                }
            }
        }
        Write-Host ""
    } catch {
        # Fallback to WebClient if buffered stream encounters issues
        Write-Host "`n→ Resuming download via standard client..." -ForegroundColor Gray
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "DropDial-Installer")
        $wc.DownloadFile($Url, $OutPath)
        $wc.Dispose()
    } finally {
        if ($fs) { $fs.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ($resp) { $resp.Dispose() }
    }
}

Download-DropDialFile -Url $downloadUrl -OutPath $tempZip

Write-Host "→ Extracting application files..." -ForegroundColor Cyan
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($tempZip, $tempExtract)
} catch {
    Expand-Archive -LiteralPath $tempZip -DestinationPath $tempExtract -Force
}

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
try {
    Copy-Item -Path "$sourceDir\*" -Destination $installDir -Recurse -Force
} catch {
    Start-Sleep -Seconds 1
    & robocopy $sourceDir $installDir /E /IS /IT /NP /R:3 /W:1 | Out-Null
}

if (-not (Test-Path $exePath)) {
    throw "Installation failed: DropDial.exe was not found in $installDir"
}

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
