"""Déploie cinetpay-init et cinetpay-notify via l'API de gestion Supabase (le module _shared/cc.ts est inliné).
Usage : SUPABASE_ACCESS_TOKEN=sbp_... python3 scripts/deployer_fonctions.py"""
import os, json, re, urllib.request, uuid, sys
T=os.environ["SUPABASE_ACCESS_TOKEN"]; R=os.environ.get("SUPABASE_REF","ewcxndlelagtrlshadlj")
base=os.path.join(os.path.dirname(__file__),"..","supabase","functions")
shared=open(os.path.join(base,"_shared","cc.ts")).read().replace("export ","")
for slug in ["cinetpay-init","cinetpay-notify"]:
    src=open(os.path.join(base,slug,"index.ts")).read()
    src=re.sub(r'import \{[^}]*\} from "\.\./_shared/cc\.ts";\n', shared+"\n", src)
    bnd="----cc"+uuid.uuid4().hex
    meta=json.dumps({"entrypoint_path":"index.ts","name":slug,"verify_jwt":False})
    body=(f"--{bnd}\r\nContent-Disposition: form-data; name=\"metadata\"\r\nContent-Type: application/json\r\n\r\n{meta}\r\n"
          f"--{bnd}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"index.ts\"\r\nContent-Type: application/typescript\r\n\r\n{src}\r\n--{bnd}--\r\n").encode()
    req=urllib.request.Request(f"https://api.supabase.com/v1/projects/{R}/functions/deploy?slug={slug}",data=body,method="POST",
        headers={"Authorization":"Bearer "+T,"Content-Type":f"multipart/form-data; boundary={bnd}"})
    try: r=json.loads(urllib.request.urlopen(req).read()); print(slug,"→ version",r.get("version"),"verify_jwt",r.get("verify_jwt"))
    except urllib.error.HTTPError as e: print(slug,"ERREUR",e.code,e.read().decode()[:400]); sys.exit(1)
