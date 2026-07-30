"""DEMO_MODE and DATABASE_URL must be set before `app.main` (and its
transitive imports) are first loaded. DEMO_MODE swaps live network/GEE calls
for fixtures (TRD NFR-10); a dedicated sqlite file keeps test runs from
leaving orphaned rows (e.g. "demo-farmer") in the real dev/demo database that
`scripts/seed_demo.py` reads from."""
import os
from pathlib import Path

os.environ.setdefault("DEMO_MODE", "true")
_TEST_DB = Path(__file__).resolve().parent / "_test.db"
_TEST_DB.unlink(missing_ok=True)
os.environ.setdefault("DATABASE_URL", f"sqlite:///{_TEST_DB}")
