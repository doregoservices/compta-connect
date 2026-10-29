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
  return { apikey: s.cinetpay_api_key, site_id: s.cinetpay_site_id };
}
export async function settings() {
  const rows = await db("cc_settings?select=cle,valeur") as { cle: string; valeur: string }[];
  const s: Record<string, string> = {}; for (const r of rows) s[r.cle] = r.valeur; return s;
}

export function moisCourt(mois: string) { return mois.slice(2, 4) + mois.slice(5, 7); }
export function reference(mois: string, code: string) { return "CC" + moisCourt(mois) + code.padStart(3, "0"); }

/** Vérifie une transaction auprès de CinetPay (source de vérité, jamais le simple POST de notification). */
export async function verifierTransaction(transaction_id: string) {
  const { apikey, site_id } = await secrets();
  const r = await fetch(`${CINETPAY_API}/payment/check`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ apikey, site_id, transaction_id }),
  });
  const j = await r.json();
  return { ok: j?.code === "00" && j?.data?.status === "ACCEPTED", brut: j, montant: Number(j?.data?.amount || 0),
    methode: String(j?.data?.payment_method || ""), operateur: String(j?.data?.operator_id || "") };
}

/** Enregistre le paiement (idempotent) : une transaction CinetPay acceptée = une ligne cc_paiements. */
export async function enregistrerPaiement(t: { id: number; transaction_id: string; membre_id: number; code: string; mois: string; montant: number; telephone: string; nom: string }, verif: { montant: number; methode: string; operateur: string }) {
  const deja = await db(`cc_paiements?select=id&libelle=eq.${encodeURIComponent("CinetPay " + t.transaction_id)}`) as unknown[];
  if (deja.length) return { deja: true };
  const montant = verif.montant || t.montant;
  await db("cc_paiements", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
    date: new Date().toISOString().slice(0, 10), montant, canal: "CinetPay" + (verif.methode ? " · " + verif.methode : ""),
    expediteur: t.nom, telephone: t.telephone, libelle: "CinetPay " + t.transaction_id + " · " + reference(t.mois, t.code),
    mois: t.mois, membre_id: t.membre_id, statut: "RAPPROCHE", methode: "cinetpay",
  }) });
  await db(`cc_transactions?id=eq.${t.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ statut: "ACCEPTEE", maj_le: new Date().toISOString(), montant_recu: montant, operateur: verif.operateur }) });
  return { deja: false };
}
