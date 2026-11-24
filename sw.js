// Retired: the app moved from / to /app/ (its worker is now /app/sw.js) and / is the commercial homepage.
// Devices that installed the old worker at / get this version, which clears the old caches and removes itself.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((ks) => Promise.all(ks.filter((k) => !k.startsWith("wcia-app-v16")).map((k) => caches.delete(k))))
      .then(() => self.registration.unregister())
      .then(() => self.clients.matchAll({ type: "window" }))
      .then((cs) => cs.forEach((c) => c.navigate(c.url)))
  );
});
