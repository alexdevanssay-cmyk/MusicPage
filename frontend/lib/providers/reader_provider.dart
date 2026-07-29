// lib/providers/reader_provider.dart
// ─────────────────────────────────
// Manages the state of the score reader:
//   • Current page displayed
//   • Real-time following position
//   • WebSocket connection state
//   • Audio capture toggle

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../models/perf_stats.dart';
import '../offline/offline_follower.dart';
import '../services/websocket_service.dart';
import '../services/audio_service.dart';
import '../services/offline_store.dart';
import 'settings_provider.dart';

// ── Reader state ─────────────────────────────────────────────────────────────────

class ReaderState {
  final String scoreId;
  final int currentPage;
  final int totalPages;
  final ScorePosition position;
  final FollowingState followingState;
  final String? errorMessage;
  final bool isPreloadingNext;

  // Performance telemetry (for the stats overlay)
  final PerfStats stats;
  final PerfSummary? summary;      // set when a session ends
  final List<double> tempoHistory; // recent relative-tempo samples (sparkline)
  final bool showStats;            // overlay visible?

  const ReaderState({
    required this.scoreId,
    this.currentPage = 1,
    this.totalPages = 1,
    this.position = ScorePosition.zero,
    this.followingState = FollowingState.idle,
    this.errorMessage,
    this.isPreloadingNext = false,
    this.stats = PerfStats.zero,
    this.summary,
    this.tempoHistory = const [],
    this.showStats = false,
  });

  ReaderState copyWith({
    int? currentPage,
    int? totalPages,
    ScorePosition? position,
    FollowingState? followingState,
    String? errorMessage,
    bool? isPreloadingNext,
    PerfStats? stats,
    PerfSummary? summary,
    bool clearSummary = false,
    List<double>? tempoHistory,
    bool? showStats,
  }) {
    return ReaderState(
      scoreId: scoreId,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      position: position ?? this.position,
      followingState: followingState ?? this.followingState,
      errorMessage: errorMessage,
      isPreloadingNext: isPreloadingNext ?? this.isPreloadingNext,
      stats: stats ?? this.stats,
      summary: clearSummary ? null : (summary ?? this.summary),
      tempoHistory: tempoHistory ?? this.tempoHistory,
      showStats: showStats ?? this.showStats,
    );
  }

  bool get isFollowing => followingState == FollowingState.following;
}

// ── Notifier ──────────────────────────────────────────────────────────────────────

class ReaderNotifier extends FamilyNotifier<ReaderState, String> {
  late WsService _ws;
  late AudioCaptureService _audio;
  final OfflineStore _store = OfflineStore();
  OfflineFollower? _offline; // non-null while following on-device

  @override
  ReaderState build(String scoreId) {
    final settings = ref.read(settingsProvider);
    _ws = WsService(wsUrl: settings.wsUrl);
    _audio = AudioCaptureService();

    // Listen to WebSocket messages
    _ws.messages.listen(_handleWsMessage, onError: _handleWsError);

    // Clean up when provider is disposed
    ref.onDispose(() {
      _stopFollowing();
      _ws.dispose();
      _audio.dispose();
    });

    return ReaderState(scoreId: scoreId);
  }

  // ── Public actions ────────────────────────────────────────────────────────────

  Future<void> startFollowing() async {
    state = state.copyWith(
      followingState: FollowingState.loading,
      stats: PerfStats.zero,
      tempoHistory: const [],
      clearSummary: true,
    );
    final settings = ref.read(settingsProvider);

    try {
      // Prefer fully on-device following when the score has been downloaded —
      // works with no server / off Wi-Fi.
      if (await _store.isDownloaded(state.scoreId)) {
        final bundle = await _store.loadBundle(state.scoreId);
        final fb = await OfflineStore.loadFilterbank();
        _offline = OfflineFollower(
          bundle: bundle,
          filterbank: fb,
          preloadThr: settings.preloadThreshold,
          turnThr: settings.pageTurnThreshold,
        );
        state = state.copyWith(
          totalPages: _offline!.totalPages,
          followingState: FollowingState.following,
        );
        await _audio.startCapture(
          onChunk: _onOfflineChunk,
          sampleRate: 22050,
          deviceId: settings.audioDeviceId,
        );
        return;
      }

      // Otherwise stream to the backend over the WebSocket.
      await _ws.connect();
      await _ws.send({
        'type': 'start_session',
        'score_id': state.scoreId,
        'sensitivity': settings.micSensitivity,
      });
      await _audio.startCapture(
        onChunk: (bytes) => _ws.sendBinary(bytes),
        sampleRate: 22050,
        deviceId: settings.audioDeviceId,
      );

      state = state.copyWith(followingState: FollowingState.following);
    } catch (e) {
      state = state.copyWith(
        followingState: FollowingState.error,
        errorMessage: e.toString(),
      );
    }
  }

