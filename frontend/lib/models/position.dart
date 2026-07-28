// lib/models/position.dart
import 'package:flutter/foundation.dart';

@immutable
class ScorePosition {
  final int measure;
  final int page;
  final double pageProgress;      // 0–1 within current page
  final double globalProgress;    // 0–1 over the whole score
  final double confidence;        // 0–1

  const ScorePosition({
    required this.measure,
    required this.page,
    required this.pageProgress,
    required this.globalProgress,
    required this.confidence,
  });

  static const zero = ScorePosition(
    measure: 1,
    page: 1,
    pageProgress: 0,
    globalProgress: 0,
    confidence: 0,
  );

  factory ScorePosition.fromJson(Map<String, dynamic> json) {
    return ScorePosition(
      measure: (json['measure'] as num).toInt(),
      page: (json['page'] as num).toInt(),
      pageProgress: (json['progress'] as num).toDouble(),
      globalProgress: (json['global_progress'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  ScorePosition copyWith({int? page}) {
    return ScorePosition(
      measure: measure,
      page: page ?? this.page,
      pageProgress: pageProgress,
      globalProgress: globalProgress,
      confidence: confidence,
    );
  }

  bool get isHighConfidence => confidence > 0.6;
}

enum FollowingState {
  idle,
  loading,
  following,
  paused,
  error,
}
