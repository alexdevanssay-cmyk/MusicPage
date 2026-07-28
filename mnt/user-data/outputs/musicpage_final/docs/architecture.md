# MusicPage – Architecture Documentation

## Technology choices for 2026

| Component | Original spec | Chosen (2026) | Reason |
|-----------|--------------|---------------|--------|
| OMR | Audiveris | **oemer** (primary) + Audiveris (opt.) | oemer is pure-Python (pip-installable), no Java runtime needed for deployment; Audiveris still available for complex orchestral scores via `OMR_BACKEND=audiveris` |
| Real-time audio→features | Basic Pitch | **librosa chroma_cqt** | Basic Pitch (TensorFlow/ONNX) adds 300–600 ms latency per block; chroma_cqt runs in <5 ms per hop. Basic Pitch kept for optional offline MIDI export. |
| Pitch tracking | CREPE (mandatory) | **CREPE optional**, YIN default | CREPE CNN inference ≈80 ms/frame on CPU – too slow for <50 ms target. Chroma-based matching is instrument-agnostic and faster. |
| Score following | Online DTW | **Online DTW** (Dixon 2005) | Still the most reliable published algorithm. Newer learned approaches (e.g. beat-transformer) are less robust on unseen scores. |
| State management (Flutter) | unspecified | **flutter_riverpod 2.x** | Code-generation, compile-time safety, replaces Provider/BLoC |
| Navigation | unspecified | **go_router 14** | First-party, URL-based, deep-link capable |
| PDF viewer | pdfx | **syncfusion_flutter_pdfviewer** | Hardware-accelerated, stable page-jump API, maintained by Syncfusion |
| Audio capture | flutter_sound | **record 5.x** | More actively maintained, cleaner streaming API |

---

