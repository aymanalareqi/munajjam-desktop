#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
  echo "Run this script natively on an Apple Silicon Mac (without Rosetta)." >&2
  exit 1
fi
PYTHON="${MUNAJJAM_PYTHON:-/opt/homebrew/bin/python3.11}"
if [[ ! -x "$PYTHON" ]]; then
  echo "Install Python 3.11 and FFmpeg: brew install python@3.11 ffmpeg" >&2
  exit 1
fi
"$PYTHON" -c 'import platform, sys; assert platform.machine() == "arm64" and sys.version_info >= (3, 10), "Native arm64 Python 3.10+ required"'
if ! command -v ffmpeg >/dev/null && [[ ! -x /opt/homebrew/bin/ffmpeg ]]; then
  echo "Install FFmpeg: brew install ffmpeg" >&2
  exit 1
fi
"$PYTHON" -m venv "$ROOT/.venv"
"$ROOT/.venv/bin/python" -m pip install -r "$ROOT/requirements.txt"
"$ROOT/.venv/bin/python" "$ROOT/download_models.py"
echo "Ready. Run: cd \"$ROOT/munajjam_desktop\" && flutter run -d macos"
