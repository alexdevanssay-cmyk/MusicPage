// End-to-end on-device test: real reference bundle (from backend) + real
// recording -> OfflineFollower. Run from frontend/: dart run tool/validate_e2e.dart
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import '../lib/offline/reference_bundle.dart';
import '../lib/offline/offline_follower.dart';

Float32List readF32(String p) {
  final u = File(p).readAsBytesSync();
  final f = Float32List(u.length ~/ 4);
  f.buffer.asUint8List().setAll(0, u);
  return f;
}

void main() {
  final dir = r'C:\Users\Alexis\AppData\Local\Temp\claude\dartval';
  final fb = readF32('$dir\\filterbank_f32.bin');
  final pcm = readF32('$dir\\mp3_full_f32.bin');
  final bundle = ReferenceBundle.fromJson(
      jsonDecode(File('$dir\\bundle_real.json').readAsStringSync()) as Map<String, dynamic>);
  print('bundle: ${bundle.totalFrames} frames, ${bundle.totalPages} pages, bpm=${bundle.baseBpm}');

  final follower = OfflineFollower(bundle: bundle, filterbank: fb);
  final positions = <int>[];
  final pageTurns = <String>[];
  Map<String, dynamic>? lastStats;
  const chunk = 2048;
  for (int i = 0; i < pcm.length; i += chunk) {
    final end = (i + chunk < pcm.length) ? i + chunk : pcm.length;
    for (final e in follower.processPcm(Float32List.sublistView(pcm, i, end))) {
      if (e['type'] == 'position_update') {
        positions.add(((e['global_progress'] as double) * bundle.totalFrames).round());
        lastStats = e['stats'] as Map<String, dynamic>;
      } else if (e['type'] == 'page_change') {
        pageTurns.add('${e['from_page']}->${e['to_page']}');
      }
    }
  }
  final n = positions.length;
  String at(double f) => '${(100 * positions[(n * f).toInt() - 1] / bundle.totalFrames).round()}';
  print('trajectory @25/50/75/100%: ${at(.25)}/${at(.5)}/${at(.75)}/${at(1.0)}%');
  print('page turns: $pageTurns');
  print('final live stats: $lastStats');
  print('session summary: ${follower.sessionSummary()}');
}
