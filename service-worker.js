// Checker-S Service Worker
const CACHE = "checker-s-v1";
const ASSETS = [
  "./",
  "./index.html",
  "./manifest.json",
  "./css/styles.css",
  "./js/data.js",
  "./js/auth.js",
  "./js/camera.js",
  "./js/ai.js",
  "./js/pdf.js",
  "./js/app.js",
  "./vendor/jspdf.umd.min.js",
  "./assets/icons/icon.svg"
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then(c => c.addAll(ASSETS)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  e.respondWith(
    caches.match(req).then(cached => {
      if (cached) return cached;
      return fetch(req).then(res => {
        // 同一オリジンのみキャッシュ
        try {
          const url = new URL(req.url);
          if (url.origin === self.location.origin) {
            const clone = res.clone();
            caches.open(CACHE).then(c => c.put(req, clone));
          }
        } catch (e) {}
        return res;
      }).catch(() => cached);
    })
  );
});
