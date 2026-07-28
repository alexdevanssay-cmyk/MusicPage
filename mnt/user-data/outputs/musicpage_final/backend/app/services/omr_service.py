"""
app/services/omr_service.py
────────────────────────────
Optical Music Recognition: converts a PDF score to MusicXML.

Two backends are supported:
  1. oemer  (primary)   – pure-Python CNN OMR, pip-installable, no Java required.
                          Best for printed, single-stave, relatively simple scores.
  2. Audiveris (optional) – Java-based, handles complex orchestral scores better.
                          Requires audiveris-5.x.jar on the host system.

The backend is selected via settings.OMR_BACKEND ("oemer" | "audiveris").
If OMR fails entirely, a minimal MusicXML stub is written so the app still loads
the PDF (the user loses score-following but can still read).
"""
from __future__ import annotations

import asyncio
import logging
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

from app.core.config import settings
from app.core.exceptions import OMRError

logger = logging.getLogger(__name__)


class OMRService:
    """Async wrapper around the chosen OMR backend."""

    async def convert(self, pdf_path: Path, out_dir: Path) -> Path:
        """
        Convert *pdf_path* to MusicXML and save into *out_dir*.

        Returns
        -------
        Path to the generated .musicxml file.

        Raises
        ------
        OMRError if conversion fails on all backends.
        """
        out_dir.mkdir(parents=True, exist_ok=True)
        stem = pdf_path.stem

        if settings.OMR_BACKEND == "audiveris" and settings.AUDIVERIS_JAR:
            try:
                return await self._run_audiveris(pdf_path, out_dir)
            except Exception as exc:
                logger.warning("Audiveris failed (%s), falling back to oemer.", exc)

        try:
            return await self._run_oemer(pdf_path, out_dir)
        except Exception as exc:
            logger.error("oemer failed: %s", exc)
            # Last resort: write a stub MusicXML
            return self._write_stub(stem, out_dir)

    # ── oemer backend ────────────────────────────────────────────────────────────

    async def _run_oemer(self, pdf_path: Path, out_dir: Path) -> Path:
        """
        Run oemer in a subprocess (it is blocking and CPU-intensive).

        oemer CLI usage:
          oemer <input_pdf_or_image>  --output-dir <dir>
        The output file is named <stem>.musicxml
        """
        logger.info("Running oemer on %s", pdf_path)

        cmd = [
            "oemer",
            str(pdf_path),
            "--output-dir", str(out_dir),
        ]

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=300)

        if proc.returncode != 0:
            raise OMRError(
                f"oemer exited {proc.returncode}: {stderr.decode()[:500]}"
            )

        # Find the generated file
        candidates = list(out_dir.glob(f"{pdf_path.stem}*.xml")) + \
                     list(out_dir.glob(f"{pdf_path.stem}*.musicxml"))
        if not candidates:
            raise OMRError("oemer produced no .musicxml output")

        result = candidates[0]
        logger.info("oemer succeeded: %s", result)
        return result

    # ── Audiveris backend ────────────────────────────────────────────────────────

    async def _run_audiveris(self, pdf_path: Path, out_dir: Path) -> Path:
        """
        Run Audiveris via its CLI.

        Audiveris invocation:
          java -jar audiveris.jar -batch -export -output <dir> -- <pdf>
        """
        jar = settings.AUDIVERIS_JAR
        logger.info("Running Audiveris on %s", pdf_path)

        cmd = [
            "java", "-jar", str(jar),
            "-batch", "-export",
            "-output", str(out_dir),
            "--", str(pdf_path),
        ]

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=600)

        if proc.returncode != 0:
            raise OMRError(
                f"Audiveris exited {proc.returncode}: {stderr.decode()[:500]}"
            )

        # Audiveris outputs .mxl (compressed MusicXML) – locate it
        candidates = (
            list(out_dir.glob("**/*.mxl")) +
            list(out_dir.glob("**/*.xml")) +
            list(out_dir.glob("**/*.musicxml"))
        )
        if not candidates:
            raise OMRError("Audiveris produced no output file")

        result = candidates[0]
        logger.info("Audiveris succeeded: %s", result)
        return result

    # ── Fallback stub ─────────────────────────────────────────────────────────────

    @staticmethod
    def _write_stub(stem: str, out_dir: Path) -> Path:
        """
        Write a minimal valid MusicXML with a single whole-note C4.
        Allows the application to continue loading even if OMR fails.
        """
        stub_path = out_dir / f"{stem}_stub.musicxml"
        stub_path.write_text(
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE score-partwise PUBLIC\n'
            '  "-//Recordare//DTD MusicXML 4.0 Partwise//EN"\n'
            '  "http://www.musicxml.org/dtds/partwise.dtd">\n'
            '<score-partwise version="4.0">\n'
            '  <part-list><score-part id="P1"><part-name>Music</part-name></score-part></part-list>\n'
            '  <part id="P1">\n'
            '    <measure number="1">\n'
            '      <attributes>\n'
            '        <divisions>1</divisions>\n'
            '        <key><fifths>0</fifths></key>\n'
            '        <time><beats>4</beats><beat-type>4</beat-type></time>\n'
            '        <clef><sign>G</sign><line>2</line></clef>\n'
            '      </attributes>\n'
            '      <note><pitch><step>C</step><octave>4</octave></pitch>'
            '<duration>4</duration><type>whole</type></note>\n'
            '    </measure>\n'
            '  </part>\n'
            '</score-partwise>\n',
            encoding="utf-8",
        )
        logger.warning("Wrote stub MusicXML to %s", stub_path)
        return stub_path
