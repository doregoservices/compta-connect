# Workflows — Compta Connect

Comment fonctionne chaque module, étape par étape, et qui fait quoi.

Légende : **Tr** = trésorier · **Sec** = secrétaire / responsable formations · **Mb** = membre · **Auto** = fait par l'outil sans intervention.

---

## 1. Cotisations — le cycle mensuel

C'est le cœur du système. Un mois de cotisation suit sept étapes, générées automatiquement dans l'onglet **Cycle mensuel**. Les dates sont calculées à partir du jour d'échéance défini dans Paramètres (10 par défaut).

### Vue d'ensemble

```
        J-10              J (échéance)        J+3        J+8        J+15       J+20       fin du mois
          │                    │                │          │          │          │              │
   ┌──────▼──────┐    ┌────────▼────────┐  ┌────▼───┐ ┌────▼───┐ ┌────▼────┐ ┌───▼────┐  ┌──────▼──────┐
   │ OUVERTURE   │    │ PREMIER POINTAGE│  │RELANCE │ │RELANCE │ │ DERNIER │ │  ÉTAT  │  │  CLÔTURE    │
   │ Tr publie   │    │ Tr importe le   │  │ amicale│ │insist. │ │  AVIS   │ │ signé  │  │  + REPORT   │
   │ montant et  │    │ relevé mobile   │  │  Auto  │ │  Auto  │ │  Auto   │ │  Tr    │  │   Auto      │
   │ références  │    │ money → Auto    │  │ génère │ │ génère │ │ génère  │ │        │  │             │
   └─────────────┘    └─────────────────┘  └────────┘ └────────┘ └─────────┘ └────────┘  └─────────────┘
```

### Étape 1 — Ouverture (Tr, J-10)

1. Ouvrir **Cycle mensuel**, sélectionner le mois.
2. Cliquer sur l'action de la tâche « Ouverture ».
3. Copier le message type dans le groupe WhatsApp :

> Cotisation de [mois] : 5 000 FCFA, à régler avant le [date].
> Motif obligatoire : CC + votre code (ex. CC2609042).
> Vérifiez votre situation : [lien de la page publique]

4. Marquer la tâche **fait**.

### Étape 2 — Le membre paie (Mb)

1. Ouvre la page publique (ou son espace membre) et entre son code.
2. Voit son montant exact, sa référence et les numéros Wave / Orange Money / MTN.
3. Transfère en inscrivant **la référence dans le motif**.
4. Envoie la capture du reçu dans le groupe.

### Étape 3 — Pointage automatique (Auto + Tr, le jour de l'échéance)

Deux façons d'alimenter le pointage :

**a) Saisie au fil de l'eau** — onglet **Paiements** → « Enregistrer un paiement reçu ». Laissez le champ *Membre* vide : l'outil identifie le payeur tout seul.

**b) Import du relevé** (recommandé, plus rapide) — onglet **Paiements** → *Importer un relevé* → copiez-collez l'historique Wave / Orange Money → *Importer et pointer*.

L'outil applique alors quatre règles, dans cet ordre :

| # | Critère | Résultat |
|---|---|---|
| 1 | Référence `CCaamm###` dans le motif | rapprochement certain |
| 2 | Numéro de téléphone de l'émetteur | rapprochement certain |
| 3 | Nom de l'émetteur dans le libellé | rapprochement probable |
| 4 | Montant exact, un seul membre concerné | rapprochement probable |

Tout ce qui reste non identifié apparaît dans l'encadré orange **« N paiement(s) non rapproché(s) »**. Le trésorier clique sur *Pointer* et choisit le membre. Cinq minutes par mois.

### Étape 4, 5, 6 — Les trois relances (Auto + Tr)

| Relance | Quand | Ton |
|---|---|---|
| Amicale | J+3 | « il te reste X FCFA à régler » |
| Insistante | J+8 | copie au bureau du réseau |
| Dernier avis | J+15 | annonce de suspension des services |

Chaque message est **généré automatiquement**, personnalisé avec le prénom, le montant exact, la référence obligatoire et les canaux de paiement. Deux façons de l'envoyer :

- **WhatsApp** : bouton *Ouvrir dans WhatsApp* sur chaque membre (ouvre `wa.me` avec le texte prêt).
- **En masse** : bouton *⬇ Relances* → fichier texte avec tous les messages, à copier-coller.
- **Email** (facultatif) : si un relais SMTP est configuré dans Paramètres, le bouton *Générer / envoyer* envoie aussi un email à chaque membre dont l'adresse est renseignée.

### Étape 7 — État signé (Tr, J+20)

