// Gestion des comptes de l'espace trésorier depuis Paramètres (réservé au rôle trésorier).
// POST { action: "liste" | "creer" | "mot_de_passe" | "role" | "supprimer", email?, mot_de_passe?, role?, nom? }
import { SB_URL, SB_KEY, cors, db, json } from "../_shared/cc.ts";

const admin = { apikey: SB_KEY, Authorization: `Bearer ${SB_KEY}`, "Content-Type": "application/json" };

async function appelant(req: Request) {
  const jeton = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!jeton) return null;
  const r = await fetch(`${SB_URL}/auth/v1/user`, { headers: { apikey: SB_KEY, Authorization: `Bearer ${jeton}` } });
  if (!r.ok) return null;
  const u = await r.json();
  return { id: String(u.id), email: String(u.email || "").toLowerCase() };
}
async function roleDe(email: string) {
  const roles = await db(`cc_roles?select=email,role`) as { email: string; role: string }[];
  if (!roles.length) return "tresorier";                                   // aucun rôle défini : compte unique = trésorier
  return roles.find((r) => r.email.toLowerCase() === email)?.role || "fondateur";
}
async function utilisateurs() {
  const r = await fetch(`${SB_URL}/auth/v1/admin/users?per_page=200`, { headers: admin });
  const j = await r.json();
  return (j.users || []) as { id: string; email: string; last_sign_in_at: string | null; created_at: string }[];
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const moi = await appelant(req);
    if (!moi) return json({ erreur: "Connexion requise" }, 401);
    if ((await roleDe(moi.email)) !== "tresorier") return json({ erreur: "Réservé au trésorier" }, 403);
    const b = await req.json().catch(() => ({}));
    const action = String(b.action || "liste");
    const email = String(b.email || "").trim().toLowerCase();
    const roles = await db(`cc_roles?select=*`) as { email: string; role: string; nom: string }[];

    if (action === "liste") {
      const us = await utilisateurs();
      return json({ comptes: us.map((u) => {
        const r = roles.find((x) => x.email.toLowerCase() === String(u.email).toLowerCase());
        return { email: u.email, nom: r?.nom || "", role: r ? r.role : (roles.length ? "fondateur" : "tresorier"), derniere_connexion: u.last_sign_in_at, cree_le: u.created_at, moi: u.email?.toLowerCase() === moi.email };
      }) });
    }
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ erreur: "E-mail invalide" }, 400);
    const role = b.role === "tresorier" ? "tresorier" : "fondateur";
    const nom = String(b.nom || "").slice(0, 80);
    const mdp = String(b.mot_de_passe || "");

    if (action === "creer") {
      if (mdp.length < 8) return json({ erreur: "Mot de passe : 8 caractères minimum" }, 400);
      const r = await fetch(`${SB_URL}/auth/v1/admin/users`, { method: "POST", headers: admin, body: JSON.stringify({ email, password: mdp, email_confirm: true, user_metadata: { nom, role } }) });
      const j = await r.json();
      if (!r.ok) return json({ erreur: j.msg || j.message || "Création refusée (e-mail déjà utilisé ?)" }, 400);
      // premier rôle enregistré : on garantit que le trésorier appelant garde ses droits
      if (!roles.length) await db("cc_roles", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ email: moi.email, role: "tresorier", nom: "" }) });
      await db("cc_roles?on_conflict=email", { method: "POST", headers: { Prefer: "return=minimal,resolution=merge-duplicates" }, body: JSON.stringify({ email, role, nom }) });
      return json({ ok: true });
    }
    const us = await utilisateurs();
    const u = us.find((x) => String(x.email).toLowerCase() === email);
    if (!u) return json({ erreur: "Compte introuvable" }, 404);

    if (action === "mot_de_passe") {
      if (mdp.length < 8) return json({ erreur: "Mot de passe : 8 caractères minimum" }, 400);
      const r = await fetch(`${SB_URL}/auth/v1/admin/users/${u.id}`, { method: "PUT", headers: admin, body: JSON.stringify({ password: mdp }) });
      if (!r.ok) return json({ erreur: "Changement refusé" }, 400);
      return json({ ok: true });
    }
    if (action === "role") {
      if (email === moi.email && role !== "tresorier") return json({ erreur: "Vous ne pouvez pas retirer vos propres droits de trésorier" }, 400);
      if (!roles.length && email !== moi.email) await db("cc_roles", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ email: moi.email, role: "tresorier", nom: "" }) });
      await db("cc_roles?on_conflict=email", { method: "POST", headers: { Prefer: "return=minimal,resolution=merge-duplicates" }, body: JSON.stringify({ email, role, nom }) });
      return json({ ok: true });
    }
    if (action === "supprimer") {
      if (email === moi.email) return json({ erreur: "Vous ne pouvez pas supprimer votre propre compte" }, 400);
      const r = await fetch(`${SB_URL}/auth/v1/admin/users/${u.id}`, { method: "DELETE", headers: admin });
      if (!r.ok) return json({ erreur: "Suppression refusée" }, 400);
      await db(`cc_roles?email=eq.${encodeURIComponent(email)}`, { method: "DELETE", headers: { Prefer: "return=minimal" } });
      return json({ ok: true });
    }
    return json({ erreur: "Action inconnue" }, 400);
  } catch (e) {
    return json({ erreur: String((e as Error).message || e) }, 500);
  }
});
