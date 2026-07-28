// lib/widgets/tracking_indicator.dart
// ─────────────────────────────────────
// Small floating HUD that shows the follower's current state,
// confidence level, and measure number. Designed to be unobtrusive
// so it never hides the score underneath.

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/position.dart';

class TrackingIndicator extends StatelessWidget {
  const TrackingIndicator({
    super.key,
    required this.state,
    required this.confidence,
    required this.measure,
    required this.pageProgress,
  });

  final FollowingState state;
  final double confidence;  // 0–1
  final int measure;
  final double pageProgress; // 0–1

  @override
  Widget build(BuildContext context) {
    if (state == FollowingState.idle) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _stateColor.withOpacity(0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Confidence arc ─────────────────────────────────────────────────
          SizedBox(
            width: 26,
            height: 26,
            child: CustomPaint(
              painter: _ConfidenceArcPainter(
                confidence: state == FollowingState.following ? confidence : 0,
                color: _stateColor,
              ),
              child: Center(
                child: _StateIcon(state: state, color: _stateColor),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Text ───────────────────────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _stateLabel,
                style: TextStyle(
                  color: _stateColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              if (state == FollowingState.following) ...[
                const SizedBox(height: 1),
                Text(
                  'M.$measure  ${(pageProgress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    )
        .animate(target: state == FollowingState.following ? 1.0 : 0.8)
        .scaleXY(duration: 200.ms);
  }

  Color get _stateColor {
    switch (state) {
      case FollowingState.following:
        if (confidence > 0.65) return Colors.greenAccent;
        if (confidence > 0.35) return Colors.amberAccent;
        return Colors.orangeAccent;
      case FollowingState.loading:
        return Colors.blueAccent;
      case FollowingState.paused:
        return Colors.grey.shade400;
      case FollowingState.error:
        return Colors.redAccent;
      case FollowingState.idle:
        return Colors.transparent;
    }
  }

  String get _stateLabel {
    switch (state) {
      case FollowingState.following:
        return 'FOLLOWING';
      case FollowingState.loading:
        return 'LOADING';
      case FollowingState.paused:
        return 'PAUSED';
      case FollowingState.error:
        return 'ERROR';
      case FollowingState.idle:
        return '';
    }
  }
}

// ── State icon ─────────────────────────────────────────────────────────────────

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state, required this.color});
  final FollowingState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case FollowingState.following:
        return Icon(Icons.graphic_eq, size: 12, color: color)
            .animate(onPlay: (c) => c.repeat())
            .scaleXY(
              begin: 0.85,
              end: 1.15,
              duration: 800.ms,
              curve: Curves.easeInOut,
            );
      case FollowingState.loading:
        return SizedBox(
          width: 10,
          height: 10,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: color,
          ),
        );
      case FollowingState.paused:
        return Icon(Icons.pause, size: 11, color: color);
      case FollowingState.error:
        return Icon(Icons.warning_amber_rounded, size: 11, color: color);
      case FollowingState.idle:
        return const SizedBox.shrink();
    }
  }
}

// ── Arc painter ────────────────────────────────────────────────────────────────

class _ConfidenceArcPainter extends CustomPainter {
  _ConfidenceArcPainter({required this.confidence, required this.color});
  final double confidence;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi,
      false,
      Paint()
        ..color = Colors.white12
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Confidence arc
    if (confidence > 0.01) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * confidence,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_ConfidenceArcPainter old) =>
      old.confidence != confidence || old.color != color;
}
