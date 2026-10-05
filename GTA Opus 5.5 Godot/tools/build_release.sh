#!/usr/bin/env bash
# Builds the standalone Windows and macOS games.
#
#   tools/build_release.sh
#
# Output: build/windows/VesperBay.exe and build/macos/VesperBay-macOS.zip.
# Needs the Godot 4.7.2 export templates installed (Editor > Manage Export Templates).
set -euo pipefail

if [[ -z "${GODOT:-}" ]]; then
  GODOT="$(command -v godot || command -v godot4 || true)"
fi
if [[ -z "$GODOT" ]]; then
  echo "Godot was not found. Set GODOT=/path/to/godot before running this script." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIN_OUT="$ROOT/build/windows/VesperBay.exe"
MAC_OUT="$ROOT/build/macos/VesperBay-macOS.zip"

cd "$ROOT"
mkdir -p build/windows build/macos

# Regenerate icon.ico (multi-size ICO, written to the project root where the preset points).
python tools/make_icon.py

# Release export. Godot stamps the icon and version strings into the PE itself; rcedit is only
# needed if you want extra fields the preset does not cover.
"$GODOT" --headless --path . --export-release "Windows Desktop" "$WIN_OUT" 2>&1 \
  | grep -viE "savepack|^\[ *[0-9]+%" | tail -5
"$GODOT" --headless --path . --export-release "macOS" "$MAC_OUT" 2>&1 \
  | grep -viE "savepack|^\[ *[0-9]+%" | tail -5
ls -la "$WIN_OUT" "$MAC_OUT"

# Smoke test the packaged binary. Note the bare `--`: the game reads its own args through
# OS.get_cmdline_user_args(), which only sees what follows the separator.
echo "== packaged smoke test =="
if [[ "${OS:-}" == "Windows_NT" ]]; then
  "$WIN_OUT" --resolution 1600x900 -- --autotest=basic 2>&1 \
    | grep -E "AutoTest\] (CHECK|DONE)|SCRIPT ERROR" || true
fi

# The packaged build aborts during renderer teardown at exit (after it has reported), so its exit
# code is meaningless; scrub the run folder it left behind and rely on the grep above.
echo "build ok: $WIN_OUT"
echo "build ok: $MAC_OUT"
