#!/usr/bin/env bash
# scripts/build_macos.sh
# ───────────────────────
# Builds MusicPage for macOS:
#   1. Packages Python backend with PyInstaller
#   2. Builds Flutter .app
#   3. Injects backend into the .app bundle
#   4. Creates a distributable .dmg
#
# Requirements:
#   - Python 3.11+ virtualenv at ../backend/.venv
#   - Flutter 3.22+ in PATH
#   - create-dmg: brew install create-dmg
#   - (Optional) Apple Developer ID for notarisation

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
FLUTTER_DIR="$REPO_ROOT/frontend"
DIST_DIR="$REPO_ROOT/dist/macos"
APP_NAME="MusicPage"
APP_VERSION="1.0.0"

echo "════════════════════════════════════════════"
echo "  MusicPage macOS Build"
echo "════════════════════════════════════════════"

# ── 1. Build Python backend ─────────────────────────────────────────────────────
echo ""
echo "▶ Step 1/4 — PyInstaller (Python backend)"
cd "$BACKEND_DIR"

if [ ! -d ".venv" ]; then
  python3 -m venv .venv
  .venv/bin/pip install --upgrade pip
  .venv/bin/pip install -r requirements.txt
fi

.venv/bin/pip install pyinstaller

# Build in folder mode (not --onefile) for faster cold starts
.venv/bin/pyinstaller musicpage.spec --distpath dist --workpath build/pyinstaller --clean

BACKEND_DIST="$BACKEND_DIR/dist/musicpage_backend"
echo "   ✓ Backend built → $BACKEND_DIST"

# ── 2. Build Flutter .app ───────────────────────────────────────────────────────
echo ""
echo "▶ Step 2/4 — Flutter macOS build"
cd "$FLUTTER_DIR"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build macos --release

FLUTTER_APP="$FLUTTER_DIR/build/macos/Build/Products/Release/$APP_NAME.app"
echo "   ✓ Flutter app built → $FLUTTER_APP"

# ── 3. Inject backend into .app bundle ─────────────────────────────────────────
echo ""
echo "▶ Step 3/4 — Inject backend into .app bundle"

RESOURCES="$FLUTTER_APP/Contents/Resources"
mkdir -p "$RESOURCES/backend"

# Copy entire PyInstaller output folder
cp -R "$BACKEND_DIST/." "$RESOURCES/backend/"
chmod +x "$RESOURCES/backend/musicpage_backend"

echo "   ✓ Backend injected into $RESOURCES/backend/"

# ── 4. Create .dmg installer ────────────────────────────────────────────────────
echo ""
echo "▶ Step 4/4 — Create .dmg"

mkdir -p "$DIST_DIR"
DMG_PATH="$DIST_DIR/${APP_NAME}-${APP_VERSION}-macOS.dmg"

create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 150 180 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 450 180 \
  "$DMG_PATH" \
  "$FLUTTER_APP"

echo ""
echo "════════════════════════════════════════════"
echo "  ✅ Build complete!"
echo "  📦 $DMG_PATH"
echo "════════════════════════════════════════════"

# ── Optional: notarise with Apple ───────────────────────────────────────────────
# Uncomment and fill in your credentials:
#
# xcrun notarytool submit "$DMG_PATH" \
#   --apple-id "you@example.com" \
#   --password "@keychain:AC_PASSWORD" \
#   --team-id  "XXXXXXXXXX" \
#   --wait
# xcrun stapler staple "$DMG_PATH"
