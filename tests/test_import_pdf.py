"""
L'import du relevé Chariow officiel (PDF de juin-juillet 2026) doit reconnaître
les 80 lignes et les rapprocher une par une.
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))

PDF = Path(__file__).resolve().parent.parent.parent / "uploads" / "ComptaConnect_Cotisation_Juin2026.pdf"

pytest.importorskip("pymupdf")

if not PDF.exists():
    pytest.skip("relevé Chariow non présent dans uploads/", allow_module_level=True)

from scripts.importer_pdf_chariow import lire_pdf  # noqa: E402


def test_le_releve_officiel_est_lu_en_entier():
    rows = lire_pdf(str(PDF))
    assert len(rows) == 80, f"{len(rows)} lignes lues, 80 attendues"
    premier, dernier = rows[0], rows[-1]
    assert premier["nom"] == "Gbahonnon Josée-therese Oraga"
    assert premier["date"] == "2026-06-10"
    assert premier["pays"] == "Côte d'Ivoire"
    assert dernier["nom"] == "Kouadio Stephane"
    assert dernier["date"] == "2026-07-11"


def test_burkina_reconnu():
    rows = lire_pdf(str(PDF))
    pays = {r["pays"] for r in rows}
    assert "Burkina Faso" in pays


def test_import_idempotent(tmp_path):
    import sqlite3
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
    from scripts.importer_pdf_chariow import importer

    db = tmp_path / "test.db"
    con = sqlite3.connect(db)
    con.executescript("""
        CREATE TABLE membres (
            id INTEGER PRIMARY KEY AUTOINCREMENT, code TEXT UNIQUE NOT NULL, nom TEXT NOT NULL,
            telephone TEXT DEFAULT '', ville TEXT DEFAULT '', specialite TEXT DEFAULT '',
            email TEXT DEFAULT '', cotisation INTEGER DEFAULT 0, date_adhesion TEXT DEFAULT '',
            actif INTEGER DEFAULT 1, exonere INTEGER DEFAULT 0);
        CREATE TABLE paiements (
            id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, montant INTEGER NOT NULL,
            canal TEXT DEFAULT '', expediteur TEXT DEFAULT '', telephone TEXT DEFAULT '',
            libelle TEXT DEFAULT '', mois TEXT DEFAULT '', membre_id INTEGER,
            statut TEXT DEFAULT 'NON_RAPPROCHE', methode TEXT DEFAULT 'aucun');
    """)
    con.close()
    rows = lire_pdf(str(PDF))
    s1 = importer(str(db), rows, "2026-06")
    s2 = importer(str(db), rows, "2026-06")
    assert s1["membres_crees"] == 80 and s1["paiements_crees"] == 80
    assert s2["membres_crees"] == 0 and s2["paiements_crees"] == 0, "le second passage ne duplique rien"
