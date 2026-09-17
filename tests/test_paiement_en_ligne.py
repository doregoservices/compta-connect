"""
Tests du paiement en ligne automatique (CinetPay) — le remplaçant de Chariow.

Aucun appel réseau : le transport HTTP est remplacé par un faux qui enregistre
les requêtes et renvoie les réponses officielles de CinetPay.
"""
import importlib.util
import sys
from pathlib import Path

import pytest

APP_DIR = Path(__file__).resolve().parent.parent / "app"
sys.path.insert(0, str(APP_DIR))

import paiement_en_ligne as P  # noqa: E402


@pytest.fixture()
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("COMPTA_DB", str(tmp_path / "test.db"))
    spec = importlib.util.spec_from_file_location("compta_app", APP_DIR / "app.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.app.config["TESTING"] = True
    with mod.app.test_client() as c:
        yield c, mod


def activer_cinetpay(mod):
    with mod.app.app_context():
        for cle, valeur in [("cinetpay_actif", "1"), ("cinetpay_site_id", "123456"),
                            ("cinetpay_apikey", "cle-test"),
                            ("cinetpay_url_api", P.URL_API),
                            ("url_publique", "https://outil.example.com")]:
            mod.db().execute("INSERT INTO settings (cle, valeur) VALUES (?, ?)"
                             " ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur",
                             (cle, valeur))
        mod.db().commit()


class FauxTransport:
    """Remplace l'appel HTTP à CinetPay et mémorise les requêtes."""

    def __init__(self, reponses):
        self.reponses = dict(reponses)
        self.appels = []

    def __call__(self, url, payload):
        self.appels.append((url, payload))
        return self.reponses[url.split("/v2/")[-1]]


# --------------------------------------------------------------------------- #
# Module (sans application web)
# --------------------------------------------------------------------------- #

def test_config_ok():
    assert not P.config_ok({})
    assert P.config_ok({"cinetpay_actif": "1", "cinetpay_site_id": "1", "cinetpay_apikey": "k"})
    assert not P.config_ok({"cinetpay_actif": "0", "cinetpay_site_id": "1", "cinetpay_apikey": "k"})


def test_creer_paiement_construit_la_bonne_demande(monkeypatch):
    faux = FauxTransport({"payment": {"code": "0", "message": "SUCCESS",
                                      "data": {"payment_url": "https://pay.cinetpay.com/abc"}}})
    monkeypatch.setattr(P, "TRANSPORT", faux)
    cfg = {"cinetpay_actif": "1", "cinetpay_site_id": "123456", "cinetpay_apikey": "cle-test"}
    rep = P.creer_paiement("CC2609006", 5000, suffixe="12345", cfg=cfg,
                           client={"code": "006", "nom": "Nabil DOREGO", "telephone": "0500000000"},
                           notify_url="https://outil.example.com/api/ipn/cinetpay",
                           return_url="https://outil.example.com/payer?code=006")
    assert rep["ok"] and rep["url"] == "https://pay.cinetpay.com/abc"
    assert rep["id"] == "CC2609006-12345"          # la référence reste en tête
    url, payload = faux.appels[0]
    assert url.endswith("/v2/payment")
    assert payload["site_id"] == "123456" and payload["apikey"] == "cle-test"
    assert payload["amount"] == 5000 and payload["currency"] == "XOF"
    assert payload["channels"] == "MOBILE_MONEY,CREDIT_CARD"
    assert payload["transaction_id"] == "CC2609006-12345"
    assert payload["notify_url"].endswith("/api/ipn/cinetpay")


def test_creer_paiement_refus_et_non_configure(monkeypatch):
    faux = FauxTransport({"payment": {"code": "100", "message": "Paramètres invalides"}})
    monkeypatch.setattr(P, "TRANSPORT", faux)
    cfg = {"cinetpay_actif": "1", "cinetpay_site_id": "123456", "cinetpay_apikey": "cle-test"}
    rep = P.creer_paiement("CC2609006", 5000, suffixe="12345", cfg=cfg)
    assert not rep["ok"] and "invalides" in rep["erreur"]
    # non configuré : aucune requête ne part
    rep = P.creer_paiement("CC2609006", 5000, suffixe="12345", cfg={"cinetpay_actif": "0"})
    assert not rep["ok"] and faux.appels[-1][1]["transaction_id"] == "CC2609006-12345"


def test_verifier_transaction(monkeypatch):
    faux = FauxTransport({"checkpay": {"code": "0", "data": {
        "payment_status": "ACCEPTED", "payment_amount": "5000", "operator_id": "0500000000"}}})
    monkeypatch.setattr(P, "TRANSPORT", faux)
    cfg = {"cinetpay_actif": "1", "cinetpay_site_id": "1", "cinetpay_apikey": "k"}
    verif = P.verifier_transaction("CC2609006-12345", cfg)
    assert verif == {"statut": "ACCEPTED", "montant": 5000, "client": "0500000000"}


# --------------------------------------------------------------------------- #
# Bouton « Payer maintenant » sur la page publique
# --------------------------------------------------------------------------- #

def test_bouton_payer_redirige_vers_cinetpay(client, monkeypatch):
    c, mod = client
    activer_cinetpay(mod)
    faux = FauxTransport({"payment": {"code": "0", "data": {"payment_url": "https://pay.cinetpay.com/xyz"}}})
    monkeypatch.setattr(P, "TRANSPORT", faux)
    r = c.post("/payer/005/en-ligne", data={"mois": "2026-09"})   # BAMBA Fatou, impayée en sept.
    assert r.status_code == 302
    assert r.headers["Location"] == "https://pay.cinetpay.com/xyz"
    payload = faux.appels[0][1]
    assert payload["transaction_id"].startswith("CC2609005-")
    assert payload["amount"] == 5000


def test_bouton_absent_si_non_configure(client):
    c, _ = client
    corps = c.get("/payer?code=005&mois=2026-09").get_data(as_text=True)
    assert "Payer maintenant" not in corps
    corps = c.get("/payer?code=005&mois=2026-09").get_data(as_text=True)
    activer_cinetpay(client[1])
    corps = c.get("/payer?code=005&mois=2026-09").get_data(as_text=True)
    assert "Payer 5 000 FCFA maintenant" in corps.replace("&#160;", " ").replace("\xa0", " ")


# --------------------------------------------------------------------------- #
# Notification instantanée (IPN) : le pointage passe à jour tout seul
# --------------------------------------------------------------------------- #

def test_ipn_credite_le_membre_automatiquement(client, monkeypatch):
    c, mod = client
    activer_cinetpay(mod)
    faux = FauxTransport({"checkpay": {"code": "0", "data": {
        "payment_status": "ACCEPTED", "payment_amount": "5000", "operator_id": "0511223344"}}})
    monkeypatch.setattr(P, "TRANSPORT", faux)

    r = c.post("/api/ipn/cinetpay", data={"transaction_id": "CC2609005-77777", "amount": "5000"})
    assert r.status_code == 200
    assert "BAMBA" in r.get_json()["message"]

    moi = c.get("/api/moi?code=005&mois=2026-09").get_json()
    assert moi["statut"] == "PAYE" and moi["verse"] == 5000

    with mod.app.app_context():
        ligne = mod.db().execute("SELECT canal, methode, statut, mois FROM paiements"
                                 " WHERE libelle = 'CC2609005-77777'").fetchone()
    assert tuple(ligne) == ("CinetPay", "ref", "RAPPROCHE", "2026-09")


def test_ipn_est_idempotente(client, monkeypatch):
    c, mod = client
    activer_cinetpay(mod)
    faux = FauxTransport({"checkpay": {"code": "0", "data": {
        "payment_status": "ACCEPTED", "payment_amount": "5000", "operator_id": "0511223344"}}})
    monkeypatch.setattr(P, "TRANSPORT", faux)
    for _ in range(3):
        c.post("/api/ipn/cinetpay", data={"transaction_id": "CC2609005-77777"})
    with mod.app.app_context():
        nb = mod.db().execute("SELECT COUNT(*) FROM paiements WHERE canal = 'CinetPay'").fetchone()[0]
    assert nb == 1


def test_ipn_ignorée_si_paiement_refuse_ou_non_configuré(client, monkeypatch):
    c, mod = client
    activer_cinetpay(mod)
    faux = FauxTransport({"checkpay": {"code": "0", "data": {"payment_status": "REFUSED"}}})
    monkeypatch.setattr(P, "TRANSPORT", faux)
    c.post("/api/ipn/cinetpay", data={"transaction_id": "CC2609005-77777"})
    with mod.app.app_context():
        nb = mod.db().execute("SELECT COUNT(*) FROM paiements WHERE canal = 'CinetPay'").fetchone()[0]
    assert nb == 0

    # sans configuration CinetPay : la notification ne fait rien (défense anti-fraude)
    with mod.app.app_context():
        mod.db().execute("UPDATE settings SET valeur='0' WHERE cle='cinetpay_actif'")
        mod.db().commit()
    c.post("/api/ipn/cinetpay", data={"transaction_id": "CC2609005-88888"})
    with mod.app.app_context():
        nb = mod.db().execute("SELECT COUNT(*) FROM paiements WHERE canal = 'CinetPay'").fetchone()[0]
    assert nb == 0
