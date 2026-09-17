# Identité visuelle ComptaConnect

Extraite automatiquement du document officiel
`ComptaConnect_Cotisation_Juin2026.pdf` (formes vectorielles, couleurs de
texte et image intégrée).

## Logo

| Fichier | Contenu |
|---|---|
| `logo-original.jpeg` | Logo complet extrait du PDF (1200×1200, fond bleu nuit) |
| `logomark.png` | Le losange seul (recadré) |
| `../app/static/logo.jpg` | Copie servie par l'application (en-tête, page publique, impression) |
| `../app/static/logomark.png` | Copie du losange servie par l'application |

Composition : losange émeraude à double contour, deux « C » texturés
(blanc et vert menthe), mot-symbole **COMPTA** (blanc) + **CONNECT** (vert
menthe), signature « Le réseau des professionnels de la comptabilité ».

## Palette

| Rôle | Couleur | Hex | Usage dans le PDF |
|---|---|---|---|
| **Bleu nuit** (fond, titres) | sombre | `#0A1C2D` | fond du logo, titres, en-têtes |
| **Émeraude** (action) | principale | `#1D9E75` | losange, boutons, barres |
| **Vert sapin** (texte fort) | texte | `#085041` | titres de section, 1 440 caractères |
| **Menthe** (accent clair) | accent | `#7DCDB0` | « CONNECT », textes sur fond sombre |
| **Menthe pâle** | accent | `#9FE1CB` | signature |
| **Vert d'eau** (fond doux) | fond | `#D5E8E0` | lignes alternées des tableaux, badges |
| **Or** (mise en avant) | accent | `#C9A227` | encadrés importants |
| **Crème doré** | fond | `#FEF5DC` | fond des encadrés or |
| **Rouge** (alerte) | alerte | `#C0392B` | prélèvements, retards |
| **Gris perle** (fond) | fond | `#F7F7F5` | fond de page |
| **Gris** (texte secondaire) | texte | `#808080` | mentions légales |

## Typographie

Le PDF utilise la famille **Helvetica** (gras pour les données, italique pour
les mentions). Sur le web, la pile équivalente est :

```css
font-family: -apple-system, "Segoe UI", "Helvetica Neue", Arial, sans-serif;
```

## Règles d'application (reprises dans l'outil)

1. En-têtes et fonds sombres en bleu nuit `#0A1C2D`, jamais en noir pur.
2. Actions et validations en émeraude `#1D9E75` ; survol en vert sapin `#085041`.
3. Statuts « à jour / payé » sur fond vert d'eau `#D5E8E0`.
4. Mises en avant (échéances, tâches à traiter) en or `#C9A227` sur crème `#FEF5DC`.
5. Retards et impayés en rouge `#C0392B`.
6. Le logo s'affiche toujours sur fond bleu nuit (son fond est bleu nuit).
