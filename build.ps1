param(
    [switch]$SkipRuntimeCheck,
    [string]$Version = ""
)
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskOutput = Join-Path $taskRoot 'outputs/DropDial'

if ([string]::IsNullOrWhiteSpace($Version) -or ($Version -notmatch '^\d+(\.\d+)*')) {
    if (-not [string]::IsNullOrWhiteSpace($env:VERSION) -and ($env:VERSION -match '^\d+(\.\d+)*')) {
        $Version = $env:VERSION.TrimStart('v')
    } elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_REF_NAME) -and ($env:GITHUB_REF_NAME -match '^v?\d+(\.\d+)*')) {
        $Version = $env:GITHUB_REF_NAME.TrimStart('v')
    } else {
        $Version = "1.0.2.5"
    }
}

if (-not $SkipRuntimeCheck) {
    foreach ($taskFile in @('runtime/python/python.exe', 'runtime/ffmpeg/ffmpeg.exe', 'runtime/ffmpeg/ffprobe.exe', 'runtime/7zip/7z.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $taskOutput $taskFile))) {
            throw "Missing $taskFile. Run python work/prepare-runtime.py first, or copy runtime from a complete build."
        }
    }
}

$publishArgs = @('publish', (Join-Path $taskRoot 'work/DropDial/DropDial.csproj'), '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-o', $taskOutput, '--nologo')
$cleanVer = $Version.TrimStart('v')
if ($cleanVer -match '^\d+(\.\d+){1,3}$') {
    $publishArgs += @("/p:Version=$cleanVer", "/p:AssemblyVersion=$cleanVer", "/p:FileVersion=$cleanVer")
}

dotnet @publishArgs
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed.' }
Copy-Item -LiteralPath (Join-Path $taskRoot 'work/DropDial/backend') -Destination $taskOutput -Recurse -Force
Get-ChildItem -LiteralPath (Join-Path $taskOutput 'backend') -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/usage.md') -Destination (Join-Path $taskOutput 'USAGE.md') -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/dependencies.json') -Destination (Join-Path $taskOutput 'dependencies.json') -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'LICENSE') -Destination (Join-Path $taskOutput 'LICENSE') -Force
# Third-party notices, opened from the tray menu; generated from docs/dependencies.json.
$taskPython = Join-Path $taskOutput 'runtime/python/python.exe'
if (Test-Path -LiteralPath $taskPython) {
    & $taskPython (Join-Path $taskRoot 'work/make-notices.py') (Join-Path $taskOutput 'THIRD-PARTY-NOTICES.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Generating third-party notices failed.' }
} elseif (-not $SkipRuntimeCheck) { throw 'Missing runtime/python; cannot generate third-party notices.' }
Copy-Item -LiteralPath (Join-Path $taskRoot 'docs/validation') -Destination $taskOutput -Recurse -Force
Write-Output "Built: $taskOutput/DropDial.exe"
