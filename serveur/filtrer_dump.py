#!/usr/bin/env python3
"""Ne garde du dump Supabase (schéma public) que les objets ComptaConnect (cc_*), en écartant les tables d'autres projets."""
import re, sys
src, dst = sys.argv[1], sys.argv[2]
txt = open(src, encoding="utf-8").read()
parts = re.split(r"(?m)^(?=--\n-- Name: )", txt)
out = [parts[0]]
for p in parts[1:]:
    m = re.match(r"--\n-- Name: (.*?); Type: (.*?); Schema: (.*?);", p)
    name, typ = (m.group(1), m.group(2)) if m else ("", "")
    if typ == "SCHEMA": continue
    if "cc_" in name or "trg_cc" in name: out.append(p)
    else: print("écarté :", typ, name[:60], file=sys.stderr)
res = "".join(out)
res = res.replace("extensions.", "").replace('SET search_path = ', 'SET search_path = ')
open(dst, "w", encoding="utf-8").write(res)
print("ok", len(out) - 1, "objets conservés")
