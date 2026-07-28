"""
tests/test_api_scores.py
─────────────────────────
Integration tests for the /api/v1/scores endpoints.
Uses an in-memory SQLite database and a real FastAPI test client.
"""
import io
import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession

from app.main import app
from app.models.database import Base, get_db

# ── In-memory test database ────────────────────────────────────────────────────

TEST_DB_URL = "sqlite+aiosqlite:///:memory:"

test_engine = create_async_engine(TEST_DB_URL, echo=False)
TestSession = async_sessionmaker(test_engine, expire_on_commit=False)


async def override_get_db():
    async with TestSession() as session:
        yield session


app.dependency_overrides[get_db] = override_get_db


@pytest_asyncio.fixture(autouse=True)
async def setup_db():
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c


# ── A minimal valid PDF (just the header bytes) ───────────────────────────────

MINIMAL_PDF = b"%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n"


# ── Tests ─────────────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_list_scores_empty(client):
    resp = await client.get("/api/v1/scores/")
    assert resp.status_code == 200
    assert resp.json() == []


@pytest.mark.asyncio
async def test_import_score(client, tmp_path, monkeypatch):
    """
    Import a score PDF.  We monkeypatch the OMR service so the test
    doesn't require Java or oemer to be installed.
    """
    # Patch OMRService.convert to immediately return a stub XML path
    from app.services import omr_service as omr_mod

    async def fake_convert(self, pdf_path, out_dir):
        xml = out_dir / "stub.musicxml"
        xml.parent.mkdir(parents=True, exist_ok=True)
        xml.write_text(STUB_MUSICXML)
        return xml

    monkeypatch.setattr(omr_mod.OMRService, "convert", fake_convert)

    pdf_file = io.BytesIO(MINIMAL_PDF)
    resp = await client.post(
        "/api/v1/scores/",
        files={"file": ("bach.pdf", pdf_file, "application/pdf")},
        data={"title": "Bach Invention", "composer": "J.S. Bach"},
    )
    assert resp.status_code == 201
    data = resp.json()
    assert data["title"] == "Bach Invention"
    assert data["composer"] == "J.S. Bach"
    assert "id" in data
    return data["id"]


@pytest.mark.asyncio
async def test_get_score_not_found(client):
    resp = await client.get("/api/v1/scores/nonexistent-id")
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_toggle_favorite(client, monkeypatch):
    from app.services import omr_service as omr_mod

    async def fake_convert(self, pdf_path, out_dir):
        xml = out_dir / "stub.musicxml"
        xml.parent.mkdir(parents=True, exist_ok=True)
        xml.write_text(STUB_MUSICXML)
        return xml

    monkeypatch.setattr(omr_mod.OMRService, "convert", fake_convert)

    # Import
    resp = await client.post(
        "/api/v1/scores/",
        files={"file": ("piece.pdf", io.BytesIO(MINIMAL_PDF), "application/pdf")},
    )
    score_id = resp.json()["id"]

    # Toggle → True
    resp = await client.post(f"/api/v1/scores/{score_id}/favorite")
    assert resp.status_code == 200
    assert resp.json()["is_favorite"] is True

    # Toggle → False
    resp = await client.post(f"/api/v1/scores/{score_id}/favorite")
    assert resp.json()["is_favorite"] is False


@pytest.mark.asyncio
async def test_delete_score(client, monkeypatch):
    from app.services import omr_service as omr_mod

    async def fake_convert(self, pdf_path, out_dir):
        xml = out_dir / "stub.musicxml"
        xml.parent.mkdir(parents=True, exist_ok=True)
        xml.write_text(STUB_MUSICXML)
        return xml

    monkeypatch.setattr(omr_mod.OMRService, "convert", fake_convert)

    resp = await client.post(
        "/api/v1/scores/",
        files={"file": ("tmp.pdf", io.BytesIO(MINIMAL_PDF), "application/pdf")},
    )
    score_id = resp.json()["id"]

    resp = await client.delete(f"/api/v1/scores/{score_id}")
    assert resp.status_code == 204

    resp = await client.get(f"/api/v1/scores/{score_id}")
    assert resp.status_code == 404


# ── Stub MusicXML ─────────────────────────────────────────────────────────────

STUB_MUSICXML = """\
<?xml version="1.0" encoding="UTF-8"?>
<score-partwise version="4.0">
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>1</divisions>
        <key><fifths>0</fifths></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
        <clef><sign>G</sign><line>2</line></clef>
      </attributes>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
      <note>
        <pitch><step>E</step><octave>4</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
      <note>
        <pitch><step>G</step><octave>4</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
      <note>
        <pitch><step>C</step><octave>5</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
    </measure>
    <measure number="2">
      <note>
        <pitch><step>D</step><octave>4</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
      <note>
        <pitch><step>F</step><octave>4</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
      <note>
        <pitch><step>A</step><octave>4</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
      <note>
        <pitch><step>D</step><octave>5</octave></pitch>
        <duration>1</duration><type>quarter</type>
      </note>
    </measure>
  </part>
</score-partwise>
"""
