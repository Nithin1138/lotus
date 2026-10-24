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
Write-Host "  ║          Drag. Dial. Done. • Universal Desktop Actions             ║" -ForegroundColor Cyan
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
Write-Host "→ Installation destination: $installDir" -ForegroundColor Gray

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

# 5. Download Installer (Ultra-fast direct edge download ~66 MB)
$downloadUrl = "https://dropdial.app/downloads/DropDial-Setup.exe"
$fallbackUrl = "https://dropdial.app/api/releases?download=DropDial-Setup.exe"
$tempSetup = Join-Path $env:TEMP ("DropDial-Setup-" + [System.Guid]::NewGuid().ToString("N") + ".exe")

Write-Host "→ Downloading DropDial installer (~66 MB)..." -ForegroundColor Cyan

# Enable modern TLS
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Check for native curl.exe (built into Windows 10/11 - maximum speed)
$curlCmd = $null
$curlCheck = Get-Command curl.exe -ErrorAction SilentlyContinue
if ($curlCheck) {
    $curlCmd = $curlCheck.Source
} elseif (Test-Path "$env:SystemRoot\System32\curl.exe") {
    $curlCmd = "$env:SystemRoot\System32\curl.exe"
} elseif (Test-Path "$env:WINDIR\System32\curl.exe") {
    $curlCmd = "$env:WINDIR\System32\curl.exe"
}

$downloaded = $false

if ($curlCmd) {
    try {
        & $curlCmd -fL --progress-bar $downloadUrl -o $tempSetup
        if ((Test-Path $tempSetup) -and ((Get-Item $tempSetup).Length -gt 10MB)) {
            $downloaded = $true
        }
    } catch {
        # Fall through to .NET buffered download
    }
}

if (-not $downloaded) {
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

    try {
        Download-DropDialFile -Url $downloadUrl -OutPath $tempSetup
    } catch {
        Download-DropDialFile -Url $fallbackUrl -OutPath $tempSetup
    }
}

if (-not (Test-Path $tempSetup) -or ((Get-Item $tempSetup).Length -lt 10MB)) {
    throw "Download failed. Please check your network connection or download DropDial-Setup.exe directly from https://dropdial.app"
}

# 6. Silent Installation
Write-Host "→ Installing DropDial..." -ForegroundColor Cyan
$installProc = Start-Process -FilePath $tempSetup -ArgumentList "/S /D=$installDir" -Wait -PassThru -NoNewWindow

Start-Sleep -Seconds 1
Remove-Item -Path $tempSetup -Force -ErrorAction SilentlyContinue

# Verify installation target
if (-not (Test-Path $exePath)) {
    if (Test-Path (Join-Path $env:LOCALAPPDATA "Programs\DropDial\DropDial.exe")) {
        $exePath = Join-Path $env:LOCALAPPDATA "Programs\DropDial\DropDial.exe"
    } else {
        throw "Installation failed: DropDial.exe was not found in $installDir"
    }
}

Write-Host ""
Write-Host "✓ DropDial installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  Location : $installDir" -ForegroundColor Gray
Write-Host "  Shortcut : Desktop & Start Menu created" -ForegroundColor Gray
Write-Host ""

# 7. Launch DropDial
Write-Host "→ Launching DropDial..." -ForegroundColor Cyan
Start-Process -FilePath $exePath -WorkingDirectory (Split-Path $exePath)

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
