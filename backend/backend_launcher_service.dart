// lib/services/backend_launcher_service.dart
// ────────────────────────────────────────────
// Responsible for finding, starting, and stopping the bundled Python backend.
//
// On DESKTOP builds (Windows / macOS / Linux) the backend executable produced
// by PyInstaller is bundled alongside the Flutter app.
//
// Expected layout
// ───────────────
//   macOS  : MusicPage.app/Contents/Resources/backend/musicpage_backend
//   Windows: MusicPage\backend\musicpage_backend.exe
//   Linux  : MusicPage/backend/musicpage_backend
//
// On MOBILE builds the backend is NOT bundled; the app connects to a desktop
// backend running on the same local network (host/port configurable in Settings).
//
// In DEVELOPMENT the backend is expected to already be running
// (`python run.py` in the backend/ dir). If /health responds within 1 s the
// launcher skips starting a new process.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum BackendStatus { idle, starting, ready, error }

class BackendLauncherService extends ChangeNotifier {
  static const _port        = 8000;
  static const _healthUrl   = 'http://127.0.0.1:$_port/health';
  static const _startupMs   = 500;   // poll interval while waiting
  static const _maxRetries  = 60;    // 30 s timeout

  Process?       _process;
  BackendStatus  _status  = BackendStatus.idle;
  String?        _error;

  BackendStatus get status  => _status;
  String?       get error   => _error;
  bool          get isReady => _status == BackendStatus.ready;

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Start the backend.
  /// Safe to call multiple times — no-ops if already running.
  Future<void> start() async {
    if (_status == BackendStatus.ready)    return;
    if (_status == BackendStatus.starting) return;

    _setStatus(BackendStatus.starting);

    // Dev / mobile shortcut: if already listening, skip subprocess.
    if (await _isAlreadyListening()) {
      debugPrint('[Backend] already running on port $_port');
      _setStatus(BackendStatus.ready);
      return;
    }

    // Mobile platforms cannot run a subprocess — connect to remote backend.
    if (Platform.isAndroid || Platform.isIOS) {
      _setError('On mobile, start the backend on your desktop and '
          'set the host in Settings.');
      return;
    }

    try {
      final exe  = _executablePath();
      final work = File(exe).parent.path;

      debugPrint('[Backend] launching: $exe');

      _process = await Process.start(
        exe,
        [],
        workingDirectory: work,
        environment: {
          ...Platform.environment,
          'PORT': '$_port',
          'HOST': '127.0.0.1',
        },
      );

      // Pipe stdout/stderr to Flutter debug console
      _process!.stdout
          .transform(utf8.decoder)
          .listen((l) => debugPrint('[Backend/out] ${l.trim()}'));
      _process!.stderr
          .transform(utf8.decoder)
          .listen((l) => debugPrint('[Backend/err] ${l.trim()}'));

      _process!.exitCode.then((code) {
        if (_status == BackendStatus.ready) {
          _setError('Backend exited unexpectedly (code $code)');
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
    _setStatus(BackendStatus.idle);
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  Future<void> _waitUntilReady() async {
    for (var i = 0; i < _maxRetries; i++) {
      await Future<void>.delayed(const Duration(milliseconds: _startupMs));
      if (await _isAlreadyListening()) {
        _setStatus(BackendStatus.ready);
        return;
      }
    }
    _setError('Backend did not respond after ${_maxRetries * _startupMs ~/ 1000} s');
  }

  Future<bool> _isAlreadyListening() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 500);
      final req  = await client.getUrl(Uri.parse(_healthUrl));
      final resp = await req.close();
      await resp.drain<void>();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _executablePath() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final name   = Platform.isWindows
        ? 'musicpage_backend.exe'
        : 'musicpage_backend';

    if (Platform.isMacOS) {
      // MusicPage.app/Contents/MacOS/ → ../Resources/backend/
      final resources = p.join(exeDir.path, '..', 'Resources');
      return p.normalize(p.join(resources, 'backend', name));
    } else {
      // Windows & Linux: sibling 'backend/' folder
      return p.join(exeDir.path, 'backend', name);
    }
  }

  void _setStatus(BackendStatus s) {
    _status = s;
    _error  = null;
    notifyListeners();
  }

  void _setError(String msg) {
    _status = BackendStatus.error;
    _error  = msg;
    notifyListeners();
    debugPrint('[Backend] ERROR: $msg');
  }
}
