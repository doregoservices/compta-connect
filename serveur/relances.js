// Relances automatiques ComptaConnect — exécuté chaque matin par cron (08:00).
// Calendrier (Paramètres « relance_jours », défaut 1,25,30,10) :
//   1  → appel : « la cotisation du mois est à régler »      (membres n'ayant pas payé le mois en cours)
//   25 → rappel                                                (idem)
//   30 → dernier rappel avant le passage en retard (ou dernier jour du mois si < 30 jours)
//   10 → retard : mois précédents non réglés après la tolérance
// Canal : e-mail via Brevo (secret « brevo_api_key », expéditeur « brevo_expediteur ») si « relance_email » ≠ non.
// Chaque envoi (ou absence d'e-mail) est journalisé dans cc_relances pour l'espace trésorier (série WhatsApp).
const URL = process.env.SUPABASE_URL || "http://127.0.0.1:3000", KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REST = URL.startsWith("http://127") ? URL : URL + "/rest/v1";
const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };
const db = async (p, o = {}) => { const r = await fetch(REST + "/" + p, { ...o, headers: { ...H, ...(o.headers || {}) } }); if (!r.ok) throw new Error(p + " → " + r.status + " " + await r.text()); const t = await r.text(); return t ? JSON.parse(t) : null; };
const mois2 = d => d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0");
const moisSuiv = m => { const [a, x] = m.split("-").map(Number); return x === 12 ? (a + 1) + "-01" : a + "-" + String(x + 1).padStart(2, "0"); };
const moisPrec = m => { const [a, x] = m.split("-").map(Number); return x === 1 ? (a - 1) + "-12" : a + "-" + String(x - 1).padStart(2, "0"); };
const MOIS = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];
const lib = m => MOIS[parseInt(m.slice(5), 10) - 1] + " " + m.slice(0, 4);
const fcfa = n => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
const norm = m => { m = String(m || ""); const x = m.match(/^(\d{4})-(\d{1,2})/); return x ? x[1] + "-" + x[2].padStart(2, "0") : null; };

let S = {}, SEC = {};
let push = null; try { push = require("./push.js"); } catch (e) { console.warn("push indisponible :", e.message); }
const notifier = async (ids, msg) => { try { return push ? await push.envoyer(ids, msg) : null; } catch (e) { console.warn("push :", e.message); return null; } };                                                 // paramètres publics / secrets (chargés au démarrage)
/* Envoi d'un e-mail via Brevo : habillage commun, « Répondre à » = adresse du réseau. Renvoie true/false, ne lève jamais. */
async function mail(dest, sujet, corps){
  try {
    if (!SEC.brevo_api_key || !/@/.test(dest.email || "")) return false;
    const reseau = S.reseau || "ComptaConnect", reponse = S.reponse_email || S.contact_email || "supportcomptaconnect@gmail.com", site = S.site_public || "https://comptaconnect.org/";
    const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:auto;color:#1d2b25"><div style="background:#06301E;color:#fff;padding:14px 18px;border-radius:10px 10px 0 0"><b style="font-size:18px;letter-spacing:.5px">${reseau.toUpperCase().replace("CONNECT", '<span style="color:#B08A38">CONNECT</span>')}</b></div>` +
      `<div style="border:1px solid #e3e8e6;border-top:0;padding:18px;border-radius:0 0 10px 10px;line-height:1.5">${corps}<p style="color:#5c6b76;font-size:12px;margin-top:22px;border-top:1px solid #eef2f0;padding-top:10px">Message automatique du réseau ${reseau} · <a href="${site}" style="color:#0B5A38">${site.replace(/^https?:\/\//, "").replace(/\/$/, "")}</a></p></div></div>`;
    const r = await fetch("https://api.brevo.com/v3/smtp/email", { method: "POST", headers: { "api-key": SEC.brevo_api_key, "Content-Type": "application/json" },
      body: JSON.stringify({ sender: { name: reseau, email: SEC.brevo_expediteur || reponse }, replyTo: { email: reponse, name: reseau }, to: [{ email: dest.email, name: dest.nom || undefined }], subject: sujet, htmlContent: html }) });
    if (!r.ok) console.warn("brevo :", r.status, (await r.text()).slice(0, 160));
    return r.ok;
  } catch (e) { console.warn("brevo :", e.message); return false; }
}
/* E-mails des membres du bureau (fiche membre au même téléphone) + adresse de contact du réseau. */
async function destinatairesBureau(){
  const b = await db("cc_bureau?select=nom,telephone&actif=is.true");
  const tels = b.map(x => String(x.telephone || "").replace(/\D/g, "")).filter(t => t.length >= 8);
  const out = new Map();
  if (tels.length) { const ms = await db(`cc_membres?select=nom,email,telephone&telephone=in.(${tels.map(t => '"' + t + '"').join(",")})`); for (const m of ms) if (/@/.test(m.email || "")) out.set(m.email.toLowerCase(), { email: m.email, nom: m.nom }); }
  const c = S.contact_email || "supportcomptaconnect@gmail.com"; if (/@/.test(c)) out.set(c.toLowerCase(), { email: c, nom: S.reseau || "ComptaConnect" });
  return [...out.values()];
}
async function majSetting(cle, valeur){ await db("cc_settings", { method: "POST", headers: { Prefer: "resolution=merge-duplicates,return=minimal" }, body: JSON.stringify({ cle, valeur }) }); }

