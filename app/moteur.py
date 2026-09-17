"""
Moteur de pointage automatique des cotisations — Compta Connect.

Ce module contient toute la logique métier, sans aucune dépendance web :
 - génération de la référence de paiement (code membre + mois),
 - rapprochement (matching) d'un paiement avec un membre,
 - calcul du statut mensuel de chaque membre (payé / partiel / impayé),
 - gestion des avances (trop-perçu) et des retards.

C'est ce fichier qui est testé par tests/test_moteur.py.
"""

from __future__ import annotations

import calendar
import re
from dataclasses import dataclass
from typing import Iterable, Optional

PREFIXE = "CC"

# Statuts possibles d'une ligne du tableau de pointage mensuel.
ST_PAYE = "PAYE"
ST_PARTIEL = "PARTIEL"
ST_IMPAYE = "IMPAYE"
ST_AVANCE = "AVANCE"        # membre qui a payé en avance un mois futur
ST_EXONERE = "EXONERE"      # membre dispensé de cotisation
ST_NON_ACTIF = "NON_ACTIF"  # membre suspendu / sorti du réseau

# Codes courts utilisés par le rapprochement automatique.
M_REF = "ref"        # référence CC AAMM### trouvée dans le libellé  -> certain
M_TELEPHONE = "tel"  # numéro de téléphone de l'émetteur              -> certain
M_MONTANT = "montant"  # montant exact + mois, un seul impayé        -> probable
M_NOM = "nom"        # nom dans le libellé                           -> probable
M_MANUEL = "manuel"  # rapproché par le trésorier                    -> certain
M_AUCUN = "aucun"


# --------------------------------------------------------------------------- #
# Périodes (mois de cotisation)
# --------------------------------------------------------------------------- #

def normaliser_mois(mois: str) -> str:
    """« septembre 2026 », « 09/2026 », « 2026-9 » -> « 2026-09 »."""
    if not mois:
        raise ValueError("mois vide")
    mois = str(mois).strip().lower().replace("/", "-").replace(" ", "-")
    mois = re.sub(r"-+", "-", mois)
    numeros = {
        "janvier": 1, "fevrier": 2, "février": 2, "mars": 3, "avril": 4,
        "mai": 5, "juin": 6, "juillet": 7, "aout": 8, "août": 8,
        "septembre": 9, "octobre": 10, "novembre": 11, "decembre": 12,
        "décembre": 12, "jan": 1, "fev": 2, "fév": 2, "mar": 3, "avr": 4,
        "jun": 6, "jui": 7, "juil": 7, "aou": 8, "aoû": 8, "sep": 9,
        "sept": 9, "oct": 10, "nov": 11, "dec": 12, "déc": 12,
    }
    morceaux = mois.split("-")
    if morceaux[0] in numeros:
        m, a = numeros[morceaux[0]], morceaux[1]
    elif len(morceaux[0]) == 4:
        a, m = morceaux[0], morceaux[1]
    else:
        m, a = morceaux[0], morceaux[1]
    a, m = int(a), int(m)
    if not 1 <= m <= 12:
        raise ValueError(f"mois invalide : {mois}")
    if not 2000 <= a <= 2100:
        raise ValueError(f"année invalide : {mois}")
    return f"{a:04d}-{m:02d}"


def mois_court(mois: str) -> str:
    """« 2026-09 » -> « 2609 » (utilisé dans la référence de paiement)."""
    m = normaliser_mois(mois)
    return m[2:4] + m[5:7]


def mois_suivant(mois: str) -> str:
    a, m = map(int, normaliser_mois(mois).split("-"))
    return f"{a + 1}-01" if m == 12 else f"{a:04d}-{m + 1:02d}"


def dernier_jour(mois: str) -> int:
    a, m = map(int, normaliser_mois(mois).split("-"))
    return calendar.monthrange(a, m)[1]


