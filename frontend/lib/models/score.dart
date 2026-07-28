// lib/models/score.dart
// ──────────────────────
// Domain models matching the backend API response schemas.

import 'package:flutter/foundation.dart';

@immutable
class Score {
  final String id;
  final String title;
  final String composer;
  final int totalPages;
  final int totalMeasures;
  final double durationSecs;
  final double tempoBpm;
  final String timeSignature;
  final bool isAnalyzed;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime? lastOpened;

  const Score({
    required this.id,
    required this.title,
    required this.composer,
    required this.totalPages,
    required this.totalMeasures,
    required this.durationSecs,
    required this.tempoBpm,
    required this.timeSignature,
    required this.isAnalyzed,
    required this.isFavorite,
    required this.createdAt,
    this.lastOpened,
  });

  factory Score.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) =>
        v is String ? DateTime.tryParse(v) : null;
    return Score(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] as String?) ?? 'Untitled',
      composer: json['composer'] as String? ?? '',
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
      totalMeasures: (json['total_measures'] as num?)?.toInt() ?? 0,
      durationSecs: (json['duration_secs'] as num?)?.toDouble() ?? 0.0,
      tempoBpm: (json['tempo_bpm'] as num?)?.toDouble() ?? 120.0,
      timeSignature: json['time_signature'] as String? ?? '4/4',
      isAnalyzed: json['is_analyzed'] as bool? ?? false,
      isFavorite: json['is_favorite'] as bool? ?? false,
      // The list endpoint may omit created_at; fall back gracefully.
      createdAt: parseDate(json['created_at']) ??
          parseDate(json['last_opened']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastOpened: parseDate(json['last_opened']),
    );
  }

  Score copyWith({
    bool? isFavorite,
    bool? isAnalyzed,
  }) {
    return Score(
      id: id,
      title: title,
      composer: composer,
      totalPages: totalPages,
      totalMeasures: totalMeasures,
      durationSecs: durationSecs,
      tempoBpm: tempoBpm,
      timeSignature: timeSignature,
      isAnalyzed: isAnalyzed ?? this.isAnalyzed,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt,
      lastOpened: lastOpened,
    );
  }

  String get durationFormatted {
    final mins = (durationSecs / 60).floor();
    final secs = (durationSecs % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