/* Rapport financier du mois précédent envoyé au bureau le 1er (ou le premier passage du mois), une seule fois par mois. */
async function rapportMensuel(auj){
  try {
    if ((S.rapport_email || "oui") === "non" || !SEC.brevo_api_key) return;
    const m = moisPrec(mois2(auj)); if (S.rapport_envoye === m) return;
    const [a, x] = m.split("-").map(Number), deb = `${m}-01`, fin = `${x === 12 ? a + 1 : a}-${String(x === 12 ? 1 : x + 1).padStart(2, "0")}-01`;
    const pAvant = await db(`cc_paiements?select=montant,frais,caisse&date=lt.${deb}&limit=100000`), dAvant = await db(`cc_depenses?select=*&date=lt.${deb}&limit=100000`);
    const p = await db(`cc_paiements?select=montant,frais,canal,caisse,membre_id,mois&date=gte.${deb}&date=lt.${fin}&limit=100000`), d = await db(`cc_depenses?select=*&date=gte.${deb}&date=lt.${fin}&order=date`);
    const net = r => Number(r.montant || 0) - Number(r.frais || 0), cot = r => (r.caisse || "cotisation") !== "inscription";
    const soldeAvant = pAvant.filter(cot).reduce((s, r) => s + net(r), 0) - dAvant.filter(cot).reduce((s, r) => s + Number(r.montant || 0), 0);
    const enc = p.filter(cot).reduce((s, r) => s + Number(r.montant || 0), 0), frais = p.filter(cot).reduce((s, r) => s + Number(r.frais || 0), 0), dep = d.filter(cot).reduce((s, r) => s + Number(r.montant || 0), 0);
    const insc = p.filter(r => !cot(r)).reduce((s, r) => s + net(r), 0), inscAvant = pAvant.filter(r => !cot(r)).reduce((s, r) => s + net(r), 0) - dAvant.filter(r => !cot(r)).reduce((s, r) => s + Number(r.montant || 0), 0), inscDep = d.filter(r => !cot(r)).reduce((s, r) => s + Number(r.montant || 0), 0);
    const parCanal = {}; for (const r of p.filter(cot)) { const c = String(r.canal || "autre").split("·")[0].trim(); parCanal[c] = (parCanal[c] || 0) + Number(r.montant || 0); }
    const payeurs = new Set(p.filter(r => cot(r) && r.mois === m).map(r => r.membre_id)).size, actifs = (await db("cc_membres?select=id&actif=is.true&exonere=is.false")).length;
    const ligne = (k, v, b) => `<tr><td style="padding:5px 0;color:#5c6b76">${k}</td><td style="padding:5px 0;text-align:right;${b ? "font-weight:bold" : ""}">${v}</td></tr>`;
    const corps = `<p>Bonjour,</p><p>Voici le rapport financier automatique du réseau pour <strong>${lib(m)}</strong>.</p><h3 style="margin:14px 0 6px;color:#06301E">Caisse des cotisations</h3><table style="width:100%;border-collapse:collapse;font-size:14px">` +
      ligne("Solde reporté au 1er", fcfa(soldeAvant) + " F") + ligne("Encaissements bruts", fcfa(enc) + " F") + Object.entries(parCanal).map(([k, v]) => ligne("&nbsp;&nbsp;dont " + k, fcfa(v) + " F")).join("") +
      ligne("Frais CinetPay retenus", "− " + fcfa(frais) + " F") + ligne("Dépenses", "− " + fcfa(dep) + " F") + ligne("Résultat du mois", fcfa(enc - frais - dep) + " F", true) + ligne("Solde en fin de mois", fcfa(soldeAvant + enc - frais - dep) + " F", true) + `</table>` +
      (d.filter(cot).length ? `<p style="margin:10px 0 4px"><b>Détail des dépenses</b></p><table style="width:100%;border-collapse:collapse;font-size:13px">` + d.filter(cot).map(r => `<tr><td style="padding:3px 0;color:#5c6b76">${r.date}</td><td style="padding:3px 6px">${r.libelle || r.categorie || ""}</td><td style="padding:3px 0;text-align:right">${fcfa(r.montant)} F</td></tr>`).join("") + `</table>` : "") +
      `<h3 style="margin:14px 0 6px;color:#06301E">Caisse des frais d'inscription</h3><table style="width:100%;border-collapse:collapse;font-size:14px">` + ligne("Solde reporté", fcfa(inscAvant) + " F") + ligne("Inscriptions nettes du mois", fcfa(insc) + " F") + ligne("Dépenses", "− " + fcfa(inscDep) + " F") + ligne("Solde en fin de mois", fcfa(inscAvant + insc - inscDep) + " F", true) + `</table>` +
      `<h3 style="margin:14px 0 6px;color:#06301E">Cotisations de ${lib(m)}</h3><p>${payeurs} membre(s) à jour sur ${actifs} cotisant(s) attendus (${actifs ? Math.round(payeurs * 100 / actifs) : 0} %).</p>` +
      `<p style="margin-top:14px"><a href="${S.site_public || "https://comptaconnect.org/"}#/solde" style="background:#0B5A38;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;display:inline-block">Ouvrir le point de trésorerie et le PDF signé</a></p>`;
    const dests = await destinatairesBureau(); let n = 0;
    for (const dst of dests) if (await mail(dst, `Rapport financier — ${lib(m)} — ${S.reseau || "ComptaConnect"}`, corps)) n++;
    await majSetting("rapport_envoye", m);
    console.log(`rapport mensuel ${m} : envoyé à ${n}/${dests.length} destinataire(s) du bureau`);
  } catch (e) { console.warn("rapport mensuel : échec —", e.message); }
}

