// Notification instantanée des messages du salon (service permanent, systemd cc-salon).
// Toutes les 3 secondes : s'il y a un nouveau message, notification push à tous les membres sauf l'auteur, comme WhatsApp.
// Ne fait rien si le salon est fermé (setting salon=non) ou si le mode choisi est « groupe » (alors nouveautes.js s'en charge).
const URL = process.env.SUPABASE_URL || "http://127.0.0.1:3000", KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REST = URL.startsWith("http://127") ? URL : URL + "/rest/v1";
const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };
const db = async (p, o = {}) => { const r = await fetch(REST + "/" + p, { ...o, headers: { ...H, ...(o.headers || {}) } }); if (!r.ok) throw new Error(p + " → " + r.status); const t = await r.text(); return t ? JSON.parse(t) : null; };
const push = require("./push.js");
let dernier = null, settingsLe = 0, S = {};
async function tour() {
  if (Date.now() - settingsLe > 60000) { S = Object.fromEntries((await db("cc_settings?select=cle,valeur&cle=in.(salon,salon_notif,reseau)")).map(x => [x.cle, x.valeur])); settingsLe = Date.now(); }
  const L = await db("cc_messages?select=id,membre_id,texte,pieces,repond_a,cree_le&supprime=is.false&order=id.desc&limit=10");
  if (dernier === null) { dernier = L.length ? L[0].id : 0; console.log("départ : dernier message", dernier); return; }
  const nouveaux = L.filter(m => m.id > dernier).reverse(); if (!nouveaux.length) return;
  dernier = L[0].id;
  if ((S.salon || "oui") === "non" || (S.salon_notif || "instantane") !== "instantane") return;
  const ids = [...new Set(nouveaux.map(m => m.membre_id).filter(Boolean))];
  const noms = Object.fromEntries((await db(`cc_membres?select=id,nom&id=in.(${ids.join(",")})`)).map(x => [x.id, x.nom]));
  const dest = (await db("cc_push?select=membre_id&actif=is.true&limit=5000")).map(x => x.membre_id);
  for (const m of nouveaux) {
    const cibles = [...new Set(dest.filter(id => id && id !== m.membre_id))]; if (!cibles.length) continue;
    const texte = (m.texte || "").replace(/\s+/g, " ").slice(0, 140) || (Array.isArray(m.pieces) && m.pieces.length ? "📎 " + m.pieces[0].nom : "");
    const r = await push.envoyer(cibles, { title: "💬 " + (noms[m.membre_id] || "Un membre") + (m.repond_a ? " a répondu" : ""), body: texte, url: "/#/salon" }).catch(e => ({ envoyes: 0, erreur: e.message }));
    console.log(new Date().toISOString(), "message", m.id, "→", r.envoyes, "appareil(s)");
  }
}
(async () => { for (;;) { try { await tour(); } catch (e) { console.warn("salon :", e.message); } await new Promise(r => setTimeout(r, 3000)); } })();
