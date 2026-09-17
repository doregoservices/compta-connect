"""
Compta Connect — plateforme de gestion de la communauté.

Modules : membres · cotisations (pointage automatique) · formations ·
          offres d'emploi · activités du réseau.

Application Flask + SQLite, aucune dépendance à un service externe.
Lancer :  python3 app/app.py   puis ouvrir http://localhost:8000
"""

from __future__ import annotations

import csv
import io
import os
import re
import sqlite3
import sys
from datetime import date, datetime
from functools import wraps
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from flask import (Flask, flash, g, jsonify, redirect, render_template, request,
                   send_file, session, url_for)

import moteur as M
import paiement_en_ligne as P
import qrcode as QR
import workflow as W

BASE = Path(__file__).resolve().parent
DB = Path(os.environ.get("COMPTA_DB") or (BASE / "compta_connect.db"))

app = Flask(__name__, template_folder=str(BASE / "templates"),
            static_folder=str(BASE / "static"))
app.secret_key = os.environ.get("SECRET_KEY", "compta-connect-dev")

CONFIG_DEFAUT = {
    "reseau": "ComptaConnect",
    "slogan": "Le réseau des professionnels de la comptabilité",
    "cotisation": 5000,
    "jour_echeance": 10,
    "devise": "FCFA",
    "caisse_nom": "Caisse du réseau",
    "caisse_telephone": "",
    "canal_wave": "1", "wave_numero": "", "wave_nom": "",
    "canal_om": "1", "om_numero": "", "om_nom": "",
    "canal_mtn": "0", "mtn_numero": "", "mtn_nom": "",
    "canal_banque": "0", "banque_nom": "", "banque_iban": "",
    "instructions": "",
    "tresorier": "Cabinet GSC — Basile EKLOU", "tresorier_tel": "+225 05 55 99 20 04",
    "contact_email": "supportcomptaconnect@gmail.com",
    "site_web": "www.comptaconnect.com",
    "groupe_whatsapp": "",
    "page_facebook": "",
    # relais SMTP pour l'envoi automatique des relances (facultatif)
    "smtp_hote": "", "smtp_port": "587", "smtp_utilisateur": "",
    "smtp_motdepasse": "", "smtp_expediteur": "",
    # paiement en ligne automatique (CinetPay — remplace Chariow)
    "cinetpay_actif": "0", "cinetpay_site_id": "", "cinetpay_apikey": "",
    "cinetpay_url_api": P.URL_API,
    "url_publique": "",
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS membres (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    nom TEXT NOT NULL,
    telephone TEXT DEFAULT '',
    ville TEXT DEFAULT '',
    specialite TEXT DEFAULT '',
    email TEXT DEFAULT '',
    cotisation INTEGER DEFAULT 0,
    date_adhesion TEXT DEFAULT '',
    actif INTEGER DEFAULT 1,
    exonere INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS paiements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date TEXT NOT NULL,
    montant INTEGER NOT NULL,
    canal TEXT DEFAULT '',
    expediteur TEXT DEFAULT '',
    telephone TEXT DEFAULT '',
    libelle TEXT DEFAULT '',
    mois TEXT DEFAULT '',
    membre_id INTEGER,
    statut TEXT DEFAULT 'NON_RAPPROCHE',
    methode TEXT DEFAULT 'aucun',
    FOREIGN KEY (membre_id) REFERENCES membres(id)
);
CREATE TABLE IF NOT EXISTS settings (cle TEXT PRIMARY KEY, valeur TEXT);
CREATE TABLE IF NOT EXISTS taches (
    cle TEXT NOT NULL,
    mois TEXT NOT NULL,
    fait_le TEXT DEFAULT '',
    note TEXT DEFAULT '',
    PRIMARY KEY (cle, mois)
);

CREATE TABLE IF NOT EXISTS formations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titre TEXT NOT NULL,
    formateur TEXT DEFAULT '',
    date TEXT DEFAULT '',
    heure TEXT DEFAULT '',
    duree TEXT DEFAULT '',
    lieu TEXT DEFAULT '',
    mode TEXT DEFAULT 'En ligne',
    cout INTEGER DEFAULT 0,
    places INTEGER DEFAULT 0,
    description TEXT DEFAULT '',
    lien TEXT DEFAULT '',
    statut TEXT DEFAULT 'ouverte'
);
CREATE TABLE IF NOT EXISTS inscriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    formation_id INTEGER NOT NULL,
    membre_id INTEGER,
    nom TEXT DEFAULT '',
    telephone TEXT DEFAULT '',
    statut TEXT DEFAULT 'inscrit',
    present INTEGER DEFAULT 0,
    date_inscription TEXT DEFAULT '',
    FOREIGN KEY (formation_id) REFERENCES formations(id)
);
CREATE TABLE IF NOT EXISTS offres (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titre TEXT NOT NULL,
    entreprise TEXT DEFAULT '',
    ville TEXT DEFAULT '',
    contrat TEXT DEFAULT 'CDI',
    date_publication TEXT DEFAULT '',
    date_limite TEXT DEFAULT '',
    description TEXT DEFAULT '',
    profil TEXT DEFAULT '',
    contact TEXT DEFAULT '',
    email TEXT DEFAULT '',
    remuneration TEXT DEFAULT '',
    statut TEXT DEFAULT 'ouverte'
);
CREATE TABLE IF NOT EXISTS candidatures (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    offre_id INTEGER NOT NULL,
    membre_id INTEGER,
    nom TEXT DEFAULT '',
    telephone TEXT DEFAULT '',
    email TEXT DEFAULT '',
    message TEXT DEFAULT '',
    statut TEXT DEFAULT 'recue',
    date_candidature TEXT DEFAULT '',
    FOREIGN KEY (offre_id) REFERENCES offres(id)
);
CREATE TABLE IF NOT EXISTS activites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    titre TEXT NOT NULL,
    categorie TEXT DEFAULT 'Rencontre',
    date TEXT DEFAULT '',
    heure TEXT DEFAULT '',
    lieu TEXT DEFAULT '',
    mode TEXT DEFAULT 'Présentiel',
    cout INTEGER DEFAULT 0,
    description TEXT DEFAULT '',
    organisateur TEXT DEFAULT '',
    statut TEXT DEFAULT 'planifiee'
);
CREATE TABLE IF NOT EXISTS participations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    activite_id INTEGER NOT NULL,
    membre_id INTEGER NOT NULL,
    statut TEXT DEFAULT 'inscrit',
    UNIQUE (activite_id, membre_id),
    FOREIGN KEY (activite_id) REFERENCES activites(id)
);
"""


# --------------------------------------------------------------------------- #
# Base de données
# --------------------------------------------------------------------------- #

def db() -> sqlite3.Connection:
    if "db" not in g:
        g.db = sqlite3.connect(DB)
        g.db.row_factory = sqlite3.Row
        g.db.execute("PRAGMA foreign_keys = ON")
    return g.db


@app.teardown_appcontext
def fermer_db(_):
    con = g.pop("db", None)
    if con is not None:
        con.close()


def _migrer(con):
    """Ajoute les colonnes apparues après la création de la base."""
    colonnes = {r[1] for r in con.execute("PRAGMA table_info(membres)")}
    if "email" not in colonnes:
        con.execute("ALTER TABLE membres ADD COLUMN email TEXT DEFAULT ''")


def init_db():
    con = sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    con.executescript(SCHEMA)
    _migrer(con)
    if con.execute("SELECT COUNT(*) FROM settings").fetchone()[0] == 0:
        con.executemany("INSERT INTO settings (cle, valeur) VALUES (?, ?)",
                        list(CONFIG_DEFAUT.items()))
    if (con.execute("SELECT COUNT(*) FROM membres").fetchone()[0] == 0
            and not os.environ.get("COMPTA_SANS_DEMO")):
        _donnees_exemple(con)
    con.commit()
    con.close()


def _donnees_exemple(con):
    """Jeu de démonstration, supprimable depuis la page Paramètres."""
    demo = [
        ("KOUASSI Aya Michelle", "0708112233", "Abidjan", "Comptable générale"),
        ("YAO Kouadio Serge", "0544556677", "Bouaké", "Fiscaliste"),
        ("TRAORE Aminata", "0102030405", "Abidjan", "Comptable générale"),
        ("GNAMIEN Éric Landry", "0777889900", "Yamoussoukro", "Auditeur"),
        ("BAMBA Fatou", "0511223344", "Korhogo", "Paie & ressources humaines"),
        ("ASSAMOI Jean-Baptiste", "0700112244", "Abidjan", "Trésorier du réseau"),
    ]
    con.executemany(
        "INSERT INTO membres (code, nom, telephone, ville, specialite, cotisation, date_adhesion)"
        " VALUES (?, ?, ?, ?, ?, 5000, ?)",
        [(f"{i + 1:03d}", *d, "2025-03-01") for i, d in enumerate(demo)],
    )
    mois = date.today().strftime("%Y-%m")
    for d, montant, canal, exp, tel, lib in [
        (f"{mois}-03", 5000, "Wave", "KOUASSI Aya", "0708112233", f"Transfert ref {M.reference(mois, '001')}"),
        (f"{mois}-05", 5000, "Orange Money", "YAO SERGE", "0544556677", f"Cotisation {M.reference(mois, '002')}"),
        (f"{mois}-07", 2000, "Wave", "TRAORE AMINATA", "0102030405", f"Acompte {M.reference(mois, '003')}"),
        (f"{mois}-09", 5000, "Orange Money", "GNAMIEN ERIC", "0777889900", "Reçu de GNAMIEN ERIC LANDRY"),
    ]:
        p = M.Paiement(id=0, date=d, montant=montant, canal=canal, expediteur=exp,
                       telephone=tel, libelle=lib)
        M.rapprocher_paiement(p, _membres_sql(con), mois)
        con.execute(
            "INSERT INTO paiements (date, montant, canal, expediteur, telephone,"
            " libelle, mois, membre_id, statut, methode) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (p.date, p.montant, p.canal, p.expediteur, p.telephone, p.libelle,
             p.mois, p.membre_id, p.statut, p.methode))

    aujourdhui = date.today()
    con.executemany(
        "INSERT INTO formations (titre, formateur, date, heure, duree, lieu, mode, cout,"
        " places, description, lien, statut) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        [("Maîtriser la déclaration TVA en Côte d'Ivoire", "YAO Kouadio Serge",
          (aujourdhui.replace(day=min(28, aujourdhui.day))).isoformat(), "18:30", "1 h 30",
          "Google Meet", "En ligne", 0, 60,
          "Cas pratiques : base imposable, taux, crédit de TVA, échéances DGI.",
          "", "ouverte"),
         ("Paie ivoirienne : CNPS, ITS et bulletins conformes", "BAMBA Fatou",
          aujourdhui.replace(day=1).isoformat(), "09:00", "3 h",
          "Abidjan-Plateau", "Présentiel", 5000, 25,
          "Atelier pratique sur logiciel de paie, avec supports remis.", "", "terminee")])
    con.executemany(
        "INSERT INTO offres (titre, entreprise, ville, contrat, date_publication,"
        " date_limite, description, profil, contact, email, remuneration, statut)"
        " VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        [("Comptable unique (PME)", "Groupe Ivoire Distribution", "Abidjan", "CDI",
          (aujourdhui.replace(day=1)).isoformat(),
          (aujourdhui.replace(day=28)).isoformat(),
          "Tenue complète de la comptabilité, déclarations fiscales et sociales.",
          "Bac+3 comptabilité, 3 ans d'expérience minimum, maîtrise de Sage.",
          "M. ASSAMOI", "rh@example.ci", "350 000 - 450 000 FCFA", "ouverte"),
         ("Auditeur junior", "Cabinet KPM & Associés", "Abidjan", "CDD",
          aujourdhui.isoformat(), "",
          "Missions d'audit légal et contractuel sur un portefeuille diversifié.",
          "Master CCA ou équivalent, première expérience en cabinet appréciée.",
          "Mme KOUASSI", "recrutement@example.ci", "à négocier", "ouverte")])
    con.executemany(
        "INSERT INTO activites (titre, categorie, date, heure, lieu, mode, cout,"
        " description, organisateur, statut) VALUES (?,?,?,?,?,?,?,?,?,?)",
        [("Assemblée générale mensuelle", "Réunion",
          aujourdhui.replace(day=min(25, aujourdhui.day)).isoformat(), "17:00",
          "WhatsApp (appel vocal)", "En ligne", 0,
          "Bilan des cotisations, point sur les formations, questions diverses.",
          "Bureau du réseau", "planifiee"),
         ("Journée de solidarité : collecte pour un membre en difficulté", "Solidarité",
          aujourdhui.replace(day=15).isoformat(), "08:00", "Abidjan-Cocody",
          "Présentiel", 0, "Collecte et remise officielle, présence souhaitée.",
          "Comité solidarité", "terminee")])
    con.executemany(
        "INSERT INTO inscriptions (formation_id, membre_id, nom, telephone,"
        " statut, present, date_inscription) VALUES (?,?,?,?,?,?,?)",
        [(1, 1, "KOUASSI Aya Michelle", "0708112233", "inscrit", 0, aujourdhui.isoformat()),
         (1, 4, "GNAMIEN Éric Landry", "0777889900", "inscrit", 0, aujourdhui.isoformat()),
         (2, 3, "TRAORE Aminata", "0102030405", "present", 1, aujourdhui.isoformat())])
    con.executemany(
        "INSERT INTO candidatures (offre_id, membre_id, nom, telephone, email, message,"
        " statut, date_candidature) VALUES (?,?,?,?,?,?,?,?)",
        [(1, 5, "BAMBA Fatou", "0511223344", "fatou@example.ci",
          "Disponible immédiatement, 5 ans en PME.", "recue", aujourdhui.isoformat())])


def _membres_sql(con) -> list[M.Membre]:
    return [M.Membre(id=r["id"], code=r["code"], nom=r["nom"], telephone=r["telephone"],
                     cotisation=r["cotisation"], actif=bool(r["actif"]),
                     exonere=bool(r["exonere"]), email=r["email"] or "")
            for r in con.execute("SELECT * FROM membres ORDER BY code")]


# --------------------------------------------------------------------------- #
# Accès aux données
# --------------------------------------------------------------------------- #

def config() -> dict:
    cfg = dict(CONFIG_DEFAUT)
    for r in db().execute("SELECT cle, valeur FROM settings"):
        cfg[r["cle"]] = r["valeur"]
    for k in ("cotisation", "jour_echeance", "canal_wave", "canal_om", "canal_mtn", "canal_banque"):
        try:
            cfg[k] = int(cfg[k])
        except (TypeError, ValueError):
            cfg[k] = 0
    return cfg


def membres(actifs_seuls: bool = False) -> list[M.Membre]:
    sql = "SELECT * FROM membres"
    if actifs_seuls:
        sql += " WHERE actif = 1"
    sql += " ORDER BY code"
    return [M.Membre(id=r["id"], code=r["code"], nom=r["nom"], telephone=r["telephone"],
                     cotisation=r["cotisation"], actif=bool(r["actif"]),
                     exonere=bool(r["exonere"]), email=r["email"] or "")
            for r in db().execute(sql)]


def paiements(mois: str | None = None, non_rapproches: bool = False) -> list[M.Paiement]:
    sql, cond, args = "SELECT * FROM paiements", [], []
    if mois:
        cond.append("mois = ?")
        args.append(mois)
    if non_rapproches:
        cond.append("statut = 'NON_RAPPROCHE'")
    if cond:
        sql += " WHERE " + " AND ".join(cond)
    sql += " ORDER BY date DESC, id DESC"
    return [M.Paiement(id=r["id"], date=r["date"], montant=r["montant"], canal=r["canal"],
                       expediteur=r["expediteur"], telephone=r["telephone"],
                       libelle=r["libelle"], mois=r["mois"], membre_id=r["membre_id"],
                       statut=r["statut"], methode=r["methode"])
            for r in db().execute(sql, args)]


def nom_membre(mid: int | None) -> str:
    if not mid:
        return "—"
    r = db().execute("SELECT nom FROM membres WHERE id = ?", (mid,)).fetchone()
    return r["nom"] if r else "—"


def mois_courant() -> str:
    return date.today().strftime("%Y-%m")


def relancer_pointage() -> int:
    ms = membres()
    nb = 0
    for p in paiements(non_rapproches=True):
        avant = p.membre_id
        M.rapprocher_paiement(p, ms, mois_courant())
        if p.membre_id and p.membre_id != avant:
            db().execute("UPDATE paiements SET mois=?, membre_id=?, statut=?, methode=? WHERE id=?",
                         (p.mois, p.membre_id, p.statut, p.methode, p.id))
            nb += 1
    db().commit()
    return nb


def lignes(sql, args=()):
    return [dict(r) for r in db().execute(sql, args)]


def fmt(n) -> str:
    return f"{int(n or 0):,}".replace(",", " ")


def fdate(txt: str) -> str:
    if not txt:
        return "—"
    for f in ("%Y-%m-%d", "%Y-%m"):
        try:
            d = datetime.strptime(txt, f)
            return d.strftime("%d/%m/%Y") if f == "%Y-%m-%d" else M.libelle_mois(txt)
        except ValueError:
            continue
    return txt


app.jinja_env.filters.update({"fcfa": fmt, "tel": M.telephone_normalise, "fdate": fdate})
app.jinja_env.globals.update(ST=M, now=lambda: datetime.now().strftime("%d/%m/%Y à %H:%M"),
                             aujourdhui=date.today().isoformat,
                             qr=lambda texte, taille=200: QR.qr_svg(texte, taille_px=taille))


def canaux(cfg) -> list[dict]:
    out = []
    if cfg["canal_wave"] and cfg["wave_numero"]:
        out.append({"nom": "Wave", "numero": cfg["wave_numero"], "titulaire": cfg["wave_nom"],
                    "detail": "Transfert gratuit pour vous, retrait gratuit"})
    if cfg["canal_om"] and cfg["om_numero"]:
        out.append({"nom": "Orange Money", "numero": cfg["om_numero"], "titulaire": cfg["om_nom"],
                    "detail": "Frais d'envoi à la charge du membre"})
    if cfg["canal_mtn"] and cfg["mtn_numero"]:
        out.append({"nom": "MTN MoMo", "numero": cfg["mtn_numero"], "titulaire": cfg["mtn_nom"],
                    "detail": "Frais d'envoi à la charge du membre"})
    if cfg["canal_banque"] and cfg["banque_iban"]:
        out.append({"nom": "Virement bancaire", "numero": cfg["banque_iban"],
                    "titulaire": cfg["banque_nom"], "detail": "Compte du réseau"})
    return out


def relances_du_mois(pt, cfg) -> list[dict]:
    canal = " / ".join(c["nom"] for c in canaux(cfg))
    return [{"membre_id": l["membre"].id, "nom": l["membre"].nom,
             "telephone": M.telephone_normalise(l["membre"].telephone),
             "message": M.message_relance(l, cfg["reseau"], canal, cfg["caisse_nom"])}
            for l in pt["lignes"] if l["statut"] in (M.ST_IMPAYE, M.ST_PARTIEL)]


# --------------------------------------------------------------------------- #
# Tableau de bord
# --------------------------------------------------------------------------- #

@app.route("/")
def dashboard():
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    pt["echeance"] = M.echeance(mois, cfg["jour_echeance"])

    historique = []
    for r in db().execute("SELECT DISTINCT mois FROM paiements WHERE mois != '' ORDER BY mois DESC LIMIT 12"):
        p2 = M.pointage(membres(), paiements(), r["mois"])
        historique.append({"mois": r["mois"], "libelle": p2["libelle"], **p2["totaux"]})

    stats = {
        "membres_actifs": db().execute("SELECT COUNT(*) FROM membres WHERE actif=1").fetchone()[0],
        "formations": db().execute("SELECT COUNT(*) FROM formations WHERE statut='ouverte'").fetchone()[0],
        "offres": db().execute("SELECT COUNT(*) FROM offres WHERE statut='ouverte'").fetchone()[0],
        "activites": db().execute("SELECT COUNT(*) FROM activites WHERE statut='planifiee'").fetchone()[0],
        "candidatures": db().execute("SELECT COUNT(*) FROM candidatures").fetchone()[0],
    }
    return render_template(
        "dashboard.html", cfg=cfg, mois=mois, pt=pt, stats=stats,
        orphelins=paiements(non_rapproches=True), historique=historique,
        mois_dispo=sorted({mois} | {h["mois"] for h in historique}, reverse=True),
        en_retard=date.today().isoformat() > pt["echeance"],
        relances=relances_du_mois(pt, cfg),
        formations=lignes("SELECT * FROM formations WHERE statut='ouverte' ORDER BY date LIMIT 3"),
        offres=lignes("SELECT * FROM offres WHERE statut='ouverte' ORDER BY date_publication DESC LIMIT 3"),
        activites=lignes("SELECT * FROM activites WHERE statut='planifiee' ORDER BY date LIMIT 3"),
        page="dashboard")


# --------------------------------------------------------------------------- #
# Membres
# --------------------------------------------------------------------------- #

@app.route("/membres")
def page_membres():
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    lignes_pt = {l["membre"].id: l for l in M.pointage(membres(), paiements(), mois)["lignes"]}
    return render_template("membres.html", membres=membres(), lignes=lignes_pt,
                           mois=mois, cfg=config(), page="membres")


def _form_membre(mid=None):
    f = request.form
    code = re.sub(r"\D", "", f.get("code", "") or "")
    if not code:
        mx = db().execute("SELECT MAX(CAST(code AS INTEGER)) c FROM membres").fetchone()["c"] or 0
        code = f"{mx + 1:03d}"
    code = code.zfill(3)
    nom = f.get("nom", "").strip()
    if not nom:
        flash("Le nom du membre est obligatoire.", "erreur")
        return redirect(url_for("page_membres"))
    vals = (code, nom, f.get("telephone", "").strip(), f.get("email", "").strip(),
            f.get("ville", "").strip(), f.get("specialite", "").strip(),
            int(f.get("cotisation") or config()["cotisation"]),
            f.get("date_adhesion", ""), 1 if f.get("actif") else 0, 1 if f.get("exonere") else 0)
    if mid:
        db().execute("UPDATE membres SET code=?, nom=?, telephone=?, email=?, ville=?,"
                     " specialite=?, cotisation=?, date_adhesion=?, actif=?, exonere=?"
                     " WHERE id=?", vals + (mid,))
        flash(f"Membre « {nom} » mis à jour.", "ok")
    else:
        db().execute("INSERT INTO membres (code, nom, telephone, email, ville, specialite,"
                     " cotisation, date_adhesion, actif, exonere) VALUES (?,?,?,?,?,?,?,?,?,?)", vals)
        flash(f"Membre « {nom} » ajouté sous le code {code}.", "ok")
    db().commit()
    return redirect(url_for("page_membres"))


@app.route("/membres/nouveau", methods=["POST"])
def nouveau_membre():
    return _form_membre()


@app.route("/membres/<int:mid>/modifier", methods=["POST"])
def modifier_membre(mid):
    return _form_membre(mid)


@app.route("/membres/<int:mid>/supprimer", methods=["POST"])
def supprimer_membre(mid):
    for table, col in [("paiements", "membre_id"), ("inscriptions", "membre_id"),
                       ("candidatures", "membre_id"), ("participations", "membre_id")]:
        db().execute(f"DELETE FROM {table} WHERE {col} = ?", (mid,))
    db().execute("DELETE FROM membres WHERE id = ?", (mid,))
    db().commit()
    flash("Membre supprimé, ainsi que ses paiements, inscriptions et candidatures.", "ok")
    return redirect(url_for("page_membres"))


@app.route("/membres/importer", methods=["POST"])
def importer_membres():
    """Importe une liste CSV/Excel copiée-collée : nom;telephone;ville;specialite."""
    brut = request.form.get("texte", "")
    if not brut.strip():
        flash("Collez d'abord la liste des membres.", "erreur")
        return redirect(url_for("page_membres"))
    cot = int(request.form.get("cotisation") or config()["cotisation"])
    sep = request.form.get("sep") or ";"
    if sep == "tab":
        sep = "\t"
    mx = db().execute("SELECT MAX(CAST(code AS INTEGER)) c FROM membres").fetchone()["c"] or 0
    existants = {m.nom.strip().lower() for m in membres()}
    ajoutes = 0
    for i, ligne in enumerate(csv.reader(io.StringIO(brut), delimiter=sep)):
        if not ligne or not ligne[0].strip():
            continue
        nom = ligne[0].strip()
        if i == 0 and nom.lower() in ("nom", "name", "membres", "membre"):
            continue
        if nom.lower() in existants:
            continue
        tel = ligne[1].strip() if len(ligne) > 1 else ""
        email = ligne[2].strip() if len(ligne) > 2 else ""
        ville = ligne[3].strip() if len(ligne) > 3 else ""
        spec = ligne[4].strip() if len(ligne) > 4 else ""
        mx += 1
        db().execute("INSERT INTO membres (code, nom, telephone, email, ville, specialite,"
                     " cotisation, date_adhesion) VALUES (?,?,?,?,?,?,?,?)",
                     (f"{mx:03d}", nom, tel, email, ville, spec, cot, date.today().isoformat()))
        ajoutes += 1
    db().commit()
    flash(f"{ajoutes} membre(s) importé(s).", "ok")
    return redirect(url_for("page_membres"))


# --------------------------------------------------------------------------- #
# Cotisations
# --------------------------------------------------------------------------- #

@app.route("/cotisations")
def page_cotisations():
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    pt["echeance"] = M.echeance(mois, cfg["jour_echeance"])
    return render_template("cotisations.html", cfg=cfg, mois=mois, pt=pt,
                           orphelins=paiements(non_rapproches=True),
                           relances=relances_du_mois(pt, cfg), page="cotisations")


@app.route("/paiements")
def page_paiements():
    mois = request.args.get("mois")
    ps = paiements(M.normaliser_mois(mois) if mois else None)
    return render_template("paiements.html", paiements=ps, cfg=config(),
                           mois=M.normaliser_mois(mois) if mois else mois_courant(),
                           membres=membres(), nom_membre=nom_membre, page="paiements")


@app.route("/paiements/enregistrer", methods=["POST"])
def enregistrer_paiement():
    f = request.form
    ms = membres()
    montant = int(re.sub(r"\D", "", f.get("montant", "") or "0") or 0)
    if montant <= 0:
        flash("Montant invalide.", "erreur")
        return redirect(url_for("page_paiements"))
    p = M.Paiement(id=0, date=f.get("date") or date.today().isoformat(), montant=montant,
                   canal=f.get("canal", ""), expediteur=f.get("expediteur", "").strip(),
                   telephone=f.get("telephone", "").strip(), libelle=f.get("libelle", "").strip())
    choix = (f.get("membre_id") or "").strip()
    if choix:
        cible = next((m for m in ms if str(m.id) == choix), None)
        p.membre_id = cible.id
        p.mois = M.normaliser_mois(f.get("mois") or mois_courant())
        p.statut, p.methode = "RAPPROCHE", M.M_MANUEL
        info = f"rapproché de {cible.nom}"
    else:
        M.rapprocher_paiement(p, ms, mois_courant())
        info = (f"rapproché automatiquement de {nom_membre(p.membre_id)} (détection « {p.methode} »)"
                if p.membre_id else "non rapproché automatiquement : à pointer manuellement")
    db().execute("INSERT INTO paiements (date, montant, canal, expediteur, telephone,"
                 " libelle, mois, membre_id, statut, methode) VALUES (?,?,?,?,?,?,?,?,?,?)",
                 (p.date, p.montant, p.canal, p.expediteur, p.telephone, p.libelle,
                  p.mois, p.membre_id, p.statut, p.methode))
    db().commit()
    flash(f"Paiement de {fmt(montant)} FCFA enregistré — {info}.", "ok")
    return redirect(url_for("page_paiements"))


@app.route("/paiements/<int:pid>/rapprocher", methods=["POST"])
def rapprocher_manuel(pid):
    mois = M.normaliser_mois(request.form.get("mois") or mois_courant())
    db().execute("UPDATE paiements SET membre_id=?, mois=?, statut='RAPPROCHE',"
                 " methode='manuel' WHERE id=?",
                 (request.form.get("membre_id") or None, mois, pid))
    db().commit()
    flash("Paiement rapproché.", "ok")
    return redirect(request.referrer or url_for("page_paiements", mois=mois))


@app.route("/paiements/<int:pid>/supprimer", methods=["POST"])
def supprimer_paiement(pid):
    db().execute("DELETE FROM paiements WHERE id = ?", (pid,))
    db().commit()
    flash("Paiement supprimé.", "ok")
    return redirect(request.referrer or url_for("page_paiements"))


@app.route("/rapprocher", methods=["POST"])
def lancer_rapprochement():
    nb = relancer_pointage()
    flash(f"Pointage automatique : {nb} paiement(s) rapproché(s)." if nb
          else "Pointage automatique : aucun nouveau paiement à rapprocher.",
          "ok" if nb else "info")
    return redirect(request.referrer or url_for("dashboard"))


@app.route("/import", methods=["GET", "POST"])
def page_import():
    cfg = config()
    if request.method == "GET":
        return render_template("import.html", cfg=cfg, page="import")
    brut = request.form.get("texte", "")
    fichier = request.files.get("fichier")
    if fichier and fichier.filename:
        brut = fichier.read().decode("utf-8-sig", errors="replace")
    if not brut.strip():
        flash("Aucune donnée à importer.", "erreur")
        return redirect(url_for("page_import"))
    mois_defaut = M.normaliser_mois(request.form.get("mois") or mois_courant())
    sep = request.form.get("sep") or ";"
    sep = "\t" if sep == "tab" else sep
    lignes_csv = [l for l in csv.reader(io.StringIO(brut), delimiter=sep)
                  if any(c.strip() for c in l)]
    idx = _colonnes(lignes_csv[0])
    if idx is None:
        idx = {n: i for i, n in enumerate(
            ["date", "montant", "canal", "expediteur", "telephone", "libelle"])}
        corps = lignes_csv
    else:
        corps = lignes_csv[1:]
    ms, importes, rapproches = membres(), 0, 0
    for l in corps:
        def val(nom):
            i = idx.get(nom)
            return l[i].strip() if i is not None and i < len(l) else ""
        montant = int(re.sub(r"\D", "", val("montant") or "0") or 0)
        if montant <= 0:
            continue
        p = M.Paiement(id=0, date=_date(val("date")), montant=montant, canal=val("canal"),
                       expediteur=val("expediteur"), telephone=val("telephone"),
                       libelle=val("libelle"))
        M.rapprocher_paiement(p, ms, mois_defaut)
        db().execute("INSERT INTO paiements (date, montant, canal, expediteur, telephone,"
                     " libelle, mois, membre_id, statut, methode) VALUES (?,?,?,?,?,?,?,?,?,?)",
                     (p.date, p.montant, p.canal, p.expediteur, p.telephone, p.libelle,
                      p.mois, p.membre_id, p.statut, p.methode))
        importes += 1
        rapproches += 1 if p.membre_id else 0
    db().commit()
    flash(f"{importes} paiement(s) importé(s) — {rapproches} rapproché(s) automatiquement, "
          f"{importes - rapproches} à pointer manuellement.", "ok")
    return redirect(url_for("page_paiements"))


def _colonnes(entete):
    alias = {
        "date": ("date", "jour", "dateoperation", "datetransaction"),
        "montant": ("montant", "amount", "montantfcfa", "somme", "valeur"),
        "canal": ("canal", "operateur", "moyen", "wallet", "type"),
        "expediteur": ("expediteur", "emetteur", "nom", "libellecompte", "sender"),
        "telephone": ("telephone", "numero", "tel", "msisdn", "phonenumber"),
        "libelle": ("libelle", "motif", "reference", "description", "commentaire", "label", "detail"),
    }
    normalises = [re.sub(r"[^a-z]", "", c.lower()) for c in entete]
    out = {}
    for cle, noms in alias.items():
        for i, n in enumerate(normalises):
            if n in noms:
                out[cle] = i
                break
    return out if "montant" in out else None


def _date(txt: str) -> str:
    txt = (txt or "").strip()
    for f in ("%Y-%m-%d", "%d/%m/%Y", "%d/%m/%y", "%d-%m-%Y", "%Y/%m/%d", "%d.%m.%Y"):
        try:
            return datetime.strptime(txt, f).date().isoformat()
        except ValueError:
            continue
    return date.today().isoformat()


# --------------------------------------------------------------------------- #
# Formations
# --------------------------------------------------------------------------- #

@app.route("/formations")
def page_formations():
    fs = lignes("SELECT * FROM formations ORDER BY date DESC")
    for f in fs:
        f["nb_inscrits"] = db().execute(
            "SELECT COUNT(*) FROM inscriptions WHERE formation_id=?", (f["id"],)).fetchone()[0]
        f["nb_presents"] = db().execute(
            "SELECT COUNT(*) FROM inscriptions WHERE formation_id=? AND present=1",
            (f["id"],)).fetchone()[0]
    return render_template("formations.html", formations=fs, cfg=config(), page="formations")


@app.route("/formations/<int:fid>")
def detail_formation(fid):
    f = db().execute("SELECT * FROM formations WHERE id=?", (fid,)).fetchone()
    if not f:
        flash("Formation introuvable.", "erreur")
        return redirect(url_for("page_formations"))
    insc = lignes("SELECT * FROM inscriptions WHERE formation_id=? ORDER BY nom", (fid,))
    return render_template("formation_detail.html", f=dict(f), inscriptions=insc,
                           membres=membres(), cfg=config(), page="formations")


def _form_formation(fid=None):
    f = request.form
    titre = f.get("titre", "").strip()
    if not titre:
        flash("Le titre de la formation est obligatoire.", "erreur")
        return redirect(url_for("page_formations"))
    vals = (titre, f.get("formateur", "").strip(), f.get("date", ""), f.get("heure", ""),
            f.get("duree", "").strip(), f.get("lieu", "").strip(), f.get("mode", "En ligne"),
            int(f.get("cout") or 0), int(f.get("places") or 0), f.get("description", "").strip(),
            f.get("lien", "").strip(), f.get("statut", "ouverte"))
    if fid:
        db().execute("UPDATE formations SET titre=?, formateur=?, date=?, heure=?, duree=?,"
                     " lieu=?, mode=?, cout=?, places=?, description=?, lien=?, statut=?"
                     " WHERE id=?", vals + (fid,))
        flash("Formation mise à jour.", "ok")
    else:
        db().execute("INSERT INTO formations (titre, formateur, date, heure, duree, lieu, mode,"
                     " cout, places, description, lien, statut) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", vals)
        flash(f"Formation « {titre} » publiée.", "ok")
    db().commit()
    return redirect(url_for("page_formations"))


@app.route("/formations/nouveau", methods=["POST"])
def nouvelle_formation():
    return _form_formation()


@app.route("/formations/<int:fid>/modifier", methods=["POST"])
def modifier_formation(fid):
    return _form_formation(fid)


@app.route("/formations/<int:fid>/supprimer", methods=["POST"])
def supprimer_formation(fid):
    db().execute("DELETE FROM inscriptions WHERE formation_id=?", (fid,))
    db().execute("DELETE FROM formations WHERE id=?", (fid,))
    db().commit()
    flash("Formation supprimée.", "ok")
    return redirect(url_for("page_formations"))


@app.route("/formations/<int:fid>/inscrire", methods=["POST"])
def inscrire_formation(fid):
    mid = (request.form.get("membre_id") or "").strip()
    nom = request.form.get("nom", "").strip()
    tel = request.form.get("telephone", "").strip()
    if mid:
        r = db().execute("SELECT * FROM membres WHERE id=?", (mid,)).fetchone()
        if not r:
            flash("Membre introuvable.", "erreur")
            return redirect(url_for("detail_formation", fid=fid))
        nom, tel = r["nom"], r["telephone"]
    elif not nom:
        flash("Choisissez un membre ou saisissez un nom.", "erreur")
        return redirect(url_for("detail_formation", fid=fid))
    deja = db().execute("SELECT COUNT(*) FROM inscriptions WHERE formation_id=? AND"
                        " ((membre_id IS NOT NULL AND membre_id=?) OR (membre_id IS NULL AND nom=?))",
                        (fid, mid or None, nom)).fetchone()[0]
    if deja:
        flash("Cette personne est déjà inscrite.", "info")
        return redirect(url_for("detail_formation", fid=fid))
    db().execute("INSERT INTO inscriptions (formation_id, membre_id, nom, telephone,"
                 " date_inscription) VALUES (?,?,?,?,?)",
                 (fid, mid or None, nom, tel, date.today().isoformat()))
    db().commit()
    flash(f"{nom} inscrit(e) à la formation.", "ok")
    return redirect(url_for("detail_formation", fid=fid))


@app.route("/inscriptions/<int:iid>/presence", methods=["POST"])
def basculer_presence(iid):
    db().execute("UPDATE inscriptions SET present = 1 - present, statut = CASE WHEN present=1"
                 " THEN 'inscrit' ELSE 'present' END WHERE id=?", (iid,))
    db().commit()
    return redirect(request.referrer or url_for("page_formations"))


@app.route("/inscriptions/<int:iid>/supprimer", methods=["POST"])
def supprimer_inscription(iid):
    db().execute("DELETE FROM inscriptions WHERE id=?", (iid,))
    db().commit()
    flash("Inscription annulée.", "ok")
    return redirect(request.referrer or url_for("page_formations"))


# --------------------------------------------------------------------------- #
# Offres d'emploi
# --------------------------------------------------------------------------- #

@app.route("/offres")
def page_offres():
    os_ = lignes("SELECT * FROM offres ORDER BY statut='ouverte' DESC, date_publication DESC")
    for o in os_:
        o["nb_candidats"] = db().execute(
            "SELECT COUNT(*) FROM candidatures WHERE offre_id=?", (o["id"],)).fetchone()[0]
    return render_template("offres.html", offres=os_, cfg=config(), page="offres")


@app.route("/offres/<int:oid>")
def detail_offre(oid):
    o = db().execute("SELECT * FROM offres WHERE id=?", (oid,)).fetchone()
    if not o:
        flash("Offre introuvable.", "erreur")
        return redirect(url_for("page_offres"))
    cand = lignes("SELECT * FROM candidatures WHERE offre_id=? ORDER BY date_candidature DESC", (oid,))
    return render_template("offre_detail.html", o=dict(o), candidatures=cand,
                           membres=membres(), cfg=config(), page="offres")


def _form_offre(oid=None):
    f = request.form
    titre = f.get("titre", "").strip()
    if not titre:
        flash("Le titre du poste est obligatoire.", "erreur")
        return redirect(url_for("page_offres"))
    vals = (titre, f.get("entreprise", "").strip(), f.get("ville", "").strip(),
            f.get("contrat", "CDI"), f.get("date_publication") or date.today().isoformat(),
            f.get("date_limite", ""), f.get("description", "").strip(), f.get("profil", "").strip(),
            f.get("contact", "").strip(), f.get("email", "").strip(),
            f.get("remuneration", "").strip(), f.get("statut", "ouverte"))
    if oid:
        db().execute("UPDATE offres SET titre=?, entreprise=?, ville=?, contrat=?,"
                     " date_publication=?, date_limite=?, description=?, profil=?, contact=?,"
                     " email=?, remuneration=?, statut=? WHERE id=?", vals + (oid,))
        flash("Offre mise à jour.", "ok")
    else:
        db().execute("INSERT INTO offres (titre, entreprise, ville, contrat, date_publication,"
                     " date_limite, description, profil, contact, email, remuneration, statut)"
                     " VALUES (?,?,?,?,?,?,?,?,?,?,?,?)", vals)
        flash(f"Offre « {titre} » publiée.", "ok")
    db().commit()
    return redirect(url_for("page_offres"))


@app.route("/offres/nouveau", methods=["POST"])
def nouvelle_offre():
    return _form_offre()


@app.route("/offres/<int:oid>/modifier", methods=["POST"])
def modifier_offre(oid):
    return _form_offre(oid)


@app.route("/offres/<int:oid>/supprimer", methods=["POST"])
def supprimer_offre(oid):
    db().execute("DELETE FROM candidatures WHERE offre_id=?", (oid,))
    db().execute("DELETE FROM offres WHERE id=?", (oid,))
    db().commit()
    flash("Offre supprimée.", "ok")
    return redirect(url_for("page_offres"))


@app.route("/offres/<int:oid>/candidater", methods=["POST"])
def candidater(oid):
    mid = (request.form.get("membre_id") or "").strip()
    nom = request.form.get("nom", "").strip()
    tel = request.form.get("telephone", "").strip()
    email = request.form.get("email", "").strip()
    if mid:
        r = db().execute("SELECT * FROM membres WHERE id=?", (mid,)).fetchone()
        if r:
            nom, tel = r["nom"], r["telephone"]
    if not nom:
        flash("Choisissez un membre ou saisissez un nom.", "erreur")
        return redirect(url_for("detail_offre", oid=oid))
    db().execute("INSERT INTO candidatures (offre_id, membre_id, nom, telephone, email, message,"
                 " date_candidature) VALUES (?,?,?,?,?,?,?)",
                 (oid, mid or None, nom, tel, email, request.form.get("message", "").strip(),
                  date.today().isoformat()))
    db().commit()
    flash(f"Candidature de {nom} enregistrée.", "ok")
    return redirect(url_for("detail_offre", oid=oid))


@app.route("/candidatures/<int:cid>/statut", methods=["POST"])
def statut_candidature(cid):
    db().execute("UPDATE candidatures SET statut=? WHERE id=?",
                 (request.form.get("statut", "recue"), cid))
    db().commit()
    flash("Statut de la candidature mis à jour.", "ok")
    r = db().execute("SELECT offre_id FROM candidatures WHERE id=?", (cid,)).fetchone()
    return redirect(request.referrer or url_for("detail_offre", oid=r["offre_id"] if r else 1))


# --------------------------------------------------------------------------- #
# Activités du réseau
# --------------------------------------------------------------------------- #

@app.route("/activites")
def page_activites():
    acts = lignes("SELECT * FROM activites ORDER BY date DESC")
    for a in acts:
        a["participants"] = lignes(
            "SELECT participations.id, membres.nom FROM participations"
            " JOIN membres ON membres.id = participations.membre_id"
            " WHERE participations.activite_id = ? ORDER BY membres.nom", (a["id"],))
        a["nb_participants"] = len(a["participants"])
    return render_template("activites.html", activites=acts, membres=membres(),
                           cfg=config(), page="activites")


def _form_activite(aid=None):
    f = request.form
    titre = f.get("titre", "").strip()
    if not titre:
        flash("Le titre de l'activité est obligatoire.", "erreur")
        return redirect(url_for("page_activites"))
    vals = (titre, f.get("categorie", "Rencontre"), f.get("date", ""), f.get("heure", ""),
            f.get("lieu", "").strip(), f.get("mode", "Présentiel"), int(f.get("cout") or 0),
            f.get("description", "").strip(), f.get("organisateur", "").strip(),
            f.get("statut", "planifiee"))
    if aid:
        db().execute("UPDATE activites SET titre=?, categorie=?, date=?, heure=?, lieu=?, mode=?,"
                     " cout=?, description=?, organisateur=?, statut=? WHERE id=?", vals + (aid,))
        flash("Activité mise à jour.", "ok")
    else:
        db().execute("INSERT INTO activites (titre, categorie, date, heure, lieu, mode, cout,"
                     " description, organisateur, statut) VALUES (?,?,?,?,?,?,?,?,?,?)", vals)
        flash(f"Activité « {titre} » créée.", "ok")
    db().commit()
    return redirect(url_for("page_activites"))


@app.route("/activites/nouveau", methods=["POST"])
def nouvelle_activite():
    return _form_activite()


@app.route("/activites/<int:aid>/modifier", methods=["POST"])
def modifier_activite(aid):
    return _form_activite(aid)


@app.route("/activites/<int:aid>/supprimer", methods=["POST"])
def supprimer_activite(aid):
    db().execute("DELETE FROM participations WHERE activite_id=?", (aid,))
    db().execute("DELETE FROM activites WHERE id=?", (aid,))
    db().commit()
    flash("Activité supprimée.", "ok")
    return redirect(url_for("page_activites"))


@app.route("/activites/<int:aid>/participer", methods=["POST"])
def participer(aid):
    mid = (request.form.get("membre_id") or "").strip()
    if not mid:
        flash("Choisissez un membre.", "erreur")
        return redirect(url_for("page_activites"))
    try:
        db().execute("INSERT INTO participations (activite_id, membre_id) VALUES (?,?)", (aid, mid))
        db().commit()
        flash(f"{nom_membre(int(mid))} participe à l'activité.", "ok")
    except sqlite3.IntegrityError:
        flash("Ce membre est déjà inscrit à cette activité.", "info")
    return redirect(request.referrer or url_for("page_activites"))


@app.route("/participations/<int:pid>/supprimer", methods=["POST"])
def annuler_participation(pid):
    db().execute("DELETE FROM participations WHERE id=?", (pid,))
    db().commit()
    flash("Participation annulée.", "ok")
    return redirect(request.referrer or url_for("page_activites"))


# --------------------------------------------------------------------------- #
# Paramètres
# --------------------------------------------------------------------------- #

@app.route("/parametres", methods=["GET", "POST"])
def page_parametres():
    if request.method == "POST":
        if request.form.get("action") == "reinitialiser":
            DB.unlink(missing_ok=True)
            init_db()
            flash("Base réinitialisée avec le jeu de démonstration.", "ok")
            return redirect(url_for("page_parametres"))
        for cle in CONFIG_DEFAUT:
            db().execute("INSERT INTO settings (cle, valeur) VALUES (?, ?)"
                         " ON CONFLICT(cle) DO UPDATE SET valeur=excluded.valeur",
                         (cle, (request.form.get(cle) or "").strip()))
        db().commit()
        flash("Paramètres enregistrés.", "ok")
        return redirect(url_for("page_parametres"))
    return render_template("parametres.html", cfg=config(), page="parametres")


# --------------------------------------------------------------------------- #
# Page publique de paiement
# --------------------------------------------------------------------------- #

@app.route("/payer")
def payer():
    cfg = config()
    code = re.sub(r"\D", "", request.args.get("code") or "")
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    moi = ligne = None
    if code:
        m = next((x for x in membres() if x.code == code.zfill(3)), None)
        if m:
            moi = m
            ligne = M.pointage([m], paiements(), mois)["lignes"][0]
    return render_template("payer.html", cfg=cfg, mois=mois, moi=moi, ligne=ligne,
                           canaux=canaux(cfg), echeance=M.echeance(mois, cfg["jour_echeance"]),
                           libelle=M.libelle_mois(mois),
                           en_ligne=P.config_ok(cfg),
                           retour=request.args.get("retour") == "1")


@app.route("/payer/recherche", methods=["POST"])
def payer_recherche():
    q = request.form.get("q", "").strip()
    mois = request.form.get("mois") or mois_courant()
    code = re.sub(r"\D", "", q)
    if len(code) >= 3:
        return redirect(url_for("payer", code=code[-3:], mois=mois))
    ms = [m for m in membres() if q.lower() in m.nom.lower()]
    if len(ms) == 1:
        return redirect(url_for("payer", code=ms[0].code, mois=mois))
    flash("Code introuvable. Utilise ton code membre à 3 chiffres, donné par le trésorier.", "erreur")
    return redirect(url_for("payer"))


@app.route("/api/moi")
def api_moi():
    code = re.sub(r"\D", "", request.args.get("code") or "")
    m = next((x for x in membres() if x.code == code.zfill(3)), None) if code else None
    if not m:
        return jsonify({"ok": False})
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    l = M.pointage([m], paiements(), mois)["lignes"][0]
    return jsonify({"ok": True, "nom": m.nom, "mois": mois, "du": l["du"], "verse": l["verse"],
                    "reliquat": l["reliquat"], "statut": l["statut"], "reference": l["reference"]})


@app.route("/qr/<path:texte>")
def qr(texte):
    return QR.qr_svg(texte, taille_px=int(request.args.get("t", 220)))


# --------------------------------------------------------------------------- #
# Paiement en ligne (CinetPay) — automatique, sans intervention du trésorier
# --------------------------------------------------------------------------- #

@app.route("/payer/<code>/en-ligne", methods=["POST"])
def payer_en_ligne(code):
    """Le membre clique « Payer » : ouvre la page CinetPay (mobile money / carte)."""
    cfg = config()
    mois = M.normaliser_mois(request.form.get("mois") or mois_courant())
    code = code.zfill(3)
    m = next((x for x in membres() if x.code == code), None)
    if not m:
        flash("Membre introuvable.", "erreur")
        return redirect(url_for("payer"))
    ligne = M.pointage([m], paiements(), mois)["lignes"][0]
    if ligne["statut"] in ("PAYE", "EXONERE", "NON_ACTIF"):
        flash("Cette cotisation est déjà à jour.", "info")
        return redirect(url_for("payer", code=code, mois=mois))
    montant = int(ligne["reliquat"] or cfg["cotisation"] or 0)
    base = (cfg.get("url_publique") or request.url_root).rstrip("/")
    rep = P.creer_paiement(
        ligne["reference"], montant,
        suffixe=str(int(datetime.now().timestamp()))[-5:],
        cfg=cfg,
        client={"code": m.code, "nom": m.nom, "telephone": m.telephone,
                "email": m.email},
        notify_url=base + url_for("ipn_cinetpay"),
        return_url=base + url_for("payer", code=code, mois=mois, retour=1),
        description=f"Cotisation {M.libelle_mois(mois)} — {m.nom}",
    )
    if rep["ok"]:
        return redirect(rep["url"])
    flash(f"Paiement en ligne indisponible : {rep['erreur']}", "erreur")
    return redirect(url_for("payer", code=code, mois=mois))


@app.route("/api/ipn/cinetpay", methods=["POST"])
def ipn_cinetpay():
    """
    Notification instantanée envoyée par CinetPay dès que le membre a payé.

    Sécurité : on ne fait pas confiance au POST — on redemande le statut à
    CinetPay (checkpay). Idempotent : une même transaction n'est jamais
    créditée deux fois.
    """
    cfg = config()
    f = request.form
    tid = (f.get("transaction_id") or "").strip()
    if not tid or not P.config_ok(cfg):
        return jsonify({"code": "0", "message": "ignoré"})
    verif = P.verifier_transaction(tid, cfg)
    if verif["statut"] != P.ST_ACCEPTE:
        return jsonify({"code": "0", "message": f"statut {verif['statut']}, ignoré"})
    deja = db().execute("SELECT id FROM paiements WHERE canal = 'CinetPay' AND libelle = ?",
                        (tid,)).fetchone()
    if deja:
        return jsonify({"code": "0", "message": "déjà traité"})
    montant = verif["montant"] or int(re.sub(r"\D", "", f.get("amount", "") or "0") or 0)
    if montant <= 0:
        return jsonify({"code": "0", "message": "montant inconnu, ignoré"})
    p = M.Paiement(id=0, date=date.today().isoformat(), montant=montant,
                   canal="CinetPay", expediteur=(verif["client"] or "")[:80],
                   telephone=f.get("payment_method", "")[:40],
                   libelle=tid)  # contient la référence CCaamm### -> rapprochement auto
    M.rapprocher_paiement(p, membres(), mois_courant())
    db().execute("INSERT INTO paiements (date, montant, canal, expediteur, telephone,"
                 " libelle, mois, membre_id, statut, methode) VALUES (?,?,?,?,?,?,?,?,?,?)",
                 (p.date, p.montant, p.canal, p.expediteur, p.telephone,
                  p.libelle, p.mois, p.membre_id, p.statut, p.methode))
    db().commit()
    return jsonify({"code": "0",
                    "message": f"crédité {nom_membre(p.membre_id) or 'à pointer'}"})


# --------------------------------------------------------------------------- #
# Cycle mensuel des cotisations (workflow)
# --------------------------------------------------------------------------- #

def taches_faites(mois: str) -> dict:
    return {r["cle"]: (r["fait_le"], r["note"]) for r in db().execute(
        "SELECT cle, fait_le, note FROM taches WHERE mois = ?", (mois,))}


def cycle(mois: str) -> list[W.Tache]:
    return W.cycle_mensuel(mois, config()["jour_echeance"],
                           aujourd_hui=date.today().isoformat(),
                           taches_faites=taches_faites(mois))


@app.route("/workflow")
def page_workflow():
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    taches = cycle(mois)
    pt = M.pointage(membres(), paiements(), mois)
    pt["echeance"] = M.echeance(mois, cfg["jour_echeance"])
    relances = relances_du_mois(pt, cfg)
    return render_template("workflow.html", cfg=cfg, mois=mois, taches=taches,
                           prog=W.progression(taches), pt=pt, relances=relances,
                           en_retard=W.taches_en_retard(taches),
                           mois_suivant=M.mois_suivant(mois),
                           mois_precedent=_mois_precedent(mois),
                           page="workflow")


def _mois_precedent(mois: str) -> str:
    a, m = map(int, M.normaliser_mois(mois).split("-"))
    return f"{a - 1}-12" if m == 1 else f"{a:04d}-{m - 1:02d}"


@app.route("/workflow/<cle>/faire", methods=["POST"])
def marquer_tache_faire(cle):
    mois = M.normaliser_mois(request.form.get("mois") or mois_courant())
    tache = next((t for t in cycle(mois) if t.cle == cle), None)
    if not tache:
        flash("Tâche inconnue pour ce mois.", "erreur")
        return redirect(url_for("page_workflow", mois=mois))
    db().execute("INSERT INTO taches (cle, mois, fait_le, note) VALUES (?,?,?,?)"
                 " ON CONFLICT(cle, mois) DO UPDATE SET fait_le=excluded.fait_le,"
                 " note=excluded.note",
                 (cle, mois, date.today().isoformat(), request.form.get("note", "").strip()))
    db().commit()
    flash(f"« {tache.titre} » marquée comme faite pour {M.libelle_mois(mois)}.", "ok")
    return redirect(url_for("page_workflow", mois=mois))


@app.route("/workflow/<cle>/annuler", methods=["POST"])
def marquer_tache_annuler(cle):
    mois = M.normaliser_mois(request.form.get("mois") or mois_courant())
    db().execute("DELETE FROM taches WHERE cle=? AND mois=?", (cle, mois))
    db().commit()
    flash("Tâche remise en attente.", "info")
    return redirect(url_for("page_workflow", mois=mois))


@app.route("/workflow/relancer", methods=["POST"])
def workflow_relancer():
    """Génère les relances du mois et les prépare pour l'envoi."""
    cfg = config()
    mois = M.normaliser_mois(request.form.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    relances = relances_du_mois(pt, cfg)
    envoyes = 0
    if cfg["smtp_hote"] and cfg["smtp_expediteur"]:
        envoyes = _envoyer_relances_email(relances, cfg, pt)
        if envoyes:
            flash(f"{envoyes} relance(s) envoyée(s) par email.", "ok")
    return redirect(url_for("page_workflow", mois=mois, _anchor="relances"))


def _envoyer_relances_email(relances, cfg, pt) -> int:
    """Envoie les relances par SMTP si un relais est configuré. Retourne le nb d'envois."""
    import smtplib
    from email.message import EmailMessage
    envoyes = 0
    try:
        with smtplib.SMTP(cfg["smtp_hote"], int(cfg["smtp_port"] or 587), timeout=15) as smtp:
            smtp.starttls()
            if cfg["smtp_utilisateur"]:
                smtp.login(cfg["smtp_utilisateur"], cfg["smtp_motdepasse"])
            for r in relances:
                row = db().execute("SELECT email FROM membres WHERE id=?",
                                   (r["membre_id"],)).fetchone()
                email = (row["email"] or "").strip() if row else ""
                if not email:
                    continue
                msg = EmailMessage()
                msg["From"] = cfg["smtp_expediteur"]
                msg["To"] = email
                msg["Subject"] = f"[{cfg['reseau']}] Cotisation {pt['libelle']} — {r['nom']}"
                msg.set_content(r["message"])
                smtp.send_message(msg)
                envoyes += 1
    except Exception as exc:  # un relais indisponible ne doit pas bloquer le pointage
        flash(f"Envoi email impossible : {exc}", "erreur")
    return envoyes


@app.route("/workflow/rapport")
def workflow_rapport():
    """Récapitulatif complet d'un mois, prêt à archiver."""
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    pt["echeance"] = M.echeance(mois, cfg["jour_echeance"])
    return render_template("rapport.html", cfg=cfg, mois=mois, pt=pt, taches=cycle(mois),
                           prog=W.progression(cycle(mois)),
                           paiements_du_mois=paiements(mois),
                           relances=relances_du_mois(pt, cfg))


@app.route("/workflow/reporter", methods=["POST"])
def workflow_reporter():
    """Clôture le mois : reporte les reliquats sur le mois suivant."""
    mois = M.normaliser_mois(request.form.get("mois") or mois_courant())
    suivant = M.mois_suivant(mois)
    pt = M.pointage(membres(), paiements(), mois)
    reports = [l for l in pt["lignes"] if l["reliquat"] > 0]
    for l in reports:
        deja = db().execute(
            "SELECT COUNT(*) FROM paiements WHERE membre_id=? AND mois=? AND libelle LIKE ?",
            (l["membre"].id, suivant, "Report automatique%")).fetchone()[0]
        if deja:
            continue
        db().execute("INSERT INTO paiements (date, montant, canal, expediteur, telephone,"
                     " libelle, mois, membre_id, statut, methode)"
                     " VALUES (?,?,?,?,?,?,?,?,?,?)",
                     (date.today().isoformat(), -l["reliquat"], "Report", l["membre"].nom,
                      l["membre"].telephone, f"Report automatique du reliquat de "
                      f"{M.libelle_mois(mois)}", suivant, l["membre"].id, "RAPPROCHE", "report"))
    db().execute("INSERT INTO taches (cle, mois, fait_le, note) VALUES (?,?,?,?)"
                 " ON CONFLICT(cle, mois) DO UPDATE SET fait_le=excluded.fait_le,"
                 " note=excluded.note",
                 ("reporter", mois, date.today().isoformat(),
                  f"{len(reports)} reliquat(s) reporté(s) sur {M.libelle_mois(suivant)}"))
    db().commit()
    flash(f"{len(reports)} reliquat(s) reporté(s) sur {M.libelle_mois(suivant)}.", "ok")
    return redirect(url_for("page_workflow", mois=suivant))


# --------------------------------------------------------------------------- #
# Espace membre (en libre-service)
# --------------------------------------------------------------------------- #

def membre_connecte():
    mid = session.get("membre_id")
    if not mid:
        return None
    r = db().execute("SELECT * FROM membres WHERE id=?", (mid,)).fetchone()
    return dict(r) if r else None


def portail_requis(f):
    @wraps(f)
    def wrapper(*args, **kwargs):
        if not membre_connecte():
            flash("Connectez-vous d'abord à votre espace membre.", "info")
            return redirect(url_for("portail_connexion"))
        return f(*args, **kwargs)
    return wrapper


@app.route("/portail/connexion", methods=["GET", "POST"])
def portail_connexion():
    if request.method == "GET":
        return render_template("portail_connexion.html", cfg=config(), page="portail")
    code = re.sub(r"\D", "", request.form.get("code") or "")
    fin = re.sub(r"\D", "", request.form.get("fin_tel") or "")
    m = next((x for x in membres() if x.code == code.zfill(3)), None) if len(code) >= 3 else None
    telephone = M.telephone_normalise(m.telephone) if m else ""
    if m and fin and telephone.endswith(fin) and len(fin) >= 4:
        session["membre_id"] = m.id
        flash(f"Bienvenue {m.nom}.", "ok")
        return redirect(url_for("portail"))
    flash("Code membre ou numéro de téléphone incorrect.", "erreur")
    return redirect(url_for("portail_connexion"))


@app.route("/portail/deconnexion", methods=["POST"])
def portail_deconnexion():
    session.pop("membre_id", None)
    flash("Vous êtes déconnecté.", "info")
    return redirect(url_for("payer"))


@app.route("/portail")
@portail_requis
def portail():
    cfg = config()
    m = membre_connecte()
    moi = next(x for x in membres() if x.id == m["id"])
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage([moi], paiements(), mois)
    ligne = pt["lignes"][0]
    historique = []
    for r in db().execute("SELECT DISTINCT mois FROM paiements WHERE membre_id=? AND mois != ''"
                          " ORDER BY mois DESC LIMIT 12", (moi.id,)):
        l = M.pointage([moi], paiements(), r["mois"])["lignes"][0]
        historique.append({"mois": r["mois"], "libelle": M.libelle_mois(r["mois"]),
                           "du": l["du"], "verse": l["verse"], "statut": l["statut"]})
    mes_formations = lignes(
        "SELECT inscriptions.*, formations.titre, formations.date AS date_formation,"
        " formations.heure, formations.mode, formations.lieu FROM inscriptions"
        " JOIN formations ON formations.id = inscriptions.formation_id"
        " WHERE inscriptions.membre_id = ? ORDER BY formations.date DESC", (moi.id,))
    mes_candidatures = lignes(
        "SELECT candidatures.*, offres.titre, offres.entreprise FROM candidatures"
        " JOIN offres ON offres.id = candidatures.offre_id"
        " WHERE candidatures.membre_id = ? ORDER BY candidatures.date_candidature DESC", (moi.id,))
    mes_activites = lignes(
        "SELECT participations.id AS pid, activites.* FROM participations"
        " JOIN activites ON activites.id = participations.activite_id"
        " WHERE participations.membre_id = ? ORDER BY activites.date DESC", (moi.id,))
    formations_ouvertes = lignes("SELECT * FROM formations WHERE statut='ouverte' ORDER BY date")
    offres_ouvertes = lignes("SELECT * FROM offres WHERE statut='ouverte' ORDER BY date_publication DESC")
    activites_ouvertes = lignes("SELECT * FROM activites WHERE statut='planifiee' ORDER BY date")
    return render_template("portail.html", cfg=cfg, moi=moi, mois=mois, ligne=ligne,
                           historique=historique, canaux=canaux(cfg),
                           mes_formations=mes_formations, mes_candidatures=mes_candidatures,
                           mes_activites=mes_activites, formations_ouvertes=formations_ouvertes,
                           offres_ouvertes=offres_ouvertes, activites_ouvertes=activites_ouvertes,
                           page="portail")


@app.route("/portail/formations/<int:fid>/inscrire", methods=["POST"])
@portail_requis
def portail_inscrire_formation(fid):
    m = membre_connecte()
    deja = db().execute("SELECT COUNT(*) FROM inscriptions WHERE formation_id=? AND membre_id=?",
                        (fid, m["id"])).fetchone()[0]
    if deja:
        flash("Vous êtes déjà inscrit(e) à cette formation.", "info")
    else:
        db().execute("INSERT INTO inscriptions (formation_id, membre_id, nom, telephone,"
                     " date_inscription) VALUES (?,?,?,?,?)",
                     (fid, m["id"], m["nom"], m["telephone"], date.today().isoformat()))
        db().commit()
        flash("Inscription enregistrée. Le formateur vous contactera.", "ok")
    return redirect(url_for("portail"))


@app.route("/portail/formations/<int:iid>/annuler", methods=["POST"])
@portail_requis
def portail_annuler_inscription(iid):
    m = membre_connecte()
    db().execute("DELETE FROM inscriptions WHERE id=? AND membre_id=?", (iid, m["id"]))
    db().commit()
    flash("Inscription annulée.", "info")
    return redirect(url_for("portail"))


@app.route("/portail/offres/<int:oid>/candidater", methods=["POST"])
@portail_requis
def portail_candidater(oid):
    m = membre_connecte()
    db().execute("INSERT INTO candidatures (offre_id, membre_id, nom, telephone, email, message,"
                 " date_candidature) VALUES (?,?,?,?,?,?,?)",
                 (oid, m["id"], m["nom"], m["telephone"], request.form.get("email", "").strip(),
                  request.form.get("message", "").strip(), date.today().isoformat()))
    db().commit()
    flash("Candidature transmise au responsable du réseau.", "ok")
    return redirect(url_for("portail"))


@app.route("/portail/activites/<int:aid>/participer", methods=["POST"])
@portail_requis
def portail_participer(aid):
    m = membre_connecte()
    try:
        db().execute("INSERT INTO participations (activite_id, membre_id) VALUES (?,?)",
                     (aid, m["id"]))
        db().commit()
        flash("Participation enregistrée.", "ok")
    except sqlite3.IntegrityError:
        flash("Vous êtes déjà inscrit(e) à cette activité.", "info")
    return redirect(url_for("portail"))


# --------------------------------------------------------------------------- #
# Exports
# --------------------------------------------------------------------------- #

def _csv(contenu: str, nom: str):
    buf = io.BytesIO(("\ufeff" + contenu).encode("utf-8"))
    return send_file(buf, mimetype="text/csv; charset=utf-8", as_attachment=True,
                     download_name=nom)


@app.route("/export/pointage.csv")
def export_pointage():
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    pt["echeance"] = M.echeance(mois, cfg["jour_echeance"])
    out = io.StringIO()
    w = csv.writer(out, delimiter=";")
    w.writerow([f"Pointage {cfg['reseau']} — {pt['libelle']}"])
    w.writerow([f"Édité le {datetime.now():%d/%m/%Y %H:%M}", "", "", "", "",
                "", "", f"Échéance : {pt['echeance']}"])
    w.writerow([])
    w.writerow(["Code", "Nom", "Téléphone", "Montant dû", "Montant versé", "Reliquat",
                "Statut", "Référence", "Nb paiements"])
    for l in pt["lignes"]:
        w.writerow([l["membre"].code, l["membre"].nom,
                    M.telephone_normalise(l["membre"].telephone), l["du"], l["verse"],
                    l["reliquat"], l["statut"], l["reference"], l["nb_paiements"]])
    t = pt["totaux"]
    w.writerow([])
    w.writerow(["TOTAL", "", "", t["du"], t["verse"], t["manquant"],
                f"{t['taux_montant']} % recouvré", "", ""])
    return _csv(out.getvalue(), f"pointage-{mois}.csv")


@app.route("/export/paiements.csv")
def export_paiements():
    out = io.StringIO()
    w = csv.writer(out, delimiter=";")
    w.writerow(["Date", "Montant", "Canal", "Expéditeur", "Téléphone", "Libellé",
                "Mois", "Membre", "Statut", "Méthode"])
    for p in paiements():
        w.writerow([p.date, p.montant, p.canal, p.expediteur, p.telephone, p.libelle,
                    p.mois, nom_membre(p.membre_id), p.statut, p.methode])
    return _csv(out.getvalue(), "paiements.csv")


@app.route("/export/membres.csv")
def export_membres():
    out = io.StringIO()
    w = csv.writer(out, delimiter=";")
    w.writerow(["Code", "Nom", "Téléphone", "Email", "Ville", "Spécialité", "Cotisation",
                "Adhésion", "Actif", "Exonéré"])
    for r in db().execute("SELECT * FROM membres ORDER BY code"):
        w.writerow([r["code"], r["nom"], r["telephone"], r["email"], r["ville"],
                    r["specialite"], r["cotisation"], r["date_adhesion"],
                    "oui" if r["actif"] else "non", "oui" if r["exonere"] else "non"])
    return _csv(out.getvalue(), "membres.csv")


@app.route("/export/relances.txt")
def export_relances():
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    canal = " / ".join(c["nom"] for c in canaux(cfg))
    blocs = [f"=== {l['membre'].nom} — {M.telephone_normalise(l['membre'].telephone)} ===\n"
             + M.message_relance(l, cfg["reseau"], canal, cfg["caisse_nom"])
             for l in pt["lignes"] if l["statut"] in (M.ST_IMPAYE, M.ST_PARTIEL)]
    texte = (f"RELANCES COTISATION {pt['libelle'].upper()} — {cfg['reseau']}\n"
             f"{len(blocs)} membre(s) à relancer\n\n" + "\n\n".join(blocs))
    buf = io.BytesIO(texte.encode("utf-8"))
    return send_file(buf, mimetype="text/plain; charset=utf-8", as_attachment=True,
                     download_name=f"relances-{mois}.txt")


@app.route("/export/pointage.xlsx")
def export_pointage_xlsx():
    try:
        from openpyxl import Workbook
        from openpyxl.styles import Alignment, Font, PatternFill
    except ImportError:
        flash("openpyxl indisponible : export CSV utilisé à la place.", "info")
        return redirect(url_for("export_pointage"))
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    pt["echeance"] = M.echeance(mois, cfg["jour_echeance"])
    wb = Workbook()
    ws = wb.active
    ws.title = pt["libelle"][:31]
    ws.append([f"{cfg['reseau']} — Pointage des cotisations — {pt['libelle']}"])
    ws["A1"].font = Font(bold=True, size=13)
    ws.append([f"Édité le {datetime.now():%d/%m/%Y %H:%M} · échéance {pt['echeance']}"])
    ws.append([])
    ws.append(["Code", "Nom", "Téléphone", "Dû", "Versé", "Reliquat", "Statut",
               "Référence", "Nb paiements"])
    for c in ws[4]:
        c.font = Font(bold=True, color="FFFFFF")
        c.fill = PatternFill("solid", fgColor="1F6F5C")
        c.alignment = Alignment(horizontal="center")
    couleurs = {M.ST_PAYE: "D8F0E3", M.ST_AVANCE: "CDEBFF", M.ST_PARTIEL: "FFF1CC",
                M.ST_IMPAYE: "FBD9D3", M.ST_EXONERE: "ECECEC"}
    for l in pt["lignes"]:
        ws.append([l["membre"].code, l["membre"].nom,
                   M.telephone_normalise(l["membre"].telephone), l["du"], l["verse"],
                   l["reliquat"], l["statut"], l["reference"], l["nb_paiements"]])
        fill = PatternFill("solid", fgColor=couleurs.get(l["statut"], "FFFFFF"))
        for c in ws[ws.max_row]:
            c.fill = fill
    t = pt["totaux"]
    ws.append([])
    ws.append(["TOTAL", "", "", t["du"], t["verse"], t["manquant"],
               f"{t['taux_montant']} %", "", ""])
    for c in ws[ws.max_row]:
        c.font = Font(bold=True)
    for col, largeur in zip("ABCDEFGHI", (8, 30, 16, 12, 12, 12, 14, 14, 14)):
        ws.column_dimensions[col].width = largeur
    buf = io.BytesIO()
    wb.save(buf)
    buf.seek(0)
    return send_file(buf, as_attachment=True, download_name=f"pointage-{mois}.xlsx",
                     mimetype="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")


@app.route("/etat")
def etat():
    cfg = config()
    mois = M.normaliser_mois(request.args.get("mois") or mois_courant())
    pt = M.pointage(membres(), paiements(), mois)
    pt["echeance"] = M.echeance(mois, cfg["jour_echeance"])
    return render_template("etat.html", cfg=cfg, pt=pt, mois=mois)


@app.route("/api/sante")
def sante():
    return jsonify({"ok": True, "membres": len(membres()), "paiements": len(paiements()),
                    "formations": len(lignes("SELECT id FROM formations")),
                    "offres": len(lignes("SELECT id FROM offres")),
                    "activites": len(lignes("SELECT id FROM activites")),
                    "mois_courant": mois_courant()})


init_db()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8000)), debug=False)