/* Révision annuelle des réponses : en janvier, un e-mail à chaque auteur listant ses réponses à revérifier (une fois par an). */
async function campagneRevision(auj){
  try {
    const an = auj.getFullYear();
    if ((S.revision_email || "oui") === "non" || (S.qr_revision || "oui") === "non" || !SEC.brevo_api_key || String(S.revision_envoyee) === String(an)) return;
    const reps = await db(`cc_reponses?select=id,question_id,membre_id,texte,verifiee_annee&publie=is.true&verifiee_annee=lt.${an}&limit=5000`);
    if (!reps.length) { await majSetting("revision_envoyee", String(an)); return; }
    const qs = await db(`cc_questions?select=id,titre&id=in.(${[...new Set(reps.map(r => r.question_id))].join(",")})`), titre = Object.fromEntries(qs.map(q => [q.id, q.titre]));
    const parAuteur = {}; for (const r of reps) if (r.membre_id) (parAuteur[r.membre_id] = parAuteur[r.membre_id] || []).push(r);
    const ids = Object.keys(parAuteur); if (!ids.length) { await majSetting("revision_envoyee", String(an)); return; }
    const ms = await db(`cc_membres?select=id,nom,email,telephone&id=in.(${ids.join(",")})`); let n = 0;
    for (const m of ms) {
      const liste = parAuteur[m.id].slice(0, 15).map(r => `<li><b>${titre[r.question_id] || "Question"}</b><br><span style="color:#5c6b76">${String(r.texte).slice(0, 140)}${r.texte.length > 140 ? "…" : ""}</span></li>`).join("");
      const lien = `${S.site_public || "https://comptaconnect.org/"}#/questions?t=${encodeURIComponent(String(m.telephone || "").replace(/\D/g, ""))}`;
      if (await mail(m, `Révision ${an} : vos réponses d'expert à revérifier`, `<p>Bonjour ${m.nom.split(" ").pop()},</p><p>Nouvelle année, nouvelles règles : les réponses que vous avez apportées à la communauté méritent un coup d'œil pour rester fiables en <b>${an}</b>. Vous en avez <b>${parAuteur[m.id].length}</b> à revérifier :</p><ul>${liste}</ul><p>Pour chacune, un clic suffit : <b>✔ Toujours valable</b> ou <b>✏️ Proposer une mise à jour</b> (points et badge 🔭 Veilleur à la clé).</p><p><a href="${lien}" style="background:#0B5A38;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;display:inline-block">Réviser mes réponses</a></p><p>Merci pour votre expertise au service du réseau.</p>`)) n++;
    }
    await majSetting("revision_envoyee", String(an));
    console.log(`révision ${an} : ${n} auteur(s) prévenus pour ${reps.length} réponse(s)`);
  } catch (e) { console.warn("révision : échec —", e.message); }
}

