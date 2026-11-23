import { getDocument, GlobalWorkerOptions } from './pdfjs/build/pdf.min.mjs';

// Only a canvas and text semantics are exposed. No PDF scripts, external links,
// forms, embedded-file actions or download button run inside this read preview.
export async function openPdf(url, status) {
  GlobalWorkerOptions.workerSrc = new URL('./pdfjs/build/pdf.worker.min.mjs', import.meta.url).href;
  const loading = getDocument({url:String(url), rangeChunkSize:256*1024,
    disableStream:true, disableAutoFetch:true, withCredentials:false,
    isEvalSupported:false, enableXfa:false, maxImageSize:4*1024*1024,
    canvasMaxAreaInBytes:16*1024*1024,
    cMapUrl:new URL('./pdfjs/cmaps/', import.meta.url).href, cMapPacked:true,
    standardFontDataUrl:new URL('./pdfjs/standard_fonts/', import.meta.url).href,
    wasmUrl:new URL('./pdfjs/wasm/', import.meta.url).href});
  let closed = false, rendering = false, current = 1, previousPage, renderTask;
  const close = () => {
    closed = true; renderTask?.cancel(); previousPage?.cleanup();
    canvas.width = canvas.height = 0; text.textContent = '';
    loading.destroy().catch(() => {});
  };
  const container = document.createElement('section'); container.className = 'pdf';
  const nav = document.createElement('nav'), before = document.createElement('button'), after = document.createElement('button');
  const label = document.createElement('span'), canvas = document.createElement('canvas'), text = document.createElement('p');
  text.className = 'pdf-text'; canvas.setAttribute('role','img');
  before.textContent = 'Previous page'; after.textContent = 'Next page';
  nav.append(before,label,after); container.append(nav,canvas,text); status.replaceWith(container);
  addEventListener('pagehide', close, {once:true});
  try {
    const documentPdf = await loading.promise;
    async function render(number) {
      if (closed || rendering) return;
      rendering = true; before.disabled = after.disabled = true;
      try {
        previousPage?.cleanup(); text.textContent = '';
        const page = await documentPdf.getPage(number); previousPage = page;
        if (closed) {page.cleanup(); return;}
        const natural = page.getViewport({scale:1});
        const scale = Math.min(2, Math.max(.25,(container.clientWidth-16)/natural.width),
          Math.sqrt(4*1024*1024/(natural.width*natural.height)));
        const viewport = page.getViewport({scale});
        canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
        canvas.setAttribute('aria-label',`PDF page ${number} of ${documentPdf.numPages}`);
        renderTask = page.render({canvasContext:canvas.getContext('2d'),viewport});
        await renderTask.promise;
        if (closed) return;
        const content = await page.getTextContent();
        if (closed) return;
        text.textContent = content.items.map(item => item.str || '').join(' ');
        current = number; label.textContent = `Page ${number} / ${documentPdf.numPages}`;
      } catch {
        if (!closed) {close(); container.replaceChildren(document.createTextNode('PDF access unavailable. Unlock or reconnect, then reopen.'));}
      } finally {
        rendering = false; before.disabled = closed || current <= 1; after.disabled = closed || current >= documentPdf.numPages;
      }
    }
    before.onclick = () => render(current-1); after.onclick = () => render(current+1);
    await render(1);
  } catch {
    close(); container.replaceChildren(document.createTextNode('PDF preview unavailable. Unlock or reconnect, then reopen.'));
  }
}
