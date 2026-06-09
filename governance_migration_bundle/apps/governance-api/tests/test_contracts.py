from __future__ import annotations

import json
from pathlib import Path

from src.main import app


SNAPSHOT = Path(__file__).parent / "snapshots" / "openapi.json"


def test_openapi_contract_matches_snapshot():
    current = app.openapi()
    expected = json.loads(SNAPSHOT.read_text(encoding="utf-8"))

    assert current == expected
