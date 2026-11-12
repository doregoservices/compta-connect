# Relais CinetPay à IP fixe — guide d'installation (≈ 15 minutes)

CinetPay exige une adresse IP fixe. Ce petit serveur sert uniquement de passerelle entre la plateforme ComptaConnect et CinetPay. Coût : **CX22 ≈ 3,79 €/mois (≈ 2 500 F CFA)**, résiliable à tout moment.

## 1. Créer le compte Hetzner (au nom du cabinet)
1. Aller sur **https://www.hetzner.com/cloud** → « Sign up ».
2. E-mail : supportcomptaconnect@gmail.com (ou une adresse du cabinet) · mot de passe fort.
3. Renseigner l'entreprise : CABINET GROUPE DES SAGES COMPTABLES, adresse de Treichville, pays Côte d'Ivoire.
4. Moyen de paiement : carte bancaire ou PayPal. Hetzner peut demander une **vérification d'identité** (photo de la CNI) : c'est normal pour un nouveau compte hors Europe, prévoir quelques heures.

## 2. Créer le serveur
1. Dans la console : **New project** → nom `ComptaConnect` → **Add server**.
2. **Location** : Falkenstein ou Nuremberg (Allemagne).
3. **Image** : **Ubuntu 24.04**.
4. **Type** : Shared vCPU → **x86 → CX22** (ou le moins cher disponible).
5. **Networking** : laisser **IPv4 public coché** (indispensable) ; IPv6 au choix.
6. **SSH keys** : ignorer (un mot de passe root sera envoyé par e-mail ; à conserver).
7. **Cloud config** (section « Cloud config » / « User data », tout en bas) : **coller intégralement le contenu du fichier `cloud-init.yaml`** fourni par Nabil.
8. **Name** : `relais-cinetpay` → **Create & Buy now**.

## 3. Récupérer l'adresse IP
Après 1 à 2 minutes, la console affiche l'**IPv4 publique** du serveur (ex. `91.98.12.34`).
➜ Envoyer cette adresse à Nabil. L'installation se termine seule en 3 à 5 minutes.

## 4. Déclarer l'IP chez CinetPay
Panneau CinetPay → **Ressources → API & Sécurité → Liste blanche IP** :
- Adresse IP : l'IPv4 du serveur · Libellé : `Relais ComptaConnect` → **+**
- Supprimer les anciennes lignes de test (35.227.140.157, 0.0.0.0).

## 5. Ensuite (fait par Nabil)
Vérification `https://<ip-avec-tirets>.sslip.io/sante`, enregistrement de l'adresse du relais dans la plateforme, puis les 5 transactions test.

## Entretien
- Rien à faire au quotidien : mises à jour de sécurité automatiques, redémarrage automatique du service.
- La facture Hetzner arrive par e-mail chaque mois ; à enregistrer dans « Dépenses » de la plateforme (« Serveur relais CinetPay »).
- Ne jamais supprimer le serveur sans prévenir : les paiements en ligne s'arrêteraient.
