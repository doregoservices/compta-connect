"""
QR code pour les pages de paiement.

On s'appuie sur la bibliothèque `segno` (implémentation de référence ISO 18004)
plutôt que sur un encodeur maison : la sortie est rendue en SVG autonome, donc
aucune ressource externe n'est chargée par le navigateur.
"""

from __future__ import annotations

import io

ALPHANUM = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"


def _matrice(texte: str) -> list[list[int]]:
    """Modules du QR code (1 = sombre), via segno."""
    try:
        import numpy as np
        import segno
        from PIL import Image
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError(
            "segno, Pillow et numpy sont requis pour générer les QR codes "
            "(pip install segno pillow numpy)"
        ) from exc
    qr = segno.make(texte, error="M", micro=False)
    buf = io.BytesIO()
    qr.save(buf, kind="png", scale=1, border=0)
    buf.seek(0)
    arr = np.array(Image.open(buf).convert("L"))
    return (arr < 128).astype(int).tolist()


def qr_svg(texte: str, taille_px: int = 220, marge: int = 4,
           couleur: str = "#0B1F3A") -> str:
    """QR code en SVG autonome — ne charge aucune ressource externe."""
    texte = str(texte).strip() or "COMPTA CONNECT"
    m = _matrice(texte)
    taille = len(m)
    n = taille + 2 * marge
    e = round(taille_px / n, 2)
    modules = "".join(
        f'<rect x="{(c + marge) * e:.2f}" y="{(l + marge) * e:.2f}" width="{e}" height="{e}"/>'
        for l in range(taille) for c in range(taille) if m[l][c])
    dim = round(n * e)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {dim} {dim}" '
            f'width="{dim}" height="{dim}" shape-rendering="crispEdges" fill="{couleur}" '
            f'role="img" aria-label="QR code"><rect width="{dim}" height="{dim}" '
            f'fill="#ffffff"/>{modules}</svg>')
