"""Tests du moteur de pointage : références, rapprochement, statuts mensuels."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import moteur as M


def membre(id_, code, nom, tel="", cot=5000, actif=True, exonere=False):
    return M.Membre(id=id_, code=code, nom=nom, telephone=tel, cotisation=cot,
                    actif=actif, exonere=exonere)


def paiement(id_, montant, mois="", membre_id=None, tel="", expediteur="", libelle="",
             date="2026-09-05"):
    return M.Paiement(id=id_, date=date, montant=montant, mois=mois, membre_id=membre_id,
                      telephone=tel, expediteur=expediteur, libelle=libelle)


# --------------------------------------------------------------------------- #
# Périodes et références
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize("entree,attendu", [
    ("2026-09", "2026-09"), ("septembre 2026", "2026-09"), ("Septembre 2026", "2026-09"),
    ("09/2026", "2026-09"), ("2026-9", "2026-09"), ("février 2027", "2027-02"),
    ("janvier 2026", "2026-01"),
])
def test_normaliser_mois(entree, attendu):
    assert M.normaliser_mois(entree) == attendu


def test_normaliser_mois_rejette_l_invalide():
    with pytest.raises(ValueError):
        M.normaliser_mois("13/2026")


def test_mois_suivant_et_echeance():
    assert M.mois_suivant("2026-12") == "2027-01"
    assert M.mois_suivant("2026-01") == "2026-02"
    assert M.echeance("2026-02", 31) == "2026-02-28"   # borné au dernier jour
    assert M.echeance("2026-09", 10) == "2026-09-10"


def test_reference_et_lecture_inverse():
    ref = M.reference("2026-09", "42")
    assert ref == "CC2609042"
    assert M.analyser_reference(f"Transfert reçu de KONE AMI ref {ref}") == ("2026-09", "042")
    assert M.analyser_reference("cc 26 09 042") == ("2026-09", "042")
    assert M.analyser_reference("motif illisible") is None


def test_analyser_reference_ignore_les_faux_positifs():
    assert M.analyser_reference("numéro 9999999999 trop long") is None
    assert M.analyser_reference("mois invalide CC2613001") is None


@pytest.mark.parametrize("entree,attendu", [
    ("+225 07 08 09 10 11", "2250708091011"),
    ("02250708091011", "2250708091011"),
    ("0708091011", "2250708091011"),
    ("", ""),
])
def test_telephone_normalise(entree, attendu):
    assert M.telephone_normalise(entree) == attendu


# --------------------------------------------------------------------------- #
# Rapprochement automatique
# --------------------------------------------------------------------------- #

MEMBRES = [
    membre(1, "001", "KOUASSI Aya Michelle", "0708112233"),
    membre(2, "002", "YAO Kouadio Serge", "0544556677"),
    membre(3, "003", "TRAORE Aminata", "0102030405"),
]


def test_rapprochement_par_reference():
    p = paiement(1, 5000, libelle="Transfert reçu ref CC2609002")
    M.rapprocher_paiement(p, MEMBRES, "2026-10")
    assert (p.membre_id, p.mois, p.methode) == (2, "2026-09", M.M_REF)


def test_la_reference_prime_sur_le_mois_par_defaut():
    """La référence indique septembre : le mois par défaut (octobre) ne doit pas l'écraser."""
    p = paiement(1, 5000, libelle="CC2609001")
    M.rapprocher_paiement(p, MEMBRES, "2026-10")
    assert p.mois == "2026-09"


def test_rapprochement_par_telephone():
    p = paiement(1, 5000, tel="+225 01 02 03 04 05")
    M.rapprocher_paiement(p, MEMBRES, "2026-09")
    assert (p.membre_id, p.methode) == (3, M.M_TELEPHONE)


def test_rapprochement_par_nom():
    p = paiement(1, 5000, expediteur="YAO Kouadio Serge")
    M.rapprocher_paiement(p, MEMBRES, "2026-09")
    assert (p.membre_id, p.methode) == (2, M.M_NOM)


def test_rapprochement_par_montant_si_un_seul_candidat():
    ms = [membre(1, "001", "A", cot=5000), membre(2, "002", "B", cot=10000)]
    p = paiement(1, 10000)
    M.rapprocher_paiement(p, ms, "2026-09")
    assert (p.membre_id, p.methode) == (2, M.M_MONTANT)


