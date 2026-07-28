# setup_dev.ps1
# ──────────────
# One-command dev setup for Windows.
# Run from the repo root in PowerShell:
#   Set-ExecutionPolicy -Scope Process Bypass; .\setup_dev.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   MusicPage — Development Setup       ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Prerequisites ─────────────────────────────────────────────────────────────
Write-Host "▶ Checking prerequisites" -ForegroundColor Blue

try { $pyVer = (python --version 2>&1).ToString() }
catch { Write-Error "Python not found. Install from https://www.python.org"; exit 1 }
Write-Host "  ✓ $pyVer" -ForegroundColor Green

try { $flVer = (flutter --version 2>&1 | Select-Object -First 1).ToString() }
catch { Write-Error "Flutter not found. Install from https://flutter.dev"; exit 1 }
Write-Host "  ✓ Flutter detected" -ForegroundColor Green

# ── Backend ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Setting up Python backend" -ForegroundColor Blue
Set-Location "$Root\backend"

if (-not (Test-Path ".venv")) {
    Write-Host "  Creating virtualenv..."
    python -m venv .venv
}

Write-Host "  Installing dependencies (may take several minutes on first run)..."
& .venv\Scripts\pip install --upgrade pip --quiet
& .venv\Scripts\pip install -r requirements.txt --quiet
Write-Host "  ✓ Backend dependencies installed" -ForegroundColor Green

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    Write-Host "  ✓ .env created" -ForegroundColor Green
}

# ── Flutter ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Setting up Flutter frontend" -ForegroundColor Blue
Set-Location "$Root\frontend"

flutter pub get --suppress-analytics
Write-Host "  ✓ Packages downloaded" -ForegroundColor Green

dart run build_runner build --delete-conflicting-outputs --suppress-analytics
Write-Host "  ✓ Code generation complete" -ForegroundColor Green

# ── Launch instructions ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "▶ Setup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Open two PowerShell windows and run:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Window 1 (backend):" -ForegroundColor Cyan
Write-Host "    cd $Root\backend"
Write-Host "    .venv\Scripts\python run.py"
Write-Host ""
Write-Host "  Window 2 (Flutter):" -ForegroundColor Cyan
Write-Host "    cd $Root\frontend"
Write-Host "    flutter run -d windows"
Write-Host ""
Write-Host "  Build installer:  .\scripts\build_windows.bat"
Write-Host "  Run tests:        cd backend && .venv\Scripts\pytest"
Write-Host ""
