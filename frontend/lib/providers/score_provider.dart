// lib/providers/score_provider.dart
// ─────────────────────────────────
// Manages the score library: fetch, import, delete, favourite.

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/score.dart';
import '../services/api_service.dart';
import 'settings_provider.dart';

// ── Scores list ─────────────────────────────────────────────────────────────────

class ScoresNotifier extends AsyncNotifier<List<Score>> {
  @override
  Future<List<Score>> build() async {
    final api = ref.read(apiServiceProvider);
    return api.fetchScores();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(apiServiceProvider).fetchScores(),
    );
  }

  Future<Score?> importPdf(
    File file, {
    String? title,
    String? composer,
  }) async {
    try {
      final api = ref.read(apiServiceProvider);
      final score = await api.importScore(
        file: file,
        title: title,
        composer: composer,
      );
      // Optimistically add to list
      final current = state.valueOrNull ?? [];
      state = AsyncValue.data([score, ...current]);
      return score;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      return null;
    }
  }

  Future<void> deleteScore(String scoreId) async {
    await ref.read(apiServiceProvider).deleteScore(scoreId);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.where((s) => s.id != scoreId).toList(),
    );
  }

  Future<void> toggleFavorite(String scoreId) async {
    final api = ref.read(apiServiceProvider);
    final isFav = await api.toggleFavorite(scoreId);
    final current = state.valueOrNull ?? [];
    state = AsyncValue.data(
      current.map((s) {
        if (s.id == scoreId) return s.copyWith(isFavorite: isFav);
        return s;
      }).toList(),
    );
  }
}

final scoresProvider = AsyncNotifierProvider<ScoresNotifier, List<Score>>(
  ScoresNotifier.new,
);

// ── Single score ─────────────────────────────────────────────────────────────────

final scoreDetailProvider = FutureProvider.family<Score, String>(
  (ref, scoreId) => ref.read(apiServiceProvider).fetchScore(scoreId),
);

// ── API service ──────────────────────────────────────────────────────────────────

final apiServiceProvider = Provider<ApiService>((ref) {
  final settings = ref.watch(settingsProvider);
  return ApiService(baseUrl: settings.baseUrl);
});

// ── Search filter ─────────────────────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

final filteredScoresProvider = Provider<List<Score>>((ref) {
  final scores = ref.watch(scoresProvider).valueOrNull ?? [];
  final query = ref.watch(searchQueryProvider).toLowerCase();
  if (query.isEmpty) return scores;
  return scores.where((s) {
    return s.title.toLowerCase().contains(query) ||
        s.composer.toLowerCase().contains(query);
  }).toList();
});
