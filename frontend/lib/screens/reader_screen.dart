// lib/screens/reader_screen.dart
// ──────────────────────────────
// Full-screen PDF viewer with real-time score following.
// Supports automatic page turns, manual navigation, recalibration.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/position.dart';
import '../providers/reader_provider.dart';
import '../providers/score_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/control_bar.dart';
import '../widgets/tracking_indicator.dart';
import '../widgets/stats_overlay.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.scoreId});
  final String scoreId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with SingleTickerProviderStateMixin {
  final PdfViewerController _pdfController = PdfViewerController();
  bool _uiVisible = true;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );
    _fadeAnim = _fadeController;

    // Enter immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pdfController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerProvider(widget.scoreId));
    final scoreAsync = ref.watch(scoreDetailProvider(widget.scoreId));
    final settings = ref.read(settingsProvider);

    // React to page changes from the backend
    ref.listen(readerProvider(widget.scoreId), (prev, next) {
      if (prev?.currentPage != next.currentPage) {
        _pdfController.jumpToPage(next.currentPage);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleUI,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── PDF Viewer ──────────────────────────────────────────────────────
            scoreAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
              error: (e, _) => Center(
                child: Text(e.toString(), style: const TextStyle(color: Colors.white)),
              ),
              data: (score) => SfPdfViewer.network(
                '${settings.baseUrl}/api/v1/scores/${widget.scoreId}/pdf',
                controller: _pdfController,
                pageLayoutMode: PdfPageLayoutMode.single,
                scrollDirection: PdfScrollDirection.horizontal,
                enableDoubleTapZooming: true,
                onPageChanged: (PdfPageChangedDetails details) {
                  ref
                      .read(readerProvider(widget.scoreId).notifier)
                      .navigateToPage(details.newPageNumber);
                },
              ),
            ),

            // ── Tracking indicator (always visible, top-right) ──────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: TrackingIndicator(
                state: readerState.followingState,
                confidence: readerState.position.confidence,
                measure: readerState.position.measure,
                pageProgress: readerState.position.pageProgress,
              ),
            ),

            // ── Performance stats overlay (hidable, top-left) ───────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 16,
              child: StatsOverlay(scoreId: widget.scoreId),
            ),

            // ── Progress bar (bottom) ────────────────────────────────────────────
            if (readerState.isFollowing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: readerState.position.globalProgress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  color: _confidenceColor(readerState.position.confidence),
                ),
              ),

            // ── Overlay UI (fades in/out on tap) ─────────────────────────────────
            AnimatedBuilder(
              animation: _fadeAnim,
              builder: (ctx, child) => Opacity(
                opacity: _fadeAnim.value,
                child: IgnorePointer(
                  ignoring: !_uiVisible,
                  child: child,
                ),
              ),
              child: Column(
                children: [
                  // Top bar
                  _TopBar(
                    scoreId: widget.scoreId,
                    onBack: () {
                      ref
                          .read(readerProvider(widget.scoreId).notifier)
                          .stopFollowing();
                      context.pop();
                    },
                  ),

                  const Spacer(),

                  // Control bar
                  ControlBar(
                    state: readerState.followingState,
                    currentPage: readerState.currentPage,
                    totalPages: readerState.totalPages,
                    currentMeasure: readerState.position.measure,
                    onStartFollowing: () => ref
                        .read(readerProvider(widget.scoreId).notifier)
                        .startFollowing(),
                    onPauseFollowing: () => ref
                        .read(readerProvider(widget.scoreId).notifier)
                        .pauseFollowing(),
                    onResumeFollowing: () => ref
                        .read(readerProvider(widget.scoreId).notifier)
                        .resumeFollowing(),
                    onStopFollowing: () => ref
                        .read(readerProvider(widget.scoreId).notifier)
                        .stopFollowing(),
                    onRecalibrate: () =>
                        _showRecalibrateDialog(readerState.position.measure),
                    onPageChanged: (page) {
                      _pdfController.jumpToPage(page);
                      ref
                          .read(readerProvider(widget.scoreId).notifier)
                          .navigateToPage(page);
                    },
                  ),
                ],
              ),
            ),

            // ── Error snackbar overlay ────────────────────────────────────────────
            if (readerState.followingState == FollowingState.error &&
                readerState.errorMessage != null)
              Positioned(
                bottom: 80,
                left: 16,
                right: 16,
                child: Material(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.red.shade900,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            readerState.errorMessage!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────────

  void _toggleUI() {
    setState(() => _uiVisible = !_uiVisible);
    if (_uiVisible) {
      _fadeController.forward();
    } else {
      _fadeController.reverse();
    }
  }

  Color _confidenceColor(double confidence) {
    if (confidence > 0.7) return Colors.greenAccent;
    if (confidence > 0.4) return Colors.amber;
    return Colors.red;
  }

  Future<void> _showRecalibrateDialog(int currentMeasure) async {
    int? measure = await showDialog<int>(
      context: context,
      builder: (ctx) => _RecalibrateDialog(initialMeasure: currentMeasure),
    );
    if (measure != null && mounted) {
      ref
          .read(readerProvider(widget.scoreId).notifier)
          .recalibrate(measure);
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.scoreId, required this.onBack});
  final String scoreId;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scoreAsync = ref.watch(scoreDetailProvider(scoreId));
    final title = scoreAsync.valueOrNull?.title ?? '';
    final showStats = ref.watch(
      readerProvider(scoreId).select((s) => s.showStats),
    );

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: 4,
        right: 16,
        bottom: 16,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Performance stats',
            icon: Icon(
              showStats ? Icons.insights : Icons.insights_outlined,
              color: showStats ? const Color(0xFF7986CB) : Colors.white,
            ),
            onPressed: () =>
                ref.read(readerProvider(scoreId).notifier).toggleStats(),
          ),
        ],
      ),
    );
  }
}

class _RecalibrateDialog extends StatefulWidget {
  const _RecalibrateDialog({required this.initialMeasure});
  final int initialMeasure;

  @override
  State<_RecalibrateDialog> createState() => _RecalibrateDialogState();
}

class _RecalibrateDialogState extends State<_RecalibrateDialog> {
  late int _measure;

  @override
  void initState() {
    super.initState();
    _measure = widget.initialMeasure;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set position'),
      content: Row(
        children: [
          const Text('Measure:'),
          const SizedBox(width: 16),
          Expanded(
            child: TextFormField(
              initialValue: _measure.toString(),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              onChanged: (v) => _measure = int.tryParse(v) ?? _measure,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _measure),
          child: const Text('Go'),
        ),
      ],
    );
  }
}
