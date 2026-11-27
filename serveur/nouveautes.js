// Notifie immédiatement les membres (notification push sur téléphone) des nouveautés du réseau :
// réponse validée, nouvelle annonce, nouvel événement, nouvelle rencontre (photos), nouveau membre activé.
// Exécuté par cron toutes les 5 min ; mémorise ce qui a déjà été notifié dans cc_notifies (jamais deux fois).
const URL = process.env.SUPABASE_URL || "http://127.0.0.1:3000", KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REST = URL.startsWith("http://127") ? URL : URL + "/rest/v1";
const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };
const db = async (p, o = {}) => { const r = await fetch(REST + "/" + p, { ...o, headers: { ...H, ...(o.headers || {}) } }); if (!r.ok) throw new Error(p + " → " + r.status + " " + await r.text()); const t = await r.text(); return t ? JSON.parse(t) : null; };
const push = require("./push.js");
// E-mail via Brevo (secrets brevo_api_key / brevo_expediteur) — ne lève jamais
async function email(dest, nom, sujet, html) {
  const SEC = Object.fromEntries((await db("cc_secrets?select=cle,valeur&cle=in.(brevo_api_key,brevo_expediteur)").catch(() => [])).map(x => [x.cle, x.valeur]));
  const S = Object.fromEntries((await db("cc_settings?select=cle,valeur&cle=in.(reseau,contact_email)")).map(x => [x.cle, x.valeur]));
  if (!SEC.brevo_api_key || !/@/.test(dest || "")) return false;
  const reponse = S.contact_email || "supportcomptaconnect@gmail.com", reseau = S.reseau || "ComptaConnect";
  const r = await fetch("https://api.brevo.com/v3/smtp/email", { method: "POST", headers: { "api-key": SEC.brevo_api_key, "Content-Type": "application/json" },
    body: JSON.stringify({ sender: { name: reseau, email: SEC.brevo_expediteur || reponse }, replyTo: { email: reponse, name: reseau }, to: [{ email: dest, name: nom || "" }], subject: sujet, htmlContent: html }) });
  return r.ok;
}
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
  // 💬 Salon : une notification groupée au plus toutes les 2 h quand il y a de nouveaux messages (jamais une par message)
  if ((S.salon || "oui") !== "non" && (S.salon_notif || "instantane") === "groupe") {
    const derniers = await db("cc_messages?select=id,membre_id,texte,cree_le&supprime=is.false&order=id.desc&limit=30").catch(() => []);
    const dernierNotif = [...vus].filter(k => k.startsWith("salon:")).map(k => parseInt(k.split(":")[1], 10)).sort((a, b) => b - a)[0] || 0;
    const nouveauxMsgs = derniers.filter(m => m.id > dernierNotif && new Date(m.cree_le) > new Date(Date.now() - 3 * 3600000));
    const derniereHeure = (await db("cc_notifies?select=le&cle=like.salon:*&order=le.desc&limit=1").catch(() => []))[0];
    if (nouveauxMsgs.length && (!derniereHeure || Date.now() - new Date(derniereHeure.le) > 2 * 3600000)) {
      const auteurs = [...new Set(nouveauxMsgs.map(m => m.membre_id))];
      const noms = (await db(`cc_membres?select=id,nom&id=in.(${auteurs.join(",")})`).catch(() => [])).map(x => x.nom.split(" ")[0]);
      const m0 = nouveauxMsgs[0];
      if (!premiere) await push.envoyer(null, { title: "💬 " + nouveauxMsgs.length + " nouveau" + (nouveauxMsgs.length > 1 ? "x messages" : " message") + " dans le salon", body: (noms.slice(0, 3).join(", ") || "Un membre") + " : " + (m0.texte || "📎 document").slice(0, 100), url: "/#/salon" }).catch(() => null);
      await db("cc_notifies", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ cle: "salon:" + m0.id }) });
      if (!premiere) console.log(new Date().toISOString(), "salon :", nouveauxMsgs.length, "message(s) notifiés");
    }
  }
  // Offres d'emploi / stage / mission validées : d'abord les membres (dès validation), puis les stagiaires inscrits (après la phase membres) ; le web suit sans notification
  const TYPE_OFFRE = { emploi: "💼 Offre d'emploi", stage: "🎓 Offre de stage", mission: "🧾 Mission" };
  for (const o of await db(`cc_offres_tout?select=id,type,titre,entreprise,membre_nom,ville,valide_le,phase,apercu&valide_le=gte.${depuis}&order=id.desc`).catch(() => [])) {
    const msg = { title: (TYPE_OFFRE[o.type] || "💼 Offre") + " · " + (o.entreprise || (o.membre_nom ? "partagée par " + o.membre_nom : "Réseau")).slice(0, 40), body: o.titre.slice(0, 90) + (o.ville ? " · " + o.ville : ""), url: "/#/entreprises?offre=" + o.id };
    file.push({ cle: "offre:" + o.id, cible: "membres", msg: { ...msg, body: msg.body + " · en avant-première pour les membres" } });
    // phase stagiaires (une candidature pendant la phase membres fige l'offre : pas de suite) ; emplois/missions : aperçu sans contact, invitation à rejoindre le réseau
    if (o.phase !== "membres") file.push({ cle: "offre:" + o.id + ":stg", cible: "stagiaires", msg: o.apercu ? { ...msg, body: msg.body.slice(0, 60) + " · réservée aux membres : rejoignez le réseau pour postuler" } : msg });
  }
  // Gels expirés : la diffusion reprend seule après offres_gel_h sans décision du recruteur
  try { const n = await db("rpc/cc_offres_lever_gels", { method: "POST", body: "{}" }); if (n) console.log(new Date().toISOString(), "offres : " + n + " pause(s) levée(s) automatiquement"); } catch (e) { console.warn("lever gels :", e.message); }
  // Nouvelles candidatures : prévenir le recruteur (entreprise : e-mail ; membre : push + e-mail) avec nom et téléphone du candidat
  try {
    const C = await db("cc_candidatures?select=id,offre_id,nom,telephone,email,origine,quand&notifie=is.false&order=id.asc&limit=50");
    for (const c of C) {
      const [o] = await db(`cc_offres?select=id,titre,entreprise_id,membre_id,fige_phase&id=eq.${c.offre_id}`);
      if (o) {
        const lien = o.entreprise_id ? "/#/entreprises" : "/#/entreprises#partageMembre";
        const orig = { membre: "membre du réseau", stagiaire: "stagiaire inscrit", public: "candidat" }[c.origine] || c.origine;
        const corps = `<p>Bonjour,</p><p>Nouvelle candidature pour votre offre <b>${o.titre}</b> :</p><p><b>${c.nom}</b> (${orig})<br>Téléphone : <a href="https://wa.me/225${String(c.telephone).replace(/\D/g, "").slice(-10)}">${c.telephone}</a>${c.email ? `<br>E-mail : ${c.email}` : ""}</p>` +
          (o.fige_phase ? `<p>La diffusion de l'offre est <b>en pause</b> pour laisser la priorité à ce candidat. Dans votre espace, indiquez <b>« Pourvue »</b> si le poste est pris ou <b>« Poursuivre »</b> pour continuer la diffusion ; sans réponse sous ${S.offres_gel_h || 72} h, elle reprend automatiquement.</p>` : "") +
          `<p><a href="${(S.site_public || "https://comptaconnect.org/").replace(/\/$/, "")}${lien}">Ouvrir mon espace</a></p>`;
        if (!premiere) {
          if (o.entreprise_id) { const [e] = await db(`cc_entreprises?select=nom,email&id=eq.${o.entreprise_id}`); if (e && /@/.test(e.email || "")) await email(e.email, e.nom, "Nouvelle candidature — " + o.titre, corps).catch(() => null); }
          else if (o.membre_id) {
            await push.envoyer([o.membre_id], { title: "👤 Nouvelle candidature", body: c.nom + " a postulé à « " + o.titre.slice(0, 50) + " »", url: lien }).catch(() => null);
            const [mb] = await db(`cc_membres?select=nom,email&id=eq.${o.membre_id}`); if (mb && /@/.test(mb.email || "")) await email(mb.email, mb.nom, "Nouvelle candidature — " + o.titre, corps).catch(() => null);
          }
        }
      }
      await db(`cc_candidatures?id=eq.${c.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ notifie: true }) });
    }
    if (C.length && !premiere) console.log(new Date().toISOString(), "candidatures : " + C.length + " recruteur(s) prévenu(s)");
  } catch (e) { console.warn("candidatures :", e.message); }
  // Annuaire des stagiaires « vivant » : après 30 jours sans confirmation, rappel (push + e-mail) ; sans réponse sous 45 jours la fiche est masquée
  try {
    const aRappeler = await db(`cc_stagiaires?select=id,nom,telephone,email,membre_id,confirme_le&publie=is.true&trouve=is.false&confirme_le=lt.${new Date(Date.now() - 30 * 86400000).toISOString()}&or=(rappele_le.is.null,rappele_le.lt.${new Date(Date.now() - 30 * 86400000).toISOString()})&limit=100`);
    for (const st of aRappeler) {
      const lien = "/#/stagiaires?confirmer=1&t=" + encodeURIComponent(st.telephone);
      const msg = { title: "🎓 Toujours à la recherche d'un stage ?", body: "Confirmez en un clic pour rester visible dans l'annuaire des stagiaires, ou indiquez que vous avez trouvé.", url: lien };
      if (!premiere) {
        if (st.membre_id) await push.envoyer([st.membre_id], msg).catch(() => null);
        else await push.envoyerStagiaires([st.id], msg).catch(() => null);
        if (/@/.test(st.email || "")) await email(st.email, st.nom, "Toujours à la recherche d'un stage ?", `<p>Bonjour ${st.nom},</p><p>Votre fiche est dans l'annuaire des stagiaires de ${S.reseau || "ComptaConnect"} depuis plus d'un mois. Êtes-vous toujours à la recherche d'un stage ?</p><p><a href="${(S.site_public || "https://comptaconnect.org/").replace(/\/$/, "")}${lien}" style="background:#0B5A38;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none">Oui, je cherche toujours</a></p><p>Sans réponse sous 15 jours, votre fiche sera masquée ; vous pourrez la réactiver à tout moment. Si vous avez trouvé : félicitations, indiquez-le sur la même page.</p>`).catch(() => null);
      }
      await db(`cc_stagiaires?id=eq.${st.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ rappele_le: new Date().toISOString() }) });
    }
    if (aRappeler.length) console.log(new Date().toISOString(), "stagiaires : " + aRappeler.length + " rappel(s) de confirmation");
  } catch (e) { console.warn("rappel stagiaires :", e.message); }
  const nouveaux = file.filter(x => !vus.has(x.cle));
  let total = 0;
  for (const x of nouveaux.slice(0, 20)) {               // 20 notifications max par passage
    if (!premiere) { const r = await push.envoyer(null, x.msg, { cible: x.cible }); total += r.envoyes || 0; console.log(new Date().toISOString(), x.cle, "→", r.envoyes, "appareil(s)" + (x.cible ? " (" + x.cible + ")" : ""));
      // Publications publiques (annonces, événements, offres) : aussi par e-mail, groupées dans le courriel quotidien (courriels.js)
      if (/^(annonce|evenement|offre):/.test(x.cle)) await db("cc_courriels_file", { method: "POST", headers: { Prefer: "resolution=ignore-duplicates,return=minimal" }, body: JSON.stringify({ cle: x.cle, titre: x.msg.title, corps: x.msg.body, url: x.msg.url, cible: x.cible || "tous" }) }).catch(() => null); }
    await db("cc_notifies", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ cle: x.cle }) });
  }
  if (premiere) console.log("première exécution : " + nouveaux.length + " élément(s) existants marqués comme déjà notifiés");
  else if (!nouveaux.length) console.log(new Date().toISOString(), "nouveautés : rien de nouveau");
})().catch(e => { console.error("nouveautés : échec —", e.message); process.exit(1); });
