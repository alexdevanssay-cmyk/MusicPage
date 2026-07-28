# backend/musicpage.spec
# ───────────────────────
# PyInstaller spec for the MusicPage backend.
# Run from the backend/ directory:
#
#   pip install pyinstaller
#   pyinstaller musicpage.spec
#
# Output: dist/musicpage_backend/   (folder-mode, not single-file)
# Single-file mode is intentionally avoided: oemer/librosa extract
# native libraries at runtime and need a stable directory.
#
# Approximate output size:
#   Without oemer (OMR_BACKEND=stub): ~350 MB
#   With    oemer (OMR_BACKEND=oemer): ~2.0 GB  (PyTorch included)
#
# To exclude PyTorch and oemer (use Audiveris instead, or stub mode):
#   Set EXCLUDE_OEMER=1 in the environment before running pyinstaller.

import os, sys
from pathlib import Path
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

EXCLUDE_OEMER = os.environ.get("EXCLUDE_OEMER", "0") == "1"

# ── Data files to bundle ────────────────────────────────────────────────────────
datas = [
    # music21 corpus and metadata
    *collect_data_files("music21"),
    # librosa data (resampling filters, etc.)
    *collect_data_files("librosa"),
]
if not EXCLUDE_OEMER:
    datas += collect_data_files("oemer")

# ── Hidden imports (uvicorn + SQLAlchemy async drivers) ─────────────────────────
hidden = [
    # uvicorn internals not found by static analysis
    "uvicorn.logging",
    "uvicorn.loops", "uvicorn.loops.auto", "uvicorn.loops.asyncio",
    "uvicorn.protocols",
    "uvicorn.protocols.http", "uvicorn.protocols.http.auto",
    "uvicorn.protocols.http.h11_impl",
    "uvicorn.protocols.websockets", "uvicorn.protocols.websockets.auto",
    "uvicorn.protocols.websockets.websockets_impl",
    "uvicorn.lifespan", "uvicorn.lifespan.on",
    # SQLAlchemy async SQLite dialect
    "sqlalchemy.dialects.sqlite",
    "aiosqlite",
    # numpy / scipy C extensions
    "numpy.core._multiarray_umath",
    "scipy._lib._ccallback_c",
    # numba (used by librosa)
    "numba", "numba.core", "numba.np.ufunc",
    # music21 submodules
    *collect_submodules("music21"),
    # FastAPI / pydantic
    "pydantic.v1",
    "fastapi",
    "starlette",
    "anyio",
    "anyio._backends._asyncio",
]
if not EXCLUDE_OEMER:
    hidden += collect_submodules("oemer")
    hidden += ["torch", "torchvision"]

# ── Exclusions (reduce bundle size) ────────────────────────────────────────────
excludes = [
    "tkinter", "matplotlib", "PIL", "IPython",
    "jupyter", "notebook", "pytest",
]
if EXCLUDE_OEMER:
    excludes += ["torch", "torchvision", "torchaudio", "oemer"]

# ── Analysis ────────────────────────────────────────────────────────────────────
# PyInstaller injects SPECPATH (the spec's directory) into this namespace.
# Fall back to the cwd if it is ever missing.
_SPEC_DIR = globals().get("SPECPATH", os.getcwd())

a = Analysis(
    ["run.py"],
    pathex=[str(Path(_SPEC_DIR))],
    binaries=[],
    datas=datas,
    hiddenimports=hidden,
    excludes=excludes,
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="musicpage_backend",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,         # keep console for log output; set False for silent bg
    icon=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    name="musicpage_backend",
)
