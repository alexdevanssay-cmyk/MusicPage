// lib/services/offline_store.dart
// Downloads a score's reference bundle + PDF for offline use and stores them in
// the app documents directory, so the on-device follower works with no server.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../offline/reference_bundle.dart';

class OfflineScoreMeta {
  final String id;
  final String title;
  final String composer;
  final int totalPages;
  const OfflineScoreMeta(this.id, this.title, this.composer, this.totalPages);
}

class OfflineStore {
  Directory? _dir;

  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'offline_scores'));
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  String _bundleName(String id) => '$id.bundle.json';
  String _pdfName(String id) => '$id.pdf';

  Future<bool> isDownloaded(String id) async {
    final d = await _root();
    return File(p.join(d.path, _bundleName(id))).exists();
  }

  Future<File> pdfFile(String id) async =>
      File(p.join((await _root()).path, _pdfName(id)));

  /// Download the reference bundle + PDF for [scoreId] from [baseUrl].
  Future<void> download(String scoreId, String baseUrl) async {
    final d = await _root();
    final dio = Dio(BaseOptions(baseUrl: baseUrl, receiveTimeout: const Duration(seconds: 60)));
    // reference bundle (JSON)
    final resp = await dio.get<String>(
      '/api/v1/scores/$scoreId/reference_bundle',
      options: Options(responseType: ResponseType.plain),
    );
    await File(p.join(d.path, _bundleName(scoreId))).writeAsString(resp.data!);
    // PDF (for offline display)
    await dio.download('/api/v1/scores/$scoreId/pdf', p.join(d.path, _pdfName(scoreId)));
  }

  Future<void> delete(String id) async {
    final d = await _root();
    for (final n in [_bundleName(id), _pdfName(id)]) {
      final f = File(p.join(d.path, n));
      if (await f.exists()) await f.delete();
    }
  }

  /// Locally-available scores (parsed from stored bundle manifests).
  Future<List<OfflineScoreMeta>> listLocal() async {
    final d = await _root();
    final out = <OfflineScoreMeta>[];
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.bundle.json')) {
        try {
          final j = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
          out.add(OfflineScoreMeta(
            j['score_id'] as String,
            (j['title'] as String?) ?? 'Untitled',
            (j['composer'] as String?) ?? '',
            (j['total_pages'] as num?)?.toInt() ?? 1,
          ));
        } catch (_) {/* skip corrupt */}
      }
    }
    return out;
  }

  Future<ReferenceBundle> loadBundle(String id) async {
    final d = await _root();
    final txt = await File(p.join(d.path, _bundleName(id))).readAsString();
    return ReferenceBundle.fromJson(jsonDecode(txt) as Map<String, dynamic>);
  }

  /// The chroma filterbank (bundled asset, shared by every score).
  static Future<Float32List> loadFilterbank() async {
    final bd = await rootBundle.load('assets/filterbank_f32.bin');
    return bd.buffer.asFloat32List(bd.offsetInBytes, bd.lengthInBytes ~/ 4);
  }
}
