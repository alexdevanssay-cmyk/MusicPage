// lib/screens/splash_screen.dart
// ────────────────────────────────
// Shown at cold start.  On desktop it launches the bundled Python backend and
// waits for /health; on mobile the launcher reports ready immediately and we
// go straight to the library (the reader connects to the remote backend).

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
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(backendLauncherProvider).start();
    });
  }

  void _goHomeOnce() {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/');
    });
  }

  @override
  Widget build(BuildContext context) {
    final launcher = ref.watch(backendLauncherProvider);

    if (launcher.status == BackendStatus.ready) {
      _goHomeOnce();
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MusicPageLogo()
                .animate()
                .fadeIn(duration: 600.ms)
                .scaleXY(begin: 0.8, curve: Curves.easeOutBack),
            const SizedBox(height: 40),
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
            _StatusWidget(launcher: launcher),
          ],
        ),
      ),
    );
  }
}

class _StatusWidget extends StatelessWidget {
  const _StatusWidget({required this.launcher});
  final BackendLauncherService launcher;

  @override
  Widget build(BuildContext context) {
    switch (launcher.status) {
      case BackendStatus.idle:
      case BackendStatus.starting:
      case BackendStatus.ready:
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
              Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white30),
                    ),
                    onPressed: () => launcher.start(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Continue anyway'),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }
}

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
