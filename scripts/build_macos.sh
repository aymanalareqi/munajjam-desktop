#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "Build on an Apple Silicon Mac without Rosetta." >&2
  exit 1
fi
PYTHON="$ROOT/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  echo "Run scripts/setup_macos.sh first." >&2
  exit 1
fi
cd "$ROOT"
"$PYTHON" -c 'import platform; assert platform.machine() == "arm64", "Native arm64 Python required"'
"$PYTHON" -m pip install 'pyinstaller>=6.11,<7'
"$PYTHON" -m PyInstaller --noconfirm packaging/munajjam_server.spec
PATH=/usr/bin:/bin "$ROOT/dist/munajjam_server/munajjam_server" --check-runtime
(
  cd munajjam_desktop
  FLUTTER_MACOS_ARM64_ONLY=true flutter build macos --release
)
APP="$ROOT/munajjam_desktop/build/macos/Build/Products/Release/Munajjam.app"
# Python package metadata is data, not a nested macOS code bundle. Its native
# binaries are signed by PyInstaller before the resource tree is sealed here.
BACKEND="$APP/Contents/Resources/backend"
rm -rf "$APP/Contents/MacOS/backend"
rm -rf "$BACKEND"
ditto "$ROOT/dist/munajjam_server" "$BACKEND"
# Models are deliberately outside the signed bundle and survive app upgrades.
# Build a completely offline distribution by shipping the models directory
# separately and copying it to ~/Library/Application Support/Munajjam/models.
IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_ARGS=(--force --sign "$IDENTITY")
if [[ "$IDENTITY" != - ]]; then
  SIGN_ARGS+=(--options runtime --timestamp)
fi
# Flutter's generated project uses ad hoc signatures. Re-sign its nested code
# with the requested identity before sealing the outer app. Ad hoc local builds
# must not enable hardened library validation without a Developer ID team.
find "$APP/Contents/Frameworks" -depth -type d -name '*.framework' -print0 | \
  while IFS= read -r -d '' framework; do
    codesign "${SIGN_ARGS[@]}" "$framework"
  done
codesign "${SIGN_ARGS[@]}" \
  --entitlements "$ROOT/munajjam_desktop/macos/Runner/Release.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$ROOT/installer_output"
ditto -c -k --sequesterRsrc --keepParent "$APP" \
  "$ROOT/installer_output/Munajjam-macos-arm64.zip"
echo "Created installer_output/Munajjam-macos-arm64.zip"
echo "Public distribution additionally requires Developer ID signing and notarization."
