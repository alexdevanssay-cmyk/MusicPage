@echo off
REM scripts/build_windows.bat
REM ──────────────────────────
REM Builds the Windows all-in-one MusicPage app:
REM   1. PyInstaller bundles the Python backend (torch-free by default)
REM   2. Flutter builds the Windows .exe
REM   3. The backend folder is copied next to the .exe so the app auto-starts it
REM   4. (optional) NSIS creates a setup.exe installer if makensis is on PATH
REM
REM Requirements: Python venv in backend\.venv, Flutter, Visual Studio 2022 (C++).
REM Run from the repo root:  scripts\build_windows.bat

setlocal enabledelayedexpansion

set REPO_ROOT=%~dp0..
set BACKEND_DIR=%REPO_ROOT%\backend
set FLUTTER_DIR=%REPO_ROOT%\frontend
set DIST_DIR=%REPO_ROOT%\dist\windows
set APP_NAME=MusicPage
set APP_VERSION=1.0.0

REM Set EXCLUDE_OEMER=0 before running to include PyTorch-based OMR (~2 GB).
if not defined EXCLUDE_OEMER set EXCLUDE_OEMER=1

echo ============================================
echo   MusicPage Windows Build  (EXCLUDE_OEMER=%EXCLUDE_OEMER%)
echo ============================================

REM ── 1. Backend ──────────────────────────────────────────────────────────────
echo.
echo ^> Step 1/4 - PyInstaller (Python backend)
cd /d "%BACKEND_DIR%"
if not exist ".venv" (
    python -m venv .venv
    .venv\Scripts\pip install --upgrade pip
    .venv\Scripts\pip install -r requirements.txt
)
.venv\Scripts\pip install pyinstaller
.venv\Scripts\pyinstaller musicpage.spec --distpath dist --workpath build --noconfirm --clean
if errorlevel 1 ( echo FAILED: backend build & exit /b 1 )
echo    OK Backend at %BACKEND_DIR%\dist\musicpage_backend\

REM ── 2. Flutter ──────────────────────────────────────────────────────────────
echo.
echo ^> Step 2/4 - Flutter Windows build
cd /d "%FLUTTER_DIR%"
flutter pub get
flutter build windows --release
if errorlevel 1 ( echo FAILED: flutter build & exit /b 1 )
set FLUTTER_OUT=%FLUTTER_DIR%\build\windows\x64\runner\Release
echo    OK Flutter app at %FLUTTER_OUT%

REM ── 3. Bundle backend next to the app ───────────────────────────────────────
echo.
echo ^> Step 3/4 - Copying backend beside the app
if exist "%FLUTTER_OUT%\backend" rmdir /s /q "%FLUTTER_OUT%\backend"
xcopy /E /I /Y "%BACKEND_DIR%\dist\musicpage_backend" "%FLUTTER_OUT%\backend" >nul
echo    OK Portable app ready: %FLUTTER_OUT%\music_page.exe

REM ── 4. Optional NSIS installer ──────────────────────────────────────────────
echo.
echo ^> Step 4/4 - Installer (optional)
where makensis >nul 2>nul
if errorlevel 1 (
    echo    makensis not found - skipping installer. The Release folder above is a
    echo    complete portable app; zip and share it, or install NSIS to build a setup.exe.
    goto :done
)
mkdir "%DIST_DIR%" 2>nul
set NSI=%TEMP%\musicpage_installer.nsi
(
echo !include "MUI2.nsh"
echo Name "%APP_NAME%"
echo OutFile "%DIST_DIR%\%APP_NAME%-Setup-%APP_VERSION%.exe"
echo InstallDir "$PROGRAMFILES64\%APP_NAME%"
echo RequestExecutionLevel admin
echo !insertmacro MUI_PAGE_DIRECTORY
echo !insertmacro MUI_PAGE_INSTFILES
echo !insertmacro MUI_UNPAGE_INSTFILES
echo !insertmacro MUI_LANGUAGE "English"
echo Section "MusicPage"
echo   SetOutPath "$INSTDIR"
echo   File /r "%FLUTTER_OUT%\*.*"
echo   CreateShortcut "$DESKTOP\%APP_NAME%.lnk" "$INSTDIR\music_page.exe"
echo   WriteUninstaller "$INSTDIR\Uninstall.exe"
echo SectionEnd
echo Section "Uninstall"
echo   RMDir /r "$INSTDIR"
echo   Delete "$DESKTOP\%APP_NAME%.lnk"
echo SectionEnd
) > "%NSI%"
makensis "%NSI%"
echo    OK Installer: %DIST_DIR%\%APP_NAME%-Setup-%APP_VERSION%.exe

:done
echo.
echo ============================================
echo   Build complete.
echo ============================================
endlocal
