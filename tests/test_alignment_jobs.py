"""Job completion contracts and incremental segmentation progress."""
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import numpy as np

from hybrid_aligner.hybrid_pipeline import _segmentation_progress
from hybrid_aligner.recitation_segmenter import QuranRecitationSegmenter
import munajjam_server


class AlignmentJobsTest(unittest.TestCase):
    def run_job(self, aligner):
        self.addCleanup(munajjam_server.JOBS.pop, 'test_job', None)
        munajjam_server.JOBS['test_job'] = {'status': 'processing'}
        with tempfile.TemporaryDirectory() as directory, \
                patch.object(munajjam_server, 'get_aligner', return_value=aligner):
            munajjam_server._run_alignment_job(
                'test_job', 'audio.wav', directory, ['test'], 1, None,
                2.0, 200, 750, 30, method='zipformer',
            )
            self.assertFalse(Path(directory).exists())
        return munajjam_server.get_align_job_status('test_job')

    def test_inference_error_is_a_terminal_failed_job(self):
        def fail(**kwargs):
            raise RuntimeError('inference failed')

        status = self.run_job(SimpleNamespace(align_audio_with_progress=fail))
        self.assertEqual(status['status'], 'failed')
        self.assertEqual(status['error'], 'inference failed')
        self.assertIn('inference failed', status['message'])

    def test_success_contains_the_alignment_result(self):
        result = {'data': [{'ayah': 1}], 'breath_groups': []}
        status = self.run_job(SimpleNamespace(
            align_audio_with_progress=lambda **kwargs: result,
        ))
        self.assertEqual(status['status'], 'success')
        self.assertEqual(status['progress'], 100)
        self.assertEqual(status['data'], result['data'])

    def test_closed_debug_pipes_cannot_leave_a_job_processing(self):
        class BrokenOutput:
            def write(self, text):
                raise BrokenPipeError('debug output pipe closed')

            def flush(self):
                pass

        with patch('sys.stdout', BrokenOutput()), patch('sys.stderr', BrokenOutput()):
            status = self.run_job(None)
        self.assertEqual(status['status'], 'failed')
        self.assertIn('debug output pipe closed', status['error'])

    def test_direct_log_survives_closed_parent_output_pipes(self):
        script = '''
import os, sys, time
from munajjam_server import configure_server_log
configure_server_log(sys.argv[1])
print('ready', flush=True)
time.sleep(0.2)
print('output after parent disconnected', flush=True)
os.write(2, b'native diagnostic after disconnect\\n')
'''
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'server.log'
            process = subprocess.Popen(
                [sys.executable, '-c', script, str(log)],
                cwd=Path(munajjam_server.__file__).parent,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            try:
                deadline = time.monotonic() + 10
                while not (log.exists() and 'ready' in log.read_text()):
                    self.assertIsNone(process.poll(), 'server exited before redirecting output')
                    self.assertLess(time.monotonic(), deadline)
                    time.sleep(0.01)
                process.stdout.close()
                process.stderr.close()
                self.assertEqual(process.wait(timeout=10), 0)
                output = log.read_text()
                self.assertIn('output after parent disconnected', output)
                self.assertIn('native diagnostic after disconnect', output)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                process.stdout.close()
                process.stderr.close()


class SegmentationProgressTest(unittest.TestCase):
    def test_progress_advances_for_every_chunk_and_keeps_the_last_partial_chunk(self):
        segmenter = QuranRecitationSegmenter.__new__(QuranRecitationSegmenter)
        segmenter.is_onnx = True
        segmenter.min_silence_duration_ms = 200
        segmenter.min_speech_duration_ms = 750
        segmenter.pad_duration_ms = 30
        segmenter.processor = lambda audio, **kwargs: SimpleNamespace(
            input_features=np.zeros((1, int(np.ceil(len(audio) / 320)), 160)),
        )
        # Predict silence; no optional interval-cleaning dependency is needed.
        segmenter.onnx_session = SimpleNamespace(
            run=lambda *args: [np.zeros((1, 1000, 2))],
        )
        updates = []
        intervals = segmenter.segment_audio(
            np.zeros(45 * 16000, dtype=np.float32),
            progress_callback=lambda current, total: updates.append((current, total)),
        )
        self.assertEqual(updates, [(0, 45), (20, 45), (40, 45), (45, 45)])
        self.assertEqual(intervals, [{'start': 0.0, 'end': 45.0, 'duration': 45.0}])

    def test_segmentation_does_not_jump_past_the_next_pipeline_stage(self):
        for start, end in [(10, 29), (20, 49)]:
            updates = []
            callback = _segmentation_progress(lambda *args: updates.append(args), start, end)
            for current in (0, 20, 40, 45):
                callback(current, 45)
            percentages = [item[0] for item in updates]
            self.assertEqual(percentages, sorted(percentages))
            self.assertEqual(percentages[0], start)
            self.assertEqual(percentages[-1], end)
            self.assertIn('45.0 / 45.0', updates[-1][1])
            self.assertNotIn('GPU', updates[-1][1])


if __name__ == '__main__':
    unittest.main()
