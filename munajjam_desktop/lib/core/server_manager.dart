import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'backend_paths.dart';

class HardwareStatus {
  final bool hasGpu;
  final String providerName;
  final bool segmenterLoaded;
  final bool zipformerLoaded;
  final bool wav2vec2Loaded;
  final bool pythonFound;
  final String message;

  HardwareStatus({
    required this.hasGpu,
    required this.providerName,
    required this.segmenterLoaded,
    required this.zipformerLoaded,
    required this.wav2vec2Loaded,
    required this.pythonFound,
    required this.message,
  });
}

class ServerManager {
  static final ServerManager _instance = ServerManager._internal();
  factory ServerManager() => _instance;
  ServerManager._internal();

  Process? _serverProcess;
  IOSink? _log;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  bool _isStarting = false;
  bool _isOnline = false;
  bool _pythonFound = false;
  int _generation = 0;
  final String _serverUrl = 'http://127.0.0.1:8000';
  Timer? _healthCheckTimer;
  Map<String, dynamic> _health = {};

  final ValueNotifier<bool> isOnlineNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<String> statusMessageNotifier = ValueNotifier<String>(
    'جاري التهيئة...',
  );
  final ValueNotifier<HardwareStatus?> hardwareStatusNotifier =
      ValueNotifier<HardwareStatus?>(null);

  String get serverUrl => _serverUrl;
  bool get isOnline => _isOnline;

  Future<Process> _launch(BackendPaths paths) async {
    final parentArgs = ['--parent-pid', pid.toString()];
    for (final executable in paths.executables) {
      if (await File(executable).exists()) {
        return Process.start(
          executable,
          parentArgs,
          workingDirectory: paths.root,
        );
      }
    }
    if (!await File(paths.script).exists()) {
      throw FileSystemException('ملف الخادم غير موجود', paths.script);
    }

    String? lastError;
    for (final python in paths.pythonCandidates) {
      try {
        // Validate the environment before launching so a missing dependency is
        // visible immediately, including when Finder has a minimal PATH.
        final probe = await Process.run(python, [
          '-c',
          'import sys, importlib.util; '
              'assert sys.version_info >= (3, 10), "Python 3.10+ required"; '
              'modules = ["fastapi", "uvicorn", "sherpa_onnx", "onnxruntime", '
              '"soundfile", "librosa", "numpy", "transformers", "torch", "psutil"]; '
              'missing = [m for m in modules if importlib.util.find_spec(m) is None]; '
              'assert not missing, "Missing packages: " + ", ".join(missing)',
        ]).timeout(const Duration(seconds: 10));
        if (probe.exitCode != 0) {
          lastError = '$python: ${probe.stderr}'.trim();
          if (python == Platform.environment['MUNAJJAM_PYTHON']) break;
          continue;
        }
        return await Process.start(
          python,
          ['-u', paths.script, ...parentArgs],
          workingDirectory: paths.root,
          environment: {'PYTHONUNBUFFERED': '1'},
        );
      } on ProcessException catch (error) {
        lastError = error.message;
      }
    }
    throw StateError(
      'شغّل scripts/setup_macos.sh لإعداد Python والنماذج. '
      '${lastError ?? "Python غير موجود"}',
    );
  }

