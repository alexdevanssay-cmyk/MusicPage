// lib/services/backend_launcher_service.dart
// ────────────────────────────────────────────
// Finds, starts, and stops the bundled Python backend.
//
// DESKTOP (Windows / macOS / Linux)
//   The backend executable produced by PyInstaller is bundled beside the app
//   and launched as a child process.
//     Windows: <app dir>\backend\musicpage_backend.exe
//     macOS  : MusicPage.app/Contents/Resources/backend/musicpage_backend
//     Linux  : <app dir>/backend/musicpage_backend
//
// MOBILE (Android / iOS)
//   The backend is NOT bundled — a phone cannot run the Python/ML stack.  The
//   app is a thin client that talks to a desktop backend over the local
//   network (host/port set in Settings).  start() is a no-op there.
//
// DEVELOPMENT
//   If something is already listening on the port (e.g. `python run.py`), the
//   launcher detects it via /health and skips starting a new process.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum BackendStatus { idle, starting, ready, error }

class BackendLauncherService extends ChangeNotifier {
  static const _port = 8000;
  static const _healthUrl = 'http://127.0.0.1:$_port/health';
  static const _pollMs = 500; // poll interval while waiting
  static const _maxRetries = 120; // 60 s startup budget (first run unpacks libs)

  Process? _process;
  BackendStatus _status = BackendStatus.idle;
  String? _error;

  BackendStatus get status => _status;
  String? get error => _error;
  bool get isReady => _status == BackendStatus.ready;

  /// True on platforms where the backend runs as a bundled subprocess.
  bool get isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Start the backend.  Safe to call repeatedly.
  Future<void> start() async {
    if (_status == BackendStatus.ready || _status == BackendStatus.starting) {
      return;
    }

    // On mobile there is nothing local to launch — the reader connects to the
    // remote backend configured in Settings.  Report ready so the UI proceeds.
    if (!isDesktop) {
      _setStatus(BackendStatus.ready);
      return;
    }

    _setStatus(BackendStatus.starting);

    // If a backend is already listening (dev mode or a previous launch), reuse it.
    if (await _isAlreadyListening()) {
      debugPrint('[Backend] already running on port $_port');
      _setStatus(BackendStatus.ready);
      return;
    }

    try {
      final exe = _executablePath();
      if (!File(exe).existsSync()) {
        _setError(
          'Bundled backend not found at:\n$exe\n\n'
          'Run the app from a packaged build, or start the backend manually '
          'with "python run.py" in the backend/ folder.',
        );
        return;
      }

      final work = File(exe).parent.path;
      debugPrint('[Backend] launching: $exe');

      _process = await Process.start(
        exe,
        <String>[],
        workingDirectory: work,
        environment: {
          ...Platform.environment,
          'PORT': '$_port',
          // Bind to all interfaces so an Android/iOS companion on the same
          // Wi-Fi can reach this desktop backend (health check still uses
          // 127.0.0.1 locally).
          'HOST': '0.0.0.0',
        },
      );

      _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((l) => debugPrint('[Backend/out] ${l.trim()}'));
      _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((l) => debugPrint('[Backend/err] ${l.trim()}'));

      _process!.exitCode.then((code) {
        if (_status == BackendStatus.ready) {
          _setError('Backend exited unexpectedly (code $code).');
        }
      });

      await _waitUntilReady();
    } catch (e) {
      _setError(e.toString());
    }
  }

  void stop() {
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
    if (_status != BackendStatus.error) _setStatus(BackendStatus.idle);
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  Future<void> _waitUntilReady() async {
    for (var i = 0; i < _maxRetries; i++) {
      await Future<void>.delayed(const Duration(milliseconds: _pollMs));
      if (await _isAlreadyListening()) {
        _setStatus(BackendStatus.ready);
        return;
      }
    }
    _setError('Backend did not respond after '
        '${_maxRetries * _pollMs ~/ 1000} s.');
  }

  Future<bool> _isAlreadyListening() async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 500);
      final req = await client.getUrl(Uri.parse(_healthUrl));
      final resp = await req.close();
      await resp.drain<void>();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  String _executablePath() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final name = Platform.isWindows ? 'musicpage_backend.exe' : 'musicpage_backend';

    if (Platform.isMacOS) {
      // MusicPage.app/Contents/MacOS/ → ../Resources/backend/
      final resources = p.join(exeDir.path, '..', 'Resources');
      return p.normalize(p.join(resources, 'backend', name));
    }
    // Windows & Linux: sibling 'backend/' folder next to the app executable.
    return p.join(exeDir.path, 'backend', name);
  }

  void _setStatus(BackendStatus s) {
    _status = s;
    _error = null;
    notifyListeners();
  }

  void _setError(String msg) {
    _status = BackendStatus.error;
    _error = msg;
    notifyListeners();
    debugPrint('[Backend] ERROR: $msg');
  }
}
