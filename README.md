# Compta Connect — plateforme de gestion pour réseau de comptables

Application web complète pour gérer une communauté de comptables :
**cotisations avec pointage automatique**, membres, formations, offres d'emploi,
activités et espace membre en libre-service.

Conçue pour fonctionner **sans plateforme intermédiaire** : les cotisations
arrivent directement sur le compte mobile money du réseau, donc aucune
commission prélevée (contre 15 % sur une plateforme de vente type Chariow).

Interface entièrement en français. Aucune dépendance à un service externe.

---

## Démarrage rapide

```bash
git clone https://github.com/doregoservices/compta-connect.git
cd compta-connect
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 app/app.py
```

Ouvrir <http://localhost:8000>.

Les données sont stockées dans `app/compta_connect.db` (SQLite).
Pour utiliser un autre emplacement : `COMPTA_DB=/chemin/base.db python3 app/app.py`.

Au premier lancement, un jeu de démonstration est chargé (6 membres, 2 formations,
2 offres, 2 activités, 4 paiements). Il se réinitialise depuis **Paramètres**.

---

## Modules

| Module | Ce qu'il fait |
|---|---|
| **Tableau de bord** | Taux de recouvrement, membres à jour, alertes, activité du réseau |
| **Membres** | Fiches, import en masse depuis Excel, exonérations, lien de paiement personnel |
| **Cotisations** | Pointage automatique, relances WhatsApp, exports Excel / état signé |
| **Cycle mensuel** | Échéancier des 7 tâches du mois, clôture et report des reliquats |
| **Paiements** | Saisie, import de relevé mobile money, pointage manuel |
| **Formations** | Sessions, inscriptions, feuille d'appel présent / absent |
| **Offres d'emploi** | Postes, candidatures, suivi reçue → entretien → retenu |
| **Activités** | Réunions, AG, solidarité, avec liste des participants |
| **Espace membre** | Libre-service : cotisations, inscriptions, candidatures |
| **Page publique** | Situation du membre, référence, QR codes des numéros |

---

## Le pointage automatique

Chaque membre reçoit un **code à 3 chiffres**. Sa référence de paiement est
construite automatiquement :

```
CC  +  2609  +  042      →      CC2609042
     année+mois   code         (septembre 2026, membre 042)
```

Le membre inscrit cette référence dans le **motif** de son transfert mobile
money. L'outil rapproche alors chaque paiement d'un membre et d'un mois, selon
quatre règles appliquées dans l'ordre :

| # | Critère | Fiabilité |
|---|---|---|
| 1 | référence `CCaamm###` dans le motif | certaine |
| 2 | numéro de téléphone de l'émetteur | certaine |
| 3 | nom de l'émetteur dans le libellé | probable |
| 4 | montant exact, un seul membre concerné | probable |

Ce qui reste non identifié est signalé et se pointe en un clic.

Sont gérés : **acomptes** (statut partiel + reliquat), **avances** (report sur le
mois suivant), **exonérations** et **membres inactifs** (exclus du taux de
recouvrement).

---

## Cycle mensuel des cotisations

Sept tâches générées automatiquement à partir du jour d'échéance :

| Étape | Quand | Action |
|---|---|---|
| Ouverture | J-10 | Publier montant et références |
| Premier pointage | J | Importer le relevé mobile money |
| Relance amicale | J+3 | Messages WhatsApp générés |
| Relance insistante | J+8 | Copie au bureau |
| Dernier avis | J+15 | Avant suspension |
| État signé | J+20 | Document à archiver |
| Clôture | fin du mois | Report automatique des reliquats |

Chaque tâche passe en **retard** si elle n'est pas traitée à sa date.

---

## Documentation

| Document | Contenu |
|---|---|
| [`WORKFLOWS.md`](WORKFLOWS.md) | **Le mode d'emploi détaillé** : chaque module étape par étape, qui fait quoi, la routine mensuelle |
| [`Comparatif-frais-et-plan.md`](Comparatif-frais-et-plan.md) | Analyse des frais (Chariow, Wave, Orange Money, agrégateurs) et plan de mise en place |
| [`DEPLOIEMENT.md`](DEPLOIEMENT.md) | Mise en ligne, sauvegardes, sécurité |

---

## Structure

```
app/
  app.py        application Flask : routes, base de données, exports
  moteur.py     logique métier : références, rapprochement, pointage mensuel
  workflow.py   échéancier du cycle mensuel
  qrcode.py     QR codes SVG (bibliothèque segno)
  templates/    interface (15 écrans)
  static/       feuille de style
tests/
  test_moteur.py        logique de pointage (36 tests)
  test_workflow.py      échéancier mensuel (9 tests)
  test_qrcode.py        QR codes vérifiés scannables par libzbar
  test_integration.py   toutes les pages + scénarios de cotisation
  test_avance.py        cycle mensuel + espace membre
```

## Tests

```bash
python3 -m pytest tests/ -q        # 87 tests
```

`pyzbar` nécessite la bibliothèque système `libzbar0`
(`sudo apt-get install libzbar0`) ; sans elle, les tests de QR code sont sautés
sans bloquer la suite.

---

## Sécurité — à lire avant mise en ligne

- **L'interface d'administration n'a pas encore de mot de passe.** Ne l'exposez
  pas sur internet en l'état : limitez l'accès au réseau du bureau, ou ajoutez
  d'abord une authentification (voir [`DEPLOIEMENT.md`](DEPLOIEMENT.md)).
- **L'espace membre** est protégé par code membre + 4 derniers chiffres du
  téléphone. Ce n'est pas une authentification forte : suffisant pour la
  consultation, insuffisant pour des données sensibles.
- **La base contient des données personnelles** (noms, téléphones, emails,
  paiements). Elle est exclue de Git (`.gitignore`) et doit être sauvegardée
  hors du serveur.
- **Jamais de secret dans le dépôt.** Utilisez des variables d'environnement
  (voir `.env.example`).

---

## Licence

Usage libre pour le réseau Compta Connect.
