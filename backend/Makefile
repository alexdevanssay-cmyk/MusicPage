# Makefile — convenience wrapper for MusicPage build targets.
# Run from the repo root.
#
# Usage:
#   make backend-dev     Start backend in development mode
#   make test            Run all backend tests
#   make build-macos     Build + package for macOS (.dmg)
#   make build-windows   Build + package for Windows (setup.exe)
#   make build-linux     Build + package for Linux (.deb + AppImage)
#   make build-android   Build Android APK/AAB
#   make build-ios       Build iOS IPA
#   make flutter-dev     Run Flutter in dev mode (assumes backend already running)
#   make clean           Remove all build artefacts

.PHONY: all backend-dev test \
        build-macos build-windows build-linux build-android build-ios \
        flutter-dev flutter-gen clean help

# ── Development ────────────────────────────────────────────────────────────────

backend-dev:
	@echo "▶ Starting backend in development mode..."
	cd backend && \
	  [ -d .venv ] || python3 -m venv .venv && \
	  .venv/bin/pip install -q -r requirements.txt && \
	  DEBUG=true .venv/bin/python run.py

test:
	@echo "▶ Running backend tests..."
	cd backend && \
	  [ -d .venv ] || python3 -m venv .venv && \
	  .venv/bin/pip install -q -r requirements.txt && \
	  .venv/bin/pytest -v

flutter-gen:
	@echo "▶ Generating Dart code (build_runner)..."
	cd frontend && \
	  flutter pub get && \
	  dart run build_runner build --delete-conflicting-outputs

flutter-dev:
	@echo "▶ Starting Flutter (connect to running backend)..."
	cd frontend && flutter run

# ── Production builds ─────────────────────────────────────────────────────────

build-macos:
	@echo "▶ Building for macOS..."
	./scripts/build_macos.sh

build-windows:
	@echo "▶ Building for Windows..."
	./scripts/build_windows.bat

build-linux:
	@echo "▶ Building for Linux..."
	./scripts/build_linux.sh

build-android:
	@echo "▶ Building for Android..."
	./scripts/build_mobile.sh android

build-ios:
	@echo "▶ Building for iOS..."
	./scripts/build_mobile.sh ios

# ── Docker ────────────────────────────────────────────────────────────────────

docker-up:
	docker compose up --build

docker-down:
	docker compose down

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean:
	@echo "▶ Cleaning build artefacts..."
	rm -rf backend/build backend/dist backend/.venv
	rm -rf frontend/build frontend/.dart_tool
	rm -rf dist/
	@echo "   ✓ Done"

help:
	@echo ""
	@echo "  MusicPage — available targets"
	@echo "  ─────────────────────────────────────────────"
	@echo "  make backend-dev    Start Python backend (dev)"
	@echo "  make test           Run backend tests"
	@echo "  make flutter-gen    Generate router.g.dart"
	@echo "  make flutter-dev    Run Flutter (backend must be running)"
	@echo "  make build-macos    Produce .dmg for macOS"
	@echo "  make build-windows  Produce setup.exe for Windows"
	@echo "  make build-linux    Produce .deb + AppImage for Linux"
	@echo "  make build-android  Produce .apk + .aab for Android"
	@echo "  make build-ios      Produce .ipa for iOS/iPadOS"
	@echo "  make docker-up      Run backend in Docker"
	@echo "  make clean          Remove all build artefacts"
	@echo ""
