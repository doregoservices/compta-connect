// Notifications push ComptaConnect — module partagé (relances.js, api.js).
// Clés VAPID dans cc_secrets (vapid_public / vapid_private), générées une fois par `node push.js init`.
const webpush = require("web-push");
const URL = process.env.SUPABASE_URL || "http://127.0.0.1:3000", KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REST = URL.startsWith("http://127") ? URL : URL + "/rest/v1";
const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };
const db = async (p, o = {}) => { const r = await fetch(REST + "/" + p, { ...o, headers: { ...H, ...(o.headers || {}) } }); if (!r.ok) throw new Error(p + " → " + r.status + " " + await r.text()); const t = await r.text(); return t ? JSON.parse(t) : null; };
let _cfg = null;
async function config() {
  if (_cfg) return _cfg;
  const rows = await db("cc_secrets?select=cle,valeur&cle=in.(vapid_public,vapid_private)"); const s = Object.fromEntries(rows.map(x => [x.cle, x.valeur]));
  const st = await db("cc_settings?select=cle,valeur&cle=in.(contact_email,reseau)"); const S = Object.fromEntries(st.map(x => [x.cle, x.valeur]));
  if (!s.vapid_public || !s.vapid_private) return null;
  webpush.setVapidDetails("mailto:" + (S.contact_email || "supportcomptaconnect@gmail.com"), s.vapid_public, s.vapid_private);
  return (_cfg = { pub: s.vapid_public, reseau: S.reseau || "ComptaConnect" });
}
/** Génère les clés VAPID si absentes et publie la clé publique dans cc_settings (vapid_public). */
async function init() {
  const rows = await db("cc_secrets?select=cle&cle=eq.vapid_public");
  if (rows.length) { const [p] = await db("cc_secrets?select=valeur&cle=eq.vapid_public"); await db("cc_settings", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ cle: "vapid_public", valeur: p.valeur }) }); return console.log("clés VAPID déjà présentes"); }
  const k = webpush.generateVAPIDKeys();
  for (const [cle, valeur] of [["vapid_public", k.publicKey], ["vapid_private", k.privateKey]]) await db("cc_secrets", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ cle, valeur }) });
  await db("cc_settings", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ cle: "vapid_public", valeur: k.publicKey }) });
  console.log("clés VAPID générées");
}
/** Envoie { title, body, url } aux appareils des membres donnés (ids) ou à tous (null). Renvoie { envoyes, echecs, desactives }. */
async function envoyer(membreIds, msg) {
  const cfg = await config(); if (!cfg) return { envoyes: 0, echecs: 0, desactives: 0, motif: "VAPID non configuré" };
  const filtre = membreIds ? "&membre_id=in.(" + membreIds.join(",") + ")" : "";
  const subs = await db("cc_push?select=id,membre_id,endpoint,p256dh,auth&actif=is.true" + filtre + "&limit=5000");
  const payload = JSON.stringify({ title: msg.title || cfg.reseau, body: msg.body || "", url: msg.url || "/" });
  let envoyes = 0, echecs = 0, desactives = 0;
  await Promise.all(subs.map(async s => {
    try { await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 }); envoyes++;
      await db(`cc_push?id=eq.${s.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ dernier_envoi: new Date().toISOString() }) }).catch(() => null); }
    catch (e) { if (e.statusCode === 404 || e.statusCode === 410) { desactives++; await db(`cc_push?id=eq.${s.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ actif: false }) }).catch(() => null); } else echecs++; }
  }));
  return { envoyes, echecs, desactives, appareils: subs.length };
}
/** Envoie aux appareils de stagiaires inscrits non membres (ids cc_stagiaires). */
async function envoyerStagiaires(stagiaireIds, msg) {
  const cfg = await config(); if (!cfg || !stagiaireIds.length) return { envoyes: 0, echecs: 0, desactives: 0 };
  const subs = await db("cc_push?select=id,endpoint,p256dh,auth&actif=is.true&stagiaire_id=in.(" + stagiaireIds.join(",") + ")&limit=1000");
  const payload = JSON.stringify({ title: msg.title || cfg.reseau, body: msg.body || "", url: msg.url || "/" });
  let envoyes = 0, echecs = 0, desactives = 0;
  await Promise.all(subs.map(async s => {
    try { await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 86400 }); envoyes++; }
    catch (e) { if (e.statusCode === 404 || e.statusCode === 410) { desactives++; await db(`cc_push?id=eq.${s.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ actif: false }) }).catch(() => null); } else echecs++; }
  }));
  return { envoyes, echecs, desactives };
}
module.exports = { envoyer, envoyerStagiaires, init, config };
if (require.main === module) { const cmd = process.argv[2]; (cmd === "init" ? init() : cmd === "test" ? envoyer(null, { title: "ComptaConnect", body: "Test de notification ✅", url: "/" }).then(r => console.log(r)) : Promise.resolve(console.log("usage : node push.js init|test"))).catch(e => { console.error(e.message); process.exit(1); }); }
