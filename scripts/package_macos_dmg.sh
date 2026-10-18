#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/munajjam_desktop/build/macos/Build/Products/Release/Munajjam.app}"
INCLUDE_MODELS="${MUNAJJAM_DMG_INCLUDE_MODELS:-1}"
OUTPUT_DIR="$ROOT/installer_output"
OUTPUT="$OUTPUT_DIR/Munajjam-macos-arm64.dmg"
IDENTITY="${CODESIGN_IDENTITY:--}"

if [[ "$(uname -s)" != Darwin || ! -d "$APP" ]]; then
  echo "A built macOS app is required. Run scripts/build_macos.sh first." >&2
  exit 1
fi
if [[ "$INCLUDE_MODELS" != 0 && "$INCLUDE_MODELS" != 1 ]]; then
  echo "MUNAJJAM_DMG_INCLUDE_MODELS must be 0 or 1." >&2
  exit 1
fi
if [[ ! -x "$APP/Contents/Resources/backend/munajjam_server" ]]; then
  echo "The app must contain its packaged Python backend. Run scripts/build_macos.sh." >&2
  exit 1
fi
codesign --verify --deep --strict "$APP"

MODEL_ROOT="${MUNAJJAM_MODELS_DIR:-$ROOT}"
if [[ -z "${MUNAJJAM_MODELS_DIR:-}" && ! -d "$MODEL_ROOT/model_zipformer" ]]; then
  MODEL_ROOT="$HOME/Library/Application Support/Munajjam/models"
fi
MODEL_NAMES=(model_segmenter model_zipformer model_wav2vec2 model_vad)
if [[ "$INCLUDE_MODELS" == 1 ]]; then
  for model in "${MODEL_NAMES[@]}"; do
    if [[ ! -f "$MODEL_ROOT/$model/.munajjam_complete" ]]; then
      echo "Complete model folder required: $MODEL_ROOT/$model" >&2
      echo "Finish scripts/setup_macos.sh or use MUNAJJAM_DMG_INCLUDE_MODELS=0." >&2
      exit 1
    fi
  done
fi

mkdir -p "$OUTPUT_DIR"
TEMP_DIR="$(mktemp -d "$OUTPUT_DIR/.munajjam-dmg.XXXXXX")"
STAGING="$TEMP_DIR/contents"
MOUNT="$TEMP_DIR/mount"
MOUNTED=0
cleanup() {
  if [[ "$MOUNTED" == 1 ]]; then
    hdiutil detach "$MOUNT" >/dev/null || true
  fi
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
mkdir -p "$STAGING" "$MOUNT"
STAGED_APP="$STAGING/Munajjam.app"
echo "Preparing Munajjam.app for the disk image..."
ditto "$APP" "$STAGED_APP"

if [[ "$INCLUDE_MODELS" == 1 ]]; then
  BUNDLED_MODELS="$STAGED_APP/Contents/Resources/backend/_internal"
  for model in "${MODEL_NAMES[@]}"; do
    echo "Including $model..."
    ditto "$MODEL_ROOT/$model" "$BUNDLED_MODELS/$model"
  done
  # Models are immutable resources inside this offline distribution. Caches
  # still live in Application Support, and the original build stays unchanged.
  SIGN_ARGS=(--force --sign "$IDENTITY")
  if [[ "$IDENTITY" != - ]]; then
    SIGN_ARGS+=(--options runtime --timestamp)
  fi
  codesign "${SIGN_ARGS[@]}" \
    --entitlements "$ROOT/munajjam_desktop/macos/Runner/Release.entitlements" "$STAGED_APP"
fi
codesign --verify --deep --strict "$STAGED_APP"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Install.txt" <<'EOF'
Munajjam for Apple Silicon — macOS 14 or later

Drag Munajjam.app to Applications, then launch it from Applications.
The Python server and FFmpeg are included in the app.
EOF
if [[ "$INCLUDE_MODELS" == 1 ]]; then
  echo 'All four AI models are included. No model download is required.' >> "$STAGING/Install.txt"
else
  echo 'AI models are separate; see the project macOS guide for setup.' >> "$STAGING/Install.txt"
fi

IMAGE="$TEMP_DIR/Munajjam-macos-arm64.dmg"
echo "Creating compressed disk image..."
hdiutil create -volname Munajjam -srcfolder "$STAGING" \
  -fs HFS+ -format UDZO -imagekey zlib-level=6 "$IMAGE"
if [[ "$IDENTITY" != - ]]; then
  codesign --force --sign "$IDENTITY" --timestamp "$IMAGE"
fi
hdiutil verify "$IMAGE"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$IMAGE" >/dev/null
MOUNTED=1
codesign --verify --deep --strict "$MOUNT/Munajjam.app"
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]]
if [[ "$INCLUDE_MODELS" == 1 ]]; then
  for model in "${MODEL_NAMES[@]}"; do
    [[ -f "$MOUNT/Munajjam.app/Contents/Resources/backend/_internal/$model/.munajjam_complete" ]]
  done
fi
hdiutil detach "$MOUNT" >/dev/null
MOUNTED=0
mv -f "$IMAGE" "$OUTPUT"
echo "Created $OUTPUT"
