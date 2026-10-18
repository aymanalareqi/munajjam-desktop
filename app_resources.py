"""Resource locations shared by development and the packaged desktop server."""

import os
from pathlib import Path
import shutil
import sys


def resource_dir() -> Path:
    # PyInstaller's onedir bundle keeps data alongside its embedded libraries.
    return Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))


def application_support_dir() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / "Munajjam"
    return resource_dir()


def models_dir() -> Path:
    override = os.environ.get("MUNAJJAM_MODELS_DIR")
    if override:
        return Path(override).expanduser().resolve()
    # Keep existing project/Windows model folders working. macOS downloads go
    # outside the signed app so they survive upgrades without modifying it.
    if (resource_dir() / "model_zipformer").is_dir():
        return resource_dir()
    if sys.platform == "darwin":
        return application_support_dir() / "models"
    return resource_dir()


def configure_cache() -> None:
    if sys.platform == "darwin":
        cache = application_support_dir() / "cache"
        os.environ.setdefault("HF_HOME", str(cache / "huggingface"))
        os.environ.setdefault("NUMBA_CACHE_DIR", str(cache / "numba"))
        os.environ.setdefault("MPLCONFIGDIR", str(cache / "matplotlib"))


def find_ffmpeg() -> str:
    override = os.environ.get("MUNAJJAM_FFMPEG")
    if override:
        return override
    name = "ffmpeg.exe" if sys.platform == "win32" else "ffmpeg"
    for folder in (Path(sys.executable).parent, resource_dir()):
        candidate = folder / name
        if candidate.is_file():
            return str(candidate)
    found = shutil.which("ffmpeg")
    if found:
        return found
    # Finder does not inherit a terminal's Homebrew PATH.
    if sys.platform == "darwin":
        for candidate in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"):
            if Path(candidate).is_file():
                return candidate
    return "ffmpeg"
