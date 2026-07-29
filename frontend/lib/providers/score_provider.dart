// lib/providers/score_provider.dart
// ─────────────────────────────────
// Manages the score library: fetch, import, delete, favourite.

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/score.dart';
import '../services/api_service.dart';
import '../services/offline_store.dart';
import 'settings_provider.dart';

// Resolves where the reader should load a score's PDF from: a locally-stored
// file when the score has been downloaded for offline use, otherwise streamed
// from the backend. Lets the reader work with the PC off.
final readerPdfProvider = FutureProvider.family<({File? file, String url}), String>((ref, scoreId) async {
  final settings = ref.watch(settingsProvider);
  final url = '${settings.baseUrl}/api/v1/scores/$scoreId/pdf';
  final store = OfflineStore();
  if (await store.isDownloaded(scoreId)) {
    final f = await store.pdfFile(scoreId);
    if (await f.exists()) return (file: f, url: url);
  }
  return (file: null, url: url);
});

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

// ── Offline downloads ─────────────────────────────────────────────────────────────

/// IDs of scores that have been downloaded for offline following.
final downloadedIdsProvider = FutureProvider<Set<String>>((ref) async {
  final metas = await OfflineStore().listLocal();
  return metas.map((m) => m.id).toSet();
});

/// Locally-stored scores, shown when the backend is unreachable.
final offlineScoresProvider = FutureProvider<List<Score>>((ref) async {
  final metas = await OfflineStore().listLocal();
  return metas
      .map((m) => Score(
            id: m.id,
            title: m.title,
            composer: m.composer,
            totalPages: m.totalPages,
            totalMeasures: 0,
            durationSecs: 0,
            tempoBpm: 120,
            timeSignature: '4/4',
            isAnalyzed: true,
            isFavorite: false,
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ))
      .toList();
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
