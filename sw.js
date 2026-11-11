// Guarda la app para que abra rápido y funcione sin conexión. Sube la versión al publicar cambios.
const CACHE = "liga-sc-v76";
const FILES = ["./", "index.html", "manifest.webmanifest", "iconos/icono-192.png", "iconos/icono-512.png", "iconos/icono-maskable-512.png", "iconos/apple-touch-icon.png", "iconos/favicon-32.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES))); self.skipWaiting(); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(k => Promise.all(k.filter(n => n !== CACHE).map(n => caches.delete(n))))); self.clients.claim(); });
// Primero la red, saltándose la caché del navegador (para ver siempre la última versión); si no hay conexión, la copia guardada.
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET" || new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(fetch(e.request.url, { cache: "no-cache", credentials: "same-origin" }).then(r => { if (r.ok) { const c = r.clone(); caches.open(CACHE).then(x => x.put(e.request, c)); } return r; }).catch(() => caches.match(e.request)));
});
