# macOS on Apple Silicon

Munajjam targets native arm64 Macs running macOS 14 or later. The Flutter UI
and local FastAPI backend share the existing Windows codebase. CPU inference is
the default; a GPU is not required. Intel/Rosetta builds are not supported by this
packaging workflow.

On Apple Silicon, the segmentation model caps its CPU worker count at the
reported performance-core count (up to eight). This reduces thread overhead
on mixed-core Macs. The model and audio chunk sizes remain the same.

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

The app-managed server writes Python and native diagnostics directly to its log
file so Flutter hot restarts cannot disconnect its output pipes. After updating
the backend, fully stop and relaunch the app to replace the running server.
Neural segmentation reports progress after each 20-second audio chunk, including
how much of the recording has been processed.

If a debug session reports `Class ... is implemented in both` for the same
`objective_c.framework` path after a hot restart, stop the debug session fully
and run `flutter run -d macos` again. A hot restart can leave earlier native
library copies loaded in the process, especially after another build has
replaced the framework. Do not delete the framework from the app bundle.

## Build a standalone app

```sh
./scripts/build_macos.sh
```

This creates two packages containing `Munajjam.app`:

- `installer_output/Munajjam-macos-arm64.dmg`: the app, Python backend, FFmpeg,
  and all four downloaded models for offline use. Open it and drag the app to
  Applications. The installed app takes approximately 5 GB.
- `installer_output/Munajjam-macos-arm64.zip`: the smaller app/runtime archive,
  with models kept separate.

Neither package requires a separate Python or Homebrew installation. The DMG
uses the completed model folders in the project root, or falls back to the
Application Support models directory. `MUNAJJAM_MODELS_DIR` overrides this source.
It requires the completion markers written by the downloader. Models included
in the DMG are read from the app bundle; caches remain in Application Support.

To create just the DMG from an already built and packaged app:

```sh
./scripts/package_macos_dmg.sh
```

For a smaller DMG with models kept separate:

```sh
MUNAJJAM_DMG_INCLUDE_MODELS=0 ./scripts/package_macos_dmg.sh
```

For the ZIP or smaller DMG, copy the complete model folders to the Application
Support models directory, or run:

```sh
/Applications/Munajjam.app/Contents/Resources/backend/munajjam_server --download-models
```

Restart the app after the download finishes so the server loads the models.

The default signature is ad hoc for local testing. For public distribution, set
`CODESIGN_IDENTITY` to your Developer ID Application identity when running the
build script. Then submit the DMG to Apple's `notarytool` and staple the ticket to
the DMG. For ZIP distribution, staple the app's ticket before making the final
archive. This repository does
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
flutter test integration_test/audio_playback_test.dart -d macos
flutter build macos --release
```

The audio integration tests use the native macOS player with generated, muted
audio to check replay after completion, seeking, verse snippets, and switching
back to continuous playback.

A successful build or mocked provider test does not establish inference accuracy.
A release should also be checked by launching from Finder, importing and playing
audio, generating waveforms, running Zipformer/hybrid/fuzzy alignment, exporting
JSON, processing a batch, and quitting while the server is loading or working.
