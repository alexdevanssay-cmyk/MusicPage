// lib/widgets/control_bar.dart
// ──────────────────────────────
// Bottom overlay bar with all reader controls:
//   Start / Pause / Resume / Stop following
//   Page navigation arrows
//   Recalibrate button

import 'package:flutter/material.dart';
import '../models/position.dart';

class ControlBar extends StatelessWidget {
  const ControlBar({
    super.key,
    required this.state,
    required this.currentPage,
    required this.totalPages,
    required this.currentMeasure,
    required this.onStartFollowing,
    required this.onPauseFollowing,
    required this.onResumeFollowing,
    required this.onStopFollowing,
    required this.onRecalibrate,
    required this.onPageChanged,
  });

  final FollowingState state;
  final int currentPage;
  final int totalPages;
  final int currentMeasure;
  final VoidCallback onStartFollowing;
  final VoidCallback onPauseFollowing;
  final VoidCallback onResumeFollowing;
  final VoidCallback onStopFollowing;
  final VoidCallback onRecalibrate;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xDD000000), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 20,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Prev page ───────────────────────────────────────────────────────
          _NavButton(
            icon: Icons.chevron_left,
            enabled: currentPage > 1,
            onTap: () => onPageChanged(currentPage - 1),
          ),

          const SizedBox(width: 8),

          // ── Page counter ────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$currentPage / $totalPages',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Next page ───────────────────────────────────────────────────────
          _NavButton(
            icon: Icons.chevron_right,
            enabled: currentPage < totalPages,
            onTap: () => onPageChanged(currentPage + 1),
          ),

          const SizedBox(width: 20),

          // ── Primary action button ───────────────────────────────────────────
          _PrimaryActionButton(state: state, onStart: onStartFollowing, onPause: onPauseFollowing, onResume: onResumeFollowing, onStop: onStopFollowing),

          // ── Recalibrate (only when following / paused) ──────────────────────
          if (state == FollowingState.following ||
              state == FollowingState.paused) ...[
            const SizedBox(width: 12),
            Tooltip(
              message: 'Recalibrate position',
              child: Material(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(50),
                child: InkWell(
                  borderRadius: BorderRadius.circular(50),
                  onTap: onRecalibrate,
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.my_location, size: 20, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? Colors.white12 : Colors.transparent,
      borderRadius: BorderRadius.circular(50),
      child: InkWell(
        borderRadius: BorderRadius.circular(50),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 26,
            color: enabled ? Colors.white : Colors.white24,
          ),
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.state,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });
  final FollowingState state;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case FollowingState.idle:
      case FollowingState.error:
        return FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.mic, size: 18),
          label: const Text('Follow'),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        );

      case FollowingState.loading:
        return FilledButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          label: const Text('Loading…'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.grey.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
        );

      case FollowingState.following:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBtn(
              icon: Icons.pause,
              tooltip: 'Pause',
              color: Colors.amber,
              onTap: onPause,
            ),
            const SizedBox(width: 8),
            _IconBtn(
              icon: Icons.stop,
              tooltip: 'Stop',
              color: Colors.red.shade300,
              onTap: onStop,
            ),
          ],
        );

      case FollowingState.paused:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBtn(
              icon: Icons.play_arrow,
              tooltip: 'Resume',
              color: Colors.greenAccent,
              onTap: onResume,
            ),
            const SizedBox(width: 8),
            _IconBtn(
              icon: Icons.stop,
              tooltip: 'Stop',
              color: Colors.red.shade300,
              onTap: onStop,
            ),
          ],
        );
    }
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(50),
        child: InkWell(
          borderRadius: BorderRadius.circular(50),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}