def libelle_mois(mois: str) -> str:
    noms = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet",
            "aout", "septembre", "octobre", "novembre", "décembre"]
    a, m = map(int, normaliser_mois(mois).split("-"))
    return f"{noms[m - 1]} {a}"


def echeance(mois: str, jour: int = 10) -> str:
    """Date limite de cotisation : « AAAA-MM-JJ », bornée au dernier jour du mois."""
    m = normaliser_mois(mois)
    return f"{m}-{min(max(int(jour), 1), dernier_jour(m)):02d}"


# --------------------------------------------------------------------------- #
# Référence de paiement
# --------------------------------------------------------------------------- #

def reference(mois: str, code_membre: str) -> str:
    """
    Référence unique à inscrire dans le motif du mobile money.

    Ex. : CC + 2609 + 042  ->  CC2609042  (cotisation de septembre 2026 du membre 042)

    C'est la clé du pointage automatique : elle contient à la fois
    le mois, le membre et elle est lisible en un coup d'œil.
    """
    return f"{PREFIXE}{mois_court(mois)}{str(code_membre).zfill(3)}"


def analyser_reference(texte: str) -> Optional[tuple[str, str]]:
    """
    Extrait une référence Compta Connect d'un libellé quelconque.
    Retourne (« 2026-09 », « 042 ») ou None.

    Tolérant : majuscules/minuscules, espaces, tirets, préfixe manquant.
    « Transfert reçu de KONE AMI ref CC2609042 »  -> (« 2026-09 », « 042 »)
    « cc 26 09 042 »                              -> (« 2026-09 », « 042 »)
    """
    if not texte:
        return None
    t = re.sub(r"[^A-Z0-9]", "", str(texte).upper())
    # 1) forme complète avec préfixe : CC + 7 chiffres (aamm + code membre sur 3 chiffres)
    m = re.search(r"CC(\d{7})", t)
    if not m:
        # 2) 7 chiffres nus (le membre a oublié le préfixe)
        m = re.search(r"(?<!\d)(\d{7})(?!\d)", t)
        if not m:
            return None
    chiffres = m.group(1)
    aa, mm, code = chiffres[0:2], chiffres[2:4], chiffres[4:7]
    annee = 2000 + int(aa)
    if not 1 <= int(mm) <= 12:
        return None
    if not 2020 <= annee <= 2099:
        return None
    return f"{annee:04d}-{mm}", code


def telephone_normalise(numero: str) -> str:
    """
    Normalise un numéro ivoirien pour la comparaison.

    « +225 07 08 09 10 11 », « 02250708091011 », « 0708091011 » -> « 2250708091011 »
    Les numéros locaux à 8 ou 10 chiffres reçoivent l'indicatif 225 ;
    le préfixe d'appel national « 0 » placé devant l'indicatif est retiré.
    """
    d = re.sub(r"\D", "", str(numero or ""))
    if not d:
        return ""
    if d.startswith("00"):
        d = d[2:]
    if d.startswith("0") and len(d) in (9, 11, 14):   # 0 + 225 + numéro local (8 ou 10 chiffres)
        d = d[1:]
    if len(d) in (8, 10):                             # numéro local sans indicatif
        d = "225" + d
    return d


def _accent_min(texte: str) -> str:
    import unicodedata
    t = unicodedata.normalize("NFKD", str(texte or ""))
    t = "".join(c for c in t if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9 ]", " ", t.lower()).strip()


def _mots(texte: str) -> set[str]:
    return {m for m in _accent_min(texte).split() if len(m) > 2}


def correspondance_nom(a: str, b: str) -> bool:
    """Vrai si deux libellés de nom désignent plausiblement la même personne."""
    ma, mb = _mots(a), _mots(b)
    if not ma or not mb:
        return False
    communs = ma & mb
    return len(communs) >= 2 and len(communs) >= min(len(ma), len(mb)) - 1


# --------------------------------------------------------------------------- #
# Modèles
# --------------------------------------------------------------------------- #

