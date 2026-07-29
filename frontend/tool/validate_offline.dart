// Validates the on-device engine (lib/offline/*) against vectors exported from
// the Python engine. Run from frontend/:  dart run tool/validate_offline.dart
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../lib/offline/chroma_extractor.dart';
import '../lib/offline/online_dtw.dart';

Float32List readF32(String p) {
  final u = File(p).readAsBytesSync();
  final f = Float32List(u.length ~/ 4);
  f.buffer.asUint8List().setAll(0, u);
  return f;
}

double cosSim(Float32List a, Float32List b) {
  double d = 0, na = 0, nb = 0;
  for (int i = 0; i < a.length; i++) { d += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]; }
  if (na < 1e-12 || nb < 1e-12) return (na < 1e-12 && nb < 1e-12) ? 1.0 : 0.0;
  return d / (sqrt(na) * sqrt(nb));
}

void main() {
  final dir = r'C:\Users\Alexis\AppData\Local\Temp\claude\dartval';
  final fb = readF32('$dir\\filterbank_f32.bin');
  final pcm = readF32('$dir\\pcm_30s_f32.bin');
  final expFlat = readF32('$dir\\expected_chroma_f32.bin');
  final refFlat = readF32('$dir\\ref_chroma_f32.bin');
  final meta = jsonDecode(File('$dir\\meta.json').readAsStringSync());
  final pyTraj = (meta['traj'] as List).map((e) => e as int).toList();

  // stream the PCM through the real streaming extractor in 2048-sample chunks
  final ex = ChromaExtractor(fb);
  final frames = <Float32List>[];
  for (int i = 0; i < pcm.length; i += 2048) {
    final end = min(i + 2048, pcm.length);
    frames.addAll(ex.push(Float32List.sublistView(pcm, i, end)));
  }

  final expN = expFlat.length ~/ 12;
  final n = min(frames.length, expN);
  double meanCos = 0, minCos = 2;
  for (int i = 0; i < n; i++) {
    final e = Float32List.sublistView(expFlat, i * 12, i * 12 + 12);
    final cs = cosSim(frames[i], e);
    meanCos += cs; if (cs < minCos) minCos = cs;
  }
  print('CHROMA  dart=${frames.length} py=$expN  cos mean=${(meanCos / n).toStringAsFixed(5)} min=${minCos.toStringAsFixed(5)}');

  // reference + follower
  final ref = <Float32List>[];
  for (int r = 0; r < refFlat.length ~/ 12; r++) ref.add(Float32List.sublistView(refFlat, r * 12, r * 12 + 12));
  final dtw = OnlineDtw(ref, window: 150, stayPenalty: 0.20);
  int maxDiff = 0, off = 0;
  final m = min(frames.length, pyTraj.length);
  for (int i = 0; i < m; i++) {
    final pos = dtw.step(frames[i]).position;
    final df = (pos - pyTraj[i]).abs();
    if (df > maxDiff) maxDiff = df;
    if (df > 1) off++;
  }
  print('FOLLOWER  frames=$m  maxPosDiff=$maxDiff  framesOff=$off');
  final ok = minCos > 0.999 && maxDiff <= 1;
  print(ok ? 'PASS: on-device engine matches Python' : 'CHECK: divergence');
  exit(ok ? 0 : 1);
}
