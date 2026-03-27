// Service worker removed. This stub clears all caches and unregisters itself
// so that users who had the old SW cached get a clean slate immediately.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys()
            .then(keys => Promise.all(keys.map(k => caches.delete(k))))
            .then(() => self.clients.claim())
            .then(() => self.registration.unregister())
    );
});
