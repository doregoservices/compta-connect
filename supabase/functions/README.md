# Paiement en ligne CinetPay — fonctions serveur (Supabase Edge Functions)

Deux fonctions, à déployer **une seule fois** par le propriétaire du projet Supabase :

| Fonction | Rôle |
|---|---|
| `cinetpay-init` | Le membre clique « Payer en ligne » → crée la transaction chez CinetPay (clés lues dans la table privée `cc_secrets`) → renvoie l'URL de paiement |
| `cinetpay-notify` | Appelée par CinetPay quand le paiement est fait (`notify_url`) et par le navigateur au retour → **revérifie** la transaction auprès de CinetPay → enregistre le paiement (rapproché, idempotent) → le trigger active le membre |

Aucune clé n'est dans le code : les fonctions utilisent la clé service du projet (fournie
automatiquement par Supabase) pour lire `cc_secrets`, où le trésorier a collé lui-même
l'API Key et le Site ID depuis *Paramètres*.

## État : DÉPLOYÉES le 29/10/2026 sur le projet `ewcxndlelagtrlshadlj` (v1, verify_jwt=false)

Pour une future mise à jour, deux voies :
- API de gestion : `POST https://api.supabase.com/v1/projects/<ref>/functions/deploy?slug=<nom>` (multipart : metadata + fichiers), avec un jeton d'accès personnel ;
- ou la CLI ci-dessous.

## Déploiement par la CLI (alternative)

1. Installer la CLI Supabase : `npm i -g supabase` (ou `brew install supabase/tap/supabase`)
2. `supabase login` (ouvre le navigateur)
3. Dans ce dossier : `supabase link --project-ref ewcxndlelagtrlshadlj`
4. `supabase functions deploy cinetpay-init --no-verify-jwt`
   `supabase functions deploy cinetpay-notify --no-verify-jwt`
   (`--no-verify-jwt` : CinetPay appelle le webhook sans jeton Supabase ; la fonction
   revérifie elle-même chaque transaction auprès de CinetPay, c'est la vraie sécurité.)
5. Dans Supabase → SQL Editor : exécuter `supabase/cinetpay.sql` (table `cc_transactions`,
   fonction `cc_paiement_en_ligne_dispo`).
6. Dans CinetPay → *Intégration* : URL de notification =
   `https://ewcxndlelagtrlshadlj.supabase.co/functions/v1/cinetpay-notify`

Dès que le trésorier a collé ses clés dans *Paramètres*, le bouton « Payer en ligne »
apparaît tout seul sur les pages des membres. Sans clés, il reste invisible et le
transfert manuel avec référence continue de fonctionner.

## Test sans argent réel
CinetPay fournit des clés de test (sandbox). Les coller dans *Paramètres*, payer 100 F
sur la page d'un membre test, vérifier que la ligne apparaît dans *Paiements* avec le canal
« CinetPay », puis remplacer par les clés de production.

## Fonction `acces` (déployée le 06/11/2026, v1, verify_jwt=false)
Gestion des comptes de l'espace trésorier depuis *Paramètres → Accès* : lister, créer (e-mail + mot de passe + rôle),
changer un mot de passe, changer un rôle, supprimer. La fonction vérifie elle-même le jeton de l'appelant et exige le
rôle `tresorier` (table `cc_roles`). Garde-fous : impossible de supprimer son propre compte ou de se retirer le rôle trésorier.
Redéploiement : `SUPABASE_ACCESS_TOKEN=sbp_… python3 scripts/deployer_fonctions.py`

## Nouvelle API CinetPay v1 (panel.cinetpay.net)
Si la clé enregistrée dans `cc_secrets.cinetpay_api_key` commence par `sk_test_` ou `sk_live_`, les fonctions utilisent l'API v1 :
`POST {base}/v1/oauth/login {api_key, api_password}` → jeton, puis `POST /v1/payment` (payment_url, payment_token, notify_token, transaction_id CinetPay) et `GET /v1/payment/{merchant_transaction_id}` pour vérifier (`status === "SUCCESS"`).
Le champ `cinetpay_site_id` contient alors le **mot de passe API**. `sk_test_` → `https://api.cinetpay.net` (bac à sable), `sk_live_` → `https://api.cinetpay.co`.
Le webhook v1 envoie `{notify_token, merchant_transaction_id, transaction_id}` ; `cinetpay-notify` retrouve la transaction par `merchant_transaction_id` (ou `cinetpay_id`), contrôle le `notify_token`, puis revérifie le statut auprès de CinetPay avant d'enregistrer.
