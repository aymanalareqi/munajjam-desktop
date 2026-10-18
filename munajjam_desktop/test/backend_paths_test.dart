import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:munajjam_desktop/core/backend_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  setUp(
    () => temporary = Directory.systemTemp.createTempSync('munajjam paths '),
  );
  tearDown(() => temporary.deleteSync(recursive: true));

  void touch(String file) {
    File(file).parent.createSync(recursive: true);
    File(file).writeAsStringSync('');
  }

  test(
    'Finder launch finds bundled backend without the project working directory',
    () {
      final contents = p.join(temporary.path, 'Munajjam.app', 'Contents');
      final backend = p.join(contents, 'Resources', 'backend');
      touch(p.join(backend, 'munajjam_server'));
      final paths = BackendPaths.discover(
        executable: p.join(contents, 'MacOS', 'Munajjam'),
        workingDirectory: '/',
      );
      expect(paths.root, backend);
      expect(paths.executables, contains(p.join(backend, 'munajjam_server')));
    },
  );

  test('development launch finds Python beside the Flutter project', () {
    touch(p.join(temporary.path, 'munajjam_server.py'));
    final paths = BackendPaths.discover(
      executable: '/unrelated/build/Munajjam',
      workingDirectory: p.join(temporary.path, 'munajjam_desktop'),
    );
    expect(paths.root, temporary.path);
    expect(paths.script, p.join(temporary.path, 'munajjam_server.py'));
    expect(
      paths.pythonCandidates,
      contains(p.join(temporary.path, '.venv', 'bin', 'python3')),
    );
  }, skip: Platform.isWindows);

  test('explicit backend directory takes precedence over a bundled server', () {
    final backend = p.join(temporary.path, 'custom backend');
    touch(p.join(backend, 'munajjam_server.py'));
    touch(p.join(temporary.path, 'backend', 'munajjam_server'));
    final paths = BackendPaths.discover(
      executable: p.join(temporary.path, 'Munajjam'),
      workingDirectory: '/',
      override: backend,
    );
    expect(paths.root, backend);
  });
}
