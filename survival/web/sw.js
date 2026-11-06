const CACHE="survival-shell-v3";
const CORE=["/","/index.html","/manifest.webmanifest","/icon.svg","/knowledge.json"];
self.addEventListener("install",event=>{
 event.waitUntil(caches.open(CACHE).then(cache=>cache.addAll(CORE)).then(()=>self.skipWaiting()));
});
self.addEventListener("activate",event=>{
 event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()));
});
self.addEventListener("fetch",event=>{
 const request=event.request;
 const url=new URL(request.url);
 if(request.method!=="GET"||url.origin!==self.location.origin)return;
 event.respondWith((async()=>{
  const cached=await caches.match(request);
  if(cached)return cached;
  try{
   const response=await fetch(request);
   if(response.ok){const copy=response.clone();const cache=await caches.open(CACHE);await cache.put(request,copy);}
   return response;
  }catch(error){
   if(request.mode==="navigate")return (await caches.match("/"))||Response.error();
   return Response.error();
  }
 })());
});
