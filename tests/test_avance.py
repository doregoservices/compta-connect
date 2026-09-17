"""
Tests d'intégration de la version avancée : cycle mensuel (workflow),
espace membre en libre-service, et relances.
"""
import importlib.util
import os
import re
import sys
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parent.parent / "app"
sys.path.insert(0, str(APP_DIR))


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("COMPTA_DB", str(tmp_path / "test.db"))
    spec = importlib.util.spec_from_file_location("compta_app", APP_DIR / "app.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.app.config["TESTING"] = True
    mod.app.config["SECRET_KEY"] = "test"
    with mod.app.test_client() as c:
        yield c, mod


# --------------------------------------------------------------------------- #
# Cycle mensuel
# --------------------------------------------------------------------------- #

def test_page_workflow_et_ses_actions(client):
    c, _ = client
    r = c.get("/workflow")
    assert r.status_code == 200
    corps = r.get_data(as_text=True)
    assert "Cycle de cotisation" in corps
    assert "Ouverture de la période" in corps and "Clôture et report" in corps


def test_marquer_une_tache_faite_puis_l_annuler(client):
    c, _ = client
    r = c.post("/workflow/ouvrir/faire", data={"mois": "2026-09", "note": "Publié lundi"},
               follow_redirects=True)
    assert "marquée comme faite" in r.get_data(as_text=True)
    assert "fait le" in r.get_data(as_text=True)

    r = c.post("/workflow/ouvrir/annuler", data={"mois": "2026-09"}, follow_redirects=True)
    assert "remise en attente" in r.get_data(as_text=True)


def test_tache_inconnue_rejetee(client):
    c, _ = client
    r = c.post("/workflow/inexistante/faire", data={"mois": "2026-09"}, follow_redirects=True)
    assert "Tâche inconnue" in r.get_data(as_text=True)


def test_generer_les_relances(client):
    c, _ = client
    r = c.post("/workflow/relancer", data={"mois": "2026-09"}, follow_redirects=True)
    assert r.status_code == 200
    corps = r.get_data(as_text=True)
    # deux membres de démonstration sont en retard sur septembre (003 partiel, 005 et 006 impayés)
    assert "Motif OBLIGATOIRE" in corps


def test_rapport_mensuel_complet(client):
    c, _ = client
    r = c.get("/workflow/rapport?mois=2026-09")
    assert r.status_code == 200
    corps = r.get_data(as_text=True)
    for attendu in ["Situation financière", "Détail par membre", "Mouvements enregistrés",
                    "Suivi du cycle administratif", "Le trésorier"]:
        assert attendu in corps, attendu


def test_report_des_reliquats_sur_le_mois_suivant(client):
    c, mod = client
    r = c.post("/workflow/reporter", data={"mois": "2026-09"}, follow_redirects=True)
    corps = r.get_data(as_text=True)
    assert "reliquat(s) reporté(s)" in corps

    # le reliquat de 3 000 F du membre 003 apparaît bien en octobre
    with mod.app.app_context():
        octobre = mod.paiements(mois="2026-10")
        reports = [p for p in octobre if p.libelle.startswith("Report automatique")]
        assert reports, "aucun report créé"
        assert sum(p.montant for p in reports) == -13000  # 3 000 (003) + 2 × 5 000 (005, 006)

    # relancer la clôture ne duplique pas les reports
    c.post("/workflow/reporter", data={"mois": "2026-09"}, follow_redirects=True)
    with mod.app.app_context():
        apres = [p for p in mod.paiements(mois="2026-10")
                 if p.libelle.startswith("Report automatique")]
        assert len(apres) == len(reports)


# --------------------------------------------------------------------------- #
# Espace membre
# --------------------------------------------------------------------------- #

def test_connexion_au_portail(client):
    c, _ = client
    r = c.post("/portail/connexion", data={"code": "001", "fin_tel": "2233"},
               follow_redirects=True)
    corps = r.get_data(as_text=True)
    assert "Bienvenue KOUASSI Aya Michelle" in corps
    assert "Ma cotisation" in corps


def test_connexion_refusee_avec_un_mauvais_numero(client):
    c, _ = client
    r = c.post("/portail/connexion", data={"code": "001", "fin_tel": "0000"},
               follow_redirects=True)
    assert "incorrect" in r.get_data(as_text=True)


def test_portail_inaccessible_sans_connexion(client):
    c, _ = client
    r = c.get("/portail")
    assert r.status_code == 302
    assert r.headers["Location"].endswith("/portail/connexion")
    assert "Espace membre" in c.get("/portail/connexion").get_data(as_text=True)


def test_membre_s_inscrit_a_une_formation(client):
    c, _ = client
    c.post("/portail/connexion", data={"code": "002", "fin_tel": "6677"}, follow_redirects=True)
    r = c.post("/portail/formations/1/inscrire", follow_redirects=True)
    assert "Inscription enregistrée" in r.get_data(as_text=True)

    # une seconde inscription est refusée proprement
    r = c.post("/portail/formations/1/inscrire", follow_redirects=True)
    assert "déjà inscrit" in r.get_data(as_text=True)

    # l'inscription apparaît bien côté administration
    r = c.get("/formations/1")
    assert "YAO Kouadio Serge" in r.get_data(as_text=True)


def test_membre_annule_son_inscription(client):
    c, _ = client
    c.post("/portail/connexion", data={"code": "002", "fin_tel": "6677"}, follow_redirects=True)
    c.post("/portail/formations/1/inscrire", follow_redirects=True)
    r = c.post("/portail/formations/4/annuler", follow_redirects=True)
    assert "annulée" in r.get_data(as_text=True)


def test_membre_postule_a_une_offre(client):
    c, _ = client
    c.post("/portail/connexion", data={"code": "003", "fin_tel": "0405"}, follow_redirects=True)
    r = c.post("/portail/offres/1/candidater",
               data={"email": "amina@example.ci", "message": "Disponible"},
               follow_redirects=True)
    assert "Candidature transmise" in r.get_data(as_text=True)

    r = c.get("/offres/1")
    assert "TRAORE Aminata" in r.get_data(as_text=True)


def test_membre_participe_a_une_activite(client):
    c, _ = client
    c.post("/portail/connexion", data={"code": "004", "fin_tel": "9900"}, follow_redirects=True)
    r = c.post("/portail/activites/1/participer", follow_redirects=True)
    assert "Participation enregistrée" in r.get_data(as_text=True)
    r = c.post("/portail/activites/1/participer", follow_redirects=True)
    assert "déjà inscrit" in r.get_data(as_text=True)


def test_deconnexion(client):
    c, _ = client
    c.post("/portail/connexion", data={"code": "001", "fin_tel": "2233"}, follow_redirects=True)
    r = c.post("/portail/deconnexion", follow_redirects=True)
    assert "déconnecté" in r.get_data(as_text=True)
    assert c.get("/portail").status_code == 302


# --------------------------------------------------------------------------- #
# Membres : email
# --------------------------------------------------------------------------- #

def test_email_d_un_membre_est_enregistre_et_exporte(client):
    c, _ = client
    c.post("/membres/nouveau", data={"nom": "TEST Email", "telephone": "0709090909",
                                     "email": "test@example.ci", "cotisation": "5000"},
           follow_redirects=True)
    assert "test@example.ci" in c.get("/membres").get_data(as_text=True)
    assert "test@example.ci" in c.get("/export/membres.csv").get_data(as_text=True)


def test_import_en_avec_email(client):
    c, _ = client
    liste = ("nom;telephone;email;ville;specialite\n"
             "IMPORT Un;0700000001;un@example.ci;Abidjan;Fiscaliste\n"
             "IMPORT Deux;0700000002;deux@example.ci;Bouaké;Auditeur\n")
    r = c.post("/membres/importer", data={"texte": liste, "sep": ";", "cotisation": "5000"},
               follow_redirects=True)
    assert "2 membre(s) importé(s)" in r.get_data(as_text=True)
    assert "un@example.ci" in r.get_data(as_text=True)


def test_relances_email_sans_smtp_ne_bloquent_pas(client):
    """Sans relais configuré, la génération de relances doit rester fonctionnelle."""
    c, _ = client
    r = c.post("/workflow/relancer", data={"mois": "2026-09"}, follow_redirects=True)
    assert r.status_code == 200
    assert "Envoi email impossible" not in r.get_data(as_text=True)
