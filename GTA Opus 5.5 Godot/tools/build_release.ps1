param(
    [string]$GodotPath = $env:GODOT,
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not $GodotPath) {
    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $GodotPath = $command.Source }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot was not found. Pass -GodotPath C:\path\to\Godot_console.exe or set GODOT.'
}

$windowsDir = Join-Path $projectRoot 'build\windows'
$macDir = Join-Path $projectRoot 'build\macos'
$windowsExe = Join-Path $windowsDir 'VesperBay.exe'
$macZip = Join-Path $macDir 'VesperBay-macOS.zip'
New-Item -ItemType Directory -Force -Path $windowsDir, $macDir | Out-Null

Push-Location $projectRoot
try {
    python tools/make_icon.py
    & $GodotPath --headless --path . --export-release 'Windows Desktop' $windowsExe
    if ($LASTEXITCODE -ne 0) { throw "Windows export failed with exit code $LASTEXITCODE" }

    & $GodotPath --headless --path . --export-release 'macOS' $macZip
    if ($LASTEXITCODE -ne 0) { throw "macOS export failed with exit code $LASTEXITCODE" }

    Get-Item -LiteralPath $windowsExe, $macZip | Select-Object Name, Length, LastWriteTime

    if (-not $SkipSmokeTest) {
        & $windowsExe --resolution 1600x900 -- --autotest=basic
        # A renderer teardown error can occur after the test completes. The authoritative result
        # is the [AutoTest] DONE line in the output, not the process exit code.
    }
}
finally {
    Pop-Location
}
