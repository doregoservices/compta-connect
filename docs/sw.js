/* ComptaConnect — service worker : l'application s'ouvre instantanément (coquille servie depuis le cache) et se met à jour en arrière-plan ;
   quand une nouvelle version arrive, la page affiche « Nouvelle version disponible · Actualiser ». Données (API, photos) : jamais mises en cache ici. */
const CACHE = "cc-v6";
const COQUILLE = ["./", "./index.html", "./logo.jpg", "./manifest.webmanifest", "./icon-192.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(COQUILLE)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()).then(prevenir)); });
async function prevenir(){ const cs = await self.clients.matchAll({ type:"window" }); for(const c of cs) c.postMessage({ type:"maj" }); }
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if(e.request.method !== "GET" || u.origin !== location.origin) return;
  if(/^\/(rest|auth|functions|storage|photos|relais)\//.test(u.pathname)) return;
  // Seule la racine (l'application) est servie depuis le cache ; les pages publiques (decouvrir.html, agenda.html, q/, actualites/…) passent par le réseau
  const coquille = u.pathname === "/" || u.pathname === "/index.html";
  if(coquille){
    const cle = "./index.html";
    e.respondWith((async () => {
      const cache = await caches.open(CACHE); const enCache = await cache.match(cle);
      const reseau = fetch(e.request).then(async r => {
        if(r.ok){ const neuf = await r.clone().text(); const ancien = enCache ? await enCache.clone().text() : ""; await cache.put(cle, r.clone()); if(enCache && neuf !== ancien) prevenir(); }
        return r;
      }).catch(() => null);
      if(enCache){ e.waitUntil(reseau); return enCache; }
      return (await reseau) || new Response("Hors connexion", { status: 503 });
    })());
    return;
  }
  // Autres fichiers statiques (icônes, logo, pages publiques) : réseau d'abord, cache en secours
  e.respondWith(fetch(e.request).then(r => { if(r.ok){ const copie = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copie)); } return r; })
    .catch(() => caches.match(e.request)));
});
self.addEventListener("push", e => {
  let d = {}; try{ d = e.data ? e.data.json() : {}; }catch(_){ d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || "ComptaConnect", { body: d.body || "", icon: "./icon-192.png", badge: "./icon-192.png", data: { url: d.url || "./" } }));
});
self.addEventListener("notificationclick", e => { e.notification.close(); e.waitUntil(clients.openWindow(e.notification.data && e.notification.data.url || "./")); });
