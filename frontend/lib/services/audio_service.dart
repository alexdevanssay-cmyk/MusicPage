// lib/services/audio_service.dart
// ─────────────────────────────────
// Real-time microphone capture.
//
// Streams raw PCM from the mic and hands the backend exactly what its chroma
// extractor expects: 32-bit float little-endian samples at `sampleRate` Hz,
// mono.  The `record` package streams 16-bit signed PCM, so each chunk is
// converted to float32 (normalised to [-1, 1]) before it is forwarded.
//
// Platform notes
// ──────────────
// • Android / iOS / macOS: fully supported (uses the native recorder).
// • Windows / Linux desktop: supported where the `record` backend implements
//   PCM streaming.  If a platform cannot stream, startCapture throws a clear
//   error and the app remains usable for manual reading.

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

typedef AudioChunkCallback = void Function(Uint8List bytes);

class AudioCaptureService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  bool _capturing = false;

  bool get isCapturing => _capturing;

  /// Ask the OS for microphone permission (and whether one is available).
  static Future<bool> requestMicPermission() async {
    final recorder = AudioRecorder();
    try {
      return await recorder.hasPermission();
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> startCapture({
    required AudioChunkCallback onChunk,
    int sampleRate = 22050,
    String? deviceId,
  }) async {
    if (_capturing) await stopCapture();

    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission was denied.');
    }

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      // A specific input device, when the user picked one in Settings.
      device: deviceId == null
          ? null
          : InputDevice(id: deviceId, label: deviceId),
    );

    final Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream(config);
    } catch (e) {
      throw Exception(
        'Microphone streaming is not available on this platform ($e).',
      );
    }

    _capturing = true;
    _sub = stream.listen(
      (pcm16) => onChunk(_int16ToFloat32Bytes(pcm16)),
      cancelOnError: false,
    );
  }

  Future<void> stopCapture() async {
    await _sub?.cancel();
    _sub = null;
    if (_capturing) {
      try {
        await _recorder.stop();
      } catch (_) {/* already stopped */}
    }
    _capturing = false;
  }

  /// Available input devices (for the Settings device picker).
  Future<List<InputDevice>> listDevices() async {
    try {
      return await _recorder.listInputDevices();
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    stopCapture();
    _recorder.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Convert a little-endian Int16 PCM chunk to little-endian Float32 bytes,
  /// normalising samples to the [-1.0, 1.0] range the backend works in.
  static Uint8List _int16ToFloat32Bytes(Uint8List pcm16) {
    final int nSamples = pcm16.lengthInBytes ~/ 2;
    final Int16List src = Int16List.view(
      pcm16.buffer,
      pcm16.offsetInBytes,
      nSamples,
    );
    final Float32List out = Float32List(nSamples);
    for (int i = 0; i < nSamples; i++) {
      out[i] = src[i] / 32768.0;
    }
    return out.buffer.asUint8List();
  }
}
