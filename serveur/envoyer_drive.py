#!/usr/bin/env python3
# Envoie les fichiers de sauvegarde du jour dans le dossier Google Drive partagé (compte de service),
# puis supprime sur Drive les sauvegardes de plus de 60 jours. Aucune dépendance hors bibliothèque standard + openssl.
import json, time, base64, subprocess, sys, os, urllib.request, urllib.parse, datetime, glob
SA = json.load(open("/etc/comptaconnect/gdrive_sa.json"))
DOSSIER = open("/etc/comptaconnect/gdrive_dossier_id").read().strip()
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def jeton():
    now = int(time.time())
    h = b64(json.dumps({"alg":"RS256","typ":"JWT"}).encode())
    c = b64(json.dumps({"iss":SA["client_email"],"scope":"https://www.googleapis.com/auth/drive","aud":SA["token_uri"],"iat":now,"exp":now+3600}).encode())
    p = subprocess.run(["openssl","dgst","-sha256","-sign","/dev/stdin"], input=(h+"."+c).encode(), capture_output=True, env={**os.environ}) if False else None
    import tempfile
    with tempfile.NamedTemporaryFile("w", delete=False) as f: f.write(SA["private_key"]); kp = f.name
    try: sig = subprocess.run(["openssl","dgst","-sha256","-sign",kp], input=(h+"."+c).encode(), capture_output=True, check=True).stdout
    finally: os.unlink(kp)
    data = urllib.parse.urlencode({"grant_type":"urn:ietf:params:oauth:grant-type:jwt-bearer","assertion":h+"."+c+"."+b64(sig)}).encode()
    return json.load(urllib.request.urlopen(urllib.request.Request(SA["token_uri"], data=data)))["access_token"]
TOK = jeton(); H = {"Authorization":"Bearer "+TOK}
def api(url, data=None, method="GET", headers={}):
    r = urllib.request.Request(url, data=data, method=method, headers={**H, **headers}); return json.load(urllib.request.urlopen(r))
def envoyer(chemin):
    nom = os.path.basename(chemin)
    meta = json.dumps({"name":nom,"parents":[DOSSIER]}).encode(); corps = open(chemin,"rb").read()
    lim = b"cc_frontiere_7f3"
    body = b"--"+lim+b"\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"+meta+b"\r\n--"+lim+b"\r\nContent-Type: application/octet-stream\r\n\r\n"+corps+b"\r\n--"+lim+b"--"
    return api("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true", body, "POST", {"Content-Type":"multipart/related; boundary="+lim.decode()})
def nettoyer(jours=60):
    seuil = (datetime.datetime.utcnow()-datetime.timedelta(days=jours)).strftime("%Y-%m-%dT%H:%M:%S")
    q = urllib.parse.quote(f"'{DOSSIER}' in parents and createdTime < '{seuil}' and trashed=false")
    for f in api(f"https://www.googleapis.com/drive/v3/files?q={q}&fields=files(id,name)&supportsAllDrives=true").get("files", []):
        api(f"https://www.googleapis.com/drive/v3/files/{f['id']}?supportsAllDrives=true", method="DELETE") if False else urllib.request.urlopen(urllib.request.Request(f"https://www.googleapis.com/drive/v3/files/{f['id']}?supportsAllDrives=true", method="DELETE", headers=H))
        print("supprimé sur Drive :", f["name"])
if __name__ == "__main__":
    fichiers = sys.argv[1:] or sorted(glob.glob("/var/backups/comptaconnect/*"+datetime.date.today().isoformat()+"*"))
    for f in fichiers: r = envoyer(f); print("envoyé :", r.get("name"), r.get("id"))
    nettoyer()
