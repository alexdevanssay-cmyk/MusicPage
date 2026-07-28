// lib/models/perf_stats.dart
// Performance telemetry emitted by the backend follower.

class PerfStats {
  final double elapsed;      // seconds of audio processed
  final double confidence;   // 0..1 smoothed tracking confidence
  final double tempoRel;     // 1.0 == the score's written tempo
  final double? bpm;         // absolute BPM if the score tempo is known
  final int wrongNotes;      // running count of audible deviations

  const PerfStats({
    this.elapsed = 0,
    this.confidence = 0,
    this.tempoRel = 1,
    this.bpm,
    this.wrongNotes = 0,
  });

  static const zero = PerfStats();

  factory PerfStats.fromJson(Map<String, dynamic> j) => PerfStats(
        elapsed: (j['elapsed'] as num?)?.toDouble() ?? 0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        tempoRel: (j['tempo_rel'] as num?)?.toDouble() ?? 1,
        bpm: (j['bpm'] as num?)?.toDouble(),
        wrongNotes: (j['wrong_notes'] as num?)?.toInt() ?? 0,
      );
}

class PerfSummary {
  final double duration;
  final double avgConfidence;
  final int wrongNotes;
  final double avgTempoRel;
  final double? avgBpm;
  final double? baseBpm;
  final List<double> tempoRange; // [min, max] relative

  const PerfSummary({
    required this.duration,
    required this.avgConfidence,
    required this.wrongNotes,
    required this.avgTempoRel,
    this.avgBpm,
    this.baseBpm,
    this.tempoRange = const [1, 1],
  });

  factory PerfSummary.fromJson(Map<String, dynamic> j) => PerfSummary(
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        avgConfidence: (j['avg_confidence'] as num?)?.toDouble() ?? 0,
        wrongNotes: (j['wrong_notes'] as num?)?.toInt() ?? 0,
        avgTempoRel: (j['avg_tempo_rel'] as num?)?.toDouble() ?? 1,
        avgBpm: (j['avg_bpm'] as num?)?.toDouble(),
        baseBpm: (j['base_bpm'] as num?)?.toDouble(),
        tempoRange: (j['tempo_rel_range'] as List?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            const [1, 1],
      );
}
