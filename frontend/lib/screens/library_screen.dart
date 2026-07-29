// lib/screens/library_screen.dart
// ─────────────────────────────────
// Main screen: list of imported scores, search, import button.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/score.dart';
import '../providers/score_provider.dart';
import '../providers/settings_provider.dart';
import '../services/offline_store.dart';
import '../widgets/score_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  bool _isImporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoresAsync = ref.watch(scoresProvider);
    final downloaded = ref.watch(downloadedIdsProvider).valueOrNull ?? const <String>{};
    // When the backend is unreachable, fall back to downloaded scores so the
    // library still works with the PC off / off the home Wi-Fi.
    final offlineMode = scoresAsync.hasError;
    final scores = offlineMode
        ? (ref.watch(offlineScoresProvider).valueOrNull ?? const <Score>[])
        : ref.watch(filteredScoresProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 140,
            floating: false,
            pinned: true,
            backgroundColor: cs.surface,
            surfaceTintColor: Colors.transparent,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'My Scores',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.primaryContainer.withOpacity(0.4),
                      cs.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Search bar ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Search by title or composer…',
                leading: Icon(Icons.search, color: cs.onSurfaceVariant),
                trailing: _searchController.text.isNotEmpty
                    ? [
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            ref.read(searchQueryProvider.notifier).state = '';
                          },
                        ),
                      ]
                    : null,
                onChanged: (q) =>
                    ref.read(searchQueryProvider.notifier).state = q,
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  cs.surfaceContainerHighest.withOpacity(0.6),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),

          // ── Loading / Error / Empty states ───────────────────────────────────
          if (scoresAsync.isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (offlineMode && scores.isEmpty)
            SliverFillRemaining(
              child: _ErrorView(
                message: scoresAsync.error.toString(),
                onRetry: () => ref.invalidate(scoresProvider),
              ),
            )
          else if (scores.isEmpty)
            SliverFillRemaining(child: _EmptyLibrary(onImport: _pickPdf))

          // ── Score grid ───────────────────────────────────────────────────────
          else ...[
            if (offlineMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.offline_bolt, size: 16, color: Colors.orange.shade700),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Offline — showing downloaded scores',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(scoresProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final score = scores[i];
                    return ScoreCard(
                      score: score,
                      isDownloaded: downloaded.contains(score.id),
                      onDownload: offlineMode ? null : () => _download(score),
                      onTap: () => context.push('/reader/${score.id}'),
                      onFavorite: () =>
                          ref.read(scoresProvider.notifier).toggleFavorite(score.id),
                      onDelete: () => _confirmDelete(score),
                    )
                        .animate(delay: Duration(milliseconds: i * 40))
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.15, duration: 300.ms);
                  },
                  childCount: scores.length,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisExtent: 200,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
              ),
            ),
          ],
        ],
      ),

      // ── FAB: import ──────────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? null : _pickPdf,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_isImporting ? 'Importing…' : 'Import Score'),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────────

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;

    setState(() => _isImporting = true);
    try {
      final file = File(result.files.single.path!);
      final score = await ref
          .read(scoresProvider.notifier)
          .importPdf(file, title: result.files.single.name.replaceAll('.pdf', ''));

      if (score != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported "${score.title}" – analysis running…'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => context.push('/reader/${score.id}'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _download(Score score) async {
    final baseUrl = ref.read(settingsProvider).baseUrl;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text('Downloading "${score.title}"…')));
    try {
      await OfflineStore().download(score.id, baseUrl);
      ref.invalidate(downloadedIdsProvider);
      ref.invalidate(offlineScoresProvider);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('"${score.title}" available offline'),
          backgroundColor: Colors.green.shade700,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _confirmDelete(Score score) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete score?'),
        content: Text('Remove "${score.title}" from your library?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(scoresProvider.notifier).deleteScore(score.id);
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────────

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.music_note_outlined, size: 72, color: cs.outlineVariant),
          const SizedBox(height: 20),
          Text(
            'Your library is empty',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Import a PDF score to get started.',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file),
            label: const Text('Import Score'),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, size: 56, color: Colors.orange),
          const SizedBox(height: 16),
          Text('Cannot reach the backend', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
