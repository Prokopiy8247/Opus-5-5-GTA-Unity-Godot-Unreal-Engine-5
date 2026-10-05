param([string]$EngineDir = "")
$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectFile = Join-Path $projectRoot "Unreal_Opus5_5_GTA.uproject"

if (-not $EngineDir) {
    $registryKeys = @(
        "HKLM:\SOFTWARE\EpicGames\Unreal Engine\5.8",
        "HKCU:\SOFTWARE\Epic Games\Unreal Engine\Builds"
    )
    foreach ($key in $registryKeys) {
        if (-not (Test-Path $key)) { continue }
        $props = Get-ItemProperty $key
        if ($props.InstalledDirectory) { $EngineDir = $props.InstalledDirectory; break }
        foreach ($property in $props.PSObject.Properties) {
            if ($property.Name -match "5\.8" -and (Test-Path $property.Value)) { $EngineDir = $property.Value; break }
        }
    }
}
if (-not $EngineDir) {
    foreach ($candidate in @("C:\Program Files\Epic Games\UE_5.8", "D:\Epic Games\UE_5.8")) {
        if (Test-Path $candidate) { $EngineDir = $candidate; break }
    }
}
$uat = Join-Path $EngineDir "Engine\Build\BatchFiles\RunUAT.bat"
if (-not (Test-Path $uat)) { throw "Unreal Engine 5.8 was not found. Pass -EngineDir with the UE_5.8 directory." }

$output = Join-Path $projectRoot "Builds"
& $uat BuildCookRun "-project=$projectFile" -noP4 -platform=Win64 -clientconfig=Development -build -cook -stage -pak -iostore -archive "-archivedirectory=$output" -map=/Game/GTA/Maps/PortHalcyon -unattended -utf8output -prereqs
if ($LASTEXITCODE -ne 0) { throw "Unreal packaging failed with exit code $LASTEXITCODE." }
Write-Host "Build complete: $output\Windows\Unreal_Opus5_5_GTA.exe"
