# Fichier à ajouter manuellement sur GitHub

Le jeton utilisé pour le premier push n'avait pas le droit `workflow`, qui est
obligatoire pour créer un fichier d'automatisation GitHub Actions.

## Deux solutions

### Solution A — l'ajouter via le site (2 minutes)

1. Ouvrir <https://github.com/doregoservices/compta-connect>
2. **Add file** → **Create new file**
3. Dans le champ du nom, taper exactement :
   `.github/workflows/deployer.yml`
4. Copier-coller le contenu de `deployer.yml` (ce dossier)
5. **Commit changes**

### Solution B — régénérer un jeton avec le bon droit

1. <https://github.com/settings/tokens>
2. **Generate new token (classic)**
3. Cocher `repo` **et** `workflow`
4. Puis, en local :

```bash
git add .github
git commit -m "Ajout du déploiement automatique Render"
git push origin main
```

## À quoi sert ce fichier

À chaque push sur `main`, il lance les 87 tests puis déclenche un déploiement
Render — uniquement si le secret `RENDER_DEPLOY_HOOK_URL` est renseigné dans
**Settings → Secrets and variables → Actions** du dépôt. Sans ce secret, il ne
fait rien d'autre que les tests.
