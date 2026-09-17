# ComptaConnect — sortir des prélèvements Chariow et automatiser le pointage

*Document mis à jour le 17 septembre 2026 avec les chiffres réels du relevé officiel
de juin-juillet 2026. Les tarifs des opérateurs et agrégateurs évoluent, à re-confirmer
avant signature.*

---

## 1. Le constat : ce que vous coûte Chariow aujourd'hui (vos chiffres réels)

Le relevé officiel « Liste officielle des membres à jour de cotisation — juin 2026 »
(période du 01/06 au 31/07/2026) donne les montants exacts :

| Poste | Montant |
|---|---|
| Membres à jour sur la période | **80** |
| Cotisation brute par membre | 5 000 FCFA |
| Prélèvement Chariow par membre | **750 FCFA** (frais de service 350 + frais de paiement 400) |
| Net perçu par membre | 4 250 FCFA |
| Total brut collecté | 400 000 FCFA |
| **Total prélevé par Chariow** | **60 000 FCFA (15 %)** |
| Total net perçu | 340 000 FCFA |

Soit **15 % de la collecte**, exactement le taux public de Chariow
([afrifute](https://afrifute.com/chariow-2026-guide-complet-pour-createurs-africains/),
[creationdigitalpro](https://creationdigitalpro.com/vendre-en-ligne-avec-chariow-ta-boutique-en-5-min/)) :
le prélèvement fixe (350 + 400) correspond bien à 15 % d'une cotisation de 5 000 FCFA.

Concrètement, sur la période juin-juillet, Chariow a prélevé **l'équivalent de
12 cotisations complètes** (60 000 ÷ 5 000). Sur une année à ce rythme, ce sont
plusieurs centaines de milliers de FCFA qui sortent de la caisse.

Pour une cotisation, c'est un non-sens : Chariow est conçu pour vendre des
formations ou des produits digitaux avec une boutique et du marketing. Une
cotisation de réseau a besoin d'un numéro où envoyer l'argent et d'un tableau
qui dit qui est à jour — rien de plus.

### Ce que cela représente selon la taille de la collecte

| Membres | Brut collecté | Prélèvement Chariow (750/membre) | Net perçu |
|---|---|---|---|
| 40 | 200 000 F | 30 000 F | 170 000 F |
| 80 (votre cas) | 400 000 F | **60 000 F** | 340 000 F |
| 120 | 600 000 F | 90 000 F | 510 000 F |
| 200 | 1 000 000 F | 150 000 F | 850 000 F |

Avec un compte mobile money au nom du réseau, ce prélèvement tombe à **0 FCFA** :
le membre transfère ses 5 000 FCFA, le réseau reçoit 5 000 FCFA, et l'éventuel
frais de transfert (~1 %, à la charge du membre) est plafonné à 5 000 FCFA chez
Wave — soit 50 FCFA pour une cotisation de 5 000.

---

## 2. Les options réelles en Côte d'Ivoire

### Option A — Compte mobile money du réseau + outil de pointage (recommandée)

Vous ouvrez **un compte marchand au nom du réseau** (Wave, Orange Money, MTN MoMo). Les membres transfèrent directement. Aucune plateforme intermédiaire, donc **aucune commission prélevée sur la cotisation**.

- **Wave** : l'encaissement marchand est gratuit pour le receveur ; le retrait d'espèces est gratuit et le transfert coûte 1 % à la charge de l'expéditeur, plafonné à 5 000 FCFA ([blog.iambeezy](https://blog.iambeezy.app/fr/frais-wave-cote-divoire-retrait-transfert-2026/), [momocalc](https://momocalc.com/fr/cote-divoire/frais-wave-ci)). Pour une cotisation de 5 000 FCFA, le membre paie environ 50 F de frais.
- **Orange Money** : le retrait est facturé 1 %, plafonné à 4 500 FCFA ([momocalc](https://momocalc.com/fr/cote-divoire/orange-ci-fees), [kabomal](https://kabomal.com/guide/retirer-argent-orange-money-cote-divoire/)). Les sources divergent sur le coût exact du transfert entre particuliers : certaines grilles 2026 annoncent des forfaits par palier (200 F jusqu'à 10 000 F), d'autres 1 à 3 % ([blog.iambeezy](https://blog.iambeezy.app/fr/tarif-orange-money-retrait-depot-transfert-2026/), [afrotools](https://afrotools.com/fr/blog/frais-orange-money-guide-2026/)). **À vérifier dans l'application au moment du transfert.**
- Aucune taxe gouvernementale par transaction n'est appliquée à l'utilisateur en Côte d'Ivoire ; le prélèvement de 7,2 % porte sur les revenus de commissions des opérateurs ([momocalc](https://momocalc.com/fr/cote-divoire/orange-ci-fees)).

**Coût pour le réseau : 0 FCFA sur les cotisations.** C'est le point décisif.

Le revers : il faut saisir ou importer les paiements pour tenir le pointage. C'est exactement ce que fait l'outil livré avec ce document (voir §4).

### Option B — Agrégateur de paiement (si vous voulez un vrai lien de paiement en ligne)

Utile si vous vendez aussi des formations payantes en ligne ou si vous voulez une page de paiement hébergée.

| Agrégateur | Mobile money | Carte bancaire | Source |
|---|---|---|---|
| FedaPay | 1,8 % | 3,6 % | [e-yebou](https://e-yebou.com/les-10-meilleurs-agregateurs-de-paiement-en-afrique-de-louest/) |
| Qosic | 1,7 % | 3,6 % | [warketingdigital](https://www.warketingdigital.net/integrateurs-dapi-de-mobile-money-en-afrique-francophone/) |
| KKiaPay | 1,9 % | 4 % | [warketingdigital](https://www.warketingdigital.net/integrateurs-dapi-de-mobile-money-en-afrique-francophone/) |
| PayDunya | 2 à 3 % | 2 à 3 % | [e-yebou](https://e-yebou.com/les-10-meilleurs-agregateurs-de-paiement-en-afrique-de-louest/) |
| CinetPay (lien de paiement) | 3,5 % (négociable à 1,5 % sur volume) | idem | [warketingdigital](https://www.warketingdigital.net/integrateurs-dapi-de-mobile-money-en-afrique-francophone/) |

⚠️ Ces fourchettes proviennent de comparatifs ; **le tarif réel se négocie** et dépend du pays et du portefeuille. Ne signez rien sans une grille écrite.

**Usage conseillé** : garder les cotisations en direct (Option A, 0 %) et ne passer par un agrégateur que pour les formations payantes, où la commission se justifie par la vente en ligne.

### Option C — Banque

Un compte au nom du réseau, alimenté par virement ou par transfert mobile money → banque. Adapté pour sécuriser la trésorerie au-delà d'un certain montant (les portefeuilles sont plafonnés à 2 000 000 FCFA de solde, [afrotools](https://afrotools.com/fr/blog/frais-orange-money-guide-2026/)). Le pointage se fait alors sur relevé bancaire, importable dans l'outil.

### Ce qu'il ne faut pas faire

Créer un lien de paiement « maison » qui encaisse sur un compte personnel. Trois risques : confusion des patrimoines, absence de justificatifs opposables, et impossibilité de rendre des comptes propres à l'assemblée. **Ouvrez le compte marchand au nom du réseau, avec au moins deux signataires.**

---

## 3. La recommandation

1. **Ouvrir un compte marchand Wave au nom du réseau** (frais les plus bas, retrait gratuit, QR code natif).
2. **Ouvrir en complément un compte Orange Money** au nom du réseau, pour les membres qui n'ont pas Wave.
3. **Garder Chariow uniquement si vous vendez des produits digitaux** (formations enregistrées, modèles de documents). Pas pour les cotisations.
4. **Basculer la trésorerie au-delà de 500 000 FCFA vers un compte bancaire** au nom du réseau.
5. **Utiliser l'outil ci-dessous pour le pointage** : c'est lui qui remplace la valeur ajoutée réelle de Chariow (le suivi), sans la commission.

---

## 4. L'outil livré : ce qu'il fait

Une application web complète, en français, qui tourne sur un ordinateur ou un petit serveur. Données stockées localement (SQLite), aucun abonnement.

### Module Cotisations — le pointage automatique

Chaque membre reçoit **un code à 3 chiffres**. Sa référence de paiement est construite automatiquement :

```
CC + 2609 + 042   →   CC2609042
   (année+mois)   (code membre)
```

Le membre inscrit cette référence dans le **motif** de son transfert. L'outil rapproche alors chaque paiement d'un membre et d'un mois selon quatre niveaux, du plus fiable au plus approximatif :

| Priorité | Critère | Fiabilité |
|---|---|---|
| 1 | Référence `CCaamm###` dans le motif | certaine |
| 2 | Numéro de téléphone de l'expéditeur | certaine |
| 3 | Nom de l'expéditeur dans le libellé | probable |
| 4 | Montant exact + un seul membre concerné | probable |

Résultat : **le tableau « qui a payé » se remplit tout seul**, mois par mois.

Ce que le module gère aussi :
- **Paiement partiel** : un acompte de 2 000 F sur 5 000 F apparaît en `partiel` avec le reliquat exact.
- **Avance** : un membre qui paie deux mois d'un coup est crédité du mois en cours, le surplus est reporté sur le mois suivant.
- **Exonérations** et membres inactifs (exclus du calcul du taux de recouvrement).
- **Relances WhatsApp générées automatiquement** : une par membre en retard, avec son nom, le montant, le motif obligatoire et le canal — ouvrables d'un clic via `wa.me`, ou téléchargeables en bloc.
- **Exports** : pointage en Excel (couleurs par statut), CSV, état imprimable A4 avec lignes de signature, liste des membres, historique des paiements.
- **Import de relevé** : copiez-collez l'historique Wave / Orange Money (ou un fichier CSV), l'outil l'importe et pointe en une fois.

### Module Membres

Fiche par membre (code, nom, téléphone, ville, spécialité, cotisation, adhésion, exonération), **import en masse** depuis Excel (`nom;telephone;ville;specialite`), et pour chacun un **lien de paiement personnel**.

### Module Formations

Publication d'une session (formateur, date, heure, durée, lieu, format en ligne / présentiel, participation, places, lien de connexion), inscription des membres ou de personnes extérieures, **feuille d'appel** (présent / absent), suivi du taux de remplissage.

### Module Offres d'emploi

Publication d'un poste (entreprise, ville, contrat, rémunération, missions, profil, contact, date limite), enregistrement des candidatures — membre du réseau ou externe — et **suivi du parcours** : reçue → transmise → entretien → retenu / refusé.

### Module Activités

Réunions, assemblées, actions de solidarité, rencontres de réseautage : date, lieu, format, participation, organisateur, et liste des participants.

### La page publique de paiement

Une page à épingler dans le groupe WhatsApp. Le membre entre son code et voit :
- sa situation (à jour / partiel / non réglée / avance) et le montant exact qui reste dû,
- sa référence de paiement en grand, avec un **QR code**,
- les numéros Wave / Orange Money / MTN du réseau, chacun avec son QR code,
- les consignes en 4 étapes.

C'est cette page qui remplace le « lien de paiement » de Chariow — sans commission.

---

## 5. Mise en place en 6 étapes

1. **Installer** : `pip install -r requirements.txt` puis `python3 app/app.py` → ouvrir http://localhost:8000.
2. **Configurer** (onglet Paramètres) : nom du réseau, cotisation, jour d'échéance, trésorier, et les **numéros Wave / Orange Money / MTN** du réseau.
3. **Importer les membres** depuis votre liste existante (copier-coller Excel).
4. **Vérifier le pointage** sur le mois en cours, pointer à la main les quelques paiements non reconnus.
5. **Épingler la page publique** dans le groupe WhatsApp, avec la consigne : *« inscrivez votre référence dans le motif, sinon votre paiement ne sera pas crédité automatiquement »*.
6. **Chaque mois** : importer le relevé, relancer le pointage automatique, envoyer les relances générées, éditer l'état imprimable pour l'assemblée.

### Pour aller plus loin

- **Héberger en ligne** pour que tout le bureau y accède : un petit VPS à ~3 000 F/mois, ou un service gratuit type Render / Railway. Prévoir alors un serveur WSGI (gunicorn) et une sauvegarde quotidienne du fichier `compta_connect.db`.
- **Automatiser complètement** : Wave et Orange Money Business exposent des API marchandes ; un relevé récupéré automatiquement chaque nuit rendrait le pointage 100 % automatique, sans saisie.
- **Notifications automatiques** : un envoi WhatsApp programmé (WhatsApp Business API, ou Twilio) le 5, le 10 et le 15 du mois.

---

## 6. Sources

- Frais Chariow : [afrifute](https://afrifute.com/chariow-2026-guide-complet-pour-createurs-africains/) · [creationdigitalpro](https://creationdigitalpro.com/vendre-en-ligne-avec-chariow-ta-boutique-en-5-min/) · [revenus-sur-internet-sans-visage](https://revenus-sur-internet-sans-visage.com/blog/%E2%AD%90-chariow-avis-2026-avantages-inconvenients-et-frais-pour-les-vendeurs-africains/) · [conditions officielles](https://chariow.com/fr/terms-of-service)
- Wave CI : [blog.iambeezy](https://blog.iambeezy.app/fr/frais-wave-cote-divoire-retrait-transfert-2026/) · [momocalc](https://momocalc.com/fr/cote-divoire/frais-wave-ci) · [recevoir un paiement Wave](https://blog.iambeezy.app/fr/recevoir-paiement-wave-cote-ivoire-2026/)
- Orange Money CI : [momocalc](https://momocalc.com/fr/cote-divoire/orange-ci-fees) · [kabomal](https://kabomal.com/guide/retirer-argent-orange-money-cote-divoire/) · [blog.iambeezy](https://blog.iambeezy.app/fr/tarif-orange-money-retrait-depot-transfert-2026/) · [afrotools](https://afrotools.com/fr/blog/frais-orange-money-guide-2026/)
- Agrégateurs : [warketingdigital](https://www.warketingdigital.net/integrateurs-dapi-de-mobile-money-en-afrique-francophone/) · [e-yebou](https://e-yebou.com/les-10-meilleurs-agregateurs-de-paiement-en-afrique-de-louest/) · [synnovaplus](https://synnovaplus.com/agregateurs-de-paiement-en-ligne-en-afrique/)
