"""
Cycle mensuel des cotisations : échéancier automatique des tâches du trésorier.

Chaque mois, une liste de tâches est générée à partir de la date d'échéance
configurée. Une tâche est « faite » quand le trésorier la marque comme telle ;
sinon elle passe en retard dès que sa date est dépassée.

Ce module est purement logique (pas d'accès base) et testé par
tests/test_workflow.py.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import date
from datetime import timedelta as _timedelta

from moteur import dernier_jour, echeance, libelle_mois, normaliser_mois

# Statuts d'une tâche du cycle
A_VENIR = "A_VENIR"
A_FAIRE = "A_FAIRE"      # arrivée à échéance, à traiter aujourd'hui
EN_RETARD = "EN_RETARD"
FAIT = "FAIT"

ACTIONS = {
    "ouvrir": "Ouvre la période : publication du montant et des consignes aux membres.",
    "relancer": "Génère les messages WhatsApp personnalisés pour les membres en retard.",
    "pointage": "Importe le relevé mobile money et lance le rapprochement automatique.",
    "etat": "Génère l'état imprimable signé, à archiver et présenter en assemblée.",
    "reporter": "Bascule les reliquats sur le mois suivant et archive la période.",
}


@dataclass
class Tache:
    cle: str
    titre: str
    jour: int
    echeance: str
    statut: str
    action: str | None
    fait_le: str | None = None
    note: str = ""


def _jour(mois: str, jour: int) -> str:
    """Date « AAAA-MM-JJ » bornée au mois : au 1er au plus tôt, au dernier jour au plus tard."""
    m = normaliser_mois(mois)
    return f"{m}-{min(max(int(jour), 1), dernier_jour(m)):02d}"


def _avant(mois: str, jour: int, jours_avant: int) -> str:
    """« jour » moins N jours, sans jamais remonter avant le 1er du mois."""
    a, m = map(int, normaliser_mois(mois).split("-"))
    d = date(a, m, min(max(jour, 1), dernier_jour(mois)))
    d = max(d - _timedelta(days=jours_avant), date(a, m, 1))
    return d.isoformat()


def _apres(mois: str, jour: int, jours_apres: int) -> str:
    """« jour » plus N jours, sans jamais dépasser le dernier jour du mois."""
    a, m = map(int, normaliser_mois(mois).split("-"))
    d = date(a, m, min(max(jour, 1), dernier_jour(mois)))
    d = min(d + _timedelta(days=jours_apres), date(a, m, dernier_jour(mois)))
    return d.isoformat()


def cycle_mensuel(mois: str, jour_echeance: int = 10,
                  aujourd_hui: str | None = None,
                  taches_faites: dict[str, tuple[str, str]] | None = None) -> list[Tache]:
    """
    Construit l'échéancier d'un mois de cotisation.

    `taches_faites` associe la clé d'une tâche à (date de réalisation, note).
    Le statut de chaque tâche est calculé par rapport à `aujourd_hui`.
    """
    mois = normaliser_mois(mois)
    auj = normaliser_mois(aujourd_hui) if aujourd_hui and len(str(aujourd_hui)) == 7 \
        else (aujourd_hui or date.today().isoformat())
    faites = taches_faites or {}

    modele = [
        # (clé, titre, date d'échéance, action, explication)
        ("ouvrir", "Ouverture de la période de cotisation",
         _avant(mois, jour_echeance, 10), None,
         "Publier le montant, la date limite et la référence de chaque membre dans le groupe."),
        ("pointage_1", "Premier pointage des paiements reçus",
         _jour(mois, jour_echeance), "pointage",
         "Importer le relevé mobile money et lancer le rapprochement automatique."),
        ("relance_1", "Relance amicale (J+3 après l'échéance)",
         _apres(mois, jour_echeance, 3), "relancer",
         "Message individuel aux membres non à jour, avec leur référence."),
        ("relance_2", "Relance insistante (J+8)",
         _apres(mois, jour_echeance, 8), "relancer",
         "Deuxième message, copie au bureau du réseau."),
        ("relance_3", "Dernier avis avant suspension (J+15)",
         _apres(mois, jour_echeance, 15), "relancer",
         "Avis formel : sans règlement, l'accès aux services du réseau est suspendu."),
        ("etat", "Édition de l'état de pointage signé",
         _apres(mois, jour_echeance, 20), "etat",
         "Document signé par le trésorier et le président, archivé pour l'assemblée."),
        ("reporter", "Clôture et report des reliquats",
         _jour(mois, dernier_jour(mois)), "reporter",
         "Les reliquats sont reportés sur le mois suivant, la période est archivée."),
    ]

    taches = []
    for cle, titre, ech, action, note in modele:
        if cle in faites:
            statut, (fait_le, commentaire) = FAIT, faites[cle]
            note = commentaire or note
        elif auj > ech:
            statut = EN_RETARD
        elif auj == ech:
            statut = A_FAIRE
        else:
            statut = A_VENIR
        taches.append(Tache(cle=cle, titre=titre, jour=int(ech[8:10]), echeance=ech,
                            statut=statut, action=action, fait_le=faites.get(cle, (None, ""))[0],
                            note=note))
    return taches


def progression(taches: list[Tache]) -> dict:
    """Synthèse de l'avancement du cycle : utile pour la jauge du tableau de bord."""
    total = len(taches)
    fait = sum(1 for t in taches if t.statut == FAIT)
    retard = sum(1 for t in taches if t.statut == EN_RETARD)
    return {
        "total": total,
        "fait": fait,
        "en_retard": retard,
        "a_faire": sum(1 for t in taches if t.statut == A_FAIRE),
        "a_venir": sum(1 for t in taches if t.statut == A_VENIR),
        "pourcent": round(100.0 * fait / total, 1) if total else 0.0,
    }


def taches_en_retard(taches: list[Tache]) -> list[Tache]:
    return [t for t in taches if t.statut in (EN_RETARD, A_FAIRE)]
