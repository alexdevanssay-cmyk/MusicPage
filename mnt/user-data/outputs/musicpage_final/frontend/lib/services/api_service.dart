// lib/services/api_service.dart
// ──────────────────────────────
// HTTP client wrapping all REST calls to the FastAPI backend.

import 'dart:io';
import 'package:dio/dio.dart';     // re-exports MediaType from http_parser

import '../models/score.dart';

class ApiService {
  ApiService({required this.baseUrl});

  final String baseUrl;

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 120), // OMR can take a while
    ),
  );

  // ── Scores ───────────────────────────────────────────────────────────────────

  Future<List<Score>> fetchScores() async {
    final resp = await _dio.get('/api/v1/scores/');
    final list = resp.data as List<dynamic>;
    return list.map((j) => Score.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Score> fetchScore(String scoreId) async {
    final resp = await _dio.get('/api/v1/scores/$scoreId');
    return Score.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Score> importScore({
    required File file,
    String? title,
    String? composer,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path,
        filename: file.path.split('/').last,
        contentType: MediaType('application', 'pdf'),
      ),
      if (title != null) 'title': title,
      if (composer != null) 'composer': composer,
    });

    final resp = await _dio.post(
      '/api/v1/scores/',
      data: formData,
      onSendProgress: (sent, total) {
        // Could expose progress stream here
      },
    );
    return Score.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> deleteScore(String scoreId) async {
    await _dio.delete('/api/v1/scores/$scoreId');
  }

  Future<bool> toggleFavorite(String scoreId) async {
    final resp = await _dio.post('/api/v1/scores/$scoreId/favorite');
    return (resp.data as Map<String, dynamic>)['is_favorite'] as bool;
  }

  // ── PDF streaming URL ─────────────────────────────────────────────────────────
  // The PDF viewer loads the file directly from disk path returned by the API,
  // OR from a URL if served statically. For local-only use, we serve PDFs via:
  //   GET /api/v1/scores/{id}/pdf
  String pdfUrl(String scoreId) => '$baseUrl/api/v1/scores/$scoreId/pdf';
}
