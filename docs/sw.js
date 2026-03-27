'use strict';

// CACHE_VERSION is bumped on each release by the GitHub Actions workflow.
// Changing this string causes the browser to install a fresh service worker,
// which triggers the "update available" banner in the app.
const CACHE_VERSION = 'v1';
const CACHE_NAME    = 'lingtex-tools-' + CACHE_VERSION;
const APP_SHELL     = ['./index.html', './', './core.js'];

// ── Install: pre-cache the app shell ─────────────────────────────────────────
// We do NOT call skipWaiting() here — the app shows a banner and lets the user
// decide when to reload. This prevents jarring mid-session reloads.
self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME).then(cache => cache.addAll(APP_SHELL))
    );
});

// ── Activate: clean up caches from previous versions ─────────────────────────
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys()
            .then(keys => Promise.all(
                keys
                    .filter(k => k.startsWith('lingtex-tools-') && k !== CACHE_NAME)
                    .map(k => caches.delete(k))
            ))
            .then(() => self.clients.claim())
    );
});

// ── Message: client can tell us to skip waiting (triggers reload in the app) ─
self.addEventListener('message', event => {
    if (event.data && event.data.type === 'SKIP_WAITING') {
        self.skipWaiting();
    }
});

// ── Fetch: stale-while-revalidate ─────────────────────────────────────────────
// Serve from cache immediately (works offline), then fetch fresh in background
// and update the cache. Next visit gets the fresh version.
self.addEventListener('fetch', event => {
    if (event.request.method !== 'GET') return;

    const url = new URL(event.request.url);
    if (url.origin !== location.origin) return;

    event.respondWith(
        caches.open(CACHE_NAME).then(cache =>
            cache.match(event.request).then(cached => {
                // Background revalidation
                const fresh = fetch(event.request, { cache: 'no-cache' })
                    .then(res => {
                        if (res && res.ok) cache.put(event.request, res.clone());
                        return res;
                    })
                    .catch(() => null);

                // Return cached immediately, fall through to network if not cached
                return cached || fresh;
            })
        )
    );
});
