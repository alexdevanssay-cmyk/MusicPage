// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<InputDevice> _devices = [];
  final _hostController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDevices();
    final s = ref.read(settingsProvider);
    _hostController.text = s.backendHost;
  }

  @override
  void dispose() {
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    try {
      final rec = AudioRecorder();
      final devs = await rec.listInputDevices();
      rec.dispose();
      if (mounted) setState(() => _devices = devs);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ────────────────────────────────────────────────────
          _SectionHeader('Appearance'),
          SwitchListTile.adaptive(
            title: const Text('Dark mode'),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: s.darkMode,
            onChanged: (v) => notifier.update((s) => s.copyWith(darkMode: v)),
          ),

          const SizedBox(height: 16),
          // ── Audio ─────────────────────────────────────────────────────────
          _SectionHeader('Audio'),
          ListTile(
            leading: const Icon(Icons.mic_outlined),
            title: const Text('Microphone sensitivity'),
            subtitle: Slider(
              value: s.micSensitivity,
              min: 0.1,
              max: 5.0,
              divisions: 49,
              label: s.micSensitivity.toStringAsFixed(1),
              onChanged: (v) =>
                  notifier.update((s) => s.copyWith(micSensitivity: v)),
            ),
            trailing: Text(
              s.micSensitivity.toStringAsFixed(1),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (_devices.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.device_hub_outlined),
              title: const Text('Input device'),
              trailing: DropdownButton<String>(
                value: s.audioDeviceId,
                hint: const Text('Default'),
                underline: const SizedBox.shrink(),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Default')),
                  ..._devices.map(
                    (d) => DropdownMenuItem(value: d.id, child: Text(d.label)),
                  ),
                ],
                onChanged: (id) =>
                    notifier.update((s) => s.copyWith(audioDeviceId: id)),
              ),
            ),

          const SizedBox(height: 16),
          // ── Page turning ──────────────────────────────────────────────────
          _SectionHeader('Page turning'),
          _ThresholdTile(
            icon: Icons.download_for_offline_outlined,
            label: 'Pre-load next page',
            description:
                'Start loading the next page when this % of the current page is played.',
            value: s.preloadThreshold,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(preloadThreshold: v)),
          ),
          _ThresholdTile(
            icon: Icons.turn_right_outlined,
            label: 'Turn page',
            description:
                'Actually flip to the next page at this % of the current page.',
            value: s.pageTurnThreshold,
            onChanged: (v) =>
                notifier.update((s) => s.copyWith(pageTurnThreshold: v)),
          ),

          const SizedBox(height: 16),
          // ── Connection ────────────────────────────────────────────────────
          _SectionHeader('Backend connection'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Host'),
            subtitle: TextFormField(
              controller: _hostController,
              decoration: const InputDecoration(
                hintText: 'localhost',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onFieldSubmitted: (v) =>
                  notifier.update((s) => s.copyWith(backendHost: v.trim())),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.tag_outlined),
            title: const Text('Port'),
            trailing: SizedBox(
              width: 90,
              child: TextFormField(
                initialValue: s.backendPort.toString(),
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onFieldSubmitted: (v) {
                  final port = int.tryParse(v);
                  if (port != null) {
                    notifier.update((s) => s.copyWith(backendPort: port));
                  }
                },
              ),
            ),
          ),

          const SizedBox(height: 32),
          // ── About ─────────────────────────────────────────────────────────
          _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('MusicPage'),
            subtitle: Text('v1.0.0 – Real-time score following'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4, top: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ThresholdTile extends StatelessWidget {
  const _ThresholdTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final String description;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description,
              style: const TextStyle(fontSize: 12), maxLines: 2),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: value,
                  min: 0.5,
                  max: 0.99,
                  divisions: 49,
                  onChanged: onChanged,
                ),
              ),
              Text('${(value * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}
