// POST { code, mois? } -> crée une transaction CinetPay et renvoie l'URL de paiement (Wave / Orange / MTN / Moov)
import { CINETPAY_API, SB_URL, cors, db, json, reference, secrets, settings } from "../_shared/cc.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { code, mois, retour } = await req.json();
    const codeN = String(code || "").replace(/\D/g, "").padStart(3, "0");
    const moisN = /^\d{4}-\d{2}$/.test(String(mois || "")) ? String(mois) : new Date().toISOString().slice(0, 7);
    const [m] = await db(`cc_membres?select=*&code=eq.${codeN}`) as Record<string, unknown>[];
    if (!m) return json({ erreur: "Code membre introuvable" }, 404);
    const cfg = await settings();
    const cot = Number(m.cotisation || cfg.cotisation || 5000);
    const montant = m.actif ? cot : Number(cfg.adhesion || cot);   // nouveau membre : droit d'adhésion
    if (montant % 5 !== 0 || montant < 100) return json({ erreur: "Montant invalide" }, 400);

    // déjà payé pour ce mois ?
    const payes = await db(`cc_paiements?select=montant&membre_id=eq.${m.id}&mois=eq.${moisN}`) as { montant: number }[];
    const verse = payes.reduce((s, p) => s + Number(p.montant), 0);
    const reste = Math.max(0, cot - verse);
    const aPayer = m.actif ? (reste > 0 ? reste : 0) : montant;
    if (aPayer <= 0) return json({ erreur: "Ce mois est déjà réglé", deja: true }, 409);

    const { apikey, site_id } = await secrets();
    const transaction_id = "CC" + Date.now().toString(36).toUpperCase() + codeN;
    const sitePublic = String(retour || cfg.site_public || "");
    if (apikey === "SIMULATION") {
      // Mode démonstration : aucune transaction réelle, page de paiement simulée dans l'application
      await db("cc_transactions", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
        transaction_id, membre_id: m.id, code: codeN, mois: moisN, montant: aPayer, telephone: m.telephone || "", nom: m.nom,
        statut: "EN_ATTENTE", payment_token: "SIMULATION" }) });
      return json({ url: sitePublic + "#/simulation?tx=" + transaction_id + "&code=" + codeN + "&montant=" + aPayer, transaction_id, montant: aPayer, simulation: true });
    }
    const notify_url = `${SB_URL}/functions/v1/cinetpay-notify`;
    const return_url = String(retour || cfg.site_public || "") + `#/payer?code=${codeN}&retour=1`;
    const nomParts = String(m.nom || "Membre").trim().split(/\s+/);
    const corps = {
      apikey, site_id, transaction_id, amount: aPayer, currency: "XOF",
      description: `${cfg.reseau || "ComptaConnect"} — ${m.actif ? "cotisation " + moisN : "adhésion"} — ${reference(moisN, codeN)}`,
      notify_url, return_url, channels: "MOBILE_MONEY", lang: "fr",
      metadata: JSON.stringify({ code: codeN, mois: moisN }),
      customer_name: nomParts[0], customer_surname: nomParts.slice(1).join(" ") || nomParts[0],
      customer_phone_number: String(m.telephone || ""), customer_email: String(m.email || "") || undefined,
      customer_address: "Abidjan", customer_city: String(m.ville || "Abidjan"), customer_country: "CI", customer_state: "CI", customer_zip_code: "00225",
    };
    const r = await fetch(`${CINETPAY_API}/payment`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(corps) });
    const j = await r.json();
    if (j?.code !== "201" || !j?.data?.payment_url) return json({ erreur: "CinetPay a refusé la création : " + (j?.message || j?.description || j?.code) }, 502);

    await db("cc_transactions", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
      transaction_id, membre_id: m.id, code: codeN, mois: moisN, montant: aPayer, telephone: m.telephone || "", nom: m.nom,
      statut: "EN_ATTENTE", payment_token: j.data.payment_token || "" }) });
    return json({ url: j.data.payment_url, transaction_id, montant: aPayer });
  } catch (e) {
    return json({ erreur: String((e as Error).message || e) }, 500);
  }
});
