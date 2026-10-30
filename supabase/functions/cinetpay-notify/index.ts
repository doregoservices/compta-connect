// Webhook CinetPay (notify_url) + vérification manuelle : GET/POST ?transaction_id=... ou formulaire cpm_trans_id
// Ne fait JAMAIS confiance au corps reçu : revérifie la transaction auprès de CinetPay avant d'enregistrer.
import { cors, db, enregistrerPaiement, json, verifierTransaction } from "../_shared/cc.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    let tid = new URL(req.url).searchParams.get("transaction_id") || "";
    if (!tid && req.method === "POST") {
      const ct = req.headers.get("content-type") || "";
      if (ct.includes("json")) { const b = await req.json().catch(() => ({})); tid = b.transaction_id || b.cpm_trans_id || ""; }
      else { const f = await req.formData().catch(() => null); tid = String(f?.get("cpm_trans_id") || f?.get("transaction_id") || ""); }
    }
    if (!tid) return json({ erreur: "transaction_id manquant" }, 400);

    const [t] = await db(`cc_transactions?select=*&transaction_id=eq.${encodeURIComponent(tid)}`) as Record<string, unknown>[];
    if (!t) return json({ erreur: "Transaction inconnue" }, 404);
    if (t.statut === "ACCEPTEE") return json({ statut: "ACCEPTEE", deja: true });

    // Mode simulation : la transaction a été créée avec le jeton "SIMULATION" ; on accepte/refuse selon le choix fait sur la page simulée
    if (t.payment_token === "SIMULATION") {
      const choix = new URL(req.url).searchParams.get("simulation") || "";
      if (choix === "ok") {
        const r = await enregistrerPaiement(t as never, { montant: Number(t.montant), methode: "SIMULATION", operateur: "TEST" });
        return json({ statut: "ACCEPTEE", deja: r.deja, simulation: true });
      }
      if (choix === "refus") {
        await db(`cc_transactions?id=eq.${t.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ statut: "REFUSEE", maj_le: new Date().toISOString() }) });
        return json({ statut: "REFUSEE", simulation: true });
      }
      return json({ statut: t.statut, simulation: true });
    }
    const v = await verifierTransaction(tid);
    if (!v.ok) {
      const st = String(v.brut?.data?.status || v.brut?.code || "EN_ATTENTE");
      await db(`cc_transactions?id=eq.${t.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" },
        body: JSON.stringify({ statut: st === "REFUSED" ? "REFUSEE" : "EN_ATTENTE", maj_le: new Date().toISOString() }) });
      return json({ statut: st === "REFUSED" ? "REFUSEE" : "EN_ATTENTE" });
    }
    const r = await enregistrerPaiement(t as never, v);
    return json({ statut: "ACCEPTEE", deja: r.deja });
  } catch (e) {
    return json({ erreur: String((e as Error).message || e) }, 500);
  }
});