Onglet **Cotisations** → *🖨 État imprimable* → imprimer ou *Enregistrer en PDF*. Le document comporte le tableau complet, les totaux, le taux de recouvrement et deux lignes de signature (trésorier, président). À archiver : c'est la pièce justificative de la gestion.

Pour un document plus complet : **Cycle mensuel** → *Rapport du mois* (situation financière + détail par membre + mouvements + suivi des tâches).

### Étape 8 — Clôture et report (Auto, fin du mois)

**Cycle mensuel** → bouton *Reporter les reliquats*. Chaque membre avec un reste à payer voit son reliquat inscrit sur le mois suivant avec le libellé `Report automatique du reliquat de [mois]`, en négatif. La tâche est cochée et la période archivée.

> Relancer la clôture ne duplique jamais un report : l'outil vérifie s'il existe déjà.

### Cas particuliers

| Situation | Comportement |
|---|---|
| Acompte (2 000 sur 5 000) | statut **partiel**, reliquat 3 000, le membre est relancé pour le solde |
| Paiement de deux mois | statut **avance**, l'excédent est reporté sur le mois suivant |
| Membre exonéré | statut **exonéré**, exclu du total dû et du taux de recouvrement |
| Membre inactif / sorti | exclu du pointage, n'apparaît plus dans les relances |
| Paiement sans motif ni numéro connu | reste **à pointer**, signalé en orange |

### Rythme recommandé

| Moment | Action | Durée |
|---|---|---|
| J-10 | Publication dans le groupe | 2 min |
| Chaque jour | Saisie des reçus reçus (ou rien) | 3 min |
| J (échéance) | Import du relevé + pointage | 10 min |
| J+3, J+8, J+15 | Envoi des relances générées | 5 min |
| J+20 | Édition de l'état signé | 5 min |
| Fin du mois | Clôture et report | 1 min |

---

## 2. Membres

### Ajouter un membre

**Membres** → formulaire → nom, téléphone, email, ville, spécialité, cotisation. Le **code à 3 chiffres est attribué automatiquement** (001, 002, …) : c'est lui qui sert de référence de paiement.

### Importer toute la liste d'un coup

**Membres** → *Importer une liste existante* → collez depuis Excel au format :

```
nom;telephone;email;ville;specialite
KOUAME Adjoua;0708091011;adjoua@example.ci;Abidjan;Comptable générale
DIALLO Mamadou;0544556677;diallo@example.ci;Bouaké;Fiscaliste
```

Séparateur au choix : point-virgule, virgule ou tabulation. Les doublons de nom sont ignorés.

### Modifier / exonérer / désactiver

Bouton **Éditer** sur la ligne du membre. Deux cases utiles :
- **Exonéré** : ne doit plus rien, reste membre actif.
- **Membre actif** : à décocher pour un membre sorti du réseau (il disparaît du pointage sans être supprimé).

### Exporter

*⬇ Exporter la liste* → CSV ouvrable dans Excel.

---

## 3. Espace membre (libre-service)

C'est ce qui fait baisser la charge administrative : **le membre fait lui-même**.

### Connexion

Page publique → *Se connecter à mon espace* → **code membre** + **les 4 derniers chiffres de son numéro de téléphone**. Les deux sont nécessaires : le code seul est trop court pour être deviné.

### Ce que le membre peut faire seul

| Action | Où |
|---|---|
| Voir son statut de cotisation et son historique | en haut de son espace |
| Obtenir sa référence et le QR code du mois | en haut de son espace |
| S'inscrire à une formation / se désinscrire | onglet Formations |
| Postuler à une offre d'emploi | onglet Offres |
| S'inscrire à une activité | onglet Activités |

Chaque action arrive directement dans le tableau de bord du bureau, avec le statut du membre. Plus de liste à tenir à la main dans le groupe.

### Côté bureau

Les inscriptions et candidatures issues du portail apparaissent dans **Formations**, **Offres** et **Activités**, exactement comme si elles avaient été saisies par le secrétaire.

---

## 4. Formations

### Publier une session

**Formations** → *Programmer une formation* :
titre, formateur (un membre du réseau), date, heure, durée, format (en ligne / présentiel / hybride), lieu ou plateforme, participation (0 = gratuit), nombre de places, lien de connexion, programme.

### Gérer les inscrits

Cliquer sur **Gérer** :
- inscrire un membre du réseau (menu déroulant) **ou** une personne extérieure (nom + téléphone),
- voir le remplissage (inscrits / places),
- le jour J, faire l'appel avec le bouton **présent / absent**.

