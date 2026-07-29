// lib/offline/chroma_extractor.dart
// On-device streaming chroma extractor. Mirrors the backend's deterministic
// chroma (explicit STFT -> power -> chroma filterbank -> L2 norm, fixed tuning),
// validated bit-for-bit against the Python engine. Pure Dart.

import 'dart:math';
import 'dart:typed_data';

import 'fft.dart';

class ChromaExtractor {
  static const int nFft = 2048;
  static const int hop = 512;
  static const int nChroma = 12;
  static const int nBins = nFft ~/ 2 + 1; // 1025
  static final double _gate = pow(10, -60 / 20).toDouble(); // -60 dBFS

  /// Chroma filterbank, row-major (nChroma * nBins), same matrix as the backend
  /// (librosa.filters.chroma at tuning 0). Loaded once from a bundled asset.
  final Float32List filterbank;

  final FFT _fft = FFT(nFft);
  final Float64List _hann = Float64List(nFft);
  final Float64List _re = Float64List(nFft);
  final Float64List _im = Float64List(nFft);
  Float32List _carry = Float32List(0);

  ChromaExtractor(this.filterbank) {
    assert(filterbank.length == nChroma * nBins);
    for (int i = 0; i < nFft; i++) {
      _hann[i] = 0.5 - 0.5 * cos(2 * pi * i / nFft);
    }
  }

  void reset() => _carry = Float32List(0);

  /// Push float32 PCM (22050 Hz mono) and get the chroma frames produced.
  /// Framing runs on one global grid (carry the unconsumed remainder) so
  /// streaming yields the same frames as processing the signal whole.
  List<Float32List> push(Float32List samples) {
    final combined = Float32List(_carry.length + samples.length);
    combined.setAll(0, _carry);
    combined.setAll(_carry.length, samples);

    final total = combined.length;
    final nFrames = total < nFft ? 0 : 1 + ((total - nFft) ~/ hop);
    final out = <Float32List>[];
    for (int i = 0; i < nFrames; i++) {
      out.add(_frame(combined, i * hop));
    }
    final consumed = nFrames * hop;
    _carry = Float32List.sublistView(combined, consumed);
    return out;
  }

  Float32List _frame(Float32List y, int off) {
    double ss = 0;
    for (int k = 0; k < nFft; k++) {
      final s = y[off + k];
      ss += s * s;
    }
    final c = Float32List(nChroma);
    if (sqrt(ss / nFft) < _gate) return c; // noise gate -> zero vector

    for (int k = 0; k < nFft; k++) {
      _re[k] = y[off + k] * _hann[k];
      _im[k] = 0.0;
    }
    _fft.transform(_re, _im);

    for (int p = 0; p < nChroma; p++) {
      double acc = 0;
      final base = p * nBins;
      for (int b = 0; b < nBins; b++) {
        acc += filterbank[base + b] * (_re[b] * _re[b] + _im[b] * _im[b]);
      }
      c[p] = acc;
    }
    double nrm = 0;
    for (int p = 0; p < nChroma; p++) nrm += c[p] * c[p];
    nrm = sqrt(nrm);
    if (nrm > 1e-7) {
      for (int p = 0; p < nChroma; p++) c[p] /= nrm;
    }
    return c;
  }
}
