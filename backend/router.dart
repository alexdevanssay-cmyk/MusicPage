// lib/router.dart
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'screens/splash_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';

part 'router.g.dart';

// keepAlive: true — the GoRouter must live for the whole app lifetime.
@Riverpod(keepAlive: true)
GoRouter router(RouterRef ref) {
  return GoRouter(
    // App always starts on the splash screen which waits for the backend.
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (_, __) => const LibraryScreen(),
      ),
      GoRoute(
        path: '/reader/:scoreId',
        builder: (_, state) => ReaderScreen(
          scoreId: state.pathParameters['scoreId']!,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
      ),
    ],
  );
}