### Le membre s'inscrit seul

Depuis son espace membre, bouton *Je m'inscris*. Une double inscription est refusée proprement.

### Clôturer

Dans **Gérer** → champ *Statut* : `ouverte` → `en cours` → `terminee`. La formation disparaît du tableau de bord mais reste dans l'historique, avec le nombre de présents.

---

## 5. Offres d'emploi

### Publier un poste

**Offres d'emploi** → *Publier une offre* :
intitulé, entreprise, ville, contrat (CDI, CDD, stage, mission, freelance, alternance), rémunération, date de publication, date limite, missions, profil recherché, contact, email.

### Suivre les candidatures

Cliquer sur **Gérer** sur l'offre. Chaque candidature passe par un parcours :

```
   recue ──→ transmise ──→ entretien ──→ retenu
                                    └──→ refuse
```

Le membre voit son statut dans son espace membre : il sait où il en est sans relancer.

### Clôturer

Champ *Statut* : `ouverte` → `pourvue` (poste pris) ou `fermee` / `suspendue`. L'offre disparaît de l'espace membre mais l'historique des candidatures est conservé.

---

## 6. Activités du réseau

Réunions, assemblées générales, actions de solidarité, rencontres de réseautage.

### Créer

**Activités** → *Créer une activité* : titre, catégorie (Rencontre, Réunion, Solidarité, Formation, Réseautage, Assemblée, Autre), date, heure, format, lieu, participation, organisateur, description.

### Gérer les participants

Le bureau inscrit un membre depuis le menu déroulant ; le membre s'inscrit lui-même depuis son espace. Une double inscription est bloquée.

### Clôturer

Statut : `planifiee` → `en cours` → `terminee` ou `annulee`.

---

## 7. Tableau de bord

Un coup d'œil pour la réunion du bureau :

- **Taux de recouvrement** du mois et montant encaissé / dû,
- **Membres à jour**, partiels et impayés,
- **Reste à encaisser** et date d'échéance,
- **Nombre de membres actifs**,
- **Formations et offres ouvertes**,
- Aperçu du pointage, historique des mois précédents,
- Alertes : paiements non rapprochés, échéance dépassée.

---

## 8. Exports et archivage

| Export | Contenu | Usage |
|---|---|---|
| `pointage-[mois].xlsx` | Tableau du mois avec couleurs par statut | Suivi comptable |
| `pointage-[mois].csv` | idem, texte | Import dans un autre outil |
| `état` (PDF) | Document signé, totaux, signatures | **Pièce d'archive pour l'AG** |
| `rapport du mois` (PDF) | Situation + membres + mouvements + tâches | Compte rendu de gestion |
| `relances-[mois].txt` | Tous les messages WhatsApp | Relance en masse |
| `membres.csv` | Liste complète des membres | Sauvegarde |
| `paiements.csv` | Historique complet des versements | **Registre des recettes** |

**Recommandation** : chaque fin de mois, téléchargez l'état signé, le rapport et `paiements.csv`, et archivez-les dans un dossier `Compta Connect/2026/09-septembre/`.

---

## 9. Rôles et responsabilités

| Rôle | Responsabilités | Accès |
|---|---|---|
| **Trésorier** | Pointage, relances, état signé, clôture, comptes bancaires | Toute l'application |
| **Secrétaire** | Membres, formations, offres, activités | Toute l'application |
| **Président** | Validation de l'état, décisions de suspension | Consultation + signature |
| **Membre** | Ses cotisations, ses inscriptions, ses candidatures | Son espace uniquement |

> ⚠️ **Version actuelle** : l'interface d'administration n'a pas encore de mot de passe. Ne l'exposez sur internet qu'après avoir ajouté une authentification, ou limitez l'accès au réseau du bureau. L'espace membre, lui, est protégé par code + téléphone.

---

## 10. Routine mensuelle en une page

```
J-10  → Publier le montant et les références dans le groupe
        [Cycle mensuel → tâche Ouverture]

J     → Importer le relevé mobile money
        [Paiements → Importer un relevé]
        Pointer les quelques paiements non reconnus

J+3   → Relance amicale
        [Cycle mensuel → Générer les relances → WhatsApp]

J+8   → Relance insistante (copie au bureau)

J+15  → Dernier avis avant suspension

J+20  → Éditer et signer l'état de pointage
        [Cotisations → État imprimable]

Fin   → Reporter les reliquats sur le mois suivant
du mois [Cycle mensuel → Reporter les reliquats]

Chaque semaine → Publier formations et offres d'emploi
                 [Formations] [Offres d'emploi]
```
