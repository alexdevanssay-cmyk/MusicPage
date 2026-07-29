// lib/offline/position_tracker.dart
// Port of the backend PositionTracker: raw reference frame -> measure, page,
// progress, and page preload/turn decisions. Pure Dart.

import 'reference_bundle.dart';

class ScorePosition {
  final int measure;
  final int page;
  final double pageProgress;
  final double globalProgress;
  final double confidence;
  final bool shouldPreloadNext;
  final bool shouldTurnPage;
  final int? nextPage;
  const ScorePosition({
    required this.measure,
    required this.page,
    required this.pageProgress,
    required this.globalProgress,
    required this.confidence,
    required this.shouldPreloadNext,
    required this.shouldTurnPage,
    required this.nextPage,
  });
}

class PositionTracker {
  final ReferenceBundle b;
  final double preloadThr;
  final double turnThr;
  final int nFrames;
  final int totalPages;

  int _currentPage = 1;
  bool _preloadEmitted = false;
  bool _turnEmitted = false;

  PositionTracker(this.b, {this.preloadThr = 0.80, this.turnThr = 0.95})
      : nFrames = b.totalFrames,
        totalPages = b.totalPages;

  ScorePosition update(int frameIn, double confidence) {
    final frame = frameIn.clamp(0, nFrames - 1);
    final measure = frame < b.measures.length ? b.measures[frame] : 1;
    final page = _frameToPage(frame);
    final pageProgress = _pageProgress(frame, page);
    final globalProgress = frame / (nFrames - 1 > 0 ? nFrames - 1 : 1);

    if (page != _currentPage) {
      _currentPage = page;
      _preloadEmitted = false;
      _turnEmitted = false;
    }

    bool shouldPreload = false, shouldTurn = false;
    final nextPage = page < totalPages ? page + 1 : null;
    if (nextPage != null) {
      if (pageProgress >= preloadThr && !_preloadEmitted) {
        shouldPreload = true;
        _preloadEmitted = true;
      }
      if (pageProgress >= turnThr && !_turnEmitted) {
        shouldTurn = true;
        _turnEmitted = true;
      }
    }

    return ScorePosition(
      measure: measure,
      page: page,
      pageProgress: pageProgress,
      globalProgress: globalProgress,
      confidence: confidence,
      shouldPreloadNext: shouldPreload,
      shouldTurnPage: shouldTurn,
      nextPage: nextPage,
    );
  }

  int _frameToPage(int frame) {
    for (final row in b.pageMap) {
      if (row[1] <= frame && frame <= row[2]) return row[0];
    }
    return 1;
  }

  double _pageProgress(int frame, int page) {
    for (final row in b.pageMap) {
      if (row[0] == page) {
        final span = row[2] - row[1];
        if (span <= 0) return 0.0;
        return (frame - row[1]) / span;
      }
    }
    return 0.0;
  }
}
