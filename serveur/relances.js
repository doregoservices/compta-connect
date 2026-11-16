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

(async () => {
  const force = process.argv[2];                                   // ex. `node relances.js retard` pour forcer un type (test)
  const S = Object.fromEntries((await db("cc_settings?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  const SEC = Object.fromEntries((await db("cc_secrets?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  const auj = new Date(), jour = auj.getDate(), dernierJour = new Date(auj.getFullYear(), auj.getMonth() + 1, 0).getDate();
  const jours = (S.relance_jours || "1,25,30,10").split(",").map(x => parseInt(x.trim(), 10)).filter(Boolean);
  const [jAppel, jRappel, jDernier, jRetard] = [jours[0] || 1, jours[1] || 25, jours[2] || 30, jours[3] || 10];
  const cour = mois2(auj), tol = parseInt(S.cotisation_tolerance || "10", 10), limite = jour > tol ? moisPrec(cour) : moisPrec(moisPrec(cour));
  const MAX = parseInt(S.relance_max_jour || "250", 10);              // plafond quotidien (Brevo gratuit : 300/jour)
  let type = force || (jour === jAppel ? "appel" : jour === jRappel ? "rappel" : (jour === Math.min(jDernier, dernierJour)) ? "dernier" : jour === jRetard ? "retard" : null);
  if (!type) {                                                         // hors calendrier : on poursuit la dernière campagne du mois si elle n'est pas terminée
    const der = await db(`cc_relances?select=type,date&date=gte.${cour}-01&order=date.desc&limit=1`);
    if (!der.length || der[0].date === auj.toISOString().slice(0, 10)) { console.log(new Date().toISOString(), "aucune relance prévue aujourd'hui (jour " + jour + ")"); return; }
    type = der[0].type;
  }
  const membres = await db("cc_membres?select=id,code,nom,telephone,email,cotisation,date_adhesion,actif,exonere&actif=is.true");
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
    for (let x = debut; x <= cour; x = moisSuiv(x)) { if ((verse[x] || 0) >= cot) continue; (x <= limite ? retard : aPayer).push(x); }
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
        const r = await fetch("https://api.brevo.com/v3/smtp/email", { method: "POST", headers: { "api-key": SEC.brevo_api_key, "Content-Type": "application/json" },
          body: JSON.stringify({ sender: { name: reseau, email: exp }, to: [{ email: c.m.email, name: c.m.nom }], subject: sujet, htmlContent: corps(c) }) });
        canal = "email"; statut = r.ok ? "envoye" : "erreur"; detail = r.ok ? "" : (await r.text()).slice(0, 200); r.ok ? ok++ : err++;
      } catch (e) { canal = "email"; statut = "erreur"; detail = String(e.message).slice(0, 200); err++; }
    } else sans++;
    await db("cc_relances", { method: "POST", body: JSON.stringify({ date: auj.toISOString().slice(0, 10), type, membre_id: c.m.id, canal, statut, detail, reste: c.reste, nb_mois: type === "retard" ? c.retard.length : 1 }) });
  }
  console.log(new Date().toISOString(), `relance « ${type} » : ${aujourdhui.length} membre(s) traités — e-mails envoyés ${ok}, erreurs ${err}, sans e-mail (WhatsApp trésorier) ${sans}` + (reportes ? `, ${reportes} reportés à demain (plafond ${MAX}/jour)` : ""));
})().catch(e => { console.error("relances : échec —", e.message); process.exit(1); });
