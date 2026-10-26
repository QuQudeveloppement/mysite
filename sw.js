const CACHE_NAME = "atelier-pwa-v3";
const APP_SHELL = [
  "./",
  "./blog.html",
  "./style.css",
  "./render.js",
  "./matrix.js",
  "./download.js",
  "./manifest.webmanifest",
  "./BlogIcon.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(APP_SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(
      keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key))
    )).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;

  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  const isAppShell = APP_SHELL.some((asset) => {
    const normalized = asset.replace(/^\.\//, "/");
    return url.pathname === normalized || (normalized === "/" && url.pathname === "/");
  });
  const isArticleData = url.pathname.endsWith("/articles.json");

  if (isArticleData) {
    event.respondWith(
      fetch(event.request, { cache: "no-store" })
        .then((response) => {
          if (response && response.ok) {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          }
          return response;
        })
        .catch(() => caches.match(event.request))
    );
    return;
  }

  if (isAppShell) {
    event.respondWith(
      caches.match(event.request).then((cached) => {
        if (cached) return cached;
        return fetch(event.request, { cache: "no-store" })
          .then((response) => {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
            return response;
          });
      })
    );
    return;
  }

  event.respondWith(
    fetch(event.request, { cache: "no-store" })
      .then((response) => {
        if (response && response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
