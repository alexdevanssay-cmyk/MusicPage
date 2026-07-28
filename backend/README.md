# MusicPage 🎵

**Real-time score following with automatic page turns.**

Import a PDF score, press **Follow**, and MusicPage listens through your microphone, tracks where you are in the music, and turns the pages automatically — on any instrument, at any tempo.

---

## Architecture overview

```
Flutter app  ←──── WebSocket (binary PCM + JSON) ────→  Python backend
  PDF viewer                                              Online DTW engine
  Audio capture                                          OMR pipeline (oemer)
  Riverpod state                                         FastAPI + SQLite
```

The backend runs locally (no cloud, no subscription). The Flutter app connects to it via `localhost:8000`.

---

## Requirements

| Tool | Version | Install |
|------|---------|---------|
| Python | ≥ 3.11 | [python.org](https://www.python.org) |
| Flutter | ≥ 3.22 | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| Dart | ≥ 3.3 | (bundled with Flutter) |

Optional for high-accuracy OMR on orchestral scores:

| Tool | Notes |
|------|-------|
| Java 11+ | Only for Audiveris backend (`OMR_BACKEND=audiveris` in `.env`) |

---

## Quickstart

### 1 — Backend

```bash
cd backend
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
python run.py
# → http://localhost:8000/docs  (Swagger UI)
# → ws://localhost:8000/ws/follow
```

**First run note:** `oemer` downloads a ~400 MB model on first use. Subsequent runs are fast.

### 2 — Flutter app

```bash
cd frontend

# Generate router.g.dart (already committed, but re-run after any change to router.dart)
dart run build_runner build --delete-conflicting-outputs

flutter pub get
flutter run                        # auto-detects connected device/simulator
# or target a specific platform:
flutter run -d macos
flutter run -d linux
flutter run -d windows
flutter run -d <android-device-id>
flutter run -d <ios-simulator-id>
```

### 3 — Run tests (backend)

```bash
cd backend
pytest                             # runs all 34 test cases
pytest --cov=app                   # with coverage report
```

---

## Platform setup

### Android
The `AndroidManifest.xml` is already configured with `RECORD_AUDIO` and `INTERNET` permissions.  
The system will prompt the user for microphone access on first launch.

### iOS / iPadOS
`Info.plist` contains the required `NSMicrophoneUsageDescription`.  
A physical device or the simulator with a virtual mic works.

### macOS
`DebugProfile.entitlements` and `Release.entitlements` grant `audio-input` and `network.client`.  
No extra steps needed on macOS 12+.

### Linux
Ensure the user is in the `audio` group:
```bash
sudo usermod -aG audio $USER   # log out and back in
```

### Windows
The OS will prompt for microphone permission on first launch via Windows Privacy settings.

---

## Configuration (`.env`)

| Key | Default | Description |
|-----|---------|-------------|
| `OMR_BACKEND` | `oemer` | `oemer` or `audiveris` |
| `AUDIVERIS_JAR` | *(empty)* | Path to `audiveris-5.x.jar` |
| `SAMPLE_RATE` | `22050` | Audio sample rate (Hz) |
| `DTW_WINDOW` | `150` | Online DTW bandwidth (frames) |
| `PRELOAD_THRESHOLD` | `0.80` | Pre-load next page at this % |
| `PAGE_TURN_THRESHOLD` | `0.95` | Turn page at this % |
| `DEBUG` | `false` | Enable hot-reload + verbose logs |

---

## How it works

### OMR pipeline
```
PDF  →  oemer (CNN OMR)  →  MusicXML  →  music21 parser
  →  note events [(pitch_midi, onset_secs, duration_secs, measure, page)]
  →  piano roll (N_frames × 128)
  →  chroma matrix (N_frames × 12)   saved as chroma.npy
```

### Real-time following
```
Microphone  →  Flutter record pkg  →  Int16 PCM chunks
  →  WebSocket (binary)  →  Python backend
  →  ChromaExtractor (CQT, ~5 ms/frame)
  →  OnlineDTW.step() — Dixon 2005 algorithm
  →  PositionTracker → {measure, page, progress, confidence}
  →  WebSocket JSON  →  Flutter updates PDF viewer
```

### Latency budget
| Stage | Time |
|-------|------|
| Audio capture → WS send | ~1 ms |
| Chroma extraction (CQT) | ~4 ms |
| Online DTW step | ~1 ms |
| WS JSON → Flutter render | ~2 ms |
| **Total** | **~8 ms** ✅ (target < 100 ms) |

---

## Project structure

```
musicpage/
├── .gitignore
├── docker-compose.yml           # docker compose up --build
├── docs/
│   └── architecture.md          # detailed arch + data model
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── run.py
│   ├── pytest.ini
│   ├── .env.example
│   └── app/
│       ├── main.py              # FastAPI app
│       ├── core/config.py       # settings
│       ├── models/database.py   # SQLAlchemy ORM
│       ├── models/schemas.py    # Pydantic schemas
│       ├── api/endpoints/scores.py
│       ├── services/score_service.py
│       ├── services/omr_service.py
│       ├── audio/chroma_extractor.py
│       ├── score_following/online_dtw.py
│       ├── score_following/reference_builder.py
│       ├── score_following/position_tracker.py
│       └── websocket/handler.py
└── frontend/
    ├── pubspec.yaml
    ├── android/app/src/main/AndroidManifest.xml
    ├── ios/Runner/Info.plist
    ├── macos/Runner/DebugProfile.entitlements
    ├── macos/Runner/Release.entitlements
    └── lib/
        ├── main.dart
        ├── router.dart + router.g.dart  ← generated, already committed
        ├── models/{score,position}.dart
        ├── providers/{score,reader,settings}_provider.dart
        ├── screens/{library,reader,settings}_screen.dart
        ├── widgets/{score_card,tracking_indicator,control_bar}.dart
        └── services/{api,websocket,audio}_service.dart
```

---

## Docker (backend only)

```bash
docker compose up --build
# Backend available at http://localhost:8000
# Flutter app still runs natively: flutter run
```

---

## Roadmap / extensions

- [ ] Offline MIDI export using Basic Pitch (Spotify)
- [ ] CREPE pitch tracking mode for monophonic instruments
- [ ] Rehearsal mark navigation (jump to letter B, etc.)
- [ ] Repeat / DC / DS handling in the score follower
- [ ] Multi-page scroll mode (instead of single-page flip)
- [ ] BLE foot pedal support for manual page turns
- [ ] iCloud / Google Drive sync of the score library

---

## Licence

MIT — see `LICENSE`.
