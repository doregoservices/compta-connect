"""
Paiement en ligne automatique — Compta Connect.

Objectif : remplacer Chariow. Le membre clique sur « Payer », règle par
mobile money (Orange Money, MTN MoMo, Wave, Moov) ou carte, et l'agrégateur
CinetPay notifie l'application immédiatement (IPN). Le paiement est créé,
rapproché du membre via sa référence CCaamm### et le pointage passe à jour
SANS aucune intervention du trésorier.

Frais : CinetPay facture environ 3,5 % (négociable) contre 15 % chez
Chariow — soit 175 FCFA au lieu de 750 FCFA pour une cotisation de 5 000.

Le module ne dépend pas de Flask : l'application passe l'URL de notification,
ce qui le rend testable sans réseau (transport injectable).
"""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from typing import Callable, Optional

# API officielle CinetPay v2 (mêmes adresses en sandbox avec les clés sandbox)
URL_API = "https://api-checkout.cinetpay.com"
CHEMIN_PAIEMENT = "/v2/payment"
CHEMIN_VERIFICATION = "/v2/checkpay"

# Statuts renvoyés par checkpay
ST_ACCEPTE = "ACCEPTED"

# Transport HTTP injectable : None = réseau réel, sinon fonction de test.
TRANSPORT: Optional[Callable[[str, dict], dict]] = None


def config_ok(cfg: dict) -> bool:
    """Le paiement en ligne est actif et configuré ?"""
    return (str(cfg.get("cinetpay_actif", "0")) == "1"
            and bool((cfg.get("cinetpay_site_id") or "").strip())
            and bool((cfg.get("cinetpay_apikey") or "").strip()))


def transaction_id(reference: str, suffixe: str) -> str:
    """Identifiant unique CinetPay : la référence + un suffixe court.

    La référence reste lisible en tête de l'identifiant : le rapprochement
    automatique par référence fonctionne toujours (CinetPay renvoie ce même
    identifiant dans sa notification).
    """
    return f"{reference}-{suffixe}"[:30]


def _poster(url: str, payload: dict) -> dict:
    if TRANSPORT is not None:
        return TRANSPORT(url, payload)
    donnees = urllib.parse.urlencode(payload).encode("utf-8")
    req = urllib.request.Request(url, data=donnees,
                                 headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as rep:
        return json.loads(rep.read().decode("utf-8"))


def _base(cfg: dict) -> str:
    return (cfg.get("cinetpay_url_api") or URL_API).rstrip("/")


def creer_paiement(reference: str, montant: int, *, suffixe: str, cfg: dict,
                   client: Optional[dict] = None, notify_url: str = "",
                   return_url: str = "", description: str = "") -> dict:
    """
    Ouvre un paiement en ligne chez CinetPay.

    Retourne {"ok": True, "url": <page de paiement>, "id": <transaction_id>}
    ou {"ok": False, "erreur": <message>}.
    """
    if not config_ok(cfg):
        return {"ok": False, "erreur": "Le paiement en ligne n'est pas configuré "
                                       "(Paramètres → Paiement en ligne)."}
    if int(montant) < 100:
        return {"ok": False, "erreur": "Montant minimum de 100 FCFA."}
    client = client or {}
    tid = transaction_id(reference, suffixe)
    payload = {
        "site_id": cfg["cinetpay_site_id"].strip(),
        "apikey": cfg["cinetpay_apikey"].strip(),
        "transaction_id": tid,
        "amount": int(montant),
        "currency": "XOF",
        "description": description or f"Cotisation ComptaConnect {reference}",
        "channels": "MOBILE_MONEY,CREDIT_CARD",
        "notify_url": notify_url,
        "return_url": return_url,
        "customer_id": str(client.get("code", reference))[:5] or "0",
        "customer_name": (client.get("nom", "").split() or ["Membre"])[0][:30],
        "customer_surname": " ".join(client.get("nom", "").split()[1:])[:30] or "-",
        "phone_number": client.get("telephone", "") or "",
        "customer_email_address": client.get("email", "") or "",
        "customer_city": client.get("ville", "") or "",
        "customer_country": client.get("pays", "") or "",
        "lang": "FR",
    }
    try:
        rep = _poster(_base(cfg) + CHEMIN_PAIEMENT, payload)
    except Exception as exc:  # réseau coupé, DNS, etc.
        return {"ok": False, "erreur": f"Service de paiement injoignable ({exc})."}
    if str(rep.get("code")) != "0":
        return {"ok": False,
                "erreur": rep.get("message") or rep.get("description") or "Refus du service."}
    url = (rep.get("data") or {}).get("payment_url", "")
    if not url:
        return {"ok": False, "erreur": "Réponse du service sans lien de paiement."}
    return {"ok": True, "url": url, "id": tid}


def verifier_transaction(tid: str, cfg: dict) -> dict:
    """
    Demande à CinetPay le statut définitif d'une transaction (méthode
    recommandée : ne jamais faire confiance au seul POST de notification).

    Retourne {"statut": ACCEPTED|PENDING|..., "montant": int, "client": str}.
    """
    if not config_ok(cfg):
        return {"statut": "NON_CONFIGURE", "montant": 0, "client": ""}
    try:
        rep = _poster(_base(cfg) + CHEMIN_VERIFICATION, {
            "site_id": cfg["cinetpay_site_id"].strip(),
            "apikey": cfg["cinetpay_apikey"].strip(),
            "transaction_id": tid,
        })
    except Exception:
        return {"statut": "ERREUR", "montant": 0, "client": ""}
    donnees = rep.get("data") or {}
    try:
        montant = int(float(str(donnees.get("payment_amount", 0)).replace(" ", "")))
    except ValueError:
        montant = 0
    return {
        "statut": str(donnees.get("payment_status", "INCONNU")).upper(),
        "montant": montant,
        "client": donnees.get("operator_id", "") or donnees.get("customer_name", ""),
    }