## System architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App                              │
│                                                                 │
│  LibraryScreen ──┐                                              │
│  ReaderScreen  ──┤── Riverpod providers ── ApiService (HTTP)   │
│  SettingsScreen──┘         │                                    │
│                            └── WsService (WebSocket)           │
│                            └── AudioCaptureService (record)    │
└────────────────────────────────────────────────────────────────-┘
              │ REST  /api/v1/scores/*          │ WS  /ws/follow
              │ HTTP GET …/pdf                  │ binary PCM + JSON
              ▼                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                     FastAPI Backend                             │
│                                                                 │
│  /api/v1/scores  ──  ScoreService                               │
│      ├── import PDF  ──  OMRService (oemer / Audiveris)         │
│      │                       └── MusicXML                       │
│      │                           └── ReferenceBuilder           │
│      │                               └── chroma.npy (cached)   │
│      └── GET /{id}/pdf  ──  FileResponse                        │
│                                                                 │
│  /ws/follow  ──  ws_session_handler                             │
│      ├── start_session  ──  loads chroma.npy                   │
│      │       └── OnlineDTW(reference_chroma)                    │
│      │       └── PositionTracker(builder)                       │
│      │       └── ChromaExtractor()                              │
│      │                                                          │
│      ├── binary PCM chunk                                       │
│      │       └── ChromaExtractor.push(pcm) → [chroma_12, …]   │
│      │       └── OnlineDTW.step(chroma) → (frame, confidence)  │
│      │       └── PositionTracker.update() → ScorePosition       │
│      │       └── emit position_update / page_change JSON        │
│      │                                                          │
│      └── manual_position  ──  dtw.seek() + tracker.seek()      │
│                                                                 │
│  SQLite (SQLAlchemy async)                                      │
│      scores / score_pages / measures / play_sessions           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Real-time pipeline latency budget

```
Microphone  →  Flutter record pkg  →  Int16 PCM chunk (512 samples)
                                            │
                              ~0.5 ms  ─────┘  Int16→Float32 conversion
                                            │
                              WS binary send (localhost ≈ <1 ms)
                                            │
              ~4 ms per frame  ────  ChromaExtractor (CQT, 512-sample window)
                                            │
              ~1 ms per frame  ────  OnlineDTW.step()  (O(W) = O(150))
                                            │
              ~0.5 ms          ────  PositionTracker.update()
                                            │
              WS JSON send back ≈ <1 ms
                                            │
              Flutter state update ≈ <1 ms
                                            │
                        Total ≈ 8–12 ms  ✅  (target: <100 ms)
```

---

## Data model

```
scores
  id            TEXT PK
  title         TEXT
  composer      TEXT
  pdf_path      TEXT        -- /data/scores/{id}_{name}.pdf
  musicxml_path TEXT        -- /data/musicxml/{id}/score.musicxml
  chroma_path   TEXT        -- /data/chroma/{id}.npy  (float32, N×12)
  total_pages   INTEGER
  total_measures INTEGER
  duration_secs REAL
  tempo_bpm     REAL
  time_signature TEXT
  is_analyzed   BOOLEAN
  is_favorite   BOOLEAN
  created_at    DATETIME
  last_opened   DATETIME

score_pages
  id            INTEGER PK
  score_id      TEXT FK → scores.id
  page_number   INTEGER
  first_measure INTEGER
  last_measure  INTEGER

measures
  id             INTEGER PK
  score_id       TEXT FK → scores.id
  measure_number INTEGER
  page_number    INTEGER
  onset_secs     REAL       -- wall-clock onset at default tempo
  duration_secs  REAL
  tempo_bpm      REAL
  time_signature TEXT
  notes          JSON       -- [{pitch_midi, onset_offset_secs, duration_secs}, …]

play_sessions
  id              TEXT PK
  score_id        TEXT FK → scores.id
  started_at      DATETIME
  ended_at        DATETIME
  last_measure    INTEGER
  completion_pct  REAL
  avg_confidence  REAL
```

---

## WebSocket protocol

### Client → Server

| Frame type | Format | Description |
|------------|--------|-------------|
| `start_session` | JSON text | Begin following `score_id` |
| `stop_session` | JSON text | Stop and clean up |
| `manual_position` | JSON text | Force follower to measure N |
| Audio chunk | **Binary** | Float32 LE PCM at 22050 Hz mono |

### Server → Client

| Frame type | Trigger | Key fields |
|------------|---------|------------|
| `session_started` | After `start_session` | `total_pages`, `frame_rate` |
| `position_update` | Every audio frame | `measure`, `page`, `progress`, `confidence` |
| `preload_next_page` | `progress ≥ 0.80` | `page` |
| `page_change` | `progress ≥ 0.95` | `from_page`, `to_page` |
| `error` | On exception | `message` |

---

## Build & run

### Backend (development)
```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python run.py
# → http://localhost:8000/docs
```

### Backend (Docker)
```bash
docker compose up --build
```

### Run tests
```bash
cd backend
pytest
```

### Flutter (development)
```bash
cd frontend
flutter pub get
flutter run -d macos          # or linux / windows / android / ios
```

### Flutter (release build)
```bash
flutter build macos --release
flutter build apk --release
flutter build ipa             # requires Xcode on macOS
```

---

## Project structure

```
musicpage/
├── docker-compose.yml
├── backend/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── pytest.ini
│   ├── run.py
│   ├── .env.example
│   ├── data/               ← gitignored; created at runtime
│   │   ├── scores/
│   │   ├── musicxml/
│   │   └── chroma/
│   ├── app/
│   │   ├── main.py
│   │   ├── core/
│   │   │   ├── config.py
│   │   │   └── exceptions.py
│   │   ├── models/
│   │   │   ├── database.py
│   │   │   └── schemas.py
│   │   ├── api/
│   │   │   ├── router.py
│   │   │   └── endpoints/
│   │   │       └── scores.py
│   │   ├── services/
│   │   │   ├── score_service.py
│   │   │   └── omr_service.py
│   │   ├── audio/
│   │   │   └── chroma_extractor.py
│   │   ├── score_following/
│   │   │   ├── online_dtw.py
│   │   │   ├── reference_builder.py
│   │   │   └── position_tracker.py
│   │   └── websocket/
│   │       └── handler.py
│   └── tests/
│       ├── test_online_dtw.py
│       ├── test_chroma_extractor.py
│       └── test_api_scores.py
└── frontend/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart
        ├── router.dart
        ├── models/
        │   ├── score.dart
        │   └── position.dart
        ├── providers/
        │   ├── score_provider.dart
        │   ├── reader_provider.dart
        │   └── settings_provider.dart
        ├── screens/
        │   ├── library_screen.dart
        │   ├── reader_screen.dart
        │   └── settings_screen.dart
        ├── widgets/
        │   ├── score_card.dart
        │   ├── tracking_indicator.dart
        │   └── control_bar.dart
        └── services/
            ├── api_service.dart
            ├── websocket_service.dart
            └── audio_service.dart
```
