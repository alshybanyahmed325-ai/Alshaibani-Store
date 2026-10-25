/* Shibani Store offline shell cache. Never cache Supabase API/auth responses. */
const CACHE_VERSION = 'shibani-offline-v5-pwa-metadata-icons';
const SHELL = ['./', './index.html', './config.js', './manifest.webmanifest', './icon-192.svg', './icon-512.svg', './icon-192.png', './icon-512.png', './icon-maskable-512.png', './apple-touch-icon.png', './favicon.ico', './assets/logo-shaibani.png'];
const STATIC_HOSTS = ['cdn.jsdelivr.net', 'fonts.googleapis.com', 'fonts.gstatic.com'];
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_VERSION);
    await cache.addAll(SHELL);
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k.startsWith('shibani-offline-') && k !== CACHE_VERSION).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  // Never cache private/admin data or database/auth API calls.
  if (url.hostname.endsWith('.supabase.co') || url.pathname.includes('/auth/')) return;
  if (req.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const fresh = await fetch(req);
        const cache = await caches.open(CACHE_VERSION);
        cache.put('./index.html', fresh.clone()).catch(() => {});
        return fresh;
      } catch (_) {
        return (await caches.match(req)) || (await caches.match('./index.html')) || new Response('المتجر غير متاح دون اتصال. افتح المتجر مرة واحدة أثناء الاتصال بالإنترنت ثم أعد المحاولة.', {status: 503, headers: {'Content-Type':'text/plain; charset=utf-8'}});
      }
    })());
    return;
  }
  const isStatic = url.origin === self.location.origin || STATIC_HOSTS.includes(url.hostname);
  if (!isStatic) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE_VERSION);
    const cached = await cache.match(req);
    if (cached) {
      event.waitUntil(fetch(req).then(res => { if (res && (res.ok || res.type === 'opaque')) return cache.put(req, res.clone()); }).catch(() => {}));
      return cached;
    }
    try {
      const res = await fetch(req);
      if (res && (res.ok || res.type === 'opaque')) event.waitUntil(cache.put(req, res.clone()));
      return res;
    } catch (err) {
      if (cached) return cached;
      throw err;
    }
  })());
});
