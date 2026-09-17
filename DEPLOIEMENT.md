# Déploiement — Compta Connect

Trois options, de la plus simple à la plus complète.

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
