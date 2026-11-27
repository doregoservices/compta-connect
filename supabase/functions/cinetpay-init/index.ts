// POST { code, mois? } -> crée une transaction CinetPay et renvoie l'URL de paiement (Wave / Orange / MTN / Moov)
import { CINETPAY_API, SB_URL, cors, db, jetonV1, json, reference, secrets, settings } from "../_shared/cc.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { code, mois, retour, appel, stagiaire, tel: telStagiaire, entreprise, code_acces, objet } = await req.json();
    const codeN = String(code || "").replace(/\D/g, "").padStart(3, "0");
    const moisN = /^\d{4}-\d{2}$/.test(String(mois || "")) ? String(mois) : new Date().toISOString().slice(0, 7);
    const cfg = await settings();
    let m: Record<string, unknown>;
    let aPayer = 0, appelId: number | null = null, libelle = "", stagiaireId: number | null = null, entrepriseId: number | null = null, objetTx = "";
    if (entreprise) {
      // Entreprise : abonnement annuel ou contact à l'unité ; identifiée par téléphone + code d'accès
      const telN = String(telStagiaire || "").replace(/\D/g, "").replace(/^225(\d{10})$/, "$1");
      const [en] = await db(`cc_entreprises?select=*&id=eq.${Number(entreprise) || 0}&telephone=eq.${encodeURIComponent(telN)}&code=eq.${encodeURIComponent(String(code_acces || "").toUpperCase().trim())}`) as Record<string, unknown>[];
      if (!en) return json({ erreur: "Entreprise introuvable ou code incorrect" }, 404);
      entrepriseId = Number(en.id);
      objetTx = ["contact", "pack3", "pack10"].includes(String(objet)) ? String(objet) : "abonnement";
      aPayer = objetTx === "contact" ? Number(cfg.entreprises_contact_tarif || 5000) : objetTx === "pack3" ? Number(cfg.entreprises_pack3_tarif || 12000) : objetTx === "pack10" ? Number(cfg.entreprises_pack10_tarif || 30000) : Number(cfg.entreprises_tarif || 150000);
      if (aPayer % 5 !== 0 || aPayer < 100) return json({ erreur: "Montant invalide" }, 400);
      libelle = objetTx === "contact" ? "contact annuaire (entreprise)" : objetTx === "pack3" ? "pack 3 contacts (entreprise)" : objetTx === "pack10" ? "pack 10 contacts (entreprise)" : "abonnement entreprise partenaire";
      m = { id: null, code: "000", nom: en.contact_nom || en.nom, telephone: en.telephone, email: en.email, ville: en.ville, actif: true, matricule: "" };
    } else if (stagiaire) {
      // Inscription à l'annuaire public des stagiaires (non-membre) : montant fixe, aucun mois de cotisation, caisse « stagiaires »
      const telN = String(telStagiaire || "").replace(/\D/g, "").replace(/^225(\d{10})$/, "$1");
      const [s] = await db(`cc_stagiaires?select=*&id=eq.${Number(stagiaire) || 0}&membre_id=is.null`) as Record<string, unknown>[];
      if (!s || String(s.telephone || "") !== telN || telN.length < 8) return json({ erreur: "Fiche stagiaire introuvable" }, 404);
      stagiaireId = Number(s.id);
      aPayer = Number((s.domaine === "autre" && cfg.stagiaires_tarif_autre) || cfg.stagiaires_tarif || 2000);
      if (aPayer % 5 !== 0 || aPayer < 100) return json({ erreur: "Montant invalide" }, 400);
      libelle = "annuaire stagiaires";
      m = { id: null, code: "000", nom: s.nom, telephone: s.telephone, email: s.email, ville: s.ville, actif: true, matricule: "" };
    } else {
      [m] = await db(`cc_membres?select=*&code=eq.${codeN}`) as Record<string, unknown>[];
      if (!m) return json({ erreur: "Code membre introuvable" }, 404);
    }
    const cot = Number(m.cotisation || cfg.cotisation || 5000);
    if (stagiaireId || entrepriseId) {
      // rien d'autre à calculer
    } else if (appel) {
      // Appel à paiement (formation, document, carte membre…) : montant de l'appel moins ce qui est déjà versé
      const [a] = await db(`cc_appels?select=*&id=eq.${Number(appel) || 0}`) as Record<string, unknown>[];
      if (!a) return json({ erreur: "Appel à paiement introuvable" }, 404);
      if (!a.ouvert) return json({ erreur: "Cet appel à paiement est clôturé" }, 409);
      appelId = Number(a.id);
      const payes = await db(`cc_paiements?select=montant&membre_id=eq.${m.id}&appel_id=eq.${appelId}`) as { montant: number }[];
      const verse = payes.reduce((s, p) => s + Number(p.montant), 0);
      aPayer = Math.max(0, Number(a.montant) - verse);
      libelle = String(a.titre);
      if (aPayer <= 0) return json({ erreur: "Déjà réglé", deja: true }, 409);
    } else {
      // Cotisation en nature (à partir de nature_depuis) : rien de dû sauf le complément annuel au mois d'échéance
      let cotMois = cot;
      if (m.cotisation_nature && (!m.nature_depuis || moisN >= String(m.nature_depuis).slice(0, 7))) {
        const ech = String(Number(cfg.nature_revision_mois || 12)).padStart(2, "0");
        const ex = (m.nature_exceptions || {}) as Record<string, unknown>;
        const comp = ex[moisN.slice(0, 4)] !== undefined ? Number(ex[moisN.slice(0, 4)]) : Number(m.nature_montant || 0);
        cotMois = moisN.slice(5, 7) === ech ? comp : 0;
        if (cotMois <= 0) return json({ erreur: "Cotisation réglée en nature pour ce mois : rien à payer" }, 409);
      }
      const montant = m.actif ? cotMois : Number(cfg.adhesion || cot);   // nouveau membre : droit d'adhésion
      if (montant % 5 !== 0 || montant < 100) return json({ erreur: "Montant invalide" }, 400);
      // déjà payé pour ce mois ?
      const payes = await db(`cc_paiements?select=montant&membre_id=eq.${m.id}&mois=eq.${moisN}&caisse=eq.cotisation`) as { montant: number }[];
      const verse = payes.reduce((s, p) => s + Number(p.montant), 0);
      const reste = Math.max(0, cotMois - verse);
      aPayer = m.actif ? (reste > 0 ? reste : 0) : montant;
      libelle = m.actif ? "cotisation " + moisN : "adhésion";
      if (aPayer <= 0) return json({ erreur: "Ce mois est déjà réglé", deja: true }, 409);
    }
    const matricule = String(m.matricule || codeN);
    const tel = String(m.telephone || "").replace(/\D/g, "");
    const ident = tel.length >= 8 ? `t=${encodeURIComponent(tel)}` : `m=${encodeURIComponent(String(m.matricule || ""))}`;
    const retourHash = entrepriseId ? `#/entreprises?retour=1` : stagiaireId ? `#/stagiaires?retour=1&t=${encodeURIComponent(tel)}` : appelId ? `#/payer?${ident}&retour=1&appel=${appelId}` : `#/payer?${ident}&retour=1`;
    const caisseTx = entrepriseId ? "entreprises" : stagiaireId ? "stagiaires" : !appelId && !m.actif ? "inscription" : "cotisation";

    const sec = await secrets();
    const { apikey, site_id } = sec;
    const transaction_id = "CC" + Date.now().toString(36).toUpperCase() + (entrepriseId ? "E" + entrepriseId : stagiaireId ? "S" + stagiaireId : codeN);
    const sitePublic = String(retour || cfg.site_public || "");
    if (apikey === "SIMULATION") {
      // Mode démonstration : aucune transaction réelle, page de paiement simulée dans l'application
      await db("cc_transactions", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
        transaction_id, membre_id: m.id, code: codeN, mois: appelId || !m.actif ? "" : moisN, appel_id: appelId, caisse: caisseTx, stagiaire_id: stagiaireId, entreprise_id: entrepriseId, objet: objetTx, montant: aPayer, telephone: m.telephone || "", nom: m.nom,
        statut: "EN_ATTENTE", payment_token: "SIMULATION" }) });
      return json({ url: sitePublic + "#/simulation?tx=" + transaction_id + "&retour=" + encodeURIComponent(retourHash) + "&montant=" + aPayer + "&libelle=" + encodeURIComponent(libelle), transaction_id, montant: aPayer, simulation: true });
    }
    const notify_url = `${SB_URL}/functions/v1/cinetpay-notify`;
    const return_url = sitePublic + retourHash;
    const nomParts = String(m.nom || "Membre").trim().split(/\s+/);
    if (sec.v1) {
      // Mode bac à sable (sk_test_) : réservé aux numéros de test listés dans Paramètres (cinetpay_test_tel), pour ne créditer aucun vrai membre par erreur
      if (sec.apikey.startsWith("sk_test_")) {
        const autorises = String(cfg.cinetpay_test_tel || "").split(/[,;\s]+/).map((x) => x.replace(/\D/g, "")).filter((x) => x.length >= 8);
        const telN = tel.length === 13 && tel.startsWith("225") ? tel.slice(3) : tel;
        if (!autorises.some((a) => a === telN || a === tel || "225" + a === tel || a === "225" + telN)) return json({ erreur: "Le paiement en ligne est en cours d'activation (phase de test). Réessayez dans quelques jours." }, 503);
      }
      // Nouvelle API CinetPay v1 : OAuth puis POST /v1/payment
      const tok = await jetonV1(sec);
      const prenom = (nomParts[0] || "Membre").padEnd(2, "."), nomF = (nomParts.slice(1).join(" ") || nomParts[0] || "Membre").padEnd(2, ".");
      const corpsV1 = {
        currency: "XOF", merchant_transaction_id: transaction_id, amount: aPayer, lang: "fr",
        designation: `${cfg.reseau || "ComptaConnect"} - ${libelle}`.slice(0, 120),
        client_email: String(m.email || "").includes("@") ? String(m.email) : (cfg.contact_email || "supportcomptaconnect@gmail.com"),
        client_first_name: prenom.slice(0, 100), client_last_name: nomF.slice(0, 100),
        client_phone_number: tel.length >= 8 ? "+" + (tel.length === 10 ? "225" + tel : tel) : undefined,
        success_url: return_url.slice(0, 120), failed_url: (return_url + "&echec=1").slice(0, 120), notify_url, channel: "PUSH",
      };
      const r = await fetch(`${sec.base}/v1/payment`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${tok}`, ...sec.entetes }, body: JSON.stringify(corpsV1) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok || !j?.payment_url) return json({ erreur: "CinetPay a refusé la création : " + (j?.description || j?.message || j?.status || r.status) }, 502);
      await db("cc_transactions", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
        transaction_id, membre_id: m.id, code: codeN, mois: appelId || !m.actif ? "" : moisN, appel_id: appelId, caisse: caisseTx, stagiaire_id: stagiaireId, entreprise_id: entrepriseId, objet: objetTx, montant: aPayer, telephone: m.telephone || "", nom: m.nom,
        statut: "EN_ATTENTE", payment_token: String(j.payment_token || ""), notify_token: String(j.notify_token || ""), cinetpay_id: String(j.transaction_id || "") }) });
      return json({ url: j.payment_url, transaction_id, montant: aPayer });
    }
    const corps = {
      apikey, site_id, transaction_id, amount: aPayer, currency: "XOF",
      description: `${cfg.reseau || "ComptaConnect"} — ${libelle} — ${entrepriseId ? "ENT" + entrepriseId : stagiaireId ? "STG" + stagiaireId : appelId ? matricule : reference(moisN, codeN)}`,
      notify_url, return_url, channels: "MOBILE_MONEY", lang: "fr",
      metadata: JSON.stringify({ code: codeN, mois: appelId || !m.actif ? "" : moisN, appel: appelId, caisse: caisseTx, stagiaire: stagiaireId }),
      customer_name: nomParts[0], customer_surname: nomParts.slice(1).join(" ") || nomParts[0],
      customer_phone_number: String(m.telephone || ""), customer_email: String(m.email || "") || undefined,
      customer_address: "Abidjan", customer_city: String(m.ville || "Abidjan"), customer_country: "CI", customer_state: "CI", customer_zip_code: "00225",
    };
    const r = await fetch(`${CINETPAY_API}/payment`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(corps) });
    const j = await r.json();
    if (j?.code !== "201" || !j?.data?.payment_url) return json({ erreur: "CinetPay a refusé la création : " + (j?.message || j?.description || j?.code) }, 502);

    await db("cc_transactions", { method: "POST", headers: { Prefer: "return=minimal" }, body: JSON.stringify({
      transaction_id, membre_id: m.id, code: codeN, mois: appelId || !m.actif ? "" : moisN, appel_id: appelId, caisse: caisseTx, stagiaire_id: stagiaireId, entreprise_id: entrepriseId, objet: objetTx, montant: aPayer, telephone: m.telephone || "", nom: m.nom,
      statut: "EN_ATTENTE", payment_token: j.data.payment_token || "" }) });
    return json({ url: j.data.payment_url, transaction_id, montant: aPayer });
  } catch (e) {
    return json({ erreur: String((e as Error).message || e) }, 500);
  }
});
