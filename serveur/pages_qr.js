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
<title>${ech(titre)}</title><meta name="google-site-verification" content="-5yRCNkmG6xfJKjFYdwrRkDkO1dhpJxQJt_FGQ9MjgY"><meta name="description" content="${ech(description)}"><link rel="canonical" href="${canon}">
<meta property="og:title" content="${ech(titre)}"><meta property="og:description" content="${ech(description)}"><meta property="og:type" content="article"><meta property="og:url" content="${canon}"><meta property="og:image" content="${BASE}/icon-512.png"><meta property="og:site_name" content="ComptaConnect">
<link rel="icon" href="/icon-192.png"><link rel="manifest" href="/manifest.webmanifest">
${jsonld ? '<script type="application/ld+json">' + JSON.stringify(jsonld) + "</script>" : ""}
<style>:root{--navy:#06301E;--vert:#0B5A38;--or:#B08A38}*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;background:#f4f6f5;color:#1d2b25;line-height:1.55}
header{background:linear-gradient(120deg,#0A1C2D,#16283E);border-bottom:3px solid #1D9E75;color:#fff}.top{display:flex;align-items:center;gap:12px;padding:10px 16px;max-width:1060px;margin:0 auto}.marque{display:flex;align-items:center;gap:10px;color:#fff;text-decoration:none;font-weight:800;font-size:17px;letter-spacing:.4px;white-space:nowrap}.marque img{width:38px;height:38px;border-radius:10px}.marque b{color:#7DCDB0}.nav{display:flex;gap:2px;flex-wrap:wrap;justify-content:center;background:rgba(255,255,255,.08);border:1px solid rgba(255,255,255,.1);border-radius:999px;padding:4px;margin:0 auto}.nav a{text-decoration:none;color:#cfe3da;font-size:13px;font-weight:600;padding:7px 11px;border-radius:999px;white-space:nowrap}.nav a.on,.nav a:hover{background:#1D9E75;color:#fff}.nav{max-width:calc(100% - 420px)}.spacer{flex:1}.top .app{background:#1D9E75;color:#fff;border-radius:9px;padding:7px 12px;font-size:13px;font-weight:700;text-decoration:none;white-space:nowrap}.burger{display:none;width:36px;height:36px;border-radius:12px;border:1px solid rgba(255,255,255,.18);background:rgba(255,255,255,.08);color:#fff;font-size:18px;align-items:center;justify-content:center;cursor:pointer;user-select:none}#menu{display:none}@media(max-width:900px){.top{padding:9px 12px;gap:8px;flex-wrap:wrap}.marque{font-size:14.5px}.marque img{width:32px;height:32px}.burger{display:inline-flex;order:4}.top .app{order:3;padding:6px 10px;font-size:12.5px}.spacer{order:2}.nav{display:none;order:9;width:100%;flex-direction:column;align-items:stretch;border-radius:16px;padding:6px;margin:8px 0 2px}.nav a{white-space:normal;padding:11px 14px;border-radius:11px;font-size:15px}#menu:checked~.nav{display:flex}}
header small{display:block;opacity:.8;font-weight:400;font-size:12px}
main{max-width:820px;margin:0 auto;padding:18px}.carte{background:#fff;border:1px solid #e3e8e6;border-radius:14px;padding:18px;margin-bottom:14px}h1{font-size:22px;color:var(--navy);margin:0 0 6px}h2{font-size:17px;color:var(--navy)}
.mut{color:#5c6b76;font-size:13.5px}.rep{border-left:3px solid var(--vert);padding-left:12px;margin-top:12px;white-space:pre-wrap}.badge{display:inline-block;background:#e6f4ec;color:var(--vert);border-radius:999px;padding:2px 9px;font-size:12px;font-weight:700}
.btn{display:inline-block;background:var(--vert);color:#fff;border-radius:9px;padding:9px 14px;text-decoration:none;font-weight:700;font-size:14px}.btn.sec{background:#e6f4ec;color:var(--navy)}.btn.wa{background:#25D366}
.cta{background:#fffbea;border:1px solid #f3c969;border-radius:14px;padding:14px 18px}.liste a{display:block;padding:10px 0;border-top:1px solid #eef2f0;color:var(--navy);text-decoration:none;font-weight:600}.liste a:first-child{border-top:0}.tag{display:inline-block;background:#eef2f0;border-radius:6px;padding:1px 7px;font-size:12px;margin-right:4px;color:#3b4a44}
footer{text-align:center;color:#5c6b76;font-size:12px;padding:20px}footer a{color:inherit}</style></head><body>
<header><div class="top"><a class="marque" href="/"><img src="/logo.jpg" alt=""><span>COMPTA<b>CONNECT</b></span></a><span class="spacer"></span><a class="app" href="/">Ouvrir l’application</a><label class="burger" for="menu" aria-label="Menu">☰</label><input type="checkbox" id="menu"><nav class="nav"><a href="/decouvrir.html"${canon.endsWith("/decouvrir.html") ? ' class="on"' : ""}>Découvrir le réseau</a><a href="/q/"${/\/q\//.test(canon) ? ' class="on"' : ""}>Base de connaissances</a><a href="/agenda.html"${canon.endsWith("/agenda.html") ? ' class="on"' : ""}>Agenda</a><a href="/#/annuaire">Annuaire</a><a href="/#/adherer">Devenir membre</a></nav></div></header><main>${corps}</main>
<footer>© ComptaConnect · <a href="/#/questions">Toutes les questions dans l’application</a> · <a href="/confidentialite.html">Confidentialité</a></footer></body></html>`;
}
(async () => {
  const S = Object.fromEntries((await db("cc_settings?select=cle,valeur")).map(x => [x.cle, x.valeur]));
  if ((S.questions || "oui") === "non") return console.log("Q/R désactivées : rien à publier");
  const qs = await db("cc_questions?select=id,question,tags,anonyme,membre_id,cree_le&publie=is.true&order=cree_le.desc&limit=5000");
  const reps = await db("cc_reponses?select=id,question_id,membre_id,texte,pieces,validations,verifiee_annee,cree_le&publie=is.true&limit=20000");
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
${rs.map(r => `<div class="rep"><div class="mut">Réponse de <strong>${ech(nom(r.membre_id))}</strong> · ${dateFR(r.cree_le)} · validée par ${(r.validations || []).map(v => ech(v.nom)).join(", ") || "le bureau"} ${r.verifiee_annee >= an ? '<span class="badge">vérifiée pour ' + r.verifiee_annee + "</span>" : '<span class="badge" style="background:#fff3cd;color:#8a5a00">vérifiée pour ' + (r.verifiee_annee || new Date(r.cree_le).getFullYear()) + " — en cours de révision</span>"}</div>${ech(r.texte)}${(Array.isArray(r.pieces) && r.pieces.length) ? '<p style="margin-top:8px">' + r.pieces.map(f => `<a class="btn sec" style="margin:2px 6px 2px 0" href="${ech(f.url)}" download>📎 ${ech(f.nom)}</a>`).join("") + "</p>" : ""}</div>`).join("")}
<p style="margin-top:16px"><a class="btn wa" href="https://wa.me/?text=${partage}">Partager sur WhatsApp</a> <a class="btn sec" href="/#/questions?id=${q.id}">Ouvrir dans l’application</a></p></div>
<div class="cta"><strong>Vous êtes comptable, financier ou étudiant ?</strong> Consultez librement cette base. Pour poser vos propres questions aux experts du réseau, accéder aux formations gratuites et au groupe professionnel : <a class="btn" style="margin-left:6px" href="/#/adherer">Devenir membre — ${Number(S.adhesion || S.cotisation || 5000).toLocaleString("fr-FR")} F CFA</a></div>
<div class="carte"><h2>Autres questions récentes</h2><div class="liste">${publiees.filter(x => x.id !== q.id).slice(0, 8).map(x => `<a href="/q/${x.id}">${ech(x.question)}</a>`).join("")}</div></div>`;
    const jsonld = { "@context": "https://schema.org", "@type": "QAPage", mainEntity: { "@type": "Question", name: q.question, text: q.question, dateCreated: q.cree_le, answerCount: rs.length, author: { "@type": "Person", name: q.anonyme ? "Membre ComptaConnect" : nom(q.membre_id) },
      acceptedAnswer: { "@type": "Answer", text: rs[0].texte, dateCreated: rs[0].cree_le, url: canon, author: { "@type": "Person", name: nom(rs[0].membre_id) } } } };
    if (ecrire(`q/${q.id}.html`, gabarit({ titre: q.question.slice(0, 90) + " — ComptaConnect", description: desc, canon, corps, jsonld }))) ecrits++;
    urls.push({ loc: canon, lastmod: rs.map(r => r.cree_le).sort().pop().slice(0, 10) });
  }
  // ---------- Pages « vie du réseau » (accueil statique indexable) ----------
  const ann = await db("cc_annonces?select=id,titre,texte,image_url,lien,lien_libelle,date,epingle&publie=is.true&order=epingle.desc,date.desc&limit=200").catch(() => []);
  const renc = await db("cc_rencontres?select=id,titre,date,lieu,description,photos&publie=is.true&order=date.desc&limit=200").catch(() => []);
  const evts = await db("cc_evenements?select=id,titre,date,heure,lieu,description,lien,appel_id,ouvert_public,places&publie=is.true&order=date.asc&limit=200").catch(() => []);
  const appels = await db("cc_appels?select=id,titre,montant,ouvert").catch(() => []); const appelDe = e => e.appel_id ? appels.find(a => a.id === e.appel_id) : null;
  const bureau = await db("cc_bureau?select=nom,poste,photo_url,ordre&actif=is.true&order=ordre.asc").catch(() => []);
  const temo = await db("cc_temoignages?select=membre_id,texte&publie=is.true&order=id.desc&limit=6").catch(() => []);
  const nbMembres = (await db("cc_membres?select=id&actif=is.true&limit=10000")).length;
  const auj = new Date().toISOString().slice(0, 10), aVenir = evts.filter(e => e.date >= auj);
  const para = t => ech(t || "").replace(/\n+/g, "<br>");
  const reseau = S.reseau || "ComptaConnect", slogan = S.slogan || "Le premier réseau professionnel des comptables et financiers d’Afrique francophone";
  const orga = { "@context": "https://schema.org", "@type": "Organization", name: reseau, url: BASE + "/", logo: BASE + "/icon-512.png", description: slogan, email: S.contact_email || undefined, telephone: S.tresorier_tel || undefined, areaServed: (S.pays_couverts || "Côte d’Ivoire").split(",").map(x => x.trim()), sameAs: [S.skool_lien].filter(Boolean), numberOfEmployees: undefined, member: { "@type": "QuantitativeValue", value: nbMembres } };
  // actualités (annonces)
  for (const x of ann) {
    const canon = `${BASE}/actualites/${x.id}`;
    const corps = `<div class="carte"><div class="mut">Annonce du bureau · ${dateFR(x.date)}</div><h1>${ech(x.titre)}</h1>${x.image_url ? `<img src="${ech(x.image_url)}" alt="" style="max-width:100%;border-radius:10px;margin:10px 0">` : ""}<p>${para(x.texte)}</p>${x.lien ? `<p><a class="btn" href="${ech(x.lien)}">${ech(x.lien_libelle || "En savoir plus")}</a></p>` : ""}</div>
<div class="cta"><strong>${ech(reseau)}</strong> — ${ech(slogan)}. <a class="btn" style="margin-left:6px" href="/#/adherer">Devenir membre</a> <a class="btn sec" href="/decouvrir.html">Découvrir le réseau</a></div>`;
    if (ecrire(`actualites/${x.id}.html`, gabarit({ titre: x.titre.slice(0, 90) + " — " + reseau, description: (x.texte || x.titre).replace(/\s+/g, " ").slice(0, 155), canon, corps, jsonld: { "@context": "https://schema.org", "@type": "NewsArticle", headline: x.titre, datePublished: x.date, articleBody: x.texte, publisher: { "@type": "Organization", name: reseau } } }))) ecrits++;
    urls.push({ loc: canon, lastmod: x.date });
  }
  if (ann.length) { if (ecrire("actualites/index.html", gabarit({ titre: "Actualités — " + reseau, description: "Annonces et actualités du réseau " + reseau, canon: BASE + "/actualites/", corps: `<div class="carte"><h1>Actualités du réseau</h1><div class="liste">${ann.map(x => `<a href="/actualites/${x.id}">${ech(x.titre)} <span class="mut">· ${dateFR(x.date)}</span></a>`).join("")}</div></div>` }))) ecrits++; urls.push({ loc: BASE + "/actualites/", lastmod: ann[0].date }); }
  // rencontres (galerie)
  for (const r of renc) {
    const canon = `${BASE}/rencontres/${r.id}`, photos = (r.photos || []).slice(0, 12);
    const corps = `<div class="carte"><div class="mut">Rencontre · ${dateFR(r.date)}${r.lieu ? " · " + ech(r.lieu) : ""}</div><h1>${ech(r.titre)}</h1><p>${para(r.description)}</p><div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(140px,1fr));gap:8px">${photos.map(u => `<img src="${ech(u)}" alt="${ech(r.titre)}" loading="lazy" style="width:100%;aspect-ratio:1;object-fit:cover;border-radius:10px">`).join("")}</div></div>
<div class="cta"><strong>Rejoignez les prochaines rencontres.</strong> <a class="btn" style="margin-left:6px" href="/#/adherer">Devenir membre</a> <a class="btn sec" href="/decouvrir.html">Découvrir le réseau</a></div>`;
    if (ecrire(`rencontres/${r.id}.html`, gabarit({ titre: r.titre.slice(0, 90) + " — " + reseau, description: (r.description || r.titre).replace(/\s+/g, " ").slice(0, 155), canon, corps, jsonld: { "@context": "https://schema.org", "@type": "Event", name: r.titre, startDate: r.date, location: r.lieu ? { "@type": "Place", name: r.lieu } : undefined, image: photos, eventStatus: "https://schema.org/EventScheduled", organizer: { "@type": "Organization", name: reseau } } }))) ecrits++;
    urls.push({ loc: canon, lastmod: r.date });
  }
  // une page par événement (brunch, formation, AG…) avec prix éventuel
  for (const e of evts) {
    const a = appelDe(e), canon = `${BASE}/evenements/${e.id}`, passe = e.date < auj;
    const corps = `<div class="carte"><div class="mut">${passe ? "Événement passé" : "Prochain événement"} · ${dateFR(e.date)}${e.heure ? " à " + ech(e.heure) : ""}${e.lieu ? " · " + ech(e.lieu) : ""}</div><h1>${ech(e.titre)}</h1><p>${para(e.description)}</p>
${a ? `<p><span class="badge">Participation : ${Number(a.montant).toLocaleString("fr-FR")} F</span></p>` : `<p><span class="badge">Gratuit pour les membres</span></p>`}
${!passe ? `<p>${a ? `<a class="btn" href="/#/appel?id=${a.id}">💳 Payer ma participation (Wave, Orange, MTN, Moov)</a> ` : ""}<a class="btn sec" href="/#/agenda">S’inscrire dans l’application</a></p>` : ""}
${e.lien ? `<p><a href="${ech(e.lien)}">Lien (programme, visio, plan)</a></p>` : ""}</div>
<div class="cta">${e.ouvert_public ? "<strong>Ouvert à tous</strong> — comptables, financiers, étudiants, dirigeants." : "<strong>Réservé aux membres du réseau.</strong>"} <a class="btn" style="margin-left:6px" href="/#/adherer">Devenir membre</a> <a class="btn sec" href="/decouvrir.html">Découvrir ${ech(reseau)}</a></div>`;
    const jsonld = { "@context": "https://schema.org", "@type": "Event", name: e.titre, description: e.description, startDate: e.date + (e.heure && /^\d{1,2}h/.test(e.heure) ? "T" + e.heure.replace("h", ":").padEnd(5, "0") : ""), eventStatus: "https://schema.org/EventScheduled", eventAttendanceMode: /ligne|visio|zoom|meet/i.test(e.lieu || "") ? "https://schema.org/OnlineEventAttendanceMode" : "https://schema.org/OfflineEventAttendanceMode", location: e.lieu ? { "@type": "Place", name: e.lieu, address: e.lieu } : undefined, organizer: { "@type": "Organization", name: reseau, url: BASE + "/" }, offers: { "@type": "Offer", price: a ? a.montant : 0, priceCurrency: "XOF", availability: "https://schema.org/InStock", url: a ? `${BASE}/#/appel?id=${a.id}` : canon, validFrom: auj } };
    if (ecrire(`evenements/${e.id}.html`, gabarit({ titre: e.titre.slice(0, 80) + " — " + dateFR(e.date) + " — " + reseau, description: ((a ? "Participation " + a.montant + " F. " : "") + (e.description || e.titre)).replace(/\s+/g, " ").slice(0, 155), canon, corps, jsonld }))) ecrits++;
    urls.push({ loc: canon, lastmod: auj });
  }
  // agenda
  if (aVenir.length) {
    const corps = `<div class="carte"><h1>Agenda du réseau</h1><div class="liste">${aVenir.map(e => `<a href="/evenements/${e.id}">${ech(e.titre)}${appelDe(e) ? " · " + Number(appelDe(e).montant).toLocaleString("fr-FR") + " F" : ""} <span class="mut">· ${dateFR(e.date)}${e.heure ? " à " + ech(e.heure) : ""}${e.lieu ? " · " + ech(e.lieu) : ""}</span></a>`).join("")}</div></div><div class="cta">Inscription en un clic depuis votre espace membre. <a class="btn" style="margin-left:6px" href="/#/adherer">Devenir membre</a></div>`;
    if (ecrire("agenda.html", gabarit({ titre: "Agenda — " + reseau, description: "Prochains événements, formations et rencontres du réseau " + reseau, canon: BASE + "/agenda.html", corps, jsonld: aVenir.map(e => ({ "@context": "https://schema.org", "@type": "Event", name: e.titre, startDate: e.date + (e.heure ? "T" + e.heure.replace("h", ":").padEnd(5, "0") : ""), location: e.lieu ? { "@type": "Place", name: e.lieu } : undefined, description: e.description, organizer: { "@type": "Organization", name: reseau } })) }))) ecrits++;
    urls.push({ loc: BASE + "/agenda.html", lastmod: auj });
  }
  // découvrir : la page d'accueil en version indexable
  const nomM = id => (ms.find(m => m.id === id) || {});
  const decouvrir = `<div class="carte"><h1>${ech(reseau)}</h1><p><strong>${ech(slogan)}</strong></p><p>${para(S.presentation)}</p>
<p class="mut">${nbMembres} membres · ${publiees.length} questions-réponses validées · fondé en 2026${S.fondateur ? " · fondateur : " + ech(S.fondateur) : ""}</p>
<p><a class="btn" href="/#/adherer">Devenir membre — ${Number(S.adhesion || 5000).toLocaleString("fr-FR")} F</a> <a class="btn sec" href="/">Ouvrir l’application</a></p></div>
${S.photo_groupe_url ? `<img src="${ech(S.photo_groupe_url)}" alt="${ech(reseau)}" style="width:100%;border-radius:14px;margin-bottom:14px">` : ""}
${bureau.length ? `<div class="carte"><h2>Le bureau</h2>${bureau.map(b => `<div style="display:flex;gap:10px;align-items:center;padding:6px 0">${b.photo_url ? `<img src="${ech(b.photo_url)}" alt="" style="width:44px;height:44px;border-radius:50%;object-fit:cover">` : ""}<div><strong>${ech(b.nom)}</strong><div class="mut">${ech(b.poste)}</div></div></div>`).join("")}</div>` : ""}
${ann.length ? `<div class="carte"><h2>Actualités</h2><div class="liste">${ann.slice(0, 6).map(x => `<a href="/actualites/${x.id}">${ech(x.titre)} <span class="mut">· ${dateFR(x.date)}</span></a>`).join("")}</div></div>` : ""}
${aVenir.length ? `<div class="carte"><h2>Prochains événements</h2><div class="liste">${aVenir.slice(0, 6).map(e => `<a href="/evenements/${e.id}">${ech(e.titre)} <span class="mut">· ${dateFR(e.date)}</span></a>`).join("")}</div></div>` : ""}
${publiees.length ? `<div class="carte"><h2>Dernières questions-réponses</h2><div class="liste">${publiees.slice(0, 8).map(x => `<a href="/q/${x.id}">${ech(x.question)}</a>`).join("")}</div><p><a class="btn sec" href="/q/">Toute la base de connaissances</a></p></div>` : ""}
${renc.length ? `<div class="carte"><h2>Nos rencontres</h2><div class="liste">${renc.slice(0, 6).map(r => `<a href="/rencontres/${r.id}">${ech(r.titre)} <span class="mut">· ${dateFR(r.date)}</span></a>`).join("")}</div></div>` : ""}
${temo.length ? `<div class="carte"><h2>Ils parlent du réseau</h2>${temo.map(t => `<blockquote style="margin:0 0 10px;padding:8px 12px;border-left:3px solid var(--or);background:#fffbea;border-radius:8px"><em>« ${ech(t.texte)} »</em><div class="mut">— ${ech(nomM(t.membre_id).nom || "Un membre")}${nomM(t.membre_id).specialite ? ", " + ech(nomM(t.membre_id).specialite) : ""}</div></blockquote>`).join("")}</div>` : ""}
<div class="cta"><strong>Contact</strong> · ${ech(S.contact_email || "")} · ${ech(S.tresorier_tel || "")} · <a href="/#/adherer">Rejoindre le réseau</a></div>`;
  if (ecrire("decouvrir.html", gabarit({ titre: reseau + " — " + slogan.slice(0, 80), description: (S.presentation || slogan).replace(/\s+/g, " ").slice(0, 155), canon: BASE + "/decouvrir.html", corps: decouvrir, jsonld: orga }))) ecrits++;
  urls.unshift({ loc: BASE + "/decouvrir.html", lastmod: auj });
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
  for (const [sous, liste] of [["actualites", ann], ["rencontres", renc], ["evenements", evts]]) { const d2 = path.join(SITE, sous); if (fs.existsSync(d2)) for (const f of fs.readdirSync(d2)) { const m = f.match(/^(\d+)\.html$/); if (m && !liste.some(x => String(x.id) === m[1])) { fs.unlinkSync(path.join(d2, f)); ecrits++; } } }
  const dir = path.join(SITE, "q"); if (fs.existsSync(dir)) for (const f of fs.readdirSync(dir)) { const m = f.match(/^(\d+)\.html$/); if (m && !publiees.some(q => String(q.id) === m[1])) { fs.unlinkSync(path.join(dir, f)); ecrits++; } }
  console.log(new Date().toISOString(), `pages Q/R : ${publiees.length} question(s) publiée(s), ${ecrits} fichier(s) écrit(s)`);
})().catch(e => { console.error("pages Q/R : échec —", e.message); process.exit(1); });
