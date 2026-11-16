/* ComptaConnect — service worker : l'application s'installe et s'ouvre hors ligne (carte de membre, dernière situation connue).
   Coquille (index, logo, icônes) : réseau d'abord, cache en secours — la page reste toujours à jour quand le réseau est là. */
const CACHE = "cc-v1";
const COQUILLE = ["./", "./index.html", "./logo.jpg", "./logomark.png", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(COQUILLE)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const u = new URL(e.request.url);
  if(e.request.method !== "GET" || u.origin !== location.origin) return;
  // API / auth / fonctions / photos : jamais mis en cache
  if(/^\/(rest|auth|functions|storage|photos|relais)\//.test(u.pathname)) return;
  e.respondWith(fetch(e.request).then(r => { if(r.ok){ const copie = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copie)); } return r; })
    .catch(() => caches.match(e.request).then(r => r || (e.request.mode === "navigate" ? caches.match("./index.html") : undefined))));
});
self.addEventListener("push", e => {
  let d = {}; try{ d = e.data ? e.data.json() : {}; }catch(_){ d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || "ComptaConnect", { body: d.body || "", icon: "./icon-192.png", badge: "./icon-192.png", data: { url: d.url || "./" } }));
});
self.addEventListener("notificationclick", e => { e.notification.close(); e.waitUntil(clients.openWindow(e.notification.data && e.notification.data.url || "./")); });
