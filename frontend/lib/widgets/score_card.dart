// lib/widgets/score_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/score.dart';

class ScoreCard extends StatelessWidget {
  const ScoreCard({
    super.key,
    required this.score,
    required this.onTap,
    required this.onFavorite,
    required this.onDelete,
    this.onDownload,
    this.isDownloaded = false,
  });

  final Score score;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback? onDownload;
  final bool isDownloaded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background gradient ──────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1E1E3A), const Color(0xFF0D0D1A)]
                      : [const Color(0xFFECECFF), const Color(0xFFDDDDF5)],
                ),
              ),
            ),

            // ── Music staff decoration ───────────────────────────────────────
            Positioned.fill(
              child: CustomPaint(painter: _StaffPainter(cs.outlineVariant)),
            ),

            // ── Content ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Analysis badge
                  Row(
                    children: [
                      _StatusChip(isAnalyzed: score.isAnalyzed),
                      const Spacer(),
                      if (isDownloaded)
                        Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Icon(Icons.offline_pin,
                              size: 18, color: Colors.green.shade400),
                        ),
                      // Context menu
                      PopupMenuButton<String>(
                        iconSize: 20,
                        onSelected: (v) {
                          if (v == 'delete') onDelete();
                          if (v == 'favorite') onFavorite();
                          if (v == 'download') onDownload?.call();
                        },
                        itemBuilder: (_) => [
                          if (onDownload != null && !isDownloaded)
                            const PopupMenuItem(
                              value: 'download',
                              child: ListTile(
                                dense: true,
                                leading: Icon(Icons.download_for_offline_outlined),
                                title: Text('Download for offline'),
                              ),
                            ),
                          PopupMenuItem(
                            value: 'favorite',
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                score.isFavorite
                                    ? Icons.star
                                    : Icons.star_outline,
                              ),
                              title: Text(score.isFavorite
                                  ? 'Remove favourite'
                                  : 'Add to favourites'),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.delete_outline,
                                  color: Colors.red),
                              title: Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Favourite star
                  if (score.isFavorite)
                    Icon(Icons.star, size: 18, color: Colors.amber.shade600)
                        .animate()
                        .scale(duration: 200.ms, curve: Curves.elasticOut),

                  const SizedBox(height: 4),

                  // Title
                  Text(
                    score.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  if (score.composer.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      score.composer,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Meta row
                  Row(
                    children: [
                      _MetaChip(
                        icon: Icons.menu_book_outlined,
                        label: '${score.totalPages}p',
                      ),
                      const SizedBox(width: 6),
                      if (score.durationSecs > 0)
                        _MetaChip(
                          icon: Icons.timer_outlined,
                          label: score.durationFormatted,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isAnalyzed});
  final bool isAnalyzed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isAnalyzed
            ? Colors.green.withOpacity(0.15)
            : Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAnalyzed
              ? Colors.green.withOpacity(0.4)
              : Colors.orange.withOpacity(0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAnalyzed ? Icons.check_circle_outline : Icons.hourglass_top,
            size: 11,
            color: isAnalyzed ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 4),
          Text(
            isAnalyzed ? 'Ready' : 'Analysing…',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isAnalyzed ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cs.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Decorative staff lines painter ────────────────────────────────────────────

class _StaffPainter extends CustomPainter {
  _StaffPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.12)
      ..strokeWidth = 0.8;

    for (int i = 0; i < 5; i++) {
      final y = size.height * 0.45 + i * 5.0;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_StaffPainter old) => old.color != color;
}
