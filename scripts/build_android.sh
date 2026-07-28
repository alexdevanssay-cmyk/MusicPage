#!/usr/bin/env bash
# scripts/build_android.sh
# ─────────────────────────
# Builds the Android thin-client APK.
#
# Android has NO bundled backend — the app connects to a desktop backend over the
# local network (host/port in Settings → Backend connection).
#
# Requirements: Flutter + the Android SDK (flutter doctor must show Android green).
# Run from the repo root:  scripts/build_android.sh [debug|release]

set -euo pipefail

MODE="${1:-debug}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_DIR="$REPO_ROOT/frontend"
DIST_DIR="$REPO_ROOT/dist/mobile"
APP_VERSION="1.0.0"
mkdir -p "$DIST_DIR"
cd "$FLUTTER_DIR"

# ── Ensure the Gradle scaffold exists, preserving our custom manifest ──────────
MANIFEST="android/app/src/main/AndroidManifest.xml"
if [[ ! -f "android/gradlew" || ! -f "android/app/build.gradle" && ! -f "android/app/build.gradle.kts" ]]; then
  echo "▶ Generating Android Gradle scaffold (flutter create)…"
  BACKUP="$(mktemp)"
  cp "$MANIFEST" "$BACKUP"
  flutter create --platforms=android .
  cp "$BACKUP" "$MANIFEST"   # restore RECORD_AUDIO / INTERNET / cleartext permissions
  echo "   Restored custom AndroidManifest.xml"
fi

flutter pub get

case "$MODE" in
  debug)
    echo "▶ Building debug APK (sideloadable, unsigned)…"
    flutter build apk --debug
    cp build/app/outputs/flutter-apk/app-debug.apk \
       "$DIST_DIR/MusicPage-$APP_VERSION-debug.apk"
    ;;
  release)
    echo "▶ Building release APK…"
    echo "  ⚠  Release signing must be configured (android/key.properties +"
    echo "     signingConfigs in android/app/build.gradle). See Flutter docs."
    flutter build apk --release
    cp build/app/outputs/flutter-apk/app-release.apk \
       "$DIST_DIR/MusicPage-$APP_VERSION-release.apk"
    ;;
  *)
    echo "Usage: $0 [debug|release]"; exit 1 ;;
esac

echo ""
echo "✅ APK(s):"
ls -1 "$DIST_DIR"/*.apk
