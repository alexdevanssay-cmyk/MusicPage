# Building MusicPage — Windows & Android

MusicPage ships as **two builds from one Flutter codebase** (`frontend/`), because
the two platforms have fundamentally different capabilities:

| | Windows (all-in-one) | Android (thin client) |
|---|---|---|
| Flutter UI | ✅ | ✅ |
| Python backend | **bundled inside the app**, auto-started | **not bundled** — runs on a PC |
| Microphone following | ✅ local | ✅ (audio sent to the PC backend over Wi-Fi) |
| PDF import + OMR | ✅ | ✅ (done on the PC backend) |

**Why Android can't be fully standalone:** the score-following engine needs
Python + librosa/numba (and, for real OMR, PyTorch). That stack can't run inside
an Android APK. So on Android the app is a *remote control* for a backend running
on a Windows/Mac/Linux machine on the same network — you set that machine's IP in
**Settings → Backend connection**. This split is the app's intended design
(`lib/services/backend_launcher_service.dart`).

---

## Prerequisites

- **Flutter** ≥ 3.22 and **Dart** ≥ 3.3 (`flutter --version`)
- **Python** 3.10–3.11 with the backend venv installed
  (`backend/.venv`, `pip install -r backend/requirements.txt`)
- **Windows build only:** Visual Studio 2022 with the *Desktop development with C++* workload
- **Android build only:** the Android SDK (via Android Studio) — `flutter doctor`
  must show a green check for Android toolchain

> **OMR note.** Real PDF→notes OMR needs `oemer` + PyTorch (~2.5 GB). It is
> optional: without it the backend writes a stub score so the app still loads and
> follows. The Windows bundle below is built **without** PyTorch (`EXCLUDE_OEMER=1`,
> ~350 MB). To include OMR, `pip install oemer` first and drop that flag.

---

## Windows — all-in-one app

Produces a folder (and optional installer) containing the Flutter `.exe` with the
Python backend bundled in a `backend\` subfolder next to it. On launch, the app's
splash screen starts `backend\musicpage_backend.exe`, waits for it to answer on
`localhost:8000`, then opens the library.

### One-shot script
```bash
scripts/build_windows.bat
```

### Manual steps
```bash
# 1. Bundle the backend into a folder-mode executable (torch-free)
cd backend
set EXCLUDE_OEMER=1
.venv\Scripts\pyinstaller musicpage.spec --distpath dist --workpath build --noconfirm
#   → backend\dist\musicpage_backend\musicpage_backend.exe

# 2. Build the Flutter Windows app
cd ..\frontend
flutter pub get
flutter build windows --release
#   → frontend\build\windows\x64\runner\Release\music_page.exe

# 3. Place the backend beside the app so the launcher can find it
xcopy /E /I /Y ..\backend\dist\musicpage_backend build\windows\x64\runner\Release\backend
```

Run `build\windows\x64\runner\Release\music_page.exe`. First launch takes a few
seconds while the bundled backend unpacks its native libraries.

The optional NSIS step in `scripts/build_windows.bat` wraps the Release folder in
a `MusicPage-Setup-1.0.0.exe` installer (requires [NSIS](https://nsis.sourceforge.io)).

---

## Android — thin client

### 1. Generate the Gradle scaffold (first time only)
The repo ships a hand-written `android/app/src/main/AndroidManifest.xml` (with the
mic/internet/cleartext permissions) but not the full Gradle project. Generate it,
then restore the manifest:

```bash
cd frontend
cp android/app/src/main/AndroidManifest.xml /tmp/MusicPage-Manifest.xml
flutter create --platforms=android .
cp /tmp/MusicPage-Manifest.xml android/app/src/main/AndroidManifest.xml   # keep our permissions
```

### 2. Build
```bash
flutter pub get
flutter build apk --debug        # sideloadable, no signing needed
#   → build/app/outputs/flutter-apk/app-debug.apk
```
(or `scripts/build_android.sh`). For a Play-Store release build, configure signing
per the notes in that script.

### 3. Use it
1. On your **PC**, start the backend: `cd backend && .venv\Scripts\python run.py`
   (or run the bundled Windows app — it exposes the same backend on port 8000).
2. Find the PC's LAN IP (`ipconfig` → e.g. `192.168.1.42`).
3. On the **phone**, install the APK, open **Settings → Backend connection**, set
   Host = `192.168.1.42`, Port = `8000`.
4. Open a score and press **Follow**. Grant the microphone permission when asked.

> The phone and PC must be on the same Wi-Fi, and the PC firewall must allow
> inbound TCP on port 8000.

---

## Verifying the backend independently
```bash
cd backend
.venv\Scripts\python run.py
# http://localhost:8000/health   → {"status":"ok"}
# http://localhost:8000/docs     → API explorer
.venv\Scripts\python -m pytest   # 28 tests
```
