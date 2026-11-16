#!/bin/bash
# Regroupe chaque fonction Deno (TypeScript) en un fichier JS exécutable sous Node, via esbuild.
set -e
SRC=${1:-/opt/compta-connect/supabase/functions}; OUT=${2:-/opt/comptaconnect/fonctions}
mkdir -p "$OUT"
for f in cinetpay-init cinetpay-notify acces otp; do
  esbuild "$SRC/$f/index.ts" --bundle --platform=node --target=node20 --format=cjs --outfile="$OUT/$f.js" --log-level=warning
done
echo "fonctions construites dans $OUT"
