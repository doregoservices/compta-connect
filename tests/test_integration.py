"""
Test d'intégration : démarre l'application réelle sur une base temporaire et
parcourt toutes les pages, puis rejoue le scénario complet d'un mois de cotisation.
"""
import importlib.util
import sys
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parent.parent / "app"
sys.path.insert(0, str(APP_DIR))


@pytest.fixture()
def client(tmp_path, monkeypatch):
    """Charge app.py avec une base de données isolée dans tmp_path."""
    monkeypatch.setenv("COMPTA_DB", str(tmp_path / "test.db"))
    spec = importlib.util.spec_from_file_location("compta_app", APP_DIR / "app.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)          # init_db() tourne à l'import, sur la base isolée
    mod.app.config["TESTING"] = True
    with mod.app.test_client() as c:
        yield c, mod


PAGES = ["/", "/membres", "/cotisations", "/paiements", "/formations", "/offres",
         "/activites", "/parametres", "/payer", "/etat", "/import", "/workflow",
         "/workflow/rapport", "/portail/connexion",
         "/api/sante", "/api/moi?code=001", "/payer?code=001"]


@pytest.mark.parametrize("url", PAGES)
def test_pages_repondent_200(client, url):
    c, _ = client
    reponse = c.get(url)
    assert reponse.status_code == 200, f"{url} -> {reponse.status_code}"


def test_scenario_complet_d_un_mois(client):
    c, mod = client

    # 1. le tableau de bord affiche les données de démonstration
    corps = c.get("/").get_data(as_text=True)
    assert "Compta Connect" in corps and "TAUX" not in corps.upper() or "recouvrement" in corps.lower()

    # 2. un paiement saisi avec la bonne référence est rapproché automatiquement
    r = c.post("/paiements/enregistrer", data={
        "montant": "5000", "date": "2026-09-12", "canal": "Wave",
        "expediteur": "BAMBA FATOU", "telephone": "0511223344",
        "libelle": "CC2609005", "membre_id": "", "mois": "2026-09",
    }, follow_redirects=True)
    assert r.status_code == 200
    assert "rapproché automatiquement de BAMBA Fatou" in r.get_data(as_text=True)

    # 3. le pointage de septembre le reflète
    corps = c.get("/cotisations?mois=2026-09").get_data(as_text=True)
    assert "CC2609005" in corps
    assert corps.count("paye") >= 1

    # 4. export Excel et CSV du pointage
    xlsx = c.get("/export/pointage.xlsx?mois=2026-09")
    assert xlsx.status_code == 200 and xlsx.data[:2] == b"PK"
    csv_ = c.get("/export/pointage.csv?mois=2026-09").get_data(as_text=True)
    assert "BAMBA Fatou" in csv_ and "PAYE" in csv_

    # 5. les relances ne concernent plus le membre qui vient de payer
    relances = c.get("/export/relances.txt?mois=2026-09").get_data(as_text=True)
    assert "BAMBA Fatou" not in relances
    assert "CC2609001" in relances or "CC2609003" in relances

    # 6. import d'un relevé : un paiement inconnu reste à pointer, un autre est reconnu
    releve = ("date;montant;canal;expediteur;telephone;libelle\n"
              "14/09/2026;5000;Orange Money;ASSAMOI JEAN;0700112244;CC2609006\n"
              "15/09/2026;5000;Wave;INCONNU TOTO;0000000000;sans motif\n")
    r = c.post("/import", data={"texte": releve, "mois": "2026-09", "sep": ";"},
               follow_redirects=True)
    assert "2 paiement(s) importé(s)" in r.get_data(as_text=True)
    assert "1 rapproché(s) automatiquement" in r.get_data(as_text=True)

    # 7. le pointage automatique ne casse rien quand on le relance
    r = c.post("/rapprocher", follow_redirects=True)
    assert r.status_code == 200


def test_cycle_de_vie_d_un_membre(client):
    c, _ = client
    r = c.post("/membres/nouveau", data={"nom": "TEST Nouvel Adhérent", "telephone": "0709090909",
                                         "ville": "Abidjan", "specialite": "Test",
                                         "cotisation": "5000"}, follow_redirects=True)
    assert "TEST Nouvel Adhérent" in r.get_data(as_text=True)

    corps = c.get("/membres").get_data(as_text=True)
    assert "TEST Nouvel Adhérent" in corps

    # le nouveau membre obtient sa page publique personnelle
    r = c.get("/payer?q=")  # recherche vide -> reste sur /payer
    assert r.status_code == 200


def test_formations_et_inscriptions(client):
    c, _ = client
    r = c.post("/formations/nouveau", data={"titre": "Test TVA", "formateur": "X",
                                            "date": "2026-09-20", "heure": "18:00",
                                            "mode": "En ligne", "lieu": "Meet",
                                            "cout": "0", "places": "10"},
               follow_redirects=True)
    assert "Test TVA" in r.get_data(as_text=True)
    fid = 3  # 2 formations de démonstration + celle créée

    r = c.post(f"/formations/{fid}/inscrire", data={"membre_id": "1"}, follow_redirects=True)
    assert "KOUASSI Aya Michelle" in r.get_data(as_text=True)

    r = c.post("/inscriptions/4/presence", follow_redirects=True)   # bascule présent/absent
    assert r.status_code == 200


def test_offres_et_candidatures(client):
    c, _ = client
    r = c.post("/offres/nouveau", data={"titre": "Comptable test", "entreprise": "Cabinet X",
                                        "ville": "Abidjan", "contrat": "CDI"},
               follow_redirects=True)
    assert "Comptable test" in r.get_data(as_text=True)

    r = c.post("/offres/3/candidater", data={"membre_id": "2", "message": "Motivé"},
               follow_redirects=True)
    assert "YAO Kouadio Serge" in r.get_data(as_text=True)

    r = c.post("/candidatures/2/statut", data={"statut": "entretien"}, follow_redirects=True)
    assert "entretien" in r.get_data(as_text=True)


def test_activites_et_participations(client):
    c, _ = client
    r = c.post("/activites/nouveau", data={"titre": "Test AG", "categorie": "Réunion",
                                           "date": "2026-09-25", "heure": "17:00",
                                           "mode": "En ligne", "cout": "0"},
               follow_redirects=True)
    assert "Test AG" in r.get_data(as_text=True)

    r = c.post("/activites/3/participer", data={"membre_id": "1"}, follow_redirects=True)
    # Jinja échappe l'apostrophe en &#39; dans le message flash
    assert "KOUASSI Aya Michelle participe" in r.get_data(as_text=True)

    # une double inscription est refusée proprement
    r = c.post("/activites/3/participer", data={"membre_id": "1"}, follow_redirects=True)
    assert "déjà inscrit" in r.get_data(as_text=True)


def test_parametres_persistes(client):
    c, _ = client
    donnees = {"reseau": "Compta Connect", "slogan": "Solidarité", "cotisation": "7500",
               "jour_echeance": "15", "canal_wave": "1", "wave_numero": "0700000000",
               "wave_nom": "Caisse CC", "caisse_nom": "Caisse du réseau"}
    r = c.post("/parametres", data=donnees, follow_redirects=True)
    assert r.status_code == 200
    corps = c.get("/payer").get_data(as_text=True)
    assert "0700000000" in corps
    assert "7 500" in corps.replace("\u202f", " ")


def test_page_publique_affiche_statut_et_reference(client):
    c, _ = client
    corps = c.get("/payer?code=001&mois=2026-09").get_data(as_text=True)
    assert "CC2609001" in corps
    assert "<svg" in corps, "le QR code doit être présent sur la page publique"


def test_sante(client):
    c, _ = client
    import json
    data = json.loads(c.get("/api/sante").get_data(as_text=True))
    assert data["ok"] and data["membres"] == 6 and data["formations"] == 2 and data["offres"] == 2
