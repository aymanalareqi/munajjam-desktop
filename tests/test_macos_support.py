"""Portable resource, execution provider and health-contract regression tests."""
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import app_resources
from hybrid_aligner.gpu_utils import get_ort_execution_providers, get_segmenter_cpu_threads
import munajjam_server


class ResourcesTest(unittest.TestCase):
    def test_macos_model_downloads_live_outside_signed_app(self):
        with tempfile.TemporaryDirectory() as temp, \
                patch.object(app_resources.sys, "platform", "darwin"), \
                patch.object(app_resources, "resource_dir", return_value=Path(temp)), \
                patch.object(Path, "home", return_value=Path(temp)), \
                patch.dict(os.environ, {}, clear=True):
            self.assertEqual(app_resources.models_dir(),
                             Path(temp) / "Library/Application Support/Munajjam/models")

    def test_model_override_and_existing_windows_layout(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with patch.dict(os.environ, {"MUNAJJAM_MODELS_DIR": str(root)}):
                self.assertEqual(app_resources.models_dir(), root.resolve())
            (root / "model_zipformer").mkdir()
            with patch.object(app_resources, "resource_dir", return_value=root), \
                    patch.dict(os.environ, {}, clear=True):
                self.assertEqual(app_resources.models_dir(), root)

    def test_frozen_backend_uses_pyinstaller_resources(self):
        with patch.object(app_resources.sys, "_MEIPASS", "/packaged/_internal", create=True):
            self.assertEqual(app_resources.resource_dir(), Path('/packaged/_internal'))

    def test_ffmpeg_finder_fallback(self):
        with patch.object(app_resources.sys, 'platform', 'darwin'), \
                patch.object(app_resources.shutil, 'which', return_value=None), \
                patch.object(Path, 'is_file', lambda p: str(p) == '/opt/homebrew/bin/ffmpeg'), \
                patch.dict(os.environ, {}, clear=True):
            self.assertEqual(app_resources.find_ffmpeg(), '/opt/homebrew/bin/ffmpeg')


class ProvidersTest(unittest.TestCase):
    def test_apple_segmenter_limits_threads_to_performance_core_count(self):
        with patch('sys.platform', 'darwin'), \
                patch('os.cpu_count', return_value=10), \
                patch('subprocess.check_output', return_value=b'4\n'):
            self.assertEqual(get_segmenter_cpu_threads(), 4)

    def test_segmenter_keeps_default_if_performance_cores_are_unavailable(self):
        with patch('sys.platform', 'darwin'), \
                patch('os.cpu_count', return_value=10), \
                patch('subprocess.check_output', side_effect=OSError):
            self.assertEqual(get_segmenter_cpu_threads(), 8)

    def test_windows_segmenter_thread_count_is_unchanged(self):
        with patch('sys.platform', 'win32'), \
                patch('os.cpu_count', return_value=12), \
                patch('subprocess.check_output') as query:
            self.assertEqual(get_segmenter_cpu_threads(), 8)
            query.assert_not_called()

    def test_apple_cpu_default_even_when_coreml_is_installed(self):
        with patch('sys.platform', 'darwin'), \
                patch('onnxruntime.get_available_providers', return_value=[
                    'CoreMLExecutionProvider', 'CPUExecutionProvider']), \
                patch.dict(os.environ, {}, clear=True):
            self.assertEqual(get_ort_execution_providers(), ['CPUExecutionProvider'])

    def test_apple_coreml_opt_in_keeps_cpu_fallback(self):
        with patch('sys.platform', 'darwin'), \
                patch('onnxruntime.get_available_providers', return_value=[
                    'CoreMLExecutionProvider', 'CPUExecutionProvider']), \
                patch.dict(os.environ, {'MUNAJJAM_ENABLE_COREML': '1'}):
            self.assertEqual(get_ort_execution_providers(),
                             ['CoreMLExecutionProvider', 'CPUExecutionProvider'])

    def test_windows_keeps_directml(self):
        with patch('sys.platform', 'win32'), \
                patch('onnxruntime.get_available_providers', return_value=[
                    'DmlExecutionProvider', 'CPUExecutionProvider']), \
                patch('hybrid_aligner.gpu_utils.get_best_dml_device_id', return_value=1):
            self.assertEqual(get_ort_execution_providers(), [
                ('DmlExecutionProvider', {'device_id': 1}), 'CPUExecutionProvider'])

    def test_health_does_not_claim_installed_but_unused_coreml(self):
        cpu_model = SimpleNamespace(onnx_session=SimpleNamespace(
            get_providers=lambda: ['CPUExecutionProvider']))
        with patch.object(munajjam_server, 'aligner_instance', SimpleNamespace(
                recognizer=object(), tokens_dict={})), \
                patch.object(munajjam_server, 'hybrid_aligner_instance', SimpleNamespace(
                    segmenter=cpu_model, wav2vec2=cpu_model)), \
                patch('onnxruntime.get_available_providers', return_value=[
                    'CoreMLExecutionProvider', 'CPUExecutionProvider']):
            health = munajjam_server.health_check()
            self.assertFalse(health['has_gpu'])
            self.assertEqual(health['provider_name'], 'CPU Execution Provider')
            self.assertTrue(all(health['models'].values()))


if __name__ == '__main__':
    unittest.main()
