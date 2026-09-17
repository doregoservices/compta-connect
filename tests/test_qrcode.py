"""
Les QR codes affichés aux membres doivent être réellement scannables.
On vérifie la sortie SVG avec libzbar, la bibliothèque qu'utilisent la plupart
des scanners du marché.
"""
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "app"))

# libzbar est une bibliothèque système : absente, on saute ces tests sans bloquer la suite
pytest.importorskip("numpy")
pytest.importorskip("PIL")
pytest.importorskip("pyzbar")

import numpy as np
from PIL import Image
from pyzbar.pyzbar import decode as zdecode

import qrcode as Q


def svg_to_matrix(svg: str) -> list[list[int]]:
    """Retourne la matrice de modules (sans marge calme) à partir du SVG produit."""
    rects = re.findall(r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)"/>', svg)
    assert rects, "le SVG ne contient aucun module"
    e = float(rects[0][2])
    dim = int(re.search(r'viewBox="0 0 (\d+) (\d+)"', svg).group(1))
    n = int(round(dim / e))
    marge = int(round(float(rects[0][0]) / e))
    m = [[0] * n for _ in range(n)]
    for x, y, _w, _h in rects:
        m[int(round(float(y) / e))][int(round(float(x) / e))] = 1
    return [ligne[marge:n - marge] for ligne in m[marge:n - marge]]


def matrix_to_image(m, facteur: int = 8, marge: int = 4) -> np.ndarray:
    n = len(m)
    img = np.full((n + 2 * marge, n + 2 * marge), 255, np.uint8)
    for l in range(n):
        for c in range(n):
            if m[l][c]:
                img[marge + l, marge + c] = 0
    return np.kron(img, np.ones((facteur, facteur), np.uint8))


CAS = [
    "CC2609042",
    "http://127.0.0.1:8000/payer?code=042&mois=2026-09",
    "https://www.comptaconnect.ci/payer?code=001&mois=2026-09",
    "0708112233",
    "5000 FCFA",
]


@pytest.mark.parametrize("attendu", CAS)
def test_qr_scannable(attendu):
    svg = Q.qr_svg(attendu, taille_px=360)
    img = matrix_to_image(svg_to_matrix(svg))
    res = zdecode(Image.fromarray(img))
    assert res, "libzbar ne détecte aucun QR code"
    assert res[0].data.decode() == attendu


def test_qr_url_longue():
    url = "https://comptaconnect.ci/payer?code=999&mois=2026-12&src=whatsapp-groupe-comptables"
    img = matrix_to_image(svg_to_matrix(Q.qr_svg(url, taille_px=420)))
    res = zdecode(Image.fromarray(img))
    assert res and res[0].data.decode() == url


def test_qr_vide_non_bloquant():
    svg = Q.qr_svg("", taille_px=200)
    assert "<svg" in svg and "<rect" in svg
