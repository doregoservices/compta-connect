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
  const base = s.cinetpay_api_key.startsWith("sk_live_") ? "https://api.cinetpay.co" : "https://api.cinetpay.net";
  return { apikey: s.cinetpay_api_key, site_id: s.cinetpay_site_id, v1, base };
}
let _jeton: { base: string; token: string; exp: number } | null = null;
/** Jeton OAuth v1 (mis en cache ~50 min dans l'instance). */
export async function jetonV1(sec: { apikey: string; site_id: string; base: string }) {
  if (_jeton && _jeton.base === sec.base && _jeton.exp > Date.now()) return _jeton.token;
  const r = await fetch(`${sec.base}/v1/oauth/login`, { method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: sec.apikey, api_password: sec.site_id }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j?.access_token) throw new Error("Connexion CinetPay refusée (clé API ou mot de passe API incorrect)");
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
    const r = await fetch(`${sec.base}/v1/payment/${encodeURIComponent(transaction_id)}`, { headers: { Authorization: `Bearer ${tok}` } });
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
  await db("cc_paiements", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
    date: new Date().toISOString().slice(0, 10), montant, canal: "CinetPay" + (verif.methode ? " · " + verif.methode : ""),
    expediteur: t.nom, telephone: t.telephone, libelle: "CinetPay " + t.transaction_id + " · " + detail,
    mois: t.appel_id || inscription ? "" : t.mois, appel_id: t.appel_id || null, membre_id: t.membre_id, statut: "RAPPROCHE", methode: "cinetpay",
    caisse: inscription ? "inscription" : "cotisation", reference_externe: t.transaction_id, frais,
  }) });
  await db(`cc_transactions?id=eq.${t.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ statut: "ACCEPTEE", maj_le: new Date().toISOString(), montant_recu: montant, operateur: verif.operateur }) });
  return { deja: false };
}
