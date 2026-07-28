#!/usr/bin/env bash
# setup_dev.sh
# ─────────────
# One command to go from a fresh clone to a running development environment.
# Run from the repo root:  bash setup_dev.sh
#
# What it does:
#   1. Checks prerequisites (Python, Flutter, Git)
#   2. Creates the Python virtualenv and installs all backend deps
#   3. Runs `flutter pub get` + code generation
#   4. Starts both processes in split terminals (or tmux if available)

set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(pwd)"

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  ✓  $*${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
err()  { echo -e "${RED}  ✗  $*${RESET}"; exit 1; }
step() { echo -e "\n${BLUE}${BOLD}▶  $*${RESET}"; }

echo -e "${BOLD}"
echo "  ╔═══════════════════════════════════════╗"
echo "  ║   MusicPage — Development Setup       ║"
echo "  ╚═══════════════════════════════════════╝"
echo -e "${RESET}"

# ── 1. Prerequisites ───────────────────────────────────────────────────────────
step "Checking prerequisites"

python3 --version &>/dev/null || err "Python 3.11+ required. Install from https://www.python.org"
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
python3 -c "import sys; exit(0 if sys.version_info >= (3,11) else 1)" \
  || err "Python 3.11+ required (found $PY_VER)"
ok "Python $PY_VER"

flutter --version &>/dev/null || err "Flutter 3.22+ required. Install from https://flutter.dev/docs/get-started/install"
FLUTTER_VER=$(flutter --version 2>/dev/null | head -1 | awk '{print $2}')
ok "Flutter $FLUTTER_VER"

git --version &>/dev/null || err "Git not found"
ok "Git"

# ── 2. Backend virtualenv ─────────────────────────────────────────────────────
step "Setting up Python backend"

cd "$REPO_ROOT/backend"

if [ ! -d ".venv" ]; then
  echo "  Creating virtualenv..."
  python3 -m venv .venv
fi

echo "  Activating virtualenv and installing deps (may take 3–10 min on first run)..."
.venv/bin/pip install --upgrade pip --quiet
.venv/bin/pip install -r requirements.txt --quiet
ok "Backend dependencies installed"

if [ ! -f ".env" ]; then
  cp .env.example .env
  ok ".env created from .env.example"
else
  ok ".env already exists"
fi

# ── 3. Flutter setup ──────────────────────────────────────────────────────────
step "Setting up Flutter frontend"

cd "$REPO_ROOT/frontend"
flutter pub get --suppress-analytics
ok "Flutter packages downloaded"

dart run build_runner build --delete-conflicting-outputs --suppress-analytics
ok "Dart code generation complete (router.g.dart)"

# ── 4. Launch both processes ──────────────────────────────────────────────────
step "Launching development environment"

cd "$REPO_ROOT"

# Helper: write a launch helper that starts both processes
LAUNCH_SCRIPT="$REPO_ROOT/.launch_dev.sh"
cat > "$LAUNCH_SCRIPT" << 'LAUNCH'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "$0")" && pwd)"
echo "Starting backend..."
cd "$ROOT/backend"
.venv/bin/python run.py &
BACKEND_PID=$!
echo "Backend PID: $BACKEND_PID"

# Wait for backend to be ready
echo "Waiting for backend on localhost:8000..."
for i in $(seq 1 30); do
  curl -s http://localhost:8000/health -o /dev/null 2>/dev/null && break
  sleep 1
  echo -n "."
done
echo ""
echo "Backend ready!"

echo "Starting Flutter..."
cd "$ROOT/frontend"
flutter run "$@"

kill $BACKEND_PID 2>/dev/null
LAUNCH
chmod +x "$LAUNCH_SCRIPT"

# Launch strategy: tmux > separate terminal windows > sequential
if command -v tmux &>/dev/null; then
  echo "  Launching with tmux (split panes)..."
  tmux new-session -d -s musicpage -x 220 -y 50
  tmux send-keys -t musicpage "cd '$REPO_ROOT/backend' && .venv/bin/python run.py" Enter
  tmux split-window -h -t musicpage
  tmux send-keys -t musicpage "sleep 4 && cd '$REPO_ROOT/frontend' && flutter run" Enter
  tmux attach-session -t musicpage

elif [[ "$OSTYPE" == "darwin"* ]]; then
  echo "  Opening two Terminal windows..."
  osascript << EOF
  tell application "Terminal"
    do script "cd '$REPO_ROOT/backend' && .venv/bin/python run.py"
    delay 3
    do script "cd '$REPO_ROOT/frontend' && flutter run"
  end tell
EOF

else
  # Fallback: print instructions
  echo ""
  warn "Could not auto-launch (no tmux). Run these in separate terminals:"
  echo ""
  echo -e "  ${BOLD}Terminal 1 (backend):${RESET}"
  echo "    cd $REPO_ROOT/backend"
  echo "    .venv/bin/python run.py"
  echo ""
  echo -e "  ${BOLD}Terminal 2 (Flutter):${RESET}"
  echo "    cd $REPO_ROOT/frontend"
  echo "    flutter run"
fi

echo ""
ok "Setup complete!"
echo ""
echo "  📖 Docs:    $REPO_ROOT/docs/architecture.md"
echo "  🔨 Build:   make build-macos  /  make build-linux  /  scripts\\build_windows.bat"
echo "  🧪 Tests:   make test"
echo ""
