// lib/router.dart
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';

part 'router.g.dart';

// keepAlive: true — le GoRouter doit vivre toute la durée de l'app.
// @riverpod seul (keepAlive: false) provoquerait une réinitialisation de la
// navigation chaque fois que MaterialApp.router cesserait de l'observer.
@Riverpod(keepAlive: true)
GoRouter router(RouterRef ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
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
