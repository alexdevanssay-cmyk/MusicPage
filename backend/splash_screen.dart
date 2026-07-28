// lib/screens/splash_screen.dart
// ────────────────────────────────
// Shown at cold start while the Python backend is launching.
// Transitions automatically to LibraryScreen once /health responds.

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/backend_provider.dart';
import '../services/backend_launcher_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Start the backend — provider already triggers this; we just listen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backendLauncherProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final launcher = ref.watch(backendLauncherProvider);

    // Navigate when ready
    if (launcher.status == BackendStatus.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
    }

    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Logo ────────────────────────────────────────────────────────
            _MusicPageLogo()
                .animate()
                .fadeIn(duration: 600.ms)
                .scaleXY(begin: 0.8, curve: Curves.easeOutBack),

            const SizedBox(height: 40),

            // ── App name ─────────────────────────────────────────────────────
            Text(
              'MusicPage',
              style: GoogleFonts.playfairDisplay(
                fontSize: 36,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ).animate(delay: 200.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 8),

            Text(
              'Real-time score following',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.5),
                letterSpacing: 1.2,
              ),
            ).animate(delay: 300.ms).fadeIn(duration: 400.ms),

            const SizedBox(height: 60),

            // ── Status ────────────────────────────────────────────────────────
            _StatusWidget(launcher: launcher),
          ],
        ),
      ),
    );
  }
}

// ── Status widget ─────────────────────────────────────────────────────────────

class _StatusWidget extends StatelessWidget {
  const _StatusWidget({required this.launcher});
  final BackendLauncherService launcher;

  @override
  Widget build(BuildContext context) {
    switch (launcher.status) {
      case BackendStatus.idle:
      case BackendStatus.starting:
        return Column(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF7986CB),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Starting engine…',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms);

      case BackendStatus.ready:
        return Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 32)
            .animate()
            .scale(duration: 300.ms, curve: Curves.elasticOut);

      case BackendStatus.error:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
              const SizedBox(height: 12),
              Text(
                launcher.error ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                ),
                onPressed: () => launcher.start(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
    }
  }
}

// ── Logo painter ──────────────────────────────────────────────────────────────

class _MusicPageLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          colors: [Color(0xFF3949AB), Color(0xFF1A237E)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3949AB).withOpacity(0.5),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Icon(Icons.music_note, color: Colors.white, size: 52),
    );
  }
}
