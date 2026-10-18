import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the backend independently of Finder's working directory and PATH.
class BackendPaths {
  BackendPaths({required this.root, String? scriptPath})
    : script = scriptPath ?? p.join(root, 'munajjam_server.py');

  final String root;
  final String script;

  factory BackendPaths.resolve({String? serverScriptPath}) {
    if (serverScriptPath != null) {
      final script = p.absolute(serverScriptPath);
      return BackendPaths(root: p.dirname(script), scriptPath: script);
    }
    return BackendPaths.discover(
      executable: Platform.resolvedExecutable,
      workingDirectory: Directory.current.path,
      override: Platform.environment['MUNAJJAM_BACKEND_DIR'],
    );
  }

  factory BackendPaths.discover({
    required String executable,
    required String workingDirectory,
    String? override,
  }) {
    final exeDir = p.dirname(executable);
    final candidates = <String>[
      if (override != null && override.isNotEmpty) override,
      p.join(exeDir, 'backend'),
      p.join(exeDir, '..', 'Resources', 'backend'),
      exeDir,
    ];
    var directory = p.absolute(workingDirectory);
    for (var i = 0; i < 8; i++) {
      candidates.add(directory);
      final parent = p.dirname(directory);
      if (parent == directory) break;
      directory = parent;
    }
    for (final rawCandidate in candidates) {
      final candidate = p.normalize(p.absolute(rawCandidate));
      if ([
            'munajjam_server.py',
            'munajjam_server',
            'munajjam_server.exe',
          ].any((name) => File(p.join(candidate, name)).existsSync()) ||
          File(p.join(candidate, 'backend', 'munajjam_server.exe'))
              .existsSync()) {
        return BackendPaths(root: p.normalize(p.absolute(candidate)));
      }
    }
    return BackendPaths(root: p.absolute(workingDirectory));
  }

  List<String> get executables => Platform.isWindows
      ? [
          p.join(root, 'backend', 'munajjam_server.exe'),
          p.join(root, 'munajjam_server.exe'),
        ]
      : [p.join(root, 'munajjam_server')];

  List<String> get pythonCandidates => [
    if (Platform.environment['MUNAJJAM_PYTHON'] case final String python)
      python,
    if (Platform.isWindows) ...[
      p.join(root, 'python_runtime', 'pythonw.exe'),
      p.join(root, '.venv', 'Scripts', 'python.exe'),
      p.join(root, 'venv', 'Scripts', 'python.exe'),
      'pythonw',
      'python',
    ] else ...[
      p.join(root, 'python_runtime', 'bin', 'python3'),
      p.join(root, '.venv', 'bin', 'python3'),
      p.join(root, 'venv', 'bin', 'python3'),
      if (Platform.isMacOS) '/opt/homebrew/bin/python3.11',
      'python3',
    ],
  ];
}
