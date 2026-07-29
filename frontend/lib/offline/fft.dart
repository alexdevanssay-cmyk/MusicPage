// lib/offline/fft.dart
// Minimal iterative radix-2 FFT (n must be a power of two). Pure Dart, no deps —
// used by the on-device chroma extractor so score-following runs offline.

import 'dart:math';
import 'dart:typed_data';

class FFT {
  final int n;
  late final Float64List _cos, _sin;
  late final Int32List _rev;

  FFT(this.n) {
    assert(n > 0 && (n & (n - 1)) == 0, 'n must be a power of two');
    _cos = Float64List(n >> 1);
    _sin = Float64List(n >> 1);
    for (int i = 0; i < (n >> 1); i++) {
      final a = -2 * pi * i / n;
      _cos[i] = cos(a);
      _sin[i] = sin(a);
    }
    int bits = 0;
    while ((1 << bits) < n) bits++;
    _rev = Int32List(n);
    for (int i = 0; i < n; i++) {
      int x = i, r = 0;
      for (int b = 0; b < bits; b++) {
        r = (r << 1) | (x & 1);
        x >>= 1;
      }
      _rev[i] = r;
    }
  }

  /// In-place complex FFT of (re, im), each length n.
  void transform(Float64List re, Float64List im) {
    for (int i = 0; i < n; i++) {
      final j = _rev[i];
      if (j > i) {
        var t = re[i]; re[i] = re[j]; re[j] = t;
        t = im[i]; im[i] = im[j]; im[j] = t;
      }
    }
    for (int len = 2; len <= n; len <<= 1) {
      final half = len >> 1, step = n ~/ len;
      for (int i = 0; i < n; i += len) {
        int k = 0;
        for (int j = i; j < i + half; j++) {
          final wr = _cos[k], wi = _sin[k];
          final tr = re[j + half] * wr - im[j + half] * wi;
          final ti = re[j + half] * wi + im[j + half] * wr;
          re[j + half] = re[j] - tr;
          im[j + half] = im[j] - ti;
          re[j] += tr;
          im[j] += ti;
          k += step;
        }
      }
    }
  }
}
