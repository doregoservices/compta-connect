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
