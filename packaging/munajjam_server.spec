# Build with the native arm64 .venv Python from the repository root.
import os
from pathlib import Path
import shutil

from PyInstaller.utils.hooks import collect_data_files, copy_metadata

root = Path(SPECPATH).parent
ffmpeg = os.environ.get("MUNAJJAM_FFMPEG") or shutil.which("ffmpeg")
if not ffmpeg:
    raise RuntimeError("FFmpeg is required: brew install ffmpeg")

datas = [(str(root / "data"), "data")]
# Transformers reads its own sources for lazy imports and distribution versions.
datas += collect_data_files("transformers", include_py_files=True)
for package in ("transformers", "torch", "sherpa-onnx", "onnxruntime", "librosa"):
    datas += copy_metadata(package)

a = Analysis(
    [str(root / "munajjam_server.py")],
    pathex=[str(root)],
    binaries=[(ffmpeg, ".")],
    datas=datas,
    hiddenimports=[
        "hybrid_aligner.hybrid_pipeline", "hybrid_aligner.recitation_segmenter",
        "hybrid_aligner.wav2vec2_aligner", "hybrid_aligner.gpu_utils",
        "uvicorn.logging", "uvicorn.loops.auto", "uvicorn.protocols.http.h11_impl",
        "uvicorn.protocols.websockets.auto", "uvicorn.lifespan.on",
        "transformers.models.wav2vec2.modeling_wav2vec2",
        "transformers.models.wav2vec2.processing_wav2vec2",
        "transformers.models.wav2vec2_bert.modeling_wav2vec2_bert",
        "transformers.models.seamless_m4t.feature_extraction_seamless_m4t",
        "transformers.models.auto.feature_extraction_auto",
        "transformers.models.auto.modeling_auto",
    ],
    excludes=["tkinter", "matplotlib", "IPython", "pytest"],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [], exclude_binaries=True, name="munajjam_server",
    console=True, target_arch="arm64",
    codesign_identity=os.environ.get("CODESIGN_IDENTITY"),
    entitlements_file=str(root / "packaging" / "backend.entitlements"),
)
coll = COLLECT(exe, a.binaries, a.datas, name="munajjam_server")
