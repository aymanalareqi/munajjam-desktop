import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:munajjam_desktop/services/audio_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late AudioService audio;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('munajjam-replay-');
    final path = '${directory.path}/audio.wav';
    await File(path).writeAsBytes(_wave());
    final player = AudioPlayer();
    await player.setVolume(0); // Exercise native playback without making noise.
    audio = AudioService.forTesting(player);
    await audio.loadAudioSource(path, isLocal: true);
  });

  tearDown(() async {
    await audio.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> finishPlayback() async {
    final completed = audio.player.onPlayerComplete.first;
    await audio.play();
    await completed.timeout(const Duration(seconds: 5));
    await _waitFor(
      () async =>
          audio.player.state == PlayerState.completed &&
          await audio.player.getCurrentPosition() == Duration.zero,
    );
  }

  void playbackTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      try {
        await body(tester);
      } finally {
        // Stop the frame position updater before the widget test's teardown
        // checks for active animation callbacks. Native playback remains real.
        await audio.pause();
        await tester.pump();
      }
    });
  }

  playbackTest('completed audio can be played again', (tester) async {
    runApp(
      const MaterialApp(home: Scaffold(body: Text('Audio replay checks'))),
    );
    await finishPlayback();
    expect(
      audio.player.source,
      isNotNull,
      reason: 'Natural completion must keep the native audio source available',
    );
    expect(audio.positionNotifier.value, Duration.zero);
    await finishPlayback();
    expect(audio.player.source, isNotNull);
    expect(audio.playerStateNotifier.value, PlayerState.completed);
  });

  playbackTest('seek after completion preserves the selected replay position', (
    tester,
  ) async {
    runApp(
      const MaterialApp(home: Scaffold(body: Text('Seek after completion'))),
    );
    await finishPlayback();
    await audio.seek(0.2);
    expect(audio.positionNotifier.value, const Duration(milliseconds: 200));
    await audio.play();
    await _waitFor(
      () async =>
          (await audio.player.getCurrentPosition() ?? Duration.zero) >
          const Duration(milliseconds: 250),
    );
    expect(audio.isPlaying, isTrue);
  });

  playbackTest('verse snippets work after the recording completes', (
    tester,
  ) async {
    runApp(
      const MaterialApp(home: Scaffold(body: Text('Snippet after completion'))),
    );
    await finishPlayback();
    await audio.playSnippet(0.1, 0.35);
    await _waitFor(() async => audio.player.state == PlayerState.paused);
    final position = await audio.player.getCurrentPosition();
    expect(position, isNotNull);
    expect(position!.inMilliseconds, greaterThanOrEqualTo(100));
    expect(position.inMilliseconds, lessThan(500));
    expect(audio.player.source, isNotNull);
  });

  playbackTest(
    'continuous playback cancels the previous snippet stop callback',
    (tester) async {
      runApp(
        const MaterialApp(home: Scaffold(body: Text('Continuous playback'))),
      );
      await audio.playSnippet(0, 0.35);
      await _waitFor(
        () async =>
            (await audio.player.getCurrentPosition() ?? Duration.zero) >
            const Duration(milliseconds: 80),
      );
      await audio.play();
      await _waitFor(
        () async =>
            (await audio.player.getCurrentPosition() ?? Duration.zero) >
            const Duration(milliseconds: 500),
      );
      expect(audio.isPlaying, isTrue);
    },
  );
}

Future<void> _waitFor(Future<bool> Function() condition) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > const Duration(seconds: 5)) {
      throw TimeoutException(
        'Native playback did not reach the expected state',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Uint8List _wave() {
  const sampleRate = 16000;
  const frames = 16000; // One second of PCM audio.
  final data = ByteData(44 + frames * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  text(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    data.setInt16(
      44 + i * 2,
      (1000 * sin(2 * pi * 440 * i / sampleRate)).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
