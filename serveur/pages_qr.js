// Pages publiques indexables des Questions & réponses (référencement Google + partage WhatsApp).
// Génère : <site>/q/<id>.html (une page par question avec au moins une réponse validée), <site>/q/index.html, sitemap.xml, robots.txt.
// Exécuté par cron toutes les 15 min ; ne réécrit que ce qui a changé (empreinte). Poids : ~6 Ko par page.
const fs = require("fs"), path = require("path"), crypto = require("crypto");
const URL = process.env.SUPABASE_URL || "http://127.0.0.1:3000", KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const REST = URL.startsWith("http://127") ? URL : URL + "/rest/v1";
const SITE = process.env.SITE_DIR || "/var/www/comptaconnect", BASE = (process.env.SITE_PUBLIC || "https://comptaconnect.org").replace(/\/$/, "");
const H = { apikey: KEY, Authorization: "Bearer " + KEY };
const db = async p => { const r = await fetch(REST + "/" + p, { headers: H }); if (!r.ok) throw new Error(p + " → " + r.status); return r.json(); };
const ech = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const slug = s => String(s).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 70);
const dateFR = d => d ? new Date(d).toLocaleDateString("fr-FR") : "";
const NOMS = ["janvier","février","mars","avril","mai","juin","juillet","août","septembre","octobre","novembre","décembre"];
const ecrire = (f, contenu) => { const p = path.join(SITE, f); fs.mkdirSync(path.dirname(p), { recursive: true }); if (fs.existsSync(p) && fs.readFileSync(p, "utf8") === contenu) return false; fs.writeFileSync(p, contenu); return true; };
function gabarit({ titre, description, canon, corps, jsonld }) {
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${ech(titre)}</title><meta name="description" content="${ech(description)}"><link rel="canonical" href="${canon}">
<meta property="og:title" content="${ech(titre)}"><meta property="og:description" content="${ech(description)}"><meta property="og:type" content="article"><meta property="og:url" content="${canon}"><meta property="og:image" content="${BASE}/icon-512.png"><meta property="og:site_name" content="ComptaConnect">
<link rel="icon" href="/icon-192.png"><link rel="manifest" href="/manifest.webmanifest">
${jsonld ? '<script type="application/ld+json">' + JSON.stringify(jsonld) + "</script>" : ""}
<style>:root{--navy:#06301E;--vert:#0B5A38;--or:#B08A38}*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;background:#f4f6f5;color:#1d2b25;line-height:1.55}
header{background:linear-gradient(135deg,#0A1C2D,#16283E 60%,#085041);color:#fff;padding:14px 18px}header a{color:#fff;text-decoration:none;font-weight:800;letter-spacing:.5px}header b{color:#7DCDB0}header small{display:block;opacity:.8;font-weight:400;font-size:12px}
main{max-width:820px;margin:0 auto;padding:18px}.carte{background:#fff;border:1px solid #e3e8e6;border-radius:14px;padding:18px;margin-bottom:14px}h1{font-size:22px;color:var(--navy);margin:0 0 6px}h2{font-size:17px;color:var(--navy)}
.mut{color:#5c6b76;font-size:13.5px}.rep{border-left:3px solid var(--vert);padding-left:12px;margin-top:12px;white-space:pre-wrap}.badge{display:inline-block;background:#e6f4ec;color:var(--vert);border-radius:999px;padding:2px 9px;font-size:12px;font-weight:700}
.btn{display:inline-block;background:var(--vert);color:#fff;border-radius:9px;padding:9px 14px;text-decoration:none;font-weight:700;font-size:14px}.btn.sec{background:#e6f4ec;color:var(--navy)}.btn.wa{background:#25D366}
.cta{background:#fffbea;border:1px solid #f3c969;border-radius:14px;padding:14px 18px}.liste a{display:block;padding:10px 0;border-top:1px solid #eef2f0;color:var(--navy);text-decoration:none;font-weight:600}.liste a:first-child{border-top:0}.tag{display:inline-block;background:#eef2f0;border-radius:6px;padding:1px 7px;font-size:12px;margin-right:4px;color:#3b4a44}
footer{text-align:center;color:#5c6b76;font-size:12px;padding:20px}footer a{color:inherit}</style></head><body>
<header><a href="/">COMPTA<b>CONNECT</b><small>Le réseau des comptables et financiers d’Afrique francophone — base de connaissances</small></a></header><main>${corps}</main>
<footer>© ComptaConnect · <a href="/#/questions">Toutes les questions dans l’application</a> · <a href="/confidentialite.html">Confidentialité</a></footer></body></html>`;
}
(async () => {
  const S = Object.fromEntries((await db("cc_settings?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  if ((S.questions || "oui") === "non") return console.log("Q/R désactivées : rien à publier");
  const qs = await db("cc_questions?select=id,question,tags,anonyme,membre_id,cree_le&publie=is.true&order=cree_le.desc&limit=5000");
  const reps = await db("cc_reponses?select=id,question_id,membre_id,texte,validations,verifiee_annee,cree_le&publie=is.true&limit=20000");
  const ms = await db("cc_membres?select=id,nom,titre,specialite&limit=10000"); const nom = id => (ms.find(m => m.id === id) || {}).nom || "Un membre du réseau";
  const parQ = {}; for (const r of reps) (parQ[r.question_id] = parQ[r.question_id] || []).push(r);
  const publiees = qs.filter(q => (parQ[q.id] || []).length), an = new Date().getFullYear();
  let ecrits = 0; const urls = [];
  for (const q of publiees) {
    const rs = parQ[q.id].sort((a, b) => new Date(a.cree_le) - new Date(b.cree_le)), canon = `${BASE}/q/${q.id}`;
    const desc = rs[0].texte.replace(/\s+/g, " ").slice(0, 155);
    const partage = encodeURIComponent(`${q.question}\n\nRéponse validée par le réseau ComptaConnect : ${canon}`);
    const corps = `<div class="carte"><div class="mut">Question posée par ${ech(q.anonyme ? "un membre" : nom(q.membre_id))} · ${dateFR(q.cree_le)}${q.tags ? " · " + q.tags.split(",").map(t => '<span class="tag">' + ech(t.trim()) + "</span>").join("") : ""}</div>
<h1>${ech(q.question)}</h1>
${rs.map(r => `<div class="rep"><div class="mut">Réponse de <strong>${ech(nom(r.membre_id))}</strong> · ${dateFR(r.cree_le)} · validée par ${(r.validations || []).map(v => ech(v.nom)).join(", ") || "le bureau"} ${r.verifiee_annee >= an ? '<span class="badge">vérifiée pour ' + r.verifiee_annee + "</span>" : '<span class="badge" style="background:#fff3cd;color:#8a5a00">vérifiée pour ' + (r.verifiee_annee || new Date(r.cree_le).getFullYear()) + " — en cours de révision</span>"}</div>${ech(r.texte)}</div>`).join("")}
<p style="margin-top:16px"><a class="btn wa" href="https://wa.me/?text=${partage}">Partager sur WhatsApp</a> <a class="btn sec" href="/#/questions?id=${q.id}">Ouvrir dans l’application</a></p></div>
<div class="cta"><strong>Vous êtes comptable, financier ou étudiant ?</strong> Consultez librement cette base. Pour poser vos propres questions aux experts du réseau, accéder aux formations gratuites et au groupe professionnel : <a class="btn" style="margin-left:6px" href="/#/adherer">Devenir membre — ${Number(S.adhesion || S.cotisation || 5000).toLocaleString("fr-FR")} F CFA</a></div>
<div class="carte"><h2>Autres questions récentes</h2><div class="liste">${publiees.filter(x => x.id !== q.id).slice(0, 8).map(x => `<a href="/q/${x.id}">${ech(x.question)}</a>`).join("")}</div></div>`;
    const jsonld = { "@context": "https://schema.org", "@type": "QAPage", mainEntity: { "@type": "Question", name: q.question, text: q.question, dateCreated: q.cree_le, answerCount: rs.length, author: { "@type": "Person", name: q.anonyme ? "Membre ComptaConnect" : nom(q.membre_id) },
      acceptedAnswer: { "@type": "Answer", text: rs[0].texte, dateCreated: rs[0].cree_le, url: canon, author: { "@type": "Person", name: nom(rs[0].membre_id) } } } };
    if (ecrire(`q/${q.id}.html`, gabarit({ titre: q.question.slice(0, 90) + " — ComptaConnect", description: desc, canon, corps, jsonld }))) ecrits++;
    urls.push({ loc: canon, lastmod: rs.map(r => r.cree_le).sort().pop().slice(0, 10) });
  }
  // index
  const parMois = {}; for (const q of publiees) { const d = new Date(q.cree_le), k = NOMS[d.getMonth()] + " " + d.getFullYear(); (parMois[k] = parMois[k] || []).push(q); }
  const index = `<div class="carte"><h1>Questions &amp; réponses des comptables</h1><p class="mut">${publiees.length} question${publiees.length > 1 ? "s" : ""} avec réponse validée par les experts du réseau — fiscalité, SYSCOHADA, DGI, CNPS, paie, logiciels. Consultation libre.</p>
<form action="/" onsubmit="location.href='/#/questions?q='+encodeURIComponent(this.q.value);return false" style="display:flex;gap:8px;margin-top:8px"><input name="q" placeholder="Rechercher : TVA, DSF, bail…" style="flex:1;padding:10px;border:1px solid #e3e8e6;border-radius:9px"><button class="btn">Rechercher</button></form></div>
${Object.entries(parMois).map(([k, L]) => `<div class="carte"><h2>${k}</h2><div class="liste">${L.map(x => `<a href="/q/${x.id}">${ech(x.question)}</a>`).join("")}</div></div>`).join("")}
<div class="cta"><strong>Poser une question aux experts ?</strong> <a class="btn" style="margin-left:6px" href="/#/adherer">Devenir membre</a></div>`;
  if (ecrire("q/index.html", gabarit({ titre: "Questions & réponses des comptables — ComptaConnect", description: "Base de connaissances publique du réseau ComptaConnect : réponses validées par des praticiens (fiscalité, SYSCOHADA, DGI, CNPS, paie).", canon: BASE + "/q/", corps: index }))) ecrits++;
  // sitemap + robots
  const sm = `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n<url><loc>${BASE}/</loc><changefreq>daily</changefreq></url>\n<url><loc>${BASE}/q/</loc><changefreq>daily</changefreq></url>\n` + urls.map(u => `<url><loc>${u.loc}</loc><lastmod>${u.lastmod}</lastmod></url>`).join("\n") + "\n</urlset>\n";
  if (ecrire("sitemap.xml", sm)) ecrits++;
  if (ecrire("robots.txt", `User-agent: *\nAllow: /\nDisallow: /rest/\nDisallow: /auth/\nDisallow: /functions/\nSitemap: ${BASE}/sitemap.xml\n`)) ecrits++;
  // nettoyage des pages dont la question a été retirée
  const dir = path.join(SITE, "q"); if (fs.existsSync(dir)) for (const f of fs.readdirSync(dir)) { const m = f.match(/^(\d+)\.html$/); if (m && !publiees.some(q => String(q.id) === m[1])) { fs.unlinkSync(path.join(dir, f)); ecrits++; } }
  console.log(new Date().toISOString(), `pages Q/R : ${publiees.length} question(s) publiée(s), ${ecrits} fichier(s) écrit(s)`);
})().catch(e => { console.error("pages Q/R : échec —", e.message); process.exit(1); });
