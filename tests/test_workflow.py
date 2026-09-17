"""Tests de l'échéancier mensuel (module workflow)."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))
import workflow as W


def cles(taches):
    return [t.cle for t in taches]


def test_cycle_complet_septembre():
    t = W.cycle_mensuel("2026-09", jour_echeance=10, aujourd_hui="2026-09-01")
    assert cles(t) == ["ouvrir", "pointage_1", "relance_1", "relance_2", "relance_3",
                       "etat", "reporter"]
    # échéance au 10 : ouverture 10 jours avant, relances à J+3, J+8, J+15
    dates = {x.cle: x.echeance for x in t}
    assert dates["ouvrir"] == "2026-09-01"      # 10 jours avant le 10, sans remonter avant le 1er
    assert dates["pointage_1"] == "2026-09-10"
    assert dates["relance_1"] == "2026-09-13"
    assert dates["relance_2"] == "2026-09-18"
    assert dates["relance_3"] == "2026-09-25"
    assert dates["etat"] == "2026-09-30"        # 10 + 20 = 30
    assert dates["reporter"] == "2026-09-30"    # dernier jour du mois


def test_dates_bornees_a_la_fin_du_mois():
    """Échéance au 25 en février : aucune tâche ne doit déborder du mois."""
    t = W.cycle_mensuel("2027-02", jour_echeance=25, aujourd_hui="2027-02-01")
    for x in t:
        assert x.echeance.startswith("2027-02"), x
    assert max(x.echeance for x in t) == "2027-02-28"


def test_statuts_selon_la_date():
    t = W.cycle_mensuel("2026-09", jour_echeance=10, aujourd_hui="2026-09-14")
    par_cle = {x.cle: x.statut for x in t}
    assert par_cle["ouvrir"] == W.EN_RETARD       # 31/08 dépassé
    assert par_cle["pointage_1"] == W.EN_RETARD   # 10/09 dépassé
    assert par_cle["relance_1"] == W.EN_RETARD    # 13/09 dépassé
    assert par_cle["relance_2"] == W.A_VENIR      # 18/09 à venir
    assert par_cle["reporter"] == W.A_VENIR


def test_tache_du_jour():
    t = W.cycle_mensuel("2026-09", jour_echeance=10, aujourd_hui="2026-09-10")
    assert next(x for x in t if x.cle == "pointage_1").statut == W.A_FAIRE


def test_tache_marquee_faite():
    t = W.cycle_mensuel("2026-09", jour_echeance=10, aujourd_hui="2026-09-20",
                        taches_faites={"ouvrir": ("2026-08-31", "Publié dans le groupe")})
    faire = next(x for x in t if x.cle == "ouvrir")
    assert faire.statut == W.FAIT
    assert faire.fait_le == "2026-08-31"
    assert faire.note == "Publié dans le groupe"


def test_progression():
    t = W.cycle_mensuel("2026-09", jour_echeance=10, aujourd_hui="2026-09-20",
                        taches_faites={"ouvrir": ("2026-08-31", ""),
                                       "pointage_1": ("2026-09-10", ""),
                                       "relance_1": ("2026-09-13", "")})
    p = W.progression(t)
    assert p["total"] == 7 and p["fait"] == 3
    assert p["a_venir"] + p["en_retard"] + p["a_faire"] + p["fait"] == 7
    assert p["pourcent"] == 42.9


def test_taches_en_retard_inclut_celles_du_jour():
    t = W.cycle_mensuel("2026-09", jour_echeance=10, aujourd_hui="2026-09-10")
    en_retard = W.taches_en_retard(t)
    assert "pointage_1" in cles(en_retard)
    assert "ouvrir" in cles(en_retard)


def test_cycle_mois_precedent_non_bloquant():
    """Un mois déjà clos reste lisible, tout est en retard tant que rien n'est marqué."""
    t = W.cycle_mensuel("2026-01", jour_echeance=10, aujourd_hui="2026-09-17")
    assert all(x.statut == W.EN_RETARD for x in t)


def test_annee_bissectile():
    t = W.cycle_mensuel("2028-02", jour_echeance=20, aujourd_hui="2028-02-01")
    assert next(x for x in t if x.cle == "reporter").echeance == "2028-02-29"
