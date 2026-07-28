// lib/providers/backend_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backend_launcher_service.dart';

/// Global singleton that owns the backend subprocess lifetime.
/// Rebuilds any watching widget whenever BackendLauncherService notifies.
final backendLauncherProvider =
    ChangeNotifierProvider<BackendLauncherService>((ref) {
  final svc = BackendLauncherService();
  ref.onDispose(svc.stop); // stop the subprocess when the app exits
  return svc;
});
