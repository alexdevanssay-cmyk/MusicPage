// lib/providers/backend_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backend_launcher_service.dart';

/// Global singleton that owns the backend subprocess lifetime.
/// ChangeNotifierProvider causes the widget tree to rebuild whenever
/// BackendLauncherService calls notifyListeners().
final backendLauncherProvider =
    ChangeNotifierProvider<BackendLauncherService>(
  (ref) {
    final svc = BackendLauncherService();
    // Auto-stop when the app exits
    ref.onDispose(svc.stop);
    return svc;
  },
);
