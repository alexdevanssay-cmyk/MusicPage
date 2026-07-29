// lib/offline/perf_stats.dart
// Port of the backend PerformanceStats — live tempo/confidence/wrong-note
// telemetry for the on-device follower. Emits the same map shape as the server
// so the existing overlay consumes it unchanged. Pure Dart.

import 'dart:collection';

class PerformanceStats {
  final double fps;
  final double? baseBpm;
  final double _low, _high;
  final int _minBad;
  final int _tempoWindow;

  int frames = 0;
  double _confSum = 0;
  double curConf = 0;

  final Queue<List<int>> _posHist = Queue(); // [frameIdx, refPos]
  double curTempoRel = 1.0;
  double _tempoSum = 0;
  int _tempoN = 0;
  double tempoMin = 1.0, tempoMax = 1.0;

  int wrongNotes = 0;
  bool _inError = false;
  int _badRun = 0;

  PerformanceStats({
    required this.fps,
    this.baseBpm,
    double tempoWindowS = 1.5,
    double lowConf = 0.35,
    double highConf = 0.55,
    int minBadFrames = 3,
  })  : _low = lowConf,
        _high = highConf,
        _minBad = minBadFrames,
        _tempoWindow = (tempoWindowS * fps).round().clamp(2, 1000000);

  void update(int frameIdx, int refPos, double confidence) {
    frames++;
    _confSum += confidence;
    curConf = frames > 1 ? 0.85 * curConf + 0.15 * confidence : confidence;

    _posHist.addLast([frameIdx, refPos]);
    while (_posHist.length > _tempoWindow) _posHist.removeFirst();
    if (_posHist.length >= 2) {
      final f0 = _posHist.first, f1 = _posHist.last;
      final df = f1[0] - f0[0];
      if (df > 0) {
        final raw = (f1[1] - f0[1]) / df;
        final r = raw < 0 ? 0.0 : raw;
        curTempoRel = 0.9 * curTempoRel + 0.1 * r;
        _tempoSum += curTempoRel;
        _tempoN++;
        if (curTempoRel < tempoMin) tempoMin = curTempoRel;
        if (curTempoRel > tempoMax) tempoMax = curTempoRel;
      }
    }

    if (confidence < _low) {
      _badRun++;
      if (!_inError && _badRun >= _minBad) {
        wrongNotes++;
        _inError = true;
      }
    } else {
      _badRun = 0;
      if (_inError && confidence >= _high) _inError = false;
    }
  }

  double get elapsedS => fps > 0 ? frames / fps : 0.0;
  double get avgConf => frames > 0 ? _confSum / frames : 0.0;
  double? bpm() => baseBpm == null ? null : (baseBpm! * curTempoRel);

  Map<String, dynamic> live() => {
        'elapsed': double.parse(elapsedS.toStringAsFixed(1)),
        'confidence': double.parse(curConf.toStringAsFixed(3)),
        'tempo_rel': double.parse(curTempoRel.toStringAsFixed(3)),
        'bpm': bpm() == null ? null : double.parse(bpm()!.toStringAsFixed(1)),
        'wrong_notes': wrongNotes,
      };

  Map<String, dynamic> summary() {
    final avgRel = _tempoN > 0 ? _tempoSum / _tempoN : 1.0;
    return {
      'type': 'session_summary',
      'duration': double.parse(elapsedS.toStringAsFixed(1)),
      'avg_confidence': double.parse(avgConf.toStringAsFixed(3)),
      'wrong_notes': wrongNotes,
      'avg_tempo_rel': double.parse(avgRel.toStringAsFixed(3)),
      'tempo_rel_range': [
        double.parse(tempoMin.toStringAsFixed(3)),
        double.parse(tempoMax.toStringAsFixed(3)),
      ],
      'avg_bpm': baseBpm == null ? null : double.parse((baseBpm! * avgRel).toStringAsFixed(1)),
      'base_bpm': baseBpm == null ? null : double.parse(baseBpm!.toStringAsFixed(1)),
    };
  }
}
