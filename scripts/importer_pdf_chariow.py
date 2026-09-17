"""
Importe la liste officielle des membres et leurs paiements depuis un relevé
Chariow exporté en PDF (format du document ComptaConnect de juin-juillet 2026).

Usage :
    python3 scripts/importer_pdf_chariow.py chemin/du/releve.pdf [--mois 2026-06]

Ce que fait le script :
  1. lit les lignes « N° / date / nom / 5 000 FCFA / 750 FCFA / 4 250 FCFA / pays » ;
  2. crée les membres absents avec le code du document (001…080) ;
  3. crée un paiement rapproché manuellement pour chaque ligne ;
  4. n'écrase jamais une donnée existante (idempotent : re-exécutable sans risque).

Le prélèvement Chariow (750 FCFA) est conservé dans le libellé pour mémoire ;
le montant enregistré est le montant brut payé par le membre (5 000 FCFA).
"""

import argparse
import re
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

import pymupdf

BASE = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE / "app"))

LIGNE = re.compile(
    r"(\d{1,4})\s*\n(\d{2}/\d{2}/\d{4})\s*\n(.+?)\s*\n5\s?000 FCFA\s*\n750 FCFA\s*\n4\s?250 FCFA\s*\n(.+?)\s*\nI À jour",
    re.S,
)


def lire_pdf(chemin: str) -> list[dict]:
    doc = pymupdf.open(chemin)
    texte = "\n".join(p.get_text("text") for p in doc)
    rows = []
    for m in LIGNE.finditer(texte):
        numero, date, nom, pays = m.groups()
        nom = " ".join(nom.split())
        if nom in ("Nom et Prénoms",):
            continue
        rows.append({
            "numero": int(numero),
            "date": datetime.strptime(date, "%d/%m/%Y").date().isoformat(),
            "nom": nom,
            "pays": " ".join(pays.split()),
        })
    return rows


def importer(chemin_db: str, rows: list[dict], mois: str, brut: int = 5000,
             prelevement: int = 750) -> dict:
    con = sqlite3.connect(chemin_db)
    con.row_factory = sqlite3.Row
    existants = {r["nom"].strip().lower(): r for r in con.execute("SELECT * FROM membres")}
    codes_pris = {int(r["code"]) for r in con.execute("SELECT code FROM membres")}
    membres_crees = paiements_crees = 0

    for ligne in rows:
        cle = ligne["nom"].lower()
        membre = existants.get(cle)
        if membre is None:
            code = ligne["numero"]
            while code in codes_pris:
                code += 1
            codes_pris.add(code)
            con.execute(
                "INSERT INTO membres (code, nom, telephone, ville, specialite, cotisation,"
                " date_adhesion, actif) VALUES (?,?,?,?,?,?,?,1)",
                (f"{code:03d}", ligne["nom"], "", ligne["pays"], "", brut, ligne["date"]))
            membre = con.execute("SELECT * FROM membres WHERE code = ?", (f"{code:03d}",)).fetchone()
            existants[cle] = membre
            membres_crees += 1

        deja = con.execute(
            "SELECT COUNT(*) FROM paiements WHERE membre_id = ? AND mois = ?",
            (membre["id"], mois)).fetchone()[0]
        if deja:
            continue
        con.execute(
            "INSERT INTO paiements (date, montant, canal, expediteur, telephone, libelle,"
            " mois, membre_id, statut, methode) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (ligne["date"], brut, "Chariow (relevé importé)", ligne["nom"], "",
             f"Import relevé Chariow — prélevé {prelevement} FCFA, net {brut - prelevement} FCFA",
             mois, membre["id"], "RAPPROCHE", "manuel"))
        paiements_crees += 1
    con.commit()
    total = con.execute("SELECT COUNT(*) FROM membres").fetchone()[0]
    con.close()
    return {"membres_crees": membres_crees, "paiements_crees": paiements_crees,
            "membres_total": total}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("pdf", help="chemin du relevé Chariow en PDF")
    ap.add_argument("--mois", default="2026-06", help="mois de cotisation attribué (défaut 2026-06)")
    ap.add_argument("--db", default=str(BASE / "app" / "compta_connect.db"),
                    help="base SQLite cible")
    args = ap.parse_args()

    rows = lire_pdf(args.pdf)
    print(f"{len(rows)} lignes lues dans {args.pdf}")
    if not rows:
        sys.exit("Aucune ligne reconnue : vérifiez le format du PDF.")
    stats = importer(args.db, rows, args.mois)
    print(f"membres créés      : {stats['membres_crees']}")
    print(f"paiements créés    : {stats['paiements_crees']}")
    print(f"membres au total   : {stats['membres_total']}")


if __name__ == "__main__":
    main()
