#!/usr/bin/env python3
# Dépose les sauvegardes du jour dans le dossier « Sauvegardes ComptaConnect » du Google Drive autorisé (OAuth, portée drive.file),
# puis supprime sur Drive celles de plus de 60 jours. Bibliothèque standard uniquement.
import json, sys, os, glob, datetime, urllib.request, urllib.parse, urllib.error
CONF = "/etc/comptaconnect/gdrive_oauth.json"   # client_id, client_secret, refresh_token, dossier_id (rempli automatiquement)
C = json.load(open(CONF))
def jeton():
    d = urllib.parse.urlencode({"client_id":C["client_id"],"client_secret":C["client_secret"],"refresh_token":C["refresh_token"],"grant_type":"refresh_token"}).encode()
    return json.load(urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=d)))["access_token"]
H = {"Authorization": "Bearer " + jeton()}
def api(url, data=None, method="GET", headers={}):
    r = urllib.request.urlopen(urllib.request.Request(url, data=data, method=method, headers={**H, **headers}))
    t = r.read(); return json.loads(t) if t else {}
def dossier():
    if C.get("dossier_id"):
        try: api(f"https://www.googleapis.com/drive/v3/files/{C['dossier_id']}?fields=id,trashed"); return C["dossier_id"]
        except urllib.error.HTTPError: pass
    q = urllib.parse.quote("name='Sauvegardes ComptaConnect' and mimeType='application/vnd.google-apps.folder' and trashed=false")
    f = api(f"https://www.googleapis.com/drive/v3/files?q={q}&fields=files(id)").get("files")
    did = f[0]["id"] if f else api("https://www.googleapis.com/drive/v3/files", json.dumps({"name":"Sauvegardes ComptaConnect","mimeType":"application/vnd.google-apps.folder"}).encode(), "POST", {"Content-Type":"application/json"})["id"]
    C["dossier_id"] = did; json.dump(C, open(CONF, "w"), indent=1); return did
DOSSIER = dossier()
def envoyer(chemin):
    meta = json.dumps({"name": os.path.basename(chemin), "parents": [DOSSIER]}).encode(); corps = open(chemin, "rb").read(); lim = b"cc_frontiere_7f3"
    body = b"--"+lim+b"\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"+meta+b"\r\n--"+lim+b"\r\nContent-Type: application/octet-stream\r\n\r\n"+corps+b"\r\n--"+lim+b"--"
    return api("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart", body, "POST", {"Content-Type": "multipart/related; boundary=" + lim.decode()})
def nettoyer(jours=60):
    seuil = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=jours)).strftime("%Y-%m-%dT%H:%M:%S")
    q = urllib.parse.quote(f"'{DOSSIER}' in parents and createdTime < '{seuil}' and trashed=false")
    for f in api(f"https://www.googleapis.com/drive/v3/files?q={q}&fields=files(id,name)").get("files", []):
        api(f"https://www.googleapis.com/drive/v3/files/{f['id']}", method="DELETE"); print("supprimé sur Drive :", f["name"])
if __name__ == "__main__":
    fichiers = sys.argv[1:] or sorted(glob.glob("/var/backups/comptaconnect/*" + datetime.date.today().isoformat() + "*"))
    for f in fichiers: r = envoyer(f); print(datetime.datetime.now().isoformat(timespec="seconds"), "envoyé sur Drive :", r.get("name"))
    nettoyer()
