const CACHE = 'future-pharma-shell-v3';
const SHELL = ['./', './index.html', './styles.css', './overrides.css', './config.js', './offline-store.js', './app.js', './eorder-book.js', './staff-portal.js'];
const CDN = [
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2',
  'https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js'
];
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await cache.addAll(SHELL);
    await Promise.allSettled(CDN.map(async url => {
      const response = await fetch(url, { mode: 'no-cors' });
      if (response.type === 'opaque' || response.ok) await cache.put(url, response);
    }));
    await self.skipWaiting();
  })());
});
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const name of await caches.keys()) if (name.startsWith('future-pharma-') && name !== CACHE) await caches.delete(name);
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin && !CDN.includes(request.url)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE), cached = await cache.match(request);
    const network = fetch(request).then(response => {
      if (response && (response.ok || response.type === 'opaque')) cache.put(request, response.clone());
      return response;
    });
    if (cached) { event.waitUntil(network.catch(() => {})); return cached; }
    try { return await network; }
    catch (error) {
      if (request.mode === 'navigate') return (await cache.match('./index.html')) || Promise.reject(error);
      throw error;
    }
  })());
});
