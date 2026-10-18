# macOS on Apple Silicon

Munajjam targets native arm64 Macs running macOS 14 or later. The Flutter UI
and local FastAPI backend share the existing Windows codebase. CPU inference is
the default; a GPU is not required. Intel/Rosetta builds are not supported by this
packaging workflow.

## Development

Install Xcode (including its command line tools), Flutter with Dart 3.13 or
later, and Homebrew. Then, from the repository root:

```sh
brew install python@3.11 ffmpeg
./scripts/setup_macos.sh
cd munajjam_desktop
flutter run -d macos
```

Setup creates `.venv`, installs the platform-specific requirements, and downloads
the ONNX graphs **and their external tensor files**. The download can be large;
rerun setup to resume an interrupted download. Completion markers are written
only after the whole model folder has downloaded.

The app finds `.venv` automatically. For a different development environment:

```sh
MUNAJJAM_PYTHON=/absolute/path/to/python3 flutter run -d macos
```

Do not use `/usr/bin/python3`: the Apple-provided version may be too old. Run
natively, without Rosetta, so Python and the inference wheels use arm64.

## Resources and diagnostics

- Downloaded models: `~/Library/Application Support/Munajjam/models/model_*`.
- Server log: `~/Library/Application Support/Munajjam/logs/server.log`.
- Hugging Face/Numba caches: `~/Library/Application Support/Munajjam/cache/`.
- Audio conversion files: the operating system's temporary directory.

Existing `model_*` folders beside the backend still work, including on Windows.
Set `MUNAJJAM_MODELS_DIR` to override the parent of those folders. Optional
`MUNAJJAM_BACKEND_DIR` and `MUNAJJAM_FFMPEG` overrides accept absolute paths.
The installed app never needs to write into its signed bundle. Finder launches
work without inheriting a shell's working directory or Homebrew PATH.

The native title bar supplies close/minimize/fullscreen controls. Closing the
window or using Cmd+Q shuts down the server started by this app. An independently
started server is left running. Batch alignment prevents idle system sleep using
`caffeinate`; its assertion ends on cancellation, completion, or app exit.
Automatic computer shutdown is available only on Windows.

## Build a standalone app

```sh
./scripts/build_macos.sh
```

This creates `installer_output/Munajjam-macos-arm64.zip`, containing `Munajjam.app`.
It packages the Python backend and FFmpeg, including dependent native libraries,
using PyInstaller. The installed app does not require Python or Homebrew.
Models are separate to avoid downloading the large weights with every app update.
On another Mac, copy the complete models directory to the location above, or run:

```sh
/Applications/Munajjam.app/Contents/Resources/backend/munajjam_server --download-models
```

Restart the app after the download finishes so the server loads the models.

The default signature is ad hoc for local testing. For public distribution, set
`CODESIGN_IDENTITY` to your Developer ID Application identity when running the
build script, then notarize the ZIP with Apple's `notarytool` and staple the
resulting ticket to the app before making the final archive. This repository does
not contain signing credentials or perform notarization automatically.

The runner deliberately uses direct distribution without App Sandbox because it
launches Python/FFmpeg and accesses user-selected batch folders. Mac App Store
sandbox support requires a separate helper/file-access design.

## Optional CoreML experiment

```sh
MUNAJJAM_ENABLE_COREML=1 flutter run -d macos
```

This registers `CoreMLExecutionProvider` when available and keeps CPU fallback.
CoreML registration does not guarantee that every operator uses Apple hardware
or that alignment runs faster. Validate timing accuracy and performance on real
audio before enabling it by default. The UI reports registered providers from
loaded sessions rather than assuming installed acceleration is in use.

## Checks

```sh
.venv/bin/python -m unittest discover -s tests -v
cd munajjam_desktop
flutter analyze
flutter test
flutter test test/test_surah_detector.dart
flutter build macos --release
```

A successful build or mocked provider test does not establish inference accuracy.
A release should also be checked by launching from Finder, importing and playing
audio, generating waveforms, running Zipformer/hybrid/fuzzy alignment, exporting
JSON, processing a batch, and quitting while the server is loading or working.
