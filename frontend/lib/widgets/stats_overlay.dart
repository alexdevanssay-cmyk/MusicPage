// lib/widgets/stats_overlay.dart
// Hidable performance HUD: live stats while following + a whole-piece recap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/perf_stats.dart';
import '../providers/reader_provider.dart';

class StatsOverlay extends ConsumerWidget {
  const StatsOverlay({super.key, required this.scoreId});
  final String scoreId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rs = ref.watch(readerProvider(scoreId));
    if (!rs.showStats) return const SizedBox.shrink();

    final notifier = ref.read(readerProvider(scoreId).notifier);

    return Container(
      width: 260,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xE60D0D1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: Color(0xFF7986CB), size: 18),
              const SizedBox(width: 6),
              Text(
                rs.summary != null ? 'Performance recap' : 'Performance',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: notifier.toggleStats,
                child: const Icon(Icons.close, color: Colors.white54, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rs.summary != null)
            _Summary(s: rs.summary!)
          else
            _Live(stats: rs.stats, tempoHistory: rs.tempoHistory),
        ],
      ),
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.stats, required this.tempoHistory});
  final PerfStats stats;
  final List<double> tempoHistory;

  @override
  Widget build(BuildContext context) {
    final tempoLabel = stats.bpm != null
        ? '${stats.bpm!.round()} bpm'
        : '${(stats.tempoRel * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Tile(label: 'Time', value: _fmtTime(stats.elapsed)),
            _Tile(
              label: 'Confidence',
              value: '${(stats.confidence * 100).round()}%',
              color: _confColor(stats.confidence),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Tile(label: 'Tempo', value: tempoLabel),
            _Tile(
              label: 'Wrong notes',
              value: '${stats.wrongNotes}',
              color: stats.wrongNotes == 0 ? Colors.greenAccent : Colors.amber,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('Tempo',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            const Spacer(),
            Text('${(tempoHistory.isEmpty ? stats.tempoRel : tempoHistory.last) * 100 ~/ 1}% of score',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          width: double.infinity,
          child: CustomPaint(painter: _Sparkline(tempoHistory)),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.s});
  final PerfSummary s;

  @override
  Widget build(BuildContext context) {
    final tempo = s.avgBpm != null
        ? '${s.avgBpm!.round()} bpm avg'
        : '${(s.avgTempoRel * 100).round()}% avg';
    final range = '${(s.tempoRange.first * 100).round()}–${(s.tempoRange.last * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Tile(label: 'Duration', value: _fmtTime(s.duration)),
            _Tile(
              label: 'Avg confidence',
              value: '${(s.avgConfidence * 100).round()}%',
              color: _confColor(s.avgConfidence),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _Tile(label: 'Tempo', value: tempo),
            _Tile(
              label: 'Wrong notes',
              value: '${s.wrongNotes}',
              color: s.wrongNotes == 0 ? Colors.greenAccent : Colors.amber,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Tempo varied $range of the written tempo',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: color ?? Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sparkline extends CustomPainter {
  _Sparkline(this.data);
  final List<double> data;

  @override
  void paint(Canvas canvas, Size size) {
    // reference-tempo baseline (100%)
    final base = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    final midY = size.height / 2;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), base);

    if (data.length < 2) return;
    // map tempo ratio 0..2 → full height (clamped)
    final n = data.length;
    final dx = size.width / (n - 1);
    final path = Path();
    for (var i = 0; i < n; i++) {
      final v = data[i].clamp(0.0, 2.0);
      final y = size.height - (v / 2.0) * size.height;
      final x = i * dx;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final line = Paint()
      ..color = const Color(0xFF7986CB)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant _Sparkline old) => old.data != data;
}

// ── shared helpers ──────────────────────────────────────────────────────────
String _fmtTime(double secs) {
  final s = secs.round();
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

Color _confColor(double c) {
  if (c > 0.6) return Colors.greenAccent;
  if (c > 0.35) return Colors.amber;
  return Colors.redAccent;
}