def test_aucun_rapprochement_si_ambigu():
    p = paiement(1, 5000)
    M.rapprocher_paiement(p, MEMBRES, "2026-09")
    assert p.membre_id is None and p.methode == M.M_AUCUN


def test_rapprochement_manuel_non_ecrase():
    p = paiement(1, 5000, membre_id=1, mois="2026-08", libelle="CC2609002")
    p.statut, p.methode = "RAPPROCHE", M.M_MANUEL
    M.rapprocher_paiement(p, MEMBRES, "2026-09")
    assert (p.membre_id, p.mois) == (1, "2026-08")


def test_rapprocher_tout():
    ps = [paiement(1, 5000, libelle="CC2609001"), paiement(2, 5000, tel="0544556677"),
          paiement(3, 5000)]
    M.rapprocher_tout(ps, MEMBRES, "2026-09")
    assert [p.membre_id for p in ps] == [1, 2, None]


# --------------------------------------------------------------------------- #
# Pointage mensuel
# --------------------------------------------------------------------------- #

def test_pointage_statuts_et_totaux():
    ms = MEMBRES + [membre(4, "004", "GNAMIEN Éric", cot=5000, exonere=True),
                    membre(5, "005", "SORTI du réseau", cot=5000, actif=False)]
    ps = [
        paiement(1, 5000, mois="2026-09", membre_id=1),                    # à jour
        paiement(2, 2000, mois="2026-09", membre_id=2),                    # partiel
        paiement(3, 8000, mois="2026-09", membre_id=3),                    # avance
        paiement(4, 5000, mois="2026-10", membre_id=3),                    # mois suivant
    ]
    pt = M.pointage(ms, ps, "2026-09")
    par_id = {l["membre"].id: l for l in pt["lignes"]}

    assert par_id[1]["statut"] == M.ST_PAYE
    assert par_id[2]["statut"] == M.ST_PARTIEL and par_id[2]["reliquat"] == 3000
    assert par_id[3]["statut"] == M.ST_AVANCE and par_id[3]["avances"] == 5000
    assert par_id[4]["statut"] == M.ST_EXONERE
    assert 5 not in par_id, "un membre inactif ne figure pas au pointage"

    t = pt["totaux"]
    assert t["du"] == 15000                     # 3 cotisants (l'exonéré ne compte pas)
    assert t["verse"] == 15000
    assert t["nb_membres"] == 4
    assert t["nb_payes"] == 2 and t["nb_partiels"] == 1 and t["nb_impayes"] == 0


def test_pointage_impayes_et_taux():
    ps = [paiement(1, 5000, mois="2026-09", membre_id=1)]
    t = M.pointage(MEMBRES, ps, "2026-09")["totaux"]
    assert t["nb_impayes"] == 2
    assert t["manquant"] == 10000
    assert t["taux_montant"] == 33.3
    assert t["taux"] == 33.3


def test_pointage_mois_vide():
    t = M.pointage(MEMBRES, [], "2026-09")["totaux"]
    assert t["verse"] == 0 and t["nb_impayes"] == 3 and t["taux"] == 0.0


def test_un_paiement_d_un_autre_mois_ne_compte_pas():
    ps = [paiement(1, 5000, mois="2026-08", membre_id=1)]
    assert M.pointage(MEMBRES, ps, "2026-09")["lignes"][0]["statut"] == M.ST_IMPAYE


# --------------------------------------------------------------------------- #
# Relances
# --------------------------------------------------------------------------- #

def _lisible(txt: str) -> str:
    """Remplace les espaces insécables fines par des espaces simples pour comparer."""
    return txt.replace("\u202f", " ").replace("\xa0", " ")


def test_message_relance_impaye():
    pt = M.pointage(MEMBRES, [], "2026-09")
    ligne = pt["lignes"][0]
    msg = _lisible(M.message_relance(ligne, "Compta Connect", "Wave", "Caisse du réseau"))
    assert msg.startswith("Bonjour KOUASSI")
    assert ligne["reference"] in msg
    assert "5 000 FCFA" in msg
    assert "Wave" in msg and "Caisse du réseau" in msg


def test_message_relance_partiel_indique_le_reliquat():
    ps = [paiement(1, 2000, mois="2026-09", membre_id=1)]
    ligne = M.pointage(MEMBRES, ps, "2026-09")["lignes"][0]
    msg = _lisible(M.message_relance(ligne, "Compta Connect"))
    assert "reste" in msg
    assert "3 000 FCFA" in msg
    assert ligne["reference"] in msg
