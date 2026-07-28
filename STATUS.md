# MusicPage — project status

Real-time score-following app (auto page turns from mic). Python/FastAPI backend
(`backend/`) + Flutter app (`frontend/`). See `BUILD.md` for build instructions.

## ✅ Working
- **Backend** repaired, **28 tests pass**. Real-time follower verified.
- **Follower tuned** against real recordings: harmonic reference, anti-lag
  stay-penalty, fixed confidence metric. Tracks a full real performance 0→99%
  and is robust to wrong-note / rhythm-error takes.
- **Performance stats** telemetry + a hidable live overlay (time, confidence,
  tempo/BPM, wrong-note count, tempo sparkline + whole-piece recap).
- **Windows all-in-one** build: `music_page.exe` auto-launches the bundled
  backend. **Android APK** (thin client): `dist/mobile/`.
- **Mobile connectivity**: desktop backend binds `0.0.0.0`; set the PC's LAN IP +
  port 8000 in the phone's Settings → Backend connection.

## 🔧 Open / next session
1. **Android mic** — a phone follow session connected & started but no audio
   frames reached the backend (stats didn't move). Backend now logs `AUDIO_IN`
   (chunk count + RMS). Retry a follow on the phone; if no `AUDIO_IN` lines →
   microphone permission/streaming issue in the Flutter `record` path.
2. **Real references** — importing a **PDF** yields only a one-note *stub*
   reference (no OMR engine bundled), so those scores can't actually be followed.
   Add **MIDI / MusicXML import** so scores get real note-level references (this
   is what makes phone-side following meaningful — the Mendelssohn/Chopin tests
   tracked well because they used MIDI).
3. **Offline on-device following (Android)** — port the chroma + DTW engine to
   Dart and package references for on-device storage, so the app works with the
   PC off / off the home Wi-Fi. Large effort; must be tested on a real device.

## Key facts
- Real OMR (PDF→notes) needs `oemer`+PyTorch (~2.5 GB), not installed → stub
  fallback. MIDI/MusicXML references are the practical path.
- BPM in the overlay is a real number only for MIDI/MusicXML-referenced scores.
