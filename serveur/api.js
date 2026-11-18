// ComptaConnect — service API du serveur : exécute les fonctions (ex-Edge Functions Deno) sous Node et gère les photos.
// Routes : /functions/v1/<nom>  ·  POST /storage/v1/object/cc_photos/<chemin>  (les GET publics des photos sont servis par Caddy)
const http = require("http"), fs = require("fs"), path = require("path"), crypto = require("crypto");
const PORT = 8788, PHOTOS = process.env.PHOTOS_DIR || "/var/lib/comptaconnect/photos";
const JWT_SECRET = process.env.JWT_SECRET || "";
const handlers = {};
let push = null; try { push = require(path.join(__dirname, "push.js")); } catch (e) { console.warn("push indisponible :", e.message); }
const SB = process.env.SUPABASE_URL || "http://127.0.0.1:3000", SBREST = SB.startsWith("http://127") ? SB : SB + "/rest/v1", ANON = process.env.SUPABASE_ANON_KEY || "";
/* Le porteur du jeton est-il trésorier/fondateur ? (vérifié par la base, jamais par le client) */
async function estTresorier(tok) {
  try { const r = await fetch(SBREST + "/rpc/cc_mon_role", { method: "POST", headers: { apikey: ANON || tok, Authorization: "Bearer " + tok, "Content-Type": "application/json" }, body: "{}" });
    if (!r.ok) return false; const role = JSON.parse(await r.text()); return ["tresorier", "bureau"].includes(String(role)); } catch { return false; }
}
// Shim minimal de l'API Deno utilisée par les fonctions
global.Deno = { env: { get: (k) => process.env[k] }, serve: (h) => { handlers[global.__fn] = h; } };
for (const nom of ["cinetpay-init", "cinetpay-notify", "acces", "otp"]) {
  global.__fn = nom; require(path.join(__dirname, "fonctions", nom + ".js"));
}
function jwtValide(tok) {
  try { const [h, p, s] = tok.split("."); const sig = crypto.createHmac("sha256", JWT_SECRET).update(h + "." + p).digest("base64url");
    if (sig !== s) return null; const c = JSON.parse(Buffer.from(p, "base64url").toString()); if (c.exp && c.exp < Date.now() / 1000) return null; return c; } catch { return null; }
}
http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost"); const chunks = []; for await (const c of req) chunks.push(c); const corps = Buffer.concat(chunks);
  const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-upsert", "Access-Control-Allow-Methods": "POST, GET, OPTIONS" };
  if (req.method === "OPTIONS") { res.writeHead(200, cors); return res.end("ok"); }
  const fin = (code, obj) => { res.writeHead(code, { ...cors, "Content-Type": "application/json" }); res.end(JSON.stringify(obj)); };
  try {
    let m;
    // Notification push envoyée par le bureau : POST /functions/v1/push { titre, corps, url, membres?: [ids] }
    if (url.pathname === "/functions/v1/push" && req.method === "POST") {
      const tok = (req.headers.authorization || "").replace(/^Bearer\s+/i, ""); if (!jwtValide(tok) || !(await estTresorier(tok))) return fin(401, { erreur: "réservé au bureau" });
      if (!push) return fin(503, { erreur: "module push absent sur le serveur" });
      let b = {}; try { b = JSON.parse(corps.toString() || "{}"); } catch { return fin(400, { erreur: "JSON invalide" }); }
      const titre = String(b.titre || "").trim().slice(0, 80), texte = String(b.corps || "").trim().slice(0, 300);
      if (!texte) return fin(400, { erreur: "message vide" });
      const ids = Array.isArray(b.membres) && b.membres.length ? b.membres.map(Number).filter(Boolean) : null;
      const r = await push.envoyer(ids, { title: titre || undefined, body: texte, url: String(b.url || "/").slice(0, 300) });
      return fin(200, r);
    }
    if ((m = url.pathname.match(/^\/functions\/v1\/([a-z0-9-]+)\/?$/))) {
      const h = handlers[m[1]]; if (!h) return fin(404, { erreur: "fonction inconnue" });
      const rq = new Request("https://comptaconnect.org" + req.url, { method: req.method, headers: req.headers, body: ["GET", "HEAD"].includes(req.method) ? undefined : corps });
      const rp = await h(rq); const hd = {}; rp.headers.forEach((v, k) => hd[k] = v);
      res.writeHead(rp.status, { ...cors, ...hd }); return res.end(Buffer.from(await rp.arrayBuffer()));
    }
    if ((m = url.pathname.match(/^\/storage\/v1\/object\/cc_photos\/(.+)$/)) && req.method === "POST") {
      const tok = (req.headers.authorization || "").replace(/^Bearer\s+/i, ""); if (!jwtValide(tok)) return fin(401, { erreur: "non autorisé" });
      const rel = decodeURIComponent(m[1]); if (!/^[a-z]+(\/[A-Za-z0-9_-]+){0,2}\/[A-Za-z0-9_.-]+\.(jpe?g|png|webp)$/.test(rel) || rel.includes("..")) return fin(400, { erreur: "chemin refusé" });
      if (corps.length > 1500000) return fin(413, { erreur: "image trop lourde" });
      const dest = path.join(PHOTOS, rel); fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, corps);
      return fin(200, { Key: "cc_photos/" + rel });
    }
    if (url.pathname === "/sante") return fin(200, { ok: true, fonctions: Object.keys(handlers), push: !!push });
    fin(404, { erreur: "introuvable" });
  } catch (e) { fin(500, { erreur: String(e && e.message || e) }); }
}).listen(PORT, "127.0.0.1", () => console.log("API ComptaConnect prête sur 127.0.0.1:" + PORT, Object.keys(handlers)));
