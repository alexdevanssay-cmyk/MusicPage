#!/usr/bin/env bash
# scripts/build_linux.sh
# ───────────────────────
# Builds MusicPage for Linux and packages it as:
#   • A .deb package  (Debian / Ubuntu / Mint)
#   • An AppImage     (distro-agnostic)
#
# Requirements:
#   - Python 3.11+ with pip
#   - Flutter 3.22+ in PATH
#   - dpkg-deb (on Debian-based systems)
#   - appimagetool: https://github.com/AppImage/AppImageKit/releases

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
FLUTTER_DIR="$REPO_ROOT/frontend"
DIST_DIR="$REPO_ROOT/dist/linux"
APP_NAME="MusicPage"
APP_ID="com.musicpage.app"
APP_VERSION="1.0.0"
ARCH="$(uname -m)"   # x86_64 or aarch64

echo "════════════════════════════════════════════"
echo "  MusicPage Linux Build  ($ARCH)"
echo "════════════════════════════════════════════"

mkdir -p "$DIST_DIR"

# ── 1. Backend ─────────────────────────────────────────────────────────────────
echo ""
echo "▶ Step 1/4 — PyInstaller"
cd "$BACKEND_DIR"
[ -d ".venv" ] || python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt pyinstaller
.venv/bin/pyinstaller musicpage.spec \
    --distpath dist --workpath build/pyinstaller --clean
echo "   ✓ Backend → $BACKEND_DIR/dist/musicpage_backend/"

# ── 2. Flutter ─────────────────────────────────────────────────────────────────
echo ""
echo "▶ Step 2/4 — Flutter Linux release"
cd "$FLUTTER_DIR"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build linux --release
FLUTTER_OUT="$FLUTTER_DIR/build/linux/$ARCH/release/bundle"
echo "   ✓ Flutter → $FLUTTER_OUT"

# ── 3. Assemble staging directory ──────────────────────────────────────────────
echo ""
echo "▶ Step 3/4 — Staging"
STAGE="$DIST_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/usr/bin"
mkdir -p "$STAGE/usr/lib/$APP_ID"
mkdir -p "$STAGE/usr/share/applications"
mkdir -p "$STAGE/usr/share/icons/hicolor/256x256/apps"

# Copy Flutter bundle
cp -R "$FLUTTER_OUT/." "$STAGE/usr/lib/$APP_ID/"

# Copy backend next to Flutter binary
cp -R "$BACKEND_DIR/dist/musicpage_backend" "$STAGE/usr/lib/$APP_ID/backend"

# Launcher script
cat > "$STAGE/usr/bin/musicpage" << 'LAUNCHER'
#!/usr/bin/env bash
exec "/usr/lib/com.musicpage.app/music_page" "$@"
LAUNCHER
chmod +x "$STAGE/usr/bin/musicpage"

# Desktop entry
cat > "$STAGE/usr/share/applications/$APP_ID.desktop" << DESKTOP
[Desktop Entry]
Name=MusicPage
Comment=Real-time score following
Exec=musicpage
Icon=$APP_ID
Type=Application
Categories=AudioVideo;Music;
DESKTOP

echo "   ✓ Staging → $STAGE"

# ── 4a. .deb package ───────────────────────────────────────────────────────────
echo ""
echo "▶ Step 4a/4 — .deb package"
DEB_DIR="$DIST_DIR/deb"
cp -R "$STAGE" "$DEB_DIR"
mkdir -p "$DEB_DIR/DEBIAN"

cat > "$DEB_DIR/DEBIAN/control" << CTRL
Package: musicpage
Version: $APP_VERSION
Architecture: $( [ "$ARCH" = "x86_64" ] && echo "amd64" || echo "arm64" )
Maintainer: MusicPage Team <hello@musicpage.app>
Depends: libgtk-3-0, libblkid1, liblzma5
Description: Real-time score following
 Automatically turns score pages based on what you play.
CTRL

dpkg-deb --build "$DEB_DIR" \
    "$DIST_DIR/${APP_NAME}-${APP_VERSION}-linux-$ARCH.deb"
echo "   ✓ .deb created"

# ── 4b. AppImage ───────────────────────────────────────────────────────────────
echo ""
echo "▶ Step 4b/4 — AppImage"

if command -v appimagetool &>/dev/null; then
  APPDIR="$DIST_DIR/AppDir"
  cp -R "$STAGE/." "$APPDIR/"
  mkdir -p "$APPDIR/AppRun"

  cat > "$APPDIR/AppRun" << 'AR'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/bin/musicpage" "$@"
AR
  chmod +x "$APPDIR/AppRun"
  cp "$APPDIR/usr/share/applications/$APP_ID.desktop" "$APPDIR/$APP_ID.desktop"

  ARCH_AI="$( [ "$ARCH" = "x86_64" ] && echo "x86_64" || echo "aarch64" )"
  ARCH="$ARCH_AI" appimagetool "$APPDIR" \
      "$DIST_DIR/${APP_NAME}-${APP_VERSION}-$ARCH_AI.AppImage"
  echo "   ✓ AppImage created"
else
  echo "   ⚠  appimagetool not found — skipping AppImage (install from github.com/AppImage/AppImageKit)"
fi

echo ""
echo "════════════════════════════════════════════"
echo "  ✅ Build complete!"
echo "  📂 $DIST_DIR/"
ls "$DIST_DIR"/*.{deb,AppImage} 2>/dev/null || true
echo "════════════════════════════════════════════"
