// Utilitaires communs aux fonctions ComptaConnect (Deno / Supabase Edge Functions)
export const CINETPAY_API = Deno.env.get("CINETPAY_API") || "https://api-checkout.cinetpay.com/v2";
export const SB_URL = Deno.env.get("SUPABASE_URL")!;
export const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};
export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

/** Accès REST à la base avec la clé service (contourne RLS : réservé au serveur). */
export async function db(path: string, init: RequestInit = {}) {
  const r = await fetch(`${SB_URL}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json",
      Prefer: "return=representation", ...(init.headers || {}) },
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`DB ${r.status} ${path}: ${txt.slice(0, 200)}`);
  return txt ? JSON.parse(txt) : null;
}

export async function secrets() {
  const rows = await db("cc_secrets?select=cle,valeur") as { cle: string; valeur: string }[];
  const s: Record<string, string> = {}; for (const r of rows) s[r.cle] = r.valeur;
  if (!s.cinetpay_api_key || !s.cinetpay_site_id) throw new Error("Clés CinetPay non configurées");
  // Nouvelle API CinetPay v1 (panel.cinetpay.net) : clé sk_test_/sk_live_ + mot de passe API (saisi dans le champ « Site ID / mot de passe »)
  const v1 = /^sk_(test|live)_/.test(s.cinetpay_api_key);
  const env = s.cinetpay_api_key.startsWith("sk_live_") ? "live" : "test";
  // Relais à IP fixe (CinetPay exige une liste blanche d'IP) : si cc_secrets contient relais_url + relais_secret, tous les appels passent par lui
  const relais = s.relais_url && s.relais_secret ? { url: s.relais_url.replace(/\/$/, ""), secret: s.relais_secret } : null;
  const base = relais ? relais.url : (env === "live" ? "https://api.cinetpay.co" : "https://api.cinetpay.net");
  const entetes: Record<string, string> = relais ? { "X-Relais-Secret": relais.secret, "X-Cinetpay-Env": env } : {};
  return { apikey: s.cinetpay_api_key, site_id: s.cinetpay_site_id, v1, base, env, entetes };
}
let _jeton: { base: string; token: string; exp: number } | null = null;
/** Jeton OAuth v1 (mis en cache ~50 min dans l'instance). */
export async function jetonV1(sec: { apikey: string; site_id: string; base: string; entetes: Record<string, string> }) {
  if (_jeton && _jeton.base === sec.base && _jeton.exp > Date.now()) return _jeton.token;
  const r = await fetch(`${sec.base}/v1/oauth/login`, { method: "POST", headers: { "Content-Type": "application/json", ...sec.entetes },
    body: JSON.stringify({ api_key: sec.apikey, api_password: sec.site_id }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j?.access_token) throw new Error("Connexion CinetPay refusée : " + (j?.description || j?.status || r.status));
  _jeton = { base: sec.base, token: String(j.access_token), exp: Date.now() + 50 * 60 * 1000 };
  return _jeton.token;
}
export async function settings() {
  const rows = await db("cc_settings?select=cle,valeur") as { cle: string; valeur: string }[];
  const s: Record<string, string> = {}; for (const r of rows) s[r.cle] = r.valeur; return s;
}

export function moisCourt(mois: string) { return mois.slice(2, 4) + mois.slice(5, 7); }
export function reference(mois: string, code: string) { return "CC" + moisCourt(mois) + code.padStart(3, "0"); }

/** Vérifie une transaction auprès de CinetPay (source de vérité, jamais le simple POST de notification). */
export async function verifierTransaction(transaction_id: string, montantAttendu = 0) {
  const sec = await secrets();
  if (sec.v1) {
    const tok = await jetonV1(sec);
    const r = await fetch(`${sec.base}/v1/payment/${encodeURIComponent(transaction_id)}`, { headers: { Authorization: `Bearer ${tok}`, ...sec.entetes } });
    const j = await r.json().catch(() => ({}));
    const st = String(j?.status || "");
    return { ok: st === "SUCCESS", brut: { data: { status: st === "SUCCESS" ? "ACCEPTED" : (st === "FAILED" ? "REFUSED" : st) }, code: j?.code }, montant: montantAttendu,
      methode: String(j?.payment_method || j?.user?.payment_method || ""), operateur: String(j?.user?.phone_number || "") };
  }
  const r = await fetch(`${CINETPAY_API}/payment/check`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ apikey: sec.apikey, site_id: sec.site_id, transaction_id }),
  });
  const j = await r.json();
  return { ok: j?.code === "00" && j?.data?.status === "ACCEPTED", brut: j, montant: Number(j?.data?.amount || 0),
    methode: String(j?.data?.payment_method || ""), operateur: String(j?.data?.operator_id || "") };
}

/** Enregistre le paiement (idempotent) : une transaction CinetPay acceptée = une ligne cc_paiements. */
export async function enregistrerPaiement(t: { id: number; transaction_id: string; membre_id: number; code: string; mois: string; appel_id?: number | null; caisse?: string | null; montant: number; telephone: string; nom: string }, verif: { montant: number; methode: string; operateur: string }) {
  const deja = await db(`cc_paiements?select=id&reference_externe=eq.${encodeURIComponent(t.transaction_id)}`) as unknown[];
  if (deja.length) return { deja: true };
  const montant = verif.montant || t.montant;
  // Commission CinetPay retenue sur l'encaissement (Paramètres → cinetpay_commission, en %) : le membre est crédité du montant payé, la caisse du net
  const cfg = await settings();
  const pct = Number(String(cfg.cinetpay_commission ?? "3.5").replace(",", ".")) || 0;
  const frais = Math.round(montant * pct / 100);
  const inscription = t.caisse === "inscription" || (!t.mois && !t.appel_id);   // droit d'adhésion : caisse séparée, aucun mois de cotisation
  let detail = inscription ? "FRAIS D'INSCRIPTION" : t.mois ? reference(t.mois, t.code) : "";
  if (t.appel_id) {
    const [a] = await db(`cc_appels?select=titre&id=eq.${t.appel_id}`) as { titre: string }[];
    detail = "APPEL " + (a?.titre || t.appel_id);
  }
  const sec = await secrets().catch(() => null);
  const test = !!sec && sec.apikey.startsWith("sk_test_");
  await db("cc_paiements", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
    date: new Date().toISOString().slice(0, 10), montant, canal: (test ? "SIMULATION CinetPay test" : "CinetPay") + (verif.methode ? " · " + verif.methode : ""),
    expediteur: t.nom, telephone: t.telephone, libelle: "CinetPay " + t.transaction_id + " · " + detail,
    mois: t.appel_id || inscription ? "" : t.mois, appel_id: t.appel_id || null, membre_id: t.membre_id, statut: "RAPPROCHE", methode: "cinetpay",
    caisse: inscription ? "inscription" : "cotisation", reference_externe: t.transaction_id, frais,
  }) });
  await db(`cc_transactions?id=eq.${t.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ statut: "ACCEPTEE", maj_le: new Date().toISOString(), montant_recu: montant, operateur: verif.operateur }) });
  // Reçu automatique par e-mail (si le membre a une adresse et que Brevo est configuré) — jamais bloquant
  try {
    const [mb] = await db(`cc_membres?select=nom,email,telephone,matricule&id=eq.${t.membre_id}`) as { nom: string; email: string; telephone: string; matricule: string }[];
    if (mb && /@/.test(mb.email || "") && (cfg.recu_email || "oui") !== "non") {
      const objet = inscription ? "Droit d'adhésion" : t.appel_id ? detail.replace(/^APPEL /, "") : "Cotisation " + moisLibelle(t.mois);
      const tel = String(mb.telephone || "").replace(/\D/g, "");
      const lien = String(cfg.site_public || "https://comptaconnect.org/") + "#/payer?t=" + encodeURIComponent(tel);
      const prenom = String(mb.nom || "").trim().split(/\s+/).pop() || "cher membre";
      const html = `<p>Bonjour ${prenom},</p><p>Nous accusons réception de votre paiement. Merci pour votre engagement !</p>` +
        `<table style="border-collapse:collapse;width:100%;font-size:14px">` +
        `<tr><td style="padding:6px 0;color:#5c6b76">Objet</td><td style="padding:6px 0;text-align:right"><b>${objet}</b></td></tr>` +
        `<tr><td style="padding:6px 0;color:#5c6b76">Montant</td><td style="padding:6px 0;text-align:right"><b>${fcfa(montant)} F CFA</b></td></tr>` +
        `<tr><td style="padding:6px 0;color:#5c6b76">Moyen</td><td style="padding:6px 0;text-align:right">${verif.methode || "mobile money"}${verif.operateur ? " · " + verif.operateur : ""}</td></tr>` +
        `<tr><td style="padding:6px 0;color:#5c6b76">Date</td><td style="padding:6px 0;text-align:right">${new Date().toLocaleDateString("fr-FR")}</td></tr>` +
        `<tr><td style="padding:6px 0;color:#5c6b76">Référence</td><td style="padding:6px 0;text-align:right;font-family:monospace">${t.transaction_id}</td></tr></table>` +
        `<p style="margin-top:16px"><a href="${lien}" style="background:#0B5A38;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;display:inline-block">Voir ma situation et télécharger le reçu</a></p>` +
        `<p style="color:#5c6b76;font-size:13px">Ce reçu est généré automatiquement dès la confirmation de l'opérateur ; il fait foi pour la trésorerie du réseau.</p>`;
      await envoyerEmail({ email: mb.email, nom: mb.nom }, `Reçu de paiement — ${objet} — ${fcfa(montant)} F`, html);
    }
  } catch { /* le reçu n'empêche jamais l'enregistrement */ }
  return { deja: false };
}

