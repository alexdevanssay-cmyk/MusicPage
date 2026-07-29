// lib/offline/offline_follower.dart
// On-device score follower. Runs the full pipeline (chroma -> DTW -> tracker ->
// stats) locally and emits the SAME event maps the server sends over the
// WebSocket, so the reader/overlay consume it with no changes. Pure Dart.

import 'dart:typed_data';

import 'chroma_extractor.dart';
import 'online_dtw.dart';
import 'perf_stats.dart';
import 'position_tracker.dart';
import 'reference_bundle.dart';

class OfflineFollower {
  final ReferenceBundle bundle;
  late final ChromaExtractor _chroma;
  late final OnlineDtw _dtw;
  late final PositionTracker _tracker;
  late final PerformanceStats _stats;

  OfflineFollower({
    required this.bundle,
    required Float32List filterbank,
    double preloadThr = 0.80,
    double turnThr = 0.95,
    double stayPenalty = 0.20,
    int window = 150,
  }) {
    _chroma = ChromaExtractor(filterbank);
    _dtw = OnlineDtw(bundle.chroma, window: window, stayPenalty: stayPenalty);
    _tracker = PositionTracker(bundle, preloadThr: preloadThr, turnThr: turnThr);
    _stats = PerformanceStats(fps: bundle.frameRate, baseBpm: bundle.baseBpm);
  }

  int get totalPages => bundle.totalPages;

  /// Feed one PCM chunk (float32, 22050 Hz mono) and get the resulting events,
  /// each a map identical in shape to a backend WebSocket message.
  List<Map<String, dynamic>> processPcm(Float32List samples) {
    final events = <Map<String, dynamic>>[];
    for (final chroma in _chroma.push(samples)) {
      final r = _dtw.step(chroma);
      final pos = _tracker.update(r.position, r.confidence);
      _stats.update(_dtw.t, r.position, r.confidence);

      if (pos.shouldPreloadNext && pos.nextPage != null) {
        events.add({'type': 'preload_next_page', 'page': pos.nextPage});
      }
      if (pos.shouldTurnPage && pos.nextPage != null) {
        events.add({'type': 'page_change', 'from_page': pos.page, 'to_page': pos.nextPage});
      }
      events.add({
        'type': 'position_update',
        'measure': pos.measure,
        'page': pos.page,
        'progress': double.parse(pos.pageProgress.toStringAsFixed(4)),
        'global_progress': double.parse(pos.globalProgress.toStringAsFixed(4)),
        'confidence': double.parse(r.confidence.toStringAsFixed(4)),
        'stats': _stats.live(),
      });
    }
    return events;
  }

  /// Convenience: feed the float32-encoded bytes the audio service produces.
  List<Map<String, dynamic>> processBytes(Uint8List float32le) {
    final f = Float32List(float32le.length ~/ 4);
    f.buffer.asUint8List().setAll(0, float32le);
    return processPcm(f);
  }

  Map<String, dynamic> sessionSummary() => _stats.summary();
}
