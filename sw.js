// Service worker: makes the catalogue work offline and on patchy shop Wi-Fi/signal.
//
// - App shell (index.html, manifest, icons): served from cache instantly, refreshed
//   in the background (stale-while-revalidate). A new index.html shows up on the
//   next open, so there's no need to bump VERSION for page edits.
// - catalogue.json: network first so you see the latest export, but if the network
//   fails or takes longer than NETWORK_TIMEOUT_MS ("lie-fi"), the last saved copy is
//   served at once. Those responses carry X-Catalogue-Source: cache so the page can
//   say it's showing saved data.
//
// Bump VERSION only when SHELL_FILES changes.
const VERSION = 'v1';
const SHELL_CACHE = `catalogue-shell-${VERSION}`;
const DATA_CACHE = 'catalogue-data';
const NETWORK_TIMEOUT_MS = 4000;

const SHELL_FILES = [
  './',
  'manifest.webmanifest',
  'icons/icon.svg',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/icon-maskable-512.png',
  'icons/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);
    // cache: 'reload' skips the HTTP cache so a fresh install never stores stale files.
    await cache.addAll(SHELL_FILES.map((url) => new Request(url, { cache: 'reload' })));
    // Save the catalogue during install too, so offline works after the very first visit.
    try {
      const res = await fetch('catalogue.json', { cache: 'no-store' });
      if (res.ok) await (await caches.open(DATA_CACHE)).put('catalogue.json', res);
    } catch (_) { /* offline during install: the page's own fetch will fill it later */ }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keep = new Set([SHELL_CACHE, DATA_CACHE]);
    for (const key of await caches.keys()) {
      if (!keep.has(key)) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  if (url.pathname.endsWith('/catalogue.json')) {
    event.respondWith(catalogue(event));
  } else if ((req.mode === 'navigate' && url.pathname.endsWith('/')) || url.pathname.endsWith('/index.html')) {
    event.respondWith(shell(event, './'));
  } else if (SHELL_FILES.some((f) => f !== './' && url.pathname.endsWith('/' + f))) {
    event.respondWith(shell(event, req));
  }
});

// Stale-while-revalidate for the app shell.
async function shell(event, key) {
  const cache = await caches.open(SHELL_CACHE);
  const cached = await cache.match(key);
  const refresh = fetch(key, { cache: 'no-cache' })
    .then((res) => { if (res.ok) return cache.put(key, res.clone()).then(() => res); return res; });
  if (cached) {
    event.waitUntil(refresh.catch(() => {}));
    return cached;
  }
  return refresh;
}

// Network first with a timeout, falling back to the saved copy.
async function catalogue(event) {
  const cache = await caches.open(DATA_CACHE);
  const network = fetch('catalogue.json', { cache: 'no-cache' }).then(async (res) => {
    if (res.ok) await cache.put('catalogue.json', res.clone());
    return res;
  });
  // Keep the SW alive until the network attempt finishes, so a slow response
  // still refreshes the saved copy for next time.
  event.waitUntil(network.catch(() => {}));

  const timeout = new Promise((resolve) => setTimeout(resolve, NETWORK_TIMEOUT_MS, null));
  let res = null;
  try { res = await Promise.race([network, timeout]); } catch (_) { res = null; }
  if (res && res.ok) return res;

  const cached = await cache.match('catalogue.json');
  if (cached) {
    const headers = new Headers(cached.headers);
    headers.set('X-Catalogue-Source', 'cache');
    return new Response(cached.body, { status: 200, statusText: 'OK', headers });
  }
  // Nothing saved yet: wait for the network after all, and let its error through.
  return network;
}
