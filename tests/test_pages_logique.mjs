/*
 * Teste la logique métier de la version GitHub Pages (docs/index.html).
 * Le bloc « LOGIQUE » est extrait du HTML puis exécuté par Node :
 * ce sont exactement les fonctions livrées aux membres, pas une copie.
 *
 * Lancer :  node tests/test_pages_logique.mjs
 */
import { readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";

const html = readFileSync(new URL("../docs/index.html", import.meta.url), "utf8");
const debut = html.indexOf("/* ==LOGIQUE-DEBUT== */");
const fin = html.indexOf("/* ==LOGIQUE-FIN== */");
if (debut < 0 || fin < 0) throw new Error("Bloc LOGIQUE introuvable dans index.html");
writeFileSync("/tmp/logique-pages.cjs", html.slice(debut, fin));
const require = createRequire(import.meta.url);
const L = require("/tmp/logique-pages.cjs");

let nb = 0;
function eq(recu, attendu, quoi) {
  nb++;
  const r = JSON.stringify(recu), a = JSON.stringify(attendu);
  if (r !== a) { console.error(`ÉCHEC ${quoi}\n  reçu     : ${r}\n  attendu  : ${a}`); process.exitCode = 1; }
}

/* --- références --- */
eq(L.reference("2026-09", "006"), "CC2609006", "reference");
eq(L.reference("2026-09", 6), "CC2609006", "reference (code numérique)");
eq(L.analyserReference("Transfert reçu de KONE AMI ref CC2609006"), ["2026-09", "006"], "ref dans un motif");
eq(L.analyserReference("cc 26 09 006"), ["2026-09", "006"], "ref espacée sans préfixe");
eq(L.analyserReference("CC2609006-12345"), ["2026-09", "006"], "ref + suffixe transaction");
eq(L.analyserReference("Paiement facture"), null, "texte sans référence");
eq(L.analyserReference("CC2613006"), null, "mois 13 invalide");

/* --- mois --- */
eq(L.normaliserMois("2026-9"), "2026-09", "normaliserMois");
eq(L.moisCourt("2026-09"), "2609", "moisCourt");
eq(L.moisSuivant("2026-12"), "2027-01", "moisSuivant (décembre)");
eq(L.libelleMois("2026-09"), "septembre 2026", "libelleMois");
eq(L.echeance("2026-02", 30), "2026-02-28", "échéance bornée au dernier jour");

/* --- téléphone (mêmes règles que le moteur Python) --- */
eq(L.telephoneNormalise("+225 07 08 09 10 11"), "2250708091011", "tél international");
eq(L.telephoneNormalise("0708091011"), "2250708091011", "tél local 10 chiffres");
eq(L.telephoneNormalise("02250708091011"), "2250708091011", "tél préfixé 0+225");

/* --- noms --- */
eq(L.correspondanceNom("GNAMIEN Éric Landry", "GNAMIEN ERIC"), true, "nom avec accents");
eq(L.correspondanceNom("KOUASSI Aya", "TRAORE Aminata"), false, "noms différents");

/* --- rapprochement --- */
const membres = [
  { id: 1, code: "001", nom: "KOUASSI Aya Michelle", telephone: "0708112233", cotisation: 5000, actif: true, exonere: false },
  { id: 2, code: "002", nom: "YAO Kouadio Serge",    telephone: "0544556677", cotisation: 5000, actif: true, exonere: false },
];
let p = { membre_id: null, mois: "", statut: "NON_RAPPROCHE", methode: "aucun", libelle: "CC2609002", telephone: "", expediteur: "", montant: 5000 };
L.rapprocherPaiement(p, membres, "2026-09");
eq([p.membre_id, p.mois, p.methode], [2, "2026-09", "ref"], "rapprochement par référence");

p = { membre_id: null, mois: "", statut: "NON_RAPPROCHE", methode: "aucun", libelle: "", telephone: "+225 07 08 11 22 33", expediteur: "", montant: 5000 };
L.rapprocherPaiement(p, membres, "2026-09");
eq([p.membre_id, p.methode], [1, "tel"], "rapprochement par téléphone");

p = { membre_id: null, mois: "", statut: "NON_RAPPROCHE", methode: "aucun", libelle: "", telephone: "", expediteur: "YAO SERGE", montant: 5000 };
L.rapprocherPaiement(p, membres, "2026-09");
eq([p.membre_id, p.methode], [2, "nom"], "rapprochement par nom");

/* --- pointage --- */
const un = [{ id: 9, code: "009", nom: "TEST Membre", telephone: "", cotisation: 5000, actif: true, exonere: false }];
const paie = (montant, mois = "2026-09") => ({ membre_id: 9, montant, mois, statut: "RAPPROCHE" });
eq(L.pointage(un, [paie(5000)], "2026-09").lignes[0].statut, "PAYE", "statut PAYE");
eq(L.pointage(un, [paie(2000)], "2026-09").lignes[0].statut, "PARTIEL", "statut PARTIEL");
eq(L.pointage(un, [paie(2000)], "2026-09").lignes[0].reliquat, 3000, "reliquat");
eq(L.pointage(un, [paie(7000)], "2026-09").lignes[0].statut, "AVANCE", "statut AVANCE");
eq(L.pointage(un, [], "2026-09").lignes[0].statut, "IMPAYE", "statut IMPAYE");
eq(L.pointage(un, [paie(5000, "2026-10")], "2026-09").lignes[0].statut, "IMPAYE", "avance ne paie pas le mois courant");
eq(L.pointage(un, [paie(5000)], "2026-09").totaux.taux, 100, "taux de recouvrement");
eq(L.fcfa(400000), "400 000", "formatage FCFA");

console.log(process.exitCode ? "ÉCHECS — voir ci-dessus" : `OK — ${nb} assertions sur la logique GitHub Pages`);
