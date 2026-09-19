# Déploiement — Compta Connect

Quatre options, de la plus simple à la plus complète.

---

## Option 0 — GitHub Pages + Supabase (gratuit, comme FKS Industrie) ✅

C'est l'architecture de votre appli FKS : **les pages sont sur GitHub, les
données sont dans un projet Supabase gratuit**. Aucun serveur à payer, aucune
mise en veille, adresse fixe `https://doregoservices.github.io/compta-connect/`.

Le site est déjà construit et poussé (dossier `docs/`, activé dans
Settings → Pages). Il reste la base de données, une seule fois.

**Pas besoin de créer un troisième projet** : le plan gratuit de Supabase
limite à 2 projets actifs. ComptaConnect s'installe **dans l'un de vos projets
existants** — toutes ses tables sont préfixées `cc_` et cohabitent sans rien
modifier ni écraser.

1. **Choisir le projet** Supabase qui hébergera ComptaConnect (n'importe
   lequel des deux ; les données des autres applications ne sont pas touchées).
2. **Installer la base** : menu *SQL Editor* → ouvrir `supabase/schema.sql`
   du dépôt (bouton *Raw*), tout copier, coller, **Run**.
   Ce fichier crée les tables `cc_`, la sécurité, ET vos 80 membres réels avec
   les cotisations de juin 2026 déjà pointées.
3. **Créer le compte trésorier** : *Authentication* → *Users* → *Add user* →
   votre email + un mot de passe (cochez « auto-confirm » pour éviter
   l'email de confirmation).
4. **Brancher l'application** : ouvrir le site, coller l'**URL du projet** et la
   **clé anon** (Supabase → *Paramètres* → *API*), enregistrer.
5. **Se connecter** avec l'email du trésorier : le tableau de bord s'ouvre.

La page publique des membres : `https://doregoservices.github.io/compta-connect/#/payer?code=006`

> Sécurité : la clé anon est publique par conception (comme dans FKS) — la
> lecture est publique, l'**écriture exige la connexion du trésorier** (droits
> RLS créés par schema.sql).

Limites de cette option : le bouton CinetPay (paiement 100 % automatique)
demande un petit relais serveur (fonction gratuite Supabase Edge, ou options
2/3). L'import du relevé mobile money reste le geste mensuel (~2 min).

---

## Pourquoi pas « GitHub Pages » seul ?

GitHub Pages ne sait servir que des **pages figées** (HTML/CSS/JS). Compta Connect
est un outil **vivant** : base de données des membres, import des relevés, pointage
automatique, notifications de paiement… Il lui faut un petit serveur.

Ce que GitHub apporte quand même, et c'est l'essentiel :

- **le code est sauvegardé et versionné** sur `github.com/doregoservices/compta-connect` ;
- **chaque modification poussée sur GitHub se déploie toute seule** sur Render
  (option 2) — le dépôt GitHub reste le point de départ de tout.

Le résultat pour les membres : une adresse fixe, du genre
`https://compta-connect.onrender.com/payer`, à épingler dans le groupe WhatsApp.

---

## Option 1 — En local sur l'ordinateur du trésorier (le plus simple)

Suffisant si une seule personne gère le pointage.

```bash
python3 app/app.py
```

Ouvrir <http://localhost:8000>. Les données restent sur la machine.

**Avantage** : rien à installer d'autre, aucune donnée sur internet.
**Limite** : le bureau n'y accède pas à distance.

Pour un accès depuis le téléphone ou le réseau local, utilisez l'adresse IP de
la machine (`http://192.168.x.x:8000`), affichée au démarrage.

---

## Option 2 — Render.com (gratuit, recommandé pour démarrer)

### Prérequis

