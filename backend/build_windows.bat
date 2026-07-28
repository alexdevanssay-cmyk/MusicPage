@echo off
REM scripts/build_windows.bat
REM ──────────────────────────
REM Builds MusicPage for Windows:
REM   1. PyInstaller packages the Python backend
REM   2. Flutter builds the Windows .exe
REM   3. Backend is copied next to the .exe
REM   4. NSIS creates a setup.exe installer
REM
REM Requirements:
REM   - Python 3.11+ in PATH
REM   - Flutter 3.22+ in PATH
REM   - NSIS 3.x: https://nsis.sourceforge.io  (for installer step)
REM   - Run from the repo root

setlocal enabledelayedexpansion

set REPO_ROOT=%~dp0..
set BACKEND_DIR=%REPO_ROOT%\backend
set FLUTTER_DIR=%REPO_ROOT%\frontend
set DIST_DIR=%REPO_ROOT%\dist\windows
set APP_NAME=MusicPage
set APP_VERSION=1.0.0

echo ============================================
echo   MusicPage Windows Build
echo ============================================

REM ── 1. Build Python backend ────────────────────────────────────────────────
echo.
echo ^> Step 1/4 - PyInstaller (Python backend)
cd /d "%BACKEND_DIR%"

if not exist ".venv" (
    python -m venv .venv
    .venv\Scripts\pip install --upgrade pip
    .venv\Scripts\pip install -r requirements.txt
)
.venv\Scripts\pip install pyinstaller

.venv\Scripts\pyinstaller musicpage.spec ^
    --distpath dist ^
    --workpath build\pyinstaller ^
    --clean

echo    OK Backend built

REM ── 2. Build Flutter Windows app ───────────────────────────────────────────
echo.
echo ^> Step 2/4 - Flutter Windows build
cd /d "%FLUTTER_DIR%"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter build windows --release

set FLUTTER_OUT=%FLUTTER_DIR%\build\windows\x64\runner\Release
echo    OK Flutter built at %FLUTTER_OUT%

REM ── 3. Copy backend next to the Flutter .exe ───────────────────────────────
echo.
echo ^> Step 3/4 - Copying backend
mkdir "%FLUTTER_OUT%\backend" 2>nul
xcopy /E /I /Y "%BACKEND_DIR%\dist\musicpage_backend" "%FLUTTER_OUT%\backend"
echo    OK Backend copied to %FLUTTER_OUT%\backend\

REM ── 4. NSIS installer ──────────────────────────────────────────────────────
echo.
echo ^> Step 4/4 - NSIS installer
mkdir "%DIST_DIR%" 2>nul

REM Write a minimal NSIS script on the fly
set NSI_SCRIPT=%TEMP%\musicpage_installer.nsi
(
echo !include "MUI2.nsh"
echo Name "%APP_NAME%"
echo OutFile "%DIST_DIR%\%APP_NAME%-Setup-%APP_VERSION%.exe"
echo InstallDir "$PROGRAMFILES64\%APP_NAME%"
echo InstallDirRegKey HKLM "Software\%APP_NAME%" "Install_Dir"
echo RequestExecutionLevel admin
echo !insertmacro MUI_PAGE_WELCOME
echo !insertmacro MUI_PAGE_DIRECTORY
echo !insertmacro MUI_PAGE_INSTFILES
echo !insertmacro MUI_PAGE_FINISH
echo !insertmacro MUI_UNPAGE_CONFIRM
echo !insertmacro MUI_UNPAGE_INSTFILES
echo !insertmacro MUI_LANGUAGE "English"
echo Section "MusicPage" SecMain
echo   SetOutPath "$INSTDIR"
echo   File /r "%FLUTTER_OUT%\*.*"
echo   WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\%APP_NAME%" "DisplayName" "%APP_NAME%"
echo   WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\%APP_NAME%" "UninstallString" "$INSTDIR\Uninstall.exe"
echo   WriteUninstaller "$INSTDIR\Uninstall.exe"
echo   CreateShortcut "$DESKTOP\%APP_NAME%.lnk" "$INSTDIR\music_page.exe"
echo   CreateDirectory "$SMPROGRAMS\%APP_NAME%"
echo   CreateShortcut "$SMPROGRAMS\%APP_NAME%\%APP_NAME%.lnk" "$INSTDIR\music_page.exe"
echo SectionEnd
echo Section "Uninstall"
echo   RMDir /r "$INSTDIR"
echo   Delete "$DESKTOP\%APP_NAME%.lnk"
echo   RMDir /r "$SMPROGRAMS\%APP_NAME%"
echo   DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\%APP_NAME%"
echo SectionEnd
) > "%NSI_SCRIPT%"

makensis "%NSI_SCRIPT%"
echo    OK Installer created

echo.
echo ============================================
echo   Build complete!
echo   %DIST_DIR%\%APP_NAME%-Setup-%APP_VERSION%.exe
echo ============================================
endlocal
