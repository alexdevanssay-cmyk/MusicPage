// lib/providers/reader_provider.dart
// ─────────────────────────────────
// Manages the state of the score reader:
//   • Current page displayed
//   • Real-time following position
//   • WebSocket connection state
//   • Audio capture toggle

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/websocket_service.dart';
import '../services/audio_service.dart';
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

  const ReaderState({
    required this.scoreId,
    this.currentPage = 1,
    this.totalPages = 1,
    this.position = ScorePosition.zero,
    this.followingState = FollowingState.idle,
    this.errorMessage,
    this.isPreloadingNext = false,
  });

  ReaderState copyWith({
    int? currentPage,
    int? totalPages,
    ScorePosition? position,
    FollowingState? followingState,
    String? errorMessage,
    bool? isPreloadingNext,
  }) {
    return ReaderState(
      scoreId: scoreId,
      currentPage: currentPage ?? this.currentPage,
      totalPages: totalPages ?? this.totalPages,
      position: position ?? this.position,
      followingState: followingState ?? this.followingState,
      errorMessage: errorMessage,
      isPreloadingNext: isPreloadingNext ?? this.isPreloadingNext,
    );
  }

  bool get isFollowing => followingState == FollowingState.following;
}

// ── Notifier ──────────────────────────────────────────────────────────────────────

class ReaderNotifier extends FamilyNotifier<ReaderState, String> {
  late WsService _ws;
  late AudioCaptureService _audio;

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
    state = state.copyWith(followingState: FollowingState.loading);
    final settings = ref.read(settingsProvider);

    try {
      // Connect WebSocket
      await _ws.connect();
      await _ws.send({
        'type': 'start_session',
        'score_id': state.scoreId,
        'sensitivity': settings.micSensitivity,
      });

      // Start audio capture – PCM chunks go directly to WebSocket
      await _audio.startCapture(
        onChunk: (bytes) => _ws.sendBinary(bytes),
        sampleRate: 22050,
      );

      state = state.copyWith(followingState: FollowingState.following);
    } catch (e) {
      state = state.copyWith(
        followingState: FollowingState.error,
        errorMessage: e.toString(),
      );
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
      onChunk: (bytes) => _ws.sendBinary(bytes),
      sampleRate: 22050,
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
        state = state.copyWith(position: pos);

      case 'preload_next_page':
        state = state.copyWith(isPreloadingNext: true);

      case 'page_change':
        final toPage = (msg['to_page'] as num).toInt();
        state = state.copyWith(
          currentPage: toPage,
          isPreloadingNext: false,
        );

      case 'error':
        state = state.copyWith(
          followingState: FollowingState.error,
          errorMessage: msg['message'] as String?,
        );
    }
  }

  void _handleWsError(Object error) {
    state = state.copyWith(
      followingState: FollowingState.error,
      errorMessage: error.toString(),
    );
  }

  void _stopFollowing() {
    _audio.stopCapture();
    _ws.send({'type': 'stop_session'}).ignore();
    _ws.disconnect();
  }
}

// NotifierProvider.family est l'API publique Riverpod 2.x.
// NotifierProviderFamily n'est PAS instanciable directement (type interne).
final readerProvider =
    NotifierProvider.family<ReaderNotifier, ReaderState, String>(
  ReaderNotifier.new,
);