  Future<void> initAndStartServer({String? serverScriptPath}) async {
    if (_isStarting || _serverProcess != null) return;
    _isStarting = true;
    final generation = ++_generation;

    try {
      if (await checkHealth()) {
        _pythonFound = true;
        statusMessageNotifier.value = 'الخادم متصل ونشط';
        _startPeriodicHealthCheck();
        return;
      }
      if (generation != _generation) return;

      statusMessageNotifier.value = 'جاري إطلاق خادم التزمين في الخلفية...';
      final paths = BackendPaths.resolve(serverScriptPath: serverScriptPath);
      final process = await _launch(paths);
      if (generation != _generation) {
        process.kill();
        return;
      }
      _serverProcess = process;
      _pythonFound = true;

      final logDir = Platform.isMacOS
          ? Directory(
              p.join(
                Platform.environment['HOME']!,
                'Library',
                'Application Support',
                'Munajjam',
                'logs',
              ),
            )
          : Directory(p.join(Directory.systemTemp.path, 'Munajjam', 'logs'));
      await logDir.create(recursive: true);
      _log = File(p.join(logDir.path, 'server.log'))
          .openWrite(mode: FileMode.writeOnlyAppend);
      _log!.writeln('\n--- ${DateTime.now().toIso8601String()} ---');
      void logOutput(List<int> bytes) {
        _log?.write(utf8.decode(bytes, allowMalformed: true));
      }

      _stdoutSubscription = process.stdout.listen(logOutput);
      _stderrSubscription = process.stderr.listen(logOutput);
      unawaited(
        process.exitCode.then((code) async {
          if (_serverProcess != process) return;
          _serverProcess = null;
          _isOnline = false;
          isOnlineNotifier.value = false;
          _healthCheckTimer?.cancel();
          statusMessageNotifier.value =
              'توقف الخادم (رمز $code). راجع ${p.join(logDir.path, 'server.log')}';
          await _closeLog();
        }),
      );

      // Cold model loading on CPU can take substantially longer than on GPU.
      for (var i = 0; i < 240; i++) {
        if (generation != _generation || _serverProcess != process) return;
        await Future<void>.delayed(const Duration(milliseconds: 750));
        if (await checkHealth()) {
          statusMessageNotifier.value = 'تم تشغيل الخادم والتحميل بنجاح';
          break;
        }
        if (_health['error'] != null) {
          statusMessageNotifier.value =
              'تعذر تحميل النماذج: ${_health['error']}';
          break;
        }
      }
      if (generation != _generation) return;
      if (!_isOnline && _health['error'] == null) {
        statusMessageNotifier.value =
            'الخادم غير جاهز بعد. راجع ${p.join(logDir.path, 'server.log')}';
      }
      if (_serverProcess == process) _startPeriodicHealthCheck();
    } catch (error) {
      if (generation == _generation) {
        debugPrint('Error starting server: $error');
        statusMessageNotifier.value = 'خطأ في تشغيل الخادم: $error';
      }
    } finally {
      if (generation == _generation) {
        _isStarting = false;
        await detectHardwareAndModels();
      }
    }
  }

  Future<bool> checkHealth() async {
    final generation = _generation;
    try {
      final response = await http
          .get(Uri.parse('$_serverUrl/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        if (generation != _generation) return false;
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['service'] == 'Munajjam Quran Audio Alignment Server') {
          _health = data;
          _isOnline =
              data['status'] == 'online' && data['model_loaded'] == true;
          isOnlineNotifier.value = _isOnline;
          return _isOnline;
        }
      }
    } catch (_) {}
    if (generation != _generation) return false;
    _health = {};
    _isOnline = false;
    isOnlineNotifier.value = false;
    return false;
  }

  void _startPeriodicHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await checkHealth();
      await detectHardwareAndModels();
    });
  }

  Future<void> detectHardwareAndModels() async {
    final models = _health['models'] as Map<String, dynamic>? ?? {};
    final hasGpu = _health['has_gpu'] == true;
    final provider =
        _health['provider_name'] as String? ?? 'CPU Execution Provider';
    hardwareStatusNotifier.value = HardwareStatus(
      hasGpu: hasGpu,
      providerName: provider,
      segmenterLoaded: models['segmenter'] == true,
      zipformerLoaded: _health['model_loaded'] == true,
      wav2vec2Loaded: models['wav2vec2'] == true,
      pythonFound: _pythonFound,
      message: hasGpu
          ? 'مسرع العتاد: $provider'
          : 'التشغيل عبر المعالج المركزي CPU',
    );
  }

  Future<void> stopServer() async {
    ++_generation;
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    final process = _serverProcess;
    _serverProcess = null;

    // An existing manually started server belongs to its caller, not this app.
    if (process != null) {
      try {
        await http
            .post(Uri.parse('$_serverUrl/shutdown'))
            .timeout(const Duration(seconds: 1));
      } catch (_) {}
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        if (Platform.isWindows) {
          await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
        } else {
          process.kill(ProcessSignal.sigkill);
        }
      }
    }
    await _closeLog();
    _health = {};
    _isOnline = false;
    _isStarting = false;
    isOnlineNotifier.value = false;
    statusMessageNotifier.value = 'تم إيقاف الخادم';
  }

  Future<void> _closeLog() async {
    final log = _log;
    _log = null;
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    await log?.flush();
    await log?.close();
  }

  void dispose() {
    unawaited(stopServer());
  }
}
