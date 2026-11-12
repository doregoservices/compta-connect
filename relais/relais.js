// Relais CinetPay à IP fixe — ComptaConnect
// Rôle : transmettre les appels de la plateforme (Supabase Edge Functions) vers l'API CinetPay depuis une adresse IP fixe.
// Sécurité : secret partagé obligatoire (en-tête X-Relais-Secret), destinations limitées aux API CinetPay, aucune donnée conservée.
// Aucune dépendance : Node.js ≥ 18 (fetch natif). Écoute en local sur 127.0.0.1:8787 ; Caddy assure le HTTPS devant.
const http = require("http");
const crypto = require("crypto");
const SECRET = process.env.RELAIS_SECRET || "";
const BASES = { test: "https://api.cinetpay.net", live: "https://api.cinetpay.co", v2: "https://api-checkout.cinetpay.com" };
if (!SECRET || SECRET.length < 20) { console.error("RELAIS_SECRET manquant"); process.exit(1); }
function egal(a, b) { const x = Buffer.from(String(a)), y = Buffer.from(String(b)); return x.length === y.length && crypto.timingSafeEqual(x, y); }
http.createServer(async (req, res) => {
  const repondre = (code, obj) => { res.writeHead(code, { "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); };
  if (req.method === "GET" && req.url === "/sante") return repondre(200, { ok: true, service: "relais-cinetpay" });
  if (!egal(req.headers["x-relais-secret"] || "", SECRET)) return repondre(401, { erreur: "non autorisé" });
  const base = BASES[String(req.headers["x-cinetpay-env"] || "test")];
  if (!base) return repondre(400, { erreur: "environnement inconnu" });
  if (!/^\/v[12]\/[A-Za-z0-9_\-\/%.]*$/.test(req.url)) return repondre(400, { erreur: "chemin refusé" });
  let corps = ""; for await (const c of req) { corps += c; if (corps.length > 65536) return repondre(413, { erreur: "trop long" }); }
  const entetes = { "Content-Type": "application/json" };
  if (req.headers.authorization) entetes.Authorization = req.headers.authorization;
  try {
    const r = await fetch(base + req.url, { method: req.method, headers: entetes, body: ["POST", "PUT", "PATCH"].includes(req.method) ? corps : undefined, signal: AbortSignal.timeout(25000) });
    const txt = await r.text();
    res.writeHead(r.status, { "Content-Type": r.headers.get("content-type") || "application/json" }); res.end(txt);
  } catch (e) { repondre(502, { erreur: "CinetPay injoignable : " + e.message }); }
}).listen(8787, "127.0.0.1", () => console.log("relais CinetPay prêt sur 127.0.0.1:8787"));