@dataclass
class Membre:
    id: int
    code: str
    nom: str
    telephone: str = ""
    cotisation: int = 0
    actif: bool = True
    exonere: bool = False
    email: str = ""


@dataclass
class Paiement:
    id: int
    date: str
    montant: int
    canal: str = ""
    expediteur: str = ""
    telephone: str = ""
    libelle: str = ""
    mois: str = ""
    membre_id: Optional[int] = None
    statut: str = "NON_RAPPROCHE"
    methode: str = M_AUCUN


# --------------------------------------------------------------------------- #
# Rapprochement automatique
# --------------------------------------------------------------------------- #

def rapprocher_paiement(
    paiement: Paiement,
    membres: Iterable[Membre],
    mois_defaut: str = "",
) -> Paiement:
    """
    Affecte un paiement à un membre et à un mois de cotisation.

    Ordre de priorité (du plus fiable au plus approximatif) :
      1. la référence CCaamm### présente dans le libellé  -> certain
      2. le numéro de téléphone de l'émetteur             -> certain
      3. le nom de l'émetteur dans le libellé             -> probable
      4. montant exact + mois par défaut, s'il n'y a qu'un seul
         membre actif impayé pour ce mois                  -> probable

    Le paiement déjà rapproché manuellement n'est jamais écrasé.
    """
    membres = list(membres)
    if paiement.statut == "RAPPROCHE" and paiement.methode == M_MANUEL:
        return paiement

    # --- 1. référence -------------------------------------------------------
    ref = analyser_reference(paiement.libelle)
    if ref:
        mois, code = ref
        candidat = next((m for m in membres if str(m.code).zfill(3) == code.zfill(3)), None)
        if candidat:
            paiement.membre_id = candidat.id
            paiement.mois = mois
            paiement.statut = "RAPPROCHE"
            paiement.methode = M_REF
            return paiement

    # --- 2. téléphone -------------------------------------------------------
    tel = telephone_normalise(paiement.telephone)
    if tel:
        candidats = [m for m in membres if telephone_normalise(m.telephone) == tel]
        if len(candidats) == 1:
            paiement.membre_id = candidats[0].id
            paiement.mois = mois_defaut or paiement.mois
            paiement.statut = "RAPPROCHE"
            paiement.methode = M_TELEPHONE
            return paiement

    # --- 3. nom dans le libellé --------------------------------------------
    if paiement.expediteur:
        candidats = [m for m in membres if correspondance_nom(m.nom, paiement.expediteur)]
        if len(candidats) == 1:
            paiement.membre_id = candidats[0].id
            paiement.mois = mois_defaut or paiement.mois
            paiement.statut = "RAPPROCHE"
            paiement.methode = M_NOM
            return paiement

    # --- 4. montant + mois par défaut --------------------------------------
    if mois_defaut and paiement.montant:
        dus = [
            m for m in membres
            if m.actif and not m.exonere and m.cotisation == paiement.montant
        ]
        if len(dus) == 1:
            paiement.membre_id = dus[0].id
            paiement.mois = mois_defaut
            paiement.statut = "RAPPROCHE"
            paiement.methode = M_MONTANT
            return paiement

    paiement.methode = M_AUCUN
    return paiement


def rapprocher_tout(paiements: Iterable[Paiement], membres: Iterable[Membre],
                    mois_defaut: str = "") -> list[Paiement]:
    """Rapproche une liste entière de paiements (import de relevé)."""
    membres = list(membres)
    return [rapprocher_paiement(p, membres, mois_defaut) for p in paiements]


# --------------------------------------------------------------------------- #
# Pointage mensuel
# --------------------------------------------------------------------------- #

