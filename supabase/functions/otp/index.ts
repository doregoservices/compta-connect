// Connexion du trésorier par code à usage unique (e-mail via Brevo).
// POST { action:"demander", email }            → envoie un code à 6 chiffres (valable 10 min) si l'adresse correspond à un compte existant
// POST { action:"verifier", email, code }      → renvoie un jeton de session (JWT signé avec le secret du serveur, 12 h)
// Les codes sont hachés (SHA-256) dans cc_otp ; 5 essais maximum ; jamais de création de compte.
import { cors, db, envoyerEmail, json, settings } from "../_shared/cc.ts";

const enc = new TextEncoder();
const sha = async (s: string) => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)))).map((b) => b.toString(16).padStart(2, "0")).join("");
const b64u = (s: string | Uint8Array) => btoa(typeof s === "string" ? s : String.fromCharCode(...s)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
async function jwt(payload: Record<string, unknown>) {
  const secret = Deno.env.get("JWT_SECRET") || ""; if (!secret) throw new Error("JWT_SECRET absent");
  const h = b64u(JSON.stringify({ alg: "HS256", typ: "JWT" })), p = b64u(JSON.stringify(payload));
  const k = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", k, enc.encode(h + "." + p)));
  return h + "." + p + "." + b64u(sig);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { action, email, code } = await req.json();
    const em = String(email || "").trim().toLowerCase();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) return json({ erreur: "Adresse e-mail invalide" }, 400);
    const [u] = await db(`rpc/cc_compte_par_email`, { method: "POST", body: JSON.stringify({ p_email: em }) }) as { id: string; email: string }[] || [];
    const reponseNeutre = { ok: true, message: "Si cette adresse correspond à un compte, un code vient d'être envoyé." };
    if (action === "demander") {
      if (!u) return json(reponseNeutre);                                  // ne révèle pas l'existence des comptes
      const recents = await db(`cc_otp?select=id&email=eq.${encodeURIComponent(em)}&cree_le=gte.${new Date(Date.now() - 60000).toISOString()}`) as unknown[];
      if (recents.length) return json({ erreur: "Un code vient déjà d'être envoyé. Patientez une minute." }, 429);
      const c = String(Math.floor(100000 + Math.random() * 900000));
      await db("cc_otp", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ email: em, hache: await sha(em + ":" + c), expire_le: new Date(Date.now() + 10 * 60000).toISOString() }) });
      const cfg = await settings();
      const ok = await envoyerEmail({ email: em }, `${c} — votre code de connexion ${cfg.reseau || "ComptaConnect"}`,
        `<p>Bonjour,</p><p>Voici votre code de connexion à l'espace trésorier :</p><p style="font-size:32px;letter-spacing:8px;font-weight:bold;color:#06301E;margin:12px 0">${c}</p>` +
        `<p>Il est valable <b>10 minutes</b> et ne peut servir qu'une fois. Si vous n'êtes pas à l'origine de cette demande, ignorez simplement ce message.</p>`);
      if (!ok) return json({ erreur: "Envoi impossible : l'e-mail n'est pas configuré (clé Brevo absente). Utilisez le mot de passe." }, 503);
      return json(reponseNeutre);
    }
    if (action === "verifier") {
      const c = String(code || "").replace(/\D/g, "");
      if (!u || c.length !== 6) return json({ erreur: "Code incorrect" }, 401);
      const [o] = await db(`cc_otp?select=*&email=eq.${encodeURIComponent(em)}&utilise=is.false&expire_le=gte.${new Date().toISOString()}&order=cree_le.desc&limit=1`) as Record<string, unknown>[];
      if (!o) return json({ erreur: "Code expiré ou inexistant. Demandez-en un nouveau." }, 401);
      if (Number(o.essais) >= 5) return json({ erreur: "Trop d'essais. Demandez un nouveau code." }, 429);
      if (o.hache !== await sha(em + ":" + c)) {
        await db(`cc_otp?id=eq.${o.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ essais: Number(o.essais) + 1 }) });
        return json({ erreur: "Code incorrect" }, 401);
      }
      await db(`cc_otp?id=eq.${o.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ utilise: true }) });
      await db(`cc_otp?expire_le=lt.${new Date().toISOString()}`, { method: "DELETE", headers: { Prefer: "return=minimal" } }).catch(() => null);
      const now = Math.floor(Date.now() / 1000), exp = now + 12 * 3600;
      const token = await jwt({ aud: "authenticated", role: "authenticated", sub: u.id, email: u.email, iss: "comptaconnect", iat: now, exp, amr: [{ method: "otp", timestamp: now }] });
      return json({ access_token: token, expires_in: exp - now, email: u.email });
    }
    return json({ erreur: "action inconnue" }, 400);
  } catch (e) { return json({ erreur: String((e as Error).message || e) }, 500); }
});
