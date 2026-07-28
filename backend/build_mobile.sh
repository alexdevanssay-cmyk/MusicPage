#!/usr/bin/env bash
# scripts/build_mobile.sh
# ────────────────────────
# Builds MusicPage for Android (APK + AAB) and iOS (IPA).
#
# IMPORTANT — Mobile architecture
# ────────────────────────────────
# On mobile there is NO bundled Python backend.
# The app connects to a backend running on the same local network
# (desktop / Raspberry Pi / NAS).
# The user configures host + port in Settings → Backend connection.
#
# For Android: no Apple account needed. APK can be sideloaded.
# For iOS: requires an Apple Developer account ($99/year) + Xcode on macOS.

set -euo pipefail

FLUTTER_DIR="$(cd "$(dirname "$0")/../frontend" && pwd)"
DIST_DIR="$(cd "$(dirname "$0")/.." && pwd)/dist/mobile"
APP_VERSION="1.0.0"

mkdir -p "$DIST_DIR"

# ── Android ────────────────────────────────────────────────────────────────────
build_android() {
  echo ""
  echo "════════════════════════════════════════════"
  echo "  Android Build"
  echo "════════════════════════════════════════════"
  cd "$FLUTTER_DIR"
  flutter pub get
  dart run build_runner build --delete-conflicting-outputs

  # Debug APK (no signing required — for testing / sideload)
  echo "▶ APK (debug, sideloadable)"
  flutter build apk --debug
  cp build/app/outputs/flutter-apk/app-debug.apk \
     "$DIST_DIR/MusicPage-$APP_VERSION-debug.apk"

  # Release APK (requires signing key)
  echo "▶ APK (release)"
  echo "   ⚠  Signing not configured. To sign:"
  echo "      1. Create a keystore:  keytool -genkey -v -keystore musicpage.jks ..."
  echo "      2. Create android/key.properties with storePassword / keyPassword / keyAlias / storeFile"
  echo "      3. Edit android/app/build.gradle to reference key.properties"
  echo "      4. Re-run: flutter build apk --release"
  echo ""

  # App Bundle for Google Play Store
  echo "▶ App Bundle (.aab — for Google Play)"
  flutter build appbundle --release 2>/dev/null || \
    echo "   ⚠  Release AAB requires signing — see note above"

  echo ""
  echo "✅ Android outputs:"
  ls "$DIST_DIR"/*.apk 2>/dev/null || true
}

# ── iOS / iPadOS ───────────────────────────────────────────────────────────────
build_ios() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "⚠  iOS builds require macOS + Xcode. Skipping."
    return
  fi

  echo ""
  echo "════════════════════════════════════════════"
  echo "  iOS / iPadOS Build"
  echo "════════════════════════════════════════════"
  cd "$FLUTTER_DIR"

  # Ensure CocoaPods are installed
  command -v pod &>/dev/null || {
    echo "Installing CocoaPods..."; sudo gem install cocoapods
  }
  cd ios && pod install && cd ..

  flutter pub get
  dart run build_runner build --delete-conflicting-outputs

  echo "▶ Simulator build (no Apple account needed)"
  flutter build ios --simulator --no-codesign
  echo "   ✓  Run on simulator: flutter run -d <simulator-id>"

  echo ""
  echo "▶ Device / App Store build"
  echo "   Requirements: Xcode, Apple Developer account, provisioning profile"
  echo "   Command: flutter build ipa --release"
  echo "   Then open ios/Runner.xcworkspace in Xcode to Archive & Distribute."
  echo ""

  # Automated IPA (requires valid provisioning profile)
  # Uncomment once signing is configured:
  #
  # flutter build ipa --release \
  #   --export-options-plist=ios/ExportOptions.plist
  # cp build/ios/ipa/MusicPage.ipa "$DIST_DIR/MusicPage-$APP_VERSION.ipa"
}

# ── Entry point ────────────────────────────────────────────────────────────────
case "${1:-all}" in
  android) build_android ;;
  ios)     build_ios     ;;
  all)     build_android; build_ios ;;
  *)
    echo "Usage: $0 [android|ios|all]"
    exit 1
    ;;
esac