/* ------------------------------ E-mails (Brevo) ------------------------------ */
/** Envoie un e-mail transactionnel via Brevo (secrets brevo_api_key / brevo_expediteur). Ne lève jamais : renvoie true/false. */
export async function envoyerEmail(dest: { email: string; nom?: string }, sujet: string, html: string) {
  try {
    if (!/@/.test(dest.email || "")) return false;
    const rows = await db("cc_secrets?select=cle,valeur&cle=in.(brevo_api_key,brevo_expediteur)") as { cle: string; valeur: string }[];
    const s: Record<string, string> = {}; for (const r of rows) s[r.cle] = r.valeur;
    if (!s.brevo_api_key) return false;
    const cfg = await settings();
    const reseau = cfg.reseau || "ComptaConnect", reponse = cfg.reponse_email || cfg.contact_email || "supportcomptaconnect@gmail.com";
    const r = await fetch("https://api.brevo.com/v3/smtp/email", { method: "POST", headers: { "api-key": s.brevo_api_key, "Content-Type": "application/json" },
      body: JSON.stringify({ sender: { name: reseau, email: s.brevo_expediteur || reponse }, replyTo: { email: reponse, name: reseau }, to: [{ email: dest.email, name: dest.nom || undefined }], subject: sujet, htmlContent: gabarit(reseau, html, cfg.site_public || "https://comptaconnect.org/") }) });
    return r.ok;
  } catch { return false; }
}
/** Habillage commun des e-mails (couleurs du réseau, pied de page). */
export function gabarit(reseau: string, corps: string, site: string) {
  return `<div style="font-family:Arial,Helvetica,sans-serif;max-width:560px;margin:auto;color:#1d2b25"><div style="background:#06301E;color:#fff;padding:14px 18px;border-radius:10px 10px 0 0"><b style="font-size:18px;letter-spacing:.5px">${reseau.toUpperCase().replace("CONNECT", '<span style="color:#B08A38">CONNECT</span>')}</b></div>` +
    `<div style="border:1px solid #e3e8e6;border-top:0;padding:18px;border-radius:0 0 10px 10px;line-height:1.5">${corps}` +
    `<p style="color:#5c6b76;font-size:12px;margin-top:22px;border-top:1px solid #eef2f0;padding-top:10px">Message automatique du réseau ${reseau} · <a href="${site}" style="color:#0B5A38">${site.replace(/^https?:\/\//, "").replace(/\/$/, "")}</a></p></div></div>`;
}
export const fcfa = (n: number) => String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, " ");
const MOIS_FR = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];
export const moisLibelle = (m: string) => /^\d{4}-\d{2}/.test(m) ? MOIS_FR[parseInt(m.slice(5, 7), 10) - 1] + " " + m.slice(0, 4) : m;
