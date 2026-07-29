// lib/offline/reference_bundle.dart
// A score's precomputed following data, downloaded from the backend once and
// stored on-device so the follower runs with no server. JSON manifest with
// base64-packed binary arrays (little-endian).

import 'dart:convert';
import 'dart:typed_data';

class ReferenceBundle {
  final String scoreId;
  final String title;
  final String composer;
  final double frameRate;
  final int totalFrames;
  final int totalPages;
  final double? baseBpm;
  final List<List<int>> pageMap; // [page, firstFrame, lastFrame]
  final List<Float32List> chroma; // totalFrames x 12
  final Int32List measures; // per-frame measure number

  ReferenceBundle({
    required this.scoreId,
    required this.title,
    required this.composer,
    required this.frameRate,
    required this.totalFrames,
    required this.totalPages,
    required this.baseBpm,
    required this.pageMap,
    required this.chroma,
    required this.measures,
  });

  factory ReferenceBundle.fromJson(Map<String, dynamic> j) {
    final total = (j['total_frames'] as num).toInt();
    final chromaBytes = base64Decode(j['chroma_b64'] as String);
    final flat = Float32List(chromaBytes.length ~/ 4);
    flat.buffer.asUint8List().setAll(0, chromaBytes);
    final chroma = <Float32List>[];
    for (int r = 0; r < total; r++) {
      chroma.add(Float32List.sublistView(flat, r * 12, r * 12 + 12));
    }
    final measBytes = base64Decode(j['measures_b64'] as String);
    final meas16 = Int16List(measBytes.length ~/ 2);
    meas16.buffer.asUint8List().setAll(0, measBytes);
    final measures = Int32List.fromList(meas16);

    return ReferenceBundle(
      scoreId: j['score_id'] as String,
      title: (j['title'] as String?) ?? 'Untitled',
      composer: (j['composer'] as String?) ?? '',
      frameRate: (j['frame_rate'] as num).toDouble(),
      totalFrames: total,
      totalPages: (j['total_pages'] as num).toInt(),
      baseBpm: (j['base_bpm'] as num?)?.toDouble(),
      pageMap: (j['page_map'] as List)
          .map((e) => (e as List).map((x) => (x as num).toInt()).toList())
          .toList(),
      chroma: chroma,
      measures: measures,
    );
  }
}
