// lib/providers/settings_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final double micSensitivity;
  final double preloadThreshold;
  final double pageTurnThreshold;
  final bool darkMode;
  final String? audioDeviceId;
  final String backendHost;
  final int backendPort;

  const AppSettings({
    this.micSensitivity = 1.0,
    this.preloadThreshold = 0.80,
    this.pageTurnThreshold = 0.95,
    this.darkMode = false,
    this.audioDeviceId,
    this.backendHost = 'localhost',
    this.backendPort = 8000,
  });

  String get baseUrl => 'http://$backendHost:$backendPort';
  String get wsUrl   => 'ws://$backendHost:$backendPort/ws/follow';

  AppSettings copyWith({
    double? micSensitivity,
    double? preloadThreshold,
    double? pageTurnThreshold,
    bool? darkMode,
    String? audioDeviceId,
    String? backendHost,
    int? backendPort,
  }) {
    return AppSettings(
      micSensitivity: micSensitivity ?? this.micSensitivity,
      preloadThreshold: preloadThreshold ?? this.preloadThreshold,
      pageTurnThreshold: pageTurnThreshold ?? this.pageTurnThreshold,
      darkMode: darkMode ?? this.darkMode,
      audioDeviceId: audioDeviceId ?? this.audioDeviceId,
      backendHost: backendHost ?? this.backendHost,
      backendPort: backendPort ?? this.backendPort,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    _load();
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      micSensitivity: prefs.getDouble('mic_sensitivity') ?? 1.0,
      preloadThreshold: prefs.getDouble('preload_threshold') ?? 0.80,
      pageTurnThreshold: prefs.getDouble('page_turn_threshold') ?? 0.95,
      darkMode: prefs.getBool('dark_mode') ?? false,
      audioDeviceId: prefs.getString('audio_device_id'),
      backendHost: prefs.getString('backend_host') ?? 'localhost',
      backendPort: prefs.getInt('backend_port') ?? 8000,
    );
  }

  Future<void> save(AppSettings updated) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('mic_sensitivity', updated.micSensitivity);
    await prefs.setDouble('preload_threshold', updated.preloadThreshold);
    await prefs.setDouble('page_turn_threshold', updated.pageTurnThreshold);
    await prefs.setBool('dark_mode', updated.darkMode);
    if (updated.audioDeviceId != null) {
      await prefs.setString('audio_device_id', updated.audioDeviceId!);
    }
    await prefs.setString('backend_host', updated.backendHost);
    await prefs.setInt('backend_port', updated.backendPort);
    state = updated;
  }

  void update(AppSettings Function(AppSettings) modifier) {
    save(modifier(state));
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
