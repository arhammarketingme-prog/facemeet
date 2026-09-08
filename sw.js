// sw.js — minimal offline shell cache.
// This does NOT cache API calls (Supabase, YouTube, etc.) — only the
// static app shell (index.html itself). Offline, the person can open
// the app and see the last-loaded UI; anything needing the network
// (feed, login, messages) will still show its normal error states.
const CACHE_NAME = 'nexus-shell-v2';
const SHELL_FILES = ['./', './index.html', './manifest.json', './icons/icon-192.png', './icons/icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  // only intercept same-origin navigation/document requests — never
  // API calls to Supabase or other external services
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;
  if (event.request.mode !== 'navigate' && event.request.destination !== 'document') return;

  event.respondWith(
    fetch(event.request).catch(() => caches.match('./index.html'))
  );
});