async function rappelsAgenda(emailActif, exp, reseau, auj){
// Agenda : rappel la veille aux inscrits (e-mail si Brevo actif)
  try {
    const demain = new Date(auj.getTime() + 86400000).toISOString().slice(0, 10);
    const evts = await db(`cc_evenements?select=*&publie=is.true&date=eq.${demain}`);
    for (const e of evts) {
      if (!emailActif) { console.log(`agenda : « ${e.titre} » demain — rappel e-mail non envoyé (Brevo inactif)`); continue; }
      const ins = await db(`cc_evenement_inscrits?select=membre_id&evenement_id=eq.${e.id}`);
      const ids = ins.map(i => i.membre_id); if (!ids.length) continue;
      const ms = await db(`cc_membres?select=id,nom,email&id=in.(${ids.join(",")})`);
      let n = 0;
      for (const m of ms) { if (!/@/.test(m.email || "")) continue;
        const html = `<p>Bonjour ${m.nom.split(" ")[0]},</p><p>Petit rappel : <strong>${e.titre}</strong> a lieu <strong>demain ${demain.slice(8,10)}/${demain.slice(5,7)}</strong>${e.heure ? " à " + e.heure : ""}${e.lieu ? " — " + e.lieu : ""}.</p>${e.description ? "<p>" + e.description.replace(/\n/g, "<br>") + "</p>" : ""}${e.lien ? `<p>Lien : <a href="${e.lien}">${e.lien}</a></p>` : ""}<p>À demain !<br>Le bureau du réseau ${reseau}</p>`;
        if (await mail(m, `Rappel : ${e.titre} — demain`, html)) n++; }
      const pr = await notifier(ids, { title: "Rappel : " + e.titre, body: "Demain" + (e.heure ? " à " + e.heure : "") + (e.lieu ? " — " + e.lieu : ""), url: "/#/agenda" });
      console.log(`agenda : « ${e.titre} » demain — ${n} rappel(s) e-mail envoyé(s)` + (pr ? `, ${pr.envoyes} notification(s) push` : ""));
    }
  } catch (e) { console.warn("agenda : rappels impossibles —", e.message); }
}
(async () => {
  const force = process.argv[2];                                   // ex. `node relances.js retard` pour forcer un type (test)
  S = Object.fromEntries((await db("cc_settings?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  SEC = Object.fromEntries((await db("cc_secrets?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  const auj = new Date(), jour = auj.getDate(), dernierJour = new Date(auj.getFullYear(), auj.getMonth() + 1, 0).getDate();
  const jours = (S.relance_jours || "1,25,30,10").split(",").map(x => parseInt(x.trim(), 10)).filter(Boolean);
  const [jAppel, jRappel, jDernier, jRetard] = [jours[0] || 1, jours[1] || 25, jours[2] || 30, jours[3] || 10];
  const cour = mois2(auj), tol = parseInt(S.cotisation_tolerance || "10", 10), limite = jour > tol ? moisPrec(cour) : moisPrec(moisPrec(cour));
  const MAX = parseInt(S.relance_max_jour || "250", 10);              // plafond quotidien (Brevo gratuit : 300/jour)
  let type = force || (jour === jAppel ? "appel" : jour === jRappel ? "rappel" : (jour === Math.min(jDernier, dernierJour)) ? "dernier" : jour === jRetard ? "retard" : null);
  await rappelsAgenda((S.relance_email || "oui") !== "non" && SEC.brevo_api_key, SEC.brevo_expediteur || "supportcomptaconnect@gmail.com", S.reseau || "ComptaConnect", auj);
  if (force === "rapport") { await majSetting("rapport_envoye", ""); await rapportMensuel(auj); return; }   // test : renvoi forcé du rapport
  await rapportMensuel(auj);                                           // 1er passage du mois : rapport du mois précédent au bureau
  await campagneRevision(auj);                                         // janvier : révision annuelle des réponses
  if (!type) {                                                         // hors calendrier : on poursuit la dernière campagne du mois si elle n'est pas terminée
    const der = await db(`cc_relances?select=type,date&date=gte.${cour}-01&order=date.desc&limit=1`);
    if (!der.length || der[0].date === auj.toISOString().slice(0, 10)) { console.log(new Date().toISOString(), "aucune relance prévue aujourd'hui (jour " + jour + ")"); return; }
    type = der[0].type;
  }
  const membres = await db("cc_membres?select=id,code,nom,telephone,email,cotisation,date_adhesion,actif,exonere,cotisation_nature,nature_depuis,nature_montant,nature_exceptions&actif=is.true");
  const paiements = await db("cc_paiements?select=membre_id,mois,montant&caisse=not.eq.inscription&limit=100000");
  const deja = new Set((await db(`cc_relances?select=membre_id&date=gte.${cour}-01&type=eq.${type}&limit=100000`)).map(x => String(x.membre_id)));   // une fois par campagne et par mois
  const plancher = /^\d{4}-\d{2}$/.test(S.debut_cotisations || "") ? S.debut_cotisations : null;
  const cibles = [];
  for (const m of membres) {
    const cot = m.exonere ? 0 : parseInt(m.cotisation || 0, 10); if (!cot || deja.has(String(m.id))) continue;
    const mesP = paiements.filter(p => String(p.membre_id) === String(m.id) && p.mois);
    let debut = /^\d{4}-\d{2}/.test(String(m.date_adhesion || "")) ? moisSuiv(String(m.date_adhesion).slice(0, 7)) : null;
    for (const p of mesP) { const pm = norm(p.mois); if (pm && (!debut || pm < debut)) debut = pm; }
    if (plancher && (!debut || debut < plancher)) debut = plancher;
    if (!debut) debut = cour;
    const verse = {}; for (const p of mesP) { const pm = norm(p.mois); verse[pm] = (verse[pm] || 0) + parseInt(p.montant, 10); }
    const retard = [], aPayer = [];
    const ech = String(parseInt(S.nature_revision_mois || "12", 10) || 12).padStart(2, "0");
    const duMois = x => { if (m.cotisation_nature && (!m.nature_depuis || x >= String(m.nature_depuis).slice(0, 7))) { const ex = m.nature_exceptions || {}; const c = ex[x.slice(0, 4)] !== undefined ? parseInt(ex[x.slice(0, 4)], 10) : parseInt(m.nature_montant || 0, 10); return x.slice(5, 7) === ech ? c : 0; } return cot; };
    for (let x = debut; x <= cour; x = moisSuiv(x)) { const d = duMois(x); if (!d || (verse[x] || 0) >= d) continue; (x <= limite ? retard : aPayer).push(x); }
    if (type === "retard" ? retard.length : aPayer.includes(cour)) cibles.push({ m, cot, retard, aPayer, reste: [...retard, ...aPayer].reduce((s, x) => s + cot - (verse[x] || 0), 0) });
  }
  const reseau = S.reseau || "ComptaConnect", site = (S.site_public || "https://comptaconnect.org/").replace(/\/?$/, "/");
  const lien = m => site + "#/payer?t=" + encodeURIComponent(m.telephone || "");
  const sujet = { appel: `${reseau} — cotisation de ${lib(cour)}`, rappel: `${reseau} — rappel : cotisation de ${lib(cour)}`, dernier: `${reseau} — dernier rappel avant retard`, retard: `${reseau} — cotisation(s) en retard` }[type];
  const corps = c => {
    const prenom = c.m.nom.split(" ")[0];
    const intro = { appel: `la cotisation de <strong>${lib(cour)}</strong> (${fcfa(c.cot)} F) est à régler dans le mois.`,
      rappel: `petit rappel : la cotisation de <strong>${lib(cour)}</strong> (${fcfa(c.cot)} F) n'est pas encore réglée.`,
      dernier: `dernier rappel : après le ${tol} ${MOIS[(auj.getMonth() + 1) % 12]}, la cotisation de <strong>${lib(cour)}</strong> sera comptée en retard.`,
      retard: `votre compte présente <strong>${c.retard.length} mois en retard</strong> (${c.retard.map(lib).join(", ")}), soit ${fcfa(c.retard.length * c.cot)} F.` }[type];
    return `<p>Bonjour ${prenom},</p><p>${intro}</p><p>Payer en ligne (mobile money) en un clic : <a href="${lien(c.m)}">${lien(c.m)}</a></p>` +
      (c.reste ? `<p>Reste total à ce jour : <strong>${fcfa(c.reste)} F</strong>.</p>` : "") + `<p>Merci pour votre engagement.<br>Le bureau du réseau ${reseau}</p>`;
  };
  const emailActif = (S.relance_email || "oui") !== "non" && SEC.brevo_api_key;
  const exp = SEC.brevo_expediteur || "supportcomptaconnect@gmail.com";
  let ok = 0, sans = 0, err = 0;
  cibles.sort((x, y) => y.reste - x.reste);
  const aujourdhui = cibles.slice(0, MAX), reportes = cibles.length - aujourdhui.length;
  for (const c of aujourdhui) {
    let canal = "aucun", statut = "a_faire", detail = "";
    if (emailActif && /@/.test(c.m.email || "")) {
      try {
        const okm = await mail(c.m, sujet, corps(c));
        canal = "email"; statut = okm ? "envoye" : "erreur"; detail = okm ? "" : "refus Brevo (voir journal)"; okm ? ok++ : err++;
      } catch (e) { canal = "email"; statut = "erreur"; detail = String(e.message).slice(0, 200); err++; }
    } else sans++;
    await db("cc_relances", { method: "POST", body: JSON.stringify({ date: auj.toISOString().slice(0, 10), type, membre_id: c.m.id, canal, statut, detail, reste: c.reste, nb_mois: type === "retard" ? c.retard.length : 1 }) });
  }
  const titres = { appel: "Cotisation du mois à régler", rappel: "Rappel : cotisation du mois", dernier: "Dernier rappel avant retard", retard: "Cotisation en retard" };
  const pr = await notifier(aujourdhui.map(c => c.m.id), { title: titres[type] || "ComptaConnect", body: "Payez en un clic depuis votre page membre (Wave, Orange, MTN, Moov).", url: "/#/" });
  if (pr) console.log(`relance « ${type} » : ${pr.envoyes} notification(s) push, ${pr.appareils} appareil(s)`);
  console.log(new Date().toISOString(), `relance « ${type} » : ${aujourdhui.length} membre(s) traités — e-mails envoyés ${ok}, erreurs ${err}, sans e-mail (WhatsApp trésorier) ${sans}` + (reportes ? `, ${reportes} reportés à demain (plafond ${MAX}/jour)` : ""));
})().catch(e => { console.error("relances : échec —", e.message); process.exit(1); });
