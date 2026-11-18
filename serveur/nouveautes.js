// Notifie immédiatement les membres (notification push sur téléphone) des nouveautés du réseau :
// réponse validée, nouvelle annonce, nouvel événement, nouvelle rencontre (photos), nouveau membre activé.
// Exécuté par cron toutes les 5 min ; mémorise ce qui a déjà été notifié dans cc_notifies (jamais deux fois).
const URL = process.env.SUPABASE_URL || "http://127.0.0.1:3000", KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REST = URL.startsWith("http://127") ? URL : URL + "/rest/v1";
const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };
const db = async (p, o = {}) => { const r = await fetch(REST + "/" + p, { ...o, headers: { ...H, ...(o.headers || {}) } }); if (!r.ok) throw new Error(p + " → " + r.status + " " + await r.text()); const t = await r.text(); return t ? JSON.parse(t) : null; };
const push = require("./push.js");
const dateFR = d => d ? new Date(d).toLocaleDateString("fr-FR", { day: "numeric", month: "long" }) : "";
(async () => {
  const S = Object.fromEntries((await db("cc_settings?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  if ((S.notif_nouveautes || "oui") === "non") return console.log("notifications des nouveautés désactivées");
  const vus = new Set((await db("cc_notifies?select=cle&limit=100000")).map(x => x.cle));
  const depuis = new Date(Date.now() - 3 * 86400000).toISOString(); // on ne rattrape jamais plus de 3 jours
  const file = [];
  // Première exécution : on marque l'existant comme vu, sans notifier (évite une rafale)
  const premiere = vus.size === 0;
  const reps = await db(`cc_reponses?select=id,question_id,cree_le&publie=is.true&order=id.desc&limit=500`);
  const qs = reps.length ? await db(`cc_questions?select=id,question&id=in.(${[...new Set(reps.map(r => r.question_id))].join(",")})`) : [];
  for (const r of reps) { const q = qs.find(x => x.id === r.question_id); if (q) file.push({ cle: "reponse:" + r.id, msg: { title: "✅ Nouvelle réponse validée", body: q.question.slice(0, 120), url: "/#/questions?id=" + q.id } }); }
  for (const a of await db(`cc_annonces?select=id,titre,texte,cree_le&publie=is.true&cree_le=gte.${depuis}&order=id.desc`)) file.push({ cle: "annonce:" + a.id, msg: { title: "📣 " + a.titre.slice(0, 60), body: (a.texte || "").replace(/\s+/g, " ").slice(0, 120), url: "/#/annonces" } });
  const appels = await db("cc_appels?select=id,montant").catch(() => []);
  for (const e of await db(`cc_evenements?select=id,titre,date,heure,lieu,appel_id,cree_le&publie=is.true&cree_le=gte.${depuis}&order=id.desc`)) { const a = appels.find(x => x.id === e.appel_id); file.push({ cle: "evenement:" + e.id, msg: { title: "📅 " + e.titre.slice(0, 60), body: "Le " + dateFR(e.date) + (e.heure ? " à " + e.heure : "") + (e.lieu ? " — " + e.lieu : "") + (a ? ". Participation " + Number(a.montant).toLocaleString("fr-FR") + " F — payez en un clic." : ". Inscrivez-vous en un clic."), url: "/#/agenda" } }); }
  for (const r of await db(`cc_rencontres?select=id,titre,date&publie=is.true&order=id.desc&limit=50`)) file.push({ cle: "rencontre:" + r.id, msg: { title: "📸 " + r.titre.slice(0, 60), body: "Les photos de la rencontre du " + dateFR(r.date) + " sont en ligne.", url: "/#/rencontres" } });
  for (const m of await db(`cc_membres?select=id,nom,ville,pays,date_adhesion&actif=is.true&date_adhesion=gte.${depuis.slice(0, 10)}&order=id.desc&limit=100`)) file.push({ cle: "membre:" + m.id, msg: { title: "🎉 Nouveau membre", body: "Bienvenue à " + m.nom + (m.ville ? " (" + m.ville + ")" : "") + " dans le réseau !", url: "/#/annuaire" } });
  const nouveaux = file.filter(x => !vus.has(x.cle));
  let total = 0;
  for (const x of nouveaux.slice(0, 20)) {               // 20 notifications max par passage
    if (!premiere) { const r = await push.envoyer(null, x.msg); total += r.envoyes || 0; console.log(new Date().toISOString(), x.cle, "→", r.envoyes, "appareil(s)"); }
    await db("cc_notifies", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ cle: x.cle }) });
  }
  if (premiere) console.log("première exécution : " + nouveaux.length + " élément(s) existants marqués comme déjà notifiés");
  else if (!nouveaux.length) console.log(new Date().toISOString(), "nouveautés : rien de nouveau");
})().catch(e => { console.error("nouveautés : échec —", e.message); process.exit(1); });
