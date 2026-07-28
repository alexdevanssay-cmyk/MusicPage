// lib/services/audio_service.dart
// ─────────────────────────────────
// Captures microphone audio and streams raw float32 PCM chunks
// to the provided callback (which forwards them to the WebSocket).
//
// Uses the `record` package (cross-platform: iOS, Android, Windows, macOS, Linux).
// PCM-16bit capture → float32 conversion matches the Python backend sr=22050 mono.

import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

typedef AudioChunkCallback = void Function(Uint8List bytes);

class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  bool _capturing = false;

  bool get isCapturing => _capturing;

  // ── Permissions ───────────────────────────────────────────────────────────────

  /// Request microphone permission and return the final status.
  /// On desktop platforms Permission.microphone may return `granted` by default.
  static Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  // ── Start / Stop ──────────────────────────────────────────────────────────────

  Future<void> startCapture({
    required AudioChunkCallback onChunk,
    int sampleRate = 22050,
    String? deviceId,
  }) async {
    if (_capturing) await stopCapture();

    // Explicit permission request before starting.
    // On iOS/Android this shows the system dialog if not yet granted.
    final granted = await requestMicPermission();
    if (!granted) throw Exception('Microphone permission denied');

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits, // universally supported; we convert below
        sampleRate: sampleRate,
        numChannels: 1,
        device: deviceId != null ? InputDevice(id: deviceId, label: '') : null,
      ),
    );

    _sub = stream.listen(
      (bytes) => onChunk(_int16ToFloat32(bytes)),
      onError: (_) => _capturing = false,
    );

    _capturing = true;
  }

  Future<void> stopCapture() async {
    await _sub?.cancel();
    _sub = null;
    if (_capturing) await _recorder.stop();
    _capturing = false;
  }

  Future<List<InputDevice>> listDevices() async => _recorder.listInputDevices();

  void dispose() {
    stopCapture();
    _recorder.dispose();
  }

  // ── Int16 → Float32 conversion ────────────────────────────────────────────────

  /// Converts 16-bit signed integer PCM bytes to normalised float32 PCM bytes.
  /// Scale: int16 range [-32768, 32767] → float32 range [-1.0, 1.0].
  static Uint8List _int16ToFloat32(Uint8List int16Bytes) {
    final int16 = Int16List.view(int16Bytes.buffer);
    final f32   = Float32List(int16.length);
    const scale = 1.0 / 32768.0;
    for (var i = 0; i < int16.length; i++) {
      f32[i] = int16[i] * scale;
    }
    return f32.buffer.asUint8List();
  }
}
