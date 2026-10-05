#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/Unreal_Opus5_5_GTA.uproject"

find_engine() {
  local candidates=(
    "${UE_ENGINE_DIR:-}"
    "/Users/Shared/Epic Games/UE_5.8"
    "/Applications/Epic Games/UE_5.8"
  )
  for engine in "${candidates[@]}"; do
    if [[ -n "$engine" && -x "$engine/Engine/Build/BatchFiles/RunUAT.sh" ]]; then printf '%s\n' "$engine"; return 0; fi
  done
  local app
  app="$(mdfind "kMDItemFSName == 'UnrealEditor.app'" 2>/dev/null | grep '/UE_5\.8/' | head -n 1 || true)"
  [[ -n "$app" ]] && printf '%s\n' "${app%/Engine/Binaries/Mac/UnrealEditor.app}"
}

ENGINE="$(find_engine)"
if [[ -z "$ENGINE" ]]; then echo "Unreal Engine 5.8 was not found. Set UE_ENGINE_DIR and try again."; read -r; exit 1; fi
if ! xcode-select -p >/dev/null 2>&1; then echo "Xcode command-line tools are required."; read -r; exit 1; fi

"$ENGINE/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
  "-project=$PROJECT" -noP4 -platform=Mac -clientconfig=Development \
  -build -cook -stage -pak -iostore -archive "-archivedirectory=$ROOT/Builds" \
  -map=/Game/GTA/Maps/PortHalcyon -unattended -utf8output -prereqs

echo "Build complete: $ROOT/Builds/Mac/Unreal_Opus5_5_GTA.app"
read -r -p "Press Return to close."
