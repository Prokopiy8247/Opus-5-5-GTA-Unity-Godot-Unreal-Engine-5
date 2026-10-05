#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/Unreal_Opus5_5_GTA.uproject"

find_editor() {
  local candidates=(
    "${UE_ENGINE_DIR:-}/Engine/Binaries/Mac/UnrealEditor.app"
    "/Users/Shared/Epic Games/UE_5.8/Engine/Binaries/Mac/UnrealEditor.app"
    "/Applications/Epic Games/UE_5.8/Engine/Binaries/Mac/UnrealEditor.app"
  )
  for app in "${candidates[@]}"; do
    if [[ -n "$app" && -d "$app" ]]; then printf '%s\n' "$app"; return 0; fi
  done
  mdfind "kMDItemFSName == 'UnrealEditor.app'" 2>/dev/null | grep '/UE_5\.8/' | head -n 1 || true
}

EDITOR_APP="$(find_editor)"
if [[ -z "$EDITOR_APP" ]]; then
  osascript -e 'display dialog "Unreal Engine 5.8 was not found. Install it through Epic Games Launcher, then run this file again." buttons {"OK"} default button "OK" with icon stop'
  exit 1
fi
open -a "$EDITOR_APP" "$PROJECT"