  void _onOfflineChunk(Uint8List bytes) {
    final f = _offline;
    if (f == null) return;
    for (final ev in f.processBytes(bytes)) {
      _handleWsMessage(ev);
    }
  }

  Future<void> pauseFollowing() async {
    if (!state.isFollowing) return;
    await _audio.stopCapture();
    state = state.copyWith(followingState: FollowingState.paused);
  }

  Future<void> resumeFollowing() async {
    if (state.followingState != FollowingState.paused) return;
    final settings = ref.read(settingsProvider);
    await _audio.startCapture(
      onChunk: _offline != null ? _onOfflineChunk : (bytes) => _ws.sendBinary(bytes),
      sampleRate: 22050,
      deviceId: settings.audioDeviceId,
    );
    state = state.copyWith(followingState: FollowingState.following);
  }

  Future<void> stopFollowing() async {
    _stopFollowing();
    state = state.copyWith(followingState: FollowingState.idle);
  }

  void navigateToPage(int page) {
    state = state.copyWith(currentPage: page);
  }

  void recalibrate(int measureNumber) {
    if (_ws.isConnected) {
      _ws.send({'type': 'manual_position', 'measure': measureNumber});
    }
  }

  // ── WebSocket message handler ─────────────────────────────────────────────────

  void _handleWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    switch (type) {
      case 'session_started':
        state = state.copyWith(
          totalPages: (msg['total_pages'] as num?)?.toInt() ?? 1,
          followingState: FollowingState.following,
        );

      case 'position_update':
        final pos = ScorePosition.fromJson(msg);
        if (msg['stats'] is Map) {
          final s = PerfStats.fromJson(msg['stats'] as Map<String, dynamic>);
          final hist = List<double>.of(state.tempoHistory)..add(s.tempoRel);
          if (hist.length > 120) hist.removeRange(0, hist.length - 120);
          state = state.copyWith(position: pos, stats: s, tempoHistory: hist);
        } else {
          state = state.copyWith(position: pos);
        }

      case 'preload_next_page':
        state = state.copyWith(isPreloadingNext: true);

      case 'page_change':
        final toPage = (msg['to_page'] as num).toInt();
        state = state.copyWith(
          currentPage: toPage,
          isPreloadingNext: false,
        );

      case 'session_summary':
        state = state.copyWith(
          summary: PerfSummary.fromJson(msg),
          showStats: true, // reveal the recap when the piece ends
        );

      case 'error':
        state = state.copyWith(
          followingState: FollowingState.error,
          errorMessage: msg['message'] as String?,
        );
    }
  }

  /// Show/hide the performance stats overlay.
  void toggleStats() => state = state.copyWith(showStats: !state.showStats);

  void _handleWsError(Object error) {
    state = state.copyWith(
      followingState: FollowingState.error,
      errorMessage: error.toString(),
    );
  }

  void _stopFollowing() {
    _audio.stopCapture();
    if (_offline != null) {
      // on-device session — emit the whole-piece recap, then release it
      _handleWsMessage(_offline!.sessionSummary());
      _offline = null;
    } else {
      _ws.send({'type': 'stop_session'}).ignore();
      _ws.disconnect();
    }
  }
}

// NotifierProvider.family est l'API publique Riverpod 2.x.
// NotifierProviderFamily n'est PAS instanciable directement (type interne).
final readerProvider =
    NotifierProvider.family<ReaderNotifier, ReaderState, String>(
  ReaderNotifier.new,
);