1. Un compte sur [render.com](https://render.com), connecté avec votre compte GitHub.
2. Le dépôt `doregoservices/compta-connect` accessible.

### Étapes

**Méthode express (recommandée)** : Render → **New +** → **Blueprint** →
choisir le dépôt `compta-connect`. Le fichier `render.yaml` à la racine du dépôt
configure tout automatiquement (serveur, variables, vérification de santé).
Vous n'avez plus qu'à cliquer sur **Apply**.

Méthode manuelle, si vous préférez tout remplir :

1. Render → **New +** → **Web Service**.
2. Choisir le dépôt `compta-connect`.
3. Configuration :
   - **Runtime** : Python 3
   - **Build command** : `pip install -r requirements.txt`
   - **Start command** : `gunicorn --bind 0.0.0.0:$PORT app.app:app`
4. Variables d'environnement :

   | Clé | Valeur |
   |---|---|
   | `SECRET_KEY` | une longue chaîne aléatoire (voir ci-dessous) |
   | `COMPTA_DB` | `/opt/render/project/src/data/compta.db` |

   Générer un `SECRET_KEY` :
   ```bash
   python3 -c "import secrets; print(secrets.token_urlsafe(48))"
   ```

5. **Create Web Service**.

### ⚠️ Deux points importants sur l'offre gratuite

- **Le disque est éphémère** : la base SQLite est perdue à chaque redéploiage.
  Pour des données durables, il faut un **disque persistant** (Render Disk,
  payant ~1 $/mois) monté sur `/data`, ou passer à l'option 3.
- **Sans disque persistant, exportez `paiements.csv` et `membres.csv` après
  chaque pointage**, sinon vous perdez l'historique au prochain déploiement.

Un workflow GitHub Actions est déjà fourni
(`.github/workflows/deployer.yml`) : il relance le déploiement Render à chaque
push, à condition d'ajouter le secret `RENDER_DEPLOY_HOOK_URL` dans les
réglages du dépôt GitHub.

---

## Option 3 — VPS avec disque persistant (recommandé en production)

Un petit VPS (Hetzner, OVH, DigitalOcean, ~3 000 à 6 000 FCFA/mois) avec un
disque permanent. C'est la solution adaptée à une vraie trésorerie.

```bash
# sur le serveur
sudo apt update && sudo apt install -y python3-venv python3-pip nginx
git clone https://github.com/doregoservices/compta-connect.git
cd compta-connect
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt gunicorn
sudo mkdir -p /var/lib/compta && sudo chown $USER /var/lib/compta
```

Service systemd `/etc/systemd/system/compta.service` :

```ini
[Unit]
Description=Compta Connect
After=network.target

[Service]
User=www-data
WorkingDirectory=/home/votreuser/compta-connect
Environment="COMPTA_DB=/var/lib/compta/compta.db"
Environment="SECRET_KEY=votre_cle_secrete"
ExecStart=/home/votreuser/compta-connect/.venv/bin/gunicorn \
          --bind 127.0.0.1:8000 --workers 2 app.app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now compta
```

Puis un reverse proxy nginx avec HTTPS (certbot) devant le port 8000.

### Sauvegarde automatique

`/etc/cron.daily/compta-backup` :

```bash
#!/bin/sh
sqlite3 /var/lib/compta/compta.db ".backup '/var/backups/compta-$(date +%F).db'"
find /var/backups -name 'compta-*.db' -mtime +90 -delete
```

```bash
sudo chmod +x /etc/cron.daily/compta-backup
```

---

## À faire avant toute mise en ligne

### 1. Ajouter un mot de passe à l'administration

**C'est le point bloquant.** Actuellement, toute personne connaissant l'adresse
peut modifier les membres et les paiements.

Solution minimale — authentification HTTP par nginx :

```bash
sudo apt install apache2-utils
sudo htpasswd -c /etc/nginx/.htpasswd tresorier
```

Dans le bloc `location /` de nginx, **avant** le `proxy_pass`, en excluant les
pages publiques :

```nginx
location ~ ^/(payer|portail|static|api/moi) {
    proxy_pass http://127.0.0.1:8000;
}
location / {
    auth_basic "Compta Connect — administration";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://127.0.0.1:8000;
}
```

Les membres continuent d'accéder librement à `/payer` et à leur espace
`/portail` (protégé par code + téléphone) ; tout le reste demande le mot de
passe du bureau.

### 2. Choisir un `SECRET_KEY` solide

Il signe les sessions de l'espace membre. À changer à la première installation
et à ne jamais publier.

### 3. Forcer HTTPS

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d compta.votredomaine.ci
```

### 4. Vérifier les sauvegardes

Faites un test de restauration **avant** d'avoir besoin d'une sauvegarde :
copiez le fichier `.db` ailleurs, ouvrez-le, vérifiez que les données sont là.

---

## Mise à jour de l'application

```bash
cd compta-connect
git pull
.venv/bin/pip install -r requirements.txt
sudo systemctl restart compta
```

Les migrations de base sont automatiques : `init_db()` ajoute les colonnes
manquantes au démarrage. **La base n'est jamais écrasée** par une mise à jour.

Pour repartir de zéro volontairement : **Paramètres** → *Réinitialiser la base*
(exportez d'abord).

---

## Vérification après déploiement

```bash
curl https://compta.votredomaine.ci/api/sante
```

Doit renvoyer :

```json
{"ok": true, "membres": 6, "paiements": 4, "formations": 2, "offres": 2,
 "activites": 2, "mois_courant": "2026-09"}
```

Puis vérifier à la main :
1. `/` → le tableau de bord s'affiche,
2. `/payer?code=001` → la situation du membre 001 et un QR code,
3. `/portail/connexion` → connexion avec un code + 4 chiffres,
4. enregistrer un paiement test puis le supprimer.

---

## Paiement en ligne automatique (CinetPay) — comme Chariow, sans ses 15 %

Le membre clique sur **« Payer maintenant »** sur sa page, règle par mobile money
ou carte, et CinetPay notifie l'outil immédiatement : le pointage passe à jour
**tout seul**, sans aucune saisie du trésorier.

### Mise en place (une seule fois, ~15 minutes)

1. Créer un compte marchand sur [cinetpay.com](https://cinetpay.com)
   (entreprise ivoirienne ; commission ≈ 3,5 %, contre 15 % chez Chariow).
2. Dans le tableau de bord CinetPay, créer une **page de paiement** pour le réseau.
3. Noter l'**identifiant du site** (site_id) et la **clé API** (apikey).
4. Dans l'outil : **Paramètres → Paiement en ligne automatique** :
   - activer le bouton,
   - coller le site_id et l'apikey,
   - renseigner l'**adresse publique** de l'outil (ex. `https://compta-connect.onrender.com/`).
5. Dans CinetPay, déclarer l'**URL de notification** :
   `https://ADRESSE-DE-L-OUTIL/api/ipn/cinetpay`

### Tester sans argent réel

CinetPay fournit des **clés sandbox** (bac à sable) : configurez-les d'abord,
réglez une cotisation fictive, vérifiez que la ligne du membre passe à
<span>« à jour »</span> seule. Puis basculez sur les clés de production.

### Sécurité intégrée

- La notification de CinetPay n'est jamais crue sur parole : l'outil **revérifie
  le statut auprès de CinetPay** avant de créditer.
- Une même transaction ne peut pas être créditée deux fois (idempotence).
- Les transferts directs (Wave/OM/MTN avec la référence en motif) restent
  possibles en parallèle — 0 % de frais pour ceux qui préfèrent.

### Ce que ça change pour le trésorier

| | Chariow | Import manuel | CinetPay intégré |
|---|---|---|---|
| Le membre clique et paie | ✅ | ❌ (transfert + motif) | ✅ |
| Pointage instantané | ✅ | ❌ (import mensuel) | ✅ |
| Frais sur 5 000 FCFA | 750 | 0 | ≈ 175 |
| Frais pour 80 membres/mois | 60 000 | 0 | ≈ 14 000 |

Les deux modes cohabitent : le bouton pour le confort, le motif pour le zéro frais.
