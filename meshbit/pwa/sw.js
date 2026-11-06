const CACHE="meshbit-shell-v2";
const SHELL=["./","./index.html","./manifest.webmanifest","./icon.svg","./vendor/nacl-fast.min.js","./app.js"];
self.addEventListener("install",event=>event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(SHELL)).then(()=>self.skipWaiting())));
self.addEventListener("activate",event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim())));
self.addEventListener("fetch",event=>{const request=event.request,url=new URL(request.url);if(request.method!=="GET"||url.origin!==location.origin||url.pathname.includes("/api/"))return;const isShell=SHELL.some(path=>new URL(path,self.registration.scope).pathname===url.pathname);if(!isShell)return;event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{if(response.ok)caches.open(CACHE).then(cache=>cache.put(request,response.clone()));return response})))});
