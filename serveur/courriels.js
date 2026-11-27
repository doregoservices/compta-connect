// Courriel quotidien des publications (annonces, événements, offres) aux membres actifs et aux stagiaires inscrits.
// Un seul e-mail par destinataire et par jour, regroupant tout ce qu'il n'a pas encore reçu (7 jours max).
// Plafond quotidien (Paramètres → courriel_plafond_jour, défaut 250 : offre Brevo gratuite) ; le reste part le lendemain.
// Exécuté par cron chaque matin (après les relances). Interrupteur : courriel_publications.
const URL = process.env.SUPABASE_URL || "http://127.0.0.1:3000", KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REST = URL.startsWith("http://127") ? URL : URL + "/rest/v1";
const H = { apikey: KEY, Authorization: "Bearer " + KEY, "Content-Type": "application/json" };
const db = async (p, o = {}) => { const r = await fetch(REST + "/" + p, { ...o, headers: { ...H, ...(o.headers || {}) } }); if (!r.ok) throw new Error(p + " → " + r.status + " " + await r.text()); const t = await r.text(); return t ? JSON.parse(t) : null; };
const ech = t => String(t || "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
(async () => {
  const S = Object.fromEntries((await db("cc_settings?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  if ((S.courriel_publications || "oui") === "non") return console.log("courriels des publications désactivés");
  const SEC = Object.fromEntries((await db("cc_secrets?select=cle,valeur&cle=in.(brevo_api_key,brevo_expediteur)")).map(x => [x.cle, x.valeur]));
  if (!SEC.brevo_api_key) return console.log("Brevo non configuré");
  const plafond = parseInt(S.courriel_plafond_jour || "250", 10) || 250, reseau = S.reseau || "ComptaConnect", site = (S.site_public || "https://comptaconnect.org/").replace(/\/$/, "");
  const depuis = new Date(Date.now() - 7 * 86400000).toISOString();
  const file = await db(`cc_courriels_file?select=*&cree_le=gte.${depuis}&order=cree_le.asc`);
  if (!file.length) return console.log(new Date().toISOString(), "courriels : rien à envoyer");
  // Destinataires : membres actifs avec e-mail + stagiaires inscrits visibles avec e-mail (dédoublonnés par adresse)
  const membres = await db("cc_membres?select=nom,email&actif=is.true&email=like.*@*");
  const stag = await db("cc_stagiaires?select=nom,email&publie=is.true&trouve=is.false&email=like.*@*").catch(() => []);
  const dest = new Map(); for (const x of [...membres, ...stag]) { const e = String(x.email).trim().toLowerCase(); if (/@/.test(e) && !dest.has(e)) dest.set(e, x.nom); }
  // Ce que chacun a déjà reçu (30 derniers jours)
  const envois = await db(`cc_courriels_envois?select=dest,cles&quand=gte.${new Date(Date.now() - 30 * 86400000).toISOString()}&limit=100000`);
  const recu = new Map(); for (const e of envois) { if (!recu.has(e.dest)) recu.set(e.dest, new Set()); for (const c of e.cles) recu.get(e.dest).add(c); }
  const dejaAuj = await db(`cc_courriels_envois?select=id&quand=gte.${new Date().toISOString().slice(0, 10)}`);
  let budget = plafond - dejaAuj.length, envoyes = 0, erreurs = 0, reportes = 0;
  const reponse = S.contact_email || "supportcomptaconnect@gmail.com";
  for (const [email, nom] of dest) {
    const items = file.filter(f => !(recu.get(email) || new Set()).has(f.cle));
    if (!items.length) continue;
    if (budget <= 0) { reportes++; continue; }
    const prenom = String(nom || "").trim().split(/\s+/).pop() || "cher membre";
    const lignes = items.map(f => `<li style="margin:0 0 10px"><a href="${site}${f.url}" style="color:#0B5A38;font-weight:700;text-decoration:none">${ech(f.titre)}</a>${f.corps ? `<div style="color:#44525c;font-size:14px">${ech(f.corps)}</div>` : ""}</li>`).join("");
    const html = `<div style="font-family:Arial,sans-serif;max-width:600px;margin:auto"><p>Bonjour ${ech(prenom)},</p><p>Du nouveau sur ${ech(reseau)} :</p><ul style="padding-left:18px">${lignes}</ul><p><a href="${site}/" style="background:#0B5A38;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;display:inline-block">Ouvrir ${ech(reseau)}</a></p><p style="color:#8a949c;font-size:12px">Vous recevez ce message car vous êtes membre du réseau ou inscrit à l'annuaire des stagiaires. Pour ne plus recevoir ces courriels, répondez « stop ».</p></div>`;
    try {
      const r = await fetch("https://api.brevo.com/v3/smtp/email", { method: "POST", headers: { "api-key": SEC.brevo_api_key, "Content-Type": "application/json" },
        body: JSON.stringify({ sender: { name: reseau, email: SEC.brevo_expediteur || reponse }, replyTo: { email: reponse, name: reseau }, to: [{ email, name: nom || "" }],
          subject: items.length === 1 ? items[0].titre.replace(/^[^\w\dÀ-ÿ]+/, "") : `${items.length} nouveautés sur ${reseau}`, htmlContent: html }) });
      if (!r.ok) { erreurs++; console.warn("brevo :", r.status, (await r.text()).slice(0, 120)); if (r.status === 402 || r.status === 429) { budget = 0; } continue; }
      envoyes++; budget--;
      await db("cc_courriels_envois", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ dest: email, cles: items.map(f => f.cle) }) });
    } catch (e) { erreurs++; }
  }
  console.log(new Date().toISOString(), `courriels : ${file.length} publication(s), ${envoyes} e-mail(s) envoyé(s), ${erreurs} erreur(s), ${reportes} reporté(s) à demain (plafond ${plafond}/jour)`);
})().catch(e => { console.error("courriels : échec —", e.message); process.exit(1); });
