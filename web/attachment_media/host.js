(async () => {
  const cap = location.hash.slice(1), status = document.getElementById('status');
  if (!/^[A-Za-z0-9_-]{43}$/.test(cap)) {status.textContent = 'Attachment unavailable.'; return;}
  if (!navigator.serviceWorker.controller) {await navigator.serviceWorker.ready; location.reload(); return;}
  const url = new URL(`content/${cap}`,location.href);
  if (new URL(location.href).searchParams.get('pdf') === '1') {
    const pdf = await import('./host_pdf.js');
    await pdf.openPdf(url, status); return;
  }
  // The fragment is a transient local capability, never a cloud URL or M05 grant.
  // Parent selects preview or export using a separate non-secret query flag.
  if (new URL(location.href).searchParams.get('export') === '1') {
    const button = document.createElement('button'); button.textContent = 'Download attachment';
    button.onclick = () => {
      // A download-attributed anchor can bypass this iframe's service worker
      // in Chrome. Navigate inside its controlled scope; the freshly guarded
      // streaming response supplies Content-Disposition and the real filename.
      location.assign(url.href);
      status.textContent = 'Download started. Check the browser downloads.';
    };
    status.replaceWith(button); return;
  }
  const video = document.createElement('video'); video.controls = true; video.preload = 'metadata'; video.playsInline = true;
  video.controlsList.add('nodownload'); video.oncontextmenu = event => event.preventDefault();
  video.src = url; video.onerror = () => {status.textContent = 'Attachment access unavailable. Unlock or reconnect, then reopen.'; video.replaceWith(status);};
  status.replaceWith(video);
})().catch(() => {document.getElementById('status').textContent = 'Attachment unavailable.';});
