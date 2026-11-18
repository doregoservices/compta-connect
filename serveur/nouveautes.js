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
  // 🎂 Anniversaires du jour : vœux à la personne (push + e-mail) et annonce au réseau — une fois par an et par membre
  if ((S.anniversaires || "oui") !== "non") {
    const auj = new Date(), mmjj = String(auj.getMonth() + 1).padStart(2, "0") + "-" + String(auj.getDate()).padStart(2, "0");
    const tous = await db(`cc_membres?select=id,nom,email,ville,date_naissance&actif=is.true&date_naissance=not.is.null`).catch(() => []);
    const fetards = tous.filter(m => String(m.date_naissance).slice(5, 10) === mmjj);
    const SEC = Object.fromEntries((await db("cc_secrets?select=cle,valeur").catch(() => [])).map(x => [x.cle, x.valeur]));
    const reseau = S.reseau || "ComptaConnect", reponse = S.reponse_email || S.contact_email || "supportcomptaconnect@gmail.com";
    for (const m of fetards) {
      const cle = "anniv:" + m.id + ":" + auj.getFullYear(); if (vus.has(cle)) continue;
      const prenom = m.nom.trim().split(/\s+/).pop();
      if (!premiere) {
        await push.envoyer([m.id], { title: "🎂 Joyeux anniversaire " + prenom + " !", body: "Tout le réseau " + reseau + " vous souhaite une excellente journée et une belle année de réussite.", url: "/#/espace" }).catch(() => null);
        if (SEC.brevo_api_key && /@/.test(m.email || "")) await fetch("https://api.brevo.com/v3/smtp/email", { method: "POST", headers: { "api-key": SEC.brevo_api_key, "Content-Type": "application/json" }, body: JSON.stringify({ sender: { name: reseau, email: SEC.brevo_expediteur || reponse }, replyTo: { email: reponse, name: reseau }, to: [{ email: m.email, name: m.nom }], subject: "🎂 Joyeux anniversaire " + prenom + " — " + reseau, htmlContent: `<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:auto;color:#1d2b25"><div style="background:#06301E;color:#fff;padding:14px 18px;border-radius:10px 10px 0 0"><b style="font-size:18px">${reseau}</b></div><div style="border:1px solid #e3e8e6;border-top:0;padding:18px;border-radius:0 0 10px 10px;line-height:1.5"><p style="font-size:28px;margin:0 0 10px">🎂</p><p>Cher(e) <b>${m.nom}</b>,</p><p>En ce jour particulier, le bureau et l’ensemble des membres de <b>${reseau}</b> vous souhaitent un très joyeux anniversaire, la santé, et une année riche en réussites professionnelles.</p><p>Merci de faire partie de cette communauté.</p><p style="color:#5c6b76;font-size:12px;margin-top:22px;border-top:1px solid #eef2f0;padding-top:10px">Message automatique du réseau · <a href="${S.site_public || "https://comptaconnect.org/"}" style="color:#0B5A38">comptaconnect.org</a></p></div></div>` }) }).catch(() => null);
        if ((S.anniversaires_reseau || "oui") !== "non") await push.envoyer(null, { title: "🎂 C’est l’anniversaire de " + m.nom, body: (m.ville ? m.ville + " · " : "") + "Souhaitez-lui une bonne fête sur le groupe WhatsApp !", url: "/#/annuaire" }).catch(() => null);
        console.log(new Date().toISOString(), cle, "vœux envoyés");
      }
      await db("cc_notifies", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ cle }) }); vus.add(cle);
    }
  }
  const nouveaux = file.filter(x => !vus.has(x.cle));
  let total = 0;
  for (const x of nouveaux.slice(0, 20)) {               // 20 notifications max par passage
    if (!premiere) { const r = await push.envoyer(null, x.msg); total += r.envoyes || 0; console.log(new Date().toISOString(), x.cle, "→", r.envoyes, "appareil(s)"); }
    await db("cc_notifies", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ cle: x.cle }) });
  }
  if (premiere) console.log("première exécution : " + nouveaux.length + " élément(s) existants marqués comme déjà notifiés");
  else if (!nouveaux.length) console.log(new Date().toISOString(), "nouveautés : rien de nouveau");
})().catch(e => { console.error("nouveautés : échec —", e.message); process.exit(1); });
