// lib/offline/online_dtw.dart
// On-device online DTW follower. Verbatim port of the tuned Python OnlineDTW
// (stay-penalty anti-lag, forward-only capped readout, local-match confidence),
// validated bit-for-bit against Python on real recordings. Pure Dart.

import 'dart:math';
import 'dart:typed_data';

double cosineDist(Float32List a, Float32List b) {
  double d = 0, na = 0, nb = 0;
  for (int i = 0; i < a.length; i++) {
    d += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na < 1e-14 || nb < 1e-14) return 1.0;
  return 1.0 - d / (sqrt(na) * sqrt(nb));
}

class DtwResult {
  final int position;    // smoothed reference frame
  final double confidence;
  const DtwResult(this.position, this.confidence);
}

class OnlineDtw {
  final List<Float32List> ref; // N x 12
  final int n; // frame count
  final int w;
  final int smoothK;
  final int maxAdv;
  final double stayPenalty;

  late Float64List _prev;
  int t = 0;
  int _pos = 0;
  final List<int> _posHist = [];
  final List<double> _confHist = [];

  OnlineDtw(
    this.ref, {
    int window = 150,
    this.smoothK = 7,
    double maxSpeedRatio = 3.0,
    this.stayPenalty = 0.20,
  })  : n = ref.length,
        w = window,
        maxAdv = max(1, maxSpeedRatio.round()) {
    _prev = Float64List(n)..fillRange(0, n, double.infinity);
    if (n > 0) _prev[0] = 0.0;
  }

  DtwResult step(Float32List obs) {
    t++;
    final cur = Float64List(n)..fillRange(0, n, double.infinity);
    final nLo = max(0, _pos - w), nHi = min(n - 1, _pos + w);
    for (int i = nLo; i <= nHi; i++) {
      final d = cosineDist(ref[i], obs);
      double bp = _prev[i] + stayPenalty; // horizontal (wait) — penalised
      if (i > 0) {
        if (_prev[i - 1] < bp) bp = _prev[i - 1]; // diagonal
        if (cur[i - 1] < bp) bp = cur[i - 1]; // vertical
      }
      cur[i] = d + (bp.isInfinite ? 0.0 : bp);
    }
    _prev = cur;

    // forward-only capped readout; most-advanced near-optimal cell
    final fwdLo = _pos, fwdHi = min(_pos + maxAdv, n - 1);
    double minCost = double.infinity;
    for (int k = fwdLo; k <= fwdHi; k++) {
      if (cur[k] < minCost) minCost = cur[k];
    }
    final tol = 1e-4 * (1.0 + minCost.abs());
    int best = fwdLo;
    for (int k = fwdLo; k <= fwdHi; k++) {
      if (cur[k] <= minCost + tol) best = k;
    }
    _pos = best;

    _posHist.add(best);
    if (_posHist.length > smoothK) _posHist.removeAt(0);
    int smoothed = _medianInt(_posHist);
    if (smoothed > n - 1) smoothed = n - 1;

    // confidence from local match quality (median-smoothed)
    final localDist = cosineDist(ref[best], obs);
    _confHist.add(max(0.0, 1.0 - localDist));
    if (_confHist.length > smoothK) _confHist.removeAt(0);
    final conf = _medianDouble(_confHist);

    return DtwResult(smoothed, conf);
  }

  void seek(int frame) {
    _pos = frame.clamp(0, n - 1);
    _posHist.clear();
    _confHist.clear();
    _prev = Float64List(n)..fillRange(0, n, double.infinity);
    _prev[_pos] = 0.0;
  }

  static int _medianInt(List<int> v) {
    final s = List<int>.from(v)..sort();
    final m = s.length;
    return m.isOdd ? s[m ~/ 2] : ((s[m ~/ 2 - 1] + s[m ~/ 2]) / 2).toInt();
  }

  static double _medianDouble(List<double> v) {
    final s = List<double>.from(v)..sort();
    final m = s.length;
    return m.isOdd ? s[m ~/ 2] : (s[m ~/ 2 - 1] + s[m ~/ 2]) / 2.0;
  }
}
