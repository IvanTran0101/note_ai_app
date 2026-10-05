/* Transient private capability/bytes. CacheStorage contains public viewer assets only. */
const media = new Map();
const chunkBytes = 256 * 1024;
const mediaRoot = new URL('./attachment_media/', self.location.href);
const uiCache = 'noteflow-attachment-ui-pdfjs6.4.299-v1';
self.addEventListener('install', event => event.waitUntil((async () => {
  const response = await fetch(new URL('asset_manifest.json',mediaRoot),{cache:'no-store'});
  if (!response.ok) throw Error('Viewer assets unavailable');
  const paths = await response.json();
  if (!Array.isArray(paths) || paths.some(p => typeof p !== 'string' || p.includes('..') ||
      !/^(?:host(?:_pdf)?\.(?:html|css|js)|pdfjs\/[A-Za-z0-9_./-]+)$/.test(p))) throw Error('Invalid viewer assets');
  const cache = await caches.open(uiCache);
  await cache.addAll(paths.map(p=>new URL(p,mediaRoot).href));
  await self.skipWaiting();
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys()) {
    if (key.startsWith('noteflow-attachment-ui-') && key !== uiCache) await caches.delete(key);
  }
  await self.clients.claim();
})()));
self.addEventListener('message', event => {
  const data = event.data;
  if (!data || !event.source || !event.source.id || !/^[A-Za-z0-9_-]{43}$/.test(data.cap)) return;
  const source = new URL(event.source.url);
  if (source.origin !== mediaRoot.origin || source.pathname.startsWith(mediaRoot.pathname)) return;
  if (data.kind === 'noteflow-media-register' && Number.isSafeInteger(data.size) && data.size > 0 && data.size <= 50*1024*1024) {
    media.set(data.cap, {client: event.source.id, size: data.size, mime: data.mime,
      fileName: data.fileName, exportFile: !!data.exportFile, expires: Date.now()+15*60*1000});
    event.ports[0]?.postMessage({registered:true});
    event.ports[0]?.close();
  } else if (data.kind === 'noteflow-media-close' && media.get(data.cap)?.client === event.source.id) media.delete(data.cap);
});
async function read(cap, record, start, end) {
  if (media.get(cap) !== record || record.expires <= Date.now()) throw Error('Closed');
  const client = await self.clients.get(record.client); if (!client) throw Error('Closed');
  const result = await new Promise((resolve,reject) => {
    const channel = new MessageChannel();
    const timer = setTimeout(() => {channel.port1.close(); reject(Error('Unavailable'));}, 30000);
    channel.port1.onmessage = event => {
      clearTimeout(timer); channel.port1.close();
      if (event.data?.error || !(event.data?.bytes instanceof Uint8Array) || event.data.bytes.length !== end-start) reject(Error('Denied'));
      else resolve(event.data.bytes);
    };
    client.postMessage({kind:'noteflow-media-read',cap,start,end},[channel.port2]);
  });
  if (media.get(cap) !== record || record.expires <= Date.now()) {result.fill(0); throw Error('Closed');}
  return result;
}
function range(header,size) {
  if (!header) return [0,size];
  const m = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!m || !m[1] && !m[2]) throw Error('Range');
  const start = m[1] ? Number(m[1]) : Math.max(0,size-Number(m[2]));
  const end = !m[1] || !m[2] ? size : Math.min(size,Number(m[2])+1);
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= end || end > size) throw Error('Range');
  return [start,end];
}
async function content(request,cap) {
  const record = media.get(cap);
  if (!record || !['GET','HEAD'].includes(request.method)) return new Response(null,{status:403});
  try {
    await read(cap,record,0,0);
    let bounds;
    try {bounds = range(request.headers.get('range'),record.size);}
    catch {return new Response(null,{status:416,headers:{'content-range':`bytes */${record.size}`}});}
    const [start,end] = bounds;
    let offset = start, stopped = false;
    const headers = {'content-type':record.mime,'content-length':String(end-start),'accept-ranges':'bytes',
      'cache-control':'no-store','x-content-type-options':'nosniff','content-security-policy':"sandbox; default-src 'none'"};
    if (request.headers.has('range')) headers['content-range'] = `bytes ${start}-${end-1}/${record.size}`;
    if (record.exportFile) headers['content-disposition'] = `attachment; filename*=UTF-8''${encodeURIComponent(record.fileName)}`;
    const stream = request.method === 'HEAD' ? null : new ReadableStream({
      async pull(controller) {
        try {
          if (stopped) return;
          const next = Math.min(end,offset+chunkBytes);
          const bytes = await read(cap,record,offset,next);
          if (stopped) {bytes.fill(0); return;}
          controller.enqueue(bytes); offset = next;
          if (offset === end) controller.close();
        } catch {stopped = true; controller.error(Error('Attachment access unavailable'));}
      },
      cancel() {stopped = true;}
    },{highWaterMark:1});
    return new Response(stream,{status:request.headers.has('range') ? 206 : 200,headers});
  } catch {return new Response(null,{status:403,headers:{'cache-control':'no-store'}});}
}
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  const prefix = mediaRoot.pathname+'content/';
  if (url.origin === mediaRoot.origin && url.pathname.startsWith(prefix)) {
    event.respondWith(content(event.request,url.pathname.slice(prefix.length)));
  } else if (url.origin === mediaRoot.origin && url.pathname.startsWith(mediaRoot.pathname) &&
      event.request.method === 'GET') {
    event.respondWith((async () => {
      const cache = await caches.open(uiCache);
      const publicUrl = new URL(url); publicUrl.search = ''; publicUrl.hash = '';
      return await cache.match(publicUrl.href) || fetch(event.request);
    })());
  }
});