def pointage(membres: Iterable[Membre], paiements: Iterable[Paiement],
             mois: str) -> dict:
    """
    Construit le tableau de pointage d'un mois donné.

    Retourne un dict :
      mois, echeance_calculee, lignes [{membre, verse, statut, reliquat, ...}],
      totaux {du, verse, nb_payes, nb_partiels, nb_impayes, taux, avances}
    """
    mois = normaliser_mois(mois)
    lignes, verse_total, du_total = [], 0, 0
    nb_payes = nb_partiels = nb_impayes = nb_avances = 0

    paiements = list(paiements)
    for m in membres:
        if not m.actif:
            continue
        montant_du = 0 if m.exonere else int(m.cotisation or 0)
        du_total += montant_du

        recus = [p for p in paiements
                 if p.membre_id == m.id and normaliser_mois(p.mois or "0000-01") == mois]
        verse = sum(int(p.montant) for p in recus)
        verse_total += verse

        # avance = ce que le membre a payé pour des mois postérieurs
        avances = sum(
            int(p.montant) for p in paiements
            if p.membre_id == m.id and p.mois and normaliser_mois(p.mois) > mois
        )

        if montant_du == 0:
            statut = ST_EXONERE
        elif verse >= montant_du:
            statut = ST_AVANCE if verse > montant_du else ST_PAYE
        elif verse > 0:
            statut = ST_PARTIEL
        else:
            statut = ST_IMPAYE

        if statut == ST_EXONERE:
            pass
        elif statut in (ST_PAYE, ST_AVANCE):
            nb_payes += 1
            if statut == ST_AVANCE:
                nb_avances += 1
        elif statut == ST_PARTIEL:
            nb_partiels += 1
        else:
            nb_impayes += 1

        lignes.append({
            "membre": m,
            "mois": mois,
            "reference": reference(mois, m.code),
            "du": montant_du,
            "verse": verse,
            "reliquat": max(0, montant_du - verse),
            "statut": statut,
            "avances": avances,
            "paiements": recus,
            "nb_paiements": len(recus),
        })

    denominateur = nb_payes + nb_partiels + nb_impayes
    return {
        "mois": mois,
        "libelle": libelle_mois(mois),
        "lignes": lignes,
        "totaux": {
            "du": du_total,
            "verse": verse_total,
            "manquant": max(0, du_total - verse_total),
            "nb_membres": len(lignes),
            "nb_payes": nb_payes,
            "nb_partiels": nb_partiels,
            "nb_impayes": nb_impayes,
            "nb_avances": nb_avances,
            "taux": round(100.0 * nb_payes / denominateur, 1) if denominateur else 0.0,
            "taux_montant": round(100.0 * verse_total / du_total, 1) if du_total else 0.0,
        },
    }


def fcfa(montant) -> str:
    """1500 -> « 1 500 » (séparateur de milliers français, insécable)."""
    return f"{int(montant or 0):,}".replace(",", "\u202f")


def message_relance(ligne: dict, reseau: str = "Compta Connect",
                    canal: str = "", destinataire_caisse: str = "") -> str:
    """Message WhatsApp de relance, personnalisé par membre et par mois."""
    m = ligne["membre"]
    mois_txt = libelle_mois(ligne.get("mois", "2026-01"))
    prenom = m.nom.split()[0] if m.nom else "cher membre"
    partiel = ligne["statut"] == ST_PARTIEL

    if partiel:
        corps = (f"Bonjour {prenom}, il te reste {fcfa(ligne['reliquat'])} FCFA "
                 f"à régler sur ta cotisation {reseau} de {mois_txt}.")
    else:
        corps = (f"Bonjour {prenom}, ta cotisation {reseau} de {mois_txt} "
                 f"n'est pas encore enregistrée.")

    lignes = [
        "",
        f"Montant à régler : {fcfa(ligne['reliquat'] if partiel else ligne['du'])} FCFA",
        f"Motif OBLIGATOIRE : {ligne['reference']}",
    ]
    if canal:
        lignes.append(f"Paiement : {canal}" + (f" — {destinataire_caisse}" if destinataire_caisse else ""))
    lignes += ["", "Merci d'envoyer la capture du reçu après paiement. 🙏"]
    return corps + "\n".join(lignes)
