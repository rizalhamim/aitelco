// Extract a layer tree from rendered HTML mockup frames for FigCraft export.
// usage: node extract.js <html> <out.json> <frameSelector>[:<tabValue>] ...
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const [, , html, out, ...sels] = process.argv;
  const outDir = path.dirname(out);
  const b = await chromium.launch();
  const page = await b.newPage({ viewport: { width: 1700, height: 1200 }, deviceScaleFactor: 1 });
  await page.goto('file://' + path.resolve(html));
  await page.addStyleTag({ content: '.fit{width:auto!important;height:auto!important} .fit>.frame{position:relative!important;transform:none!important;box-shadow:none!important} .panel{display:block!important} video{opacity:0!important} .sec-bar i{width:35%!important}' });
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(600);
  const sprite = await page.evaluate(() => document.querySelector('svg[aria-hidden="true"][width="0"]').outerHTML);
  const frames = [];
  for (const sel of sels) {
    const tree = await page.evaluate((sel) => {
      const root = document.querySelector(sel);
      let rid = 0;
      const rasters = [];
      const R = (el) => el.getBoundingClientRect();
      const nameOf = (el) => el.dataset.name || el.getAttribute('aria-label') || (el.className && typeof el.className === 'string' && el.className.split(' ')[0]) || el.tagName.toLowerCase();
      function textStyle(cs) {
        return { family: cs.fontFamily.split(',')[0].replace(/"/g, '').trim(), weight: +cs.fontWeight, size: parseFloat(cs.fontSize),
          lh: cs.lineHeight === 'normal' ? null : parseFloat(cs.lineHeight), ls: cs.letterSpacing === 'normal' ? 0 : parseFloat(cs.letterSpacing),
          color: cs.color, clip: cs.webkitBackgroundClip === 'text' || cs.backgroundClip === 'text', align: cs.textAlign, transform: cs.textTransform };
      }
      function inlineOnly(el) {
        for (const c of el.childNodes) {
          if (c.nodeType === 1) {
            const d = getComputedStyle(c).display;
            if (c.tagName === 'BR') continue;
            if (d !== 'inline' || c.tagName === 'svg' || c.tagName === 'INPUT') return false;
            if (!inlineOnly(c)) return false;
          }
        }
        return true;
      }
      function collectRuns(el, acc) {
        for (const c of el.childNodes) {
          if (c.nodeType === 3) {
            const t = c.textContent.replace(/\s+/g, ' ');
            if (t) acc.push({ text: t, style: textStyle(getComputedStyle(c.parentElement)) });
          } else if (c.nodeType === 1) {
            if (c.tagName === 'BR') acc.push({ text: '\n', style: textStyle(getComputedStyle(el)) });
            else collectRuns(c, acc);
          }
        }
        return acc;
      }
      function walk(el, pr) {
        const cs = getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden' || el.classList.contains('poster')) return null;
        const r = R(el);
        const n = { name: nameOf(el), tag: el.tagName.toLowerCase(), x: r.left - pr.left, y: r.top - pr.top, w: r.width, h: r.height,
          bg: cs.backgroundColor, bgImage: cs.backgroundImage, radius: [cs.borderTopLeftRadius, cs.borderTopRightRadius, cs.borderBottomRightRadius, cs.borderBottomLeftRadius].map(parseFloat),
          border: { w: parseFloat(cs.borderTopWidth), color: cs.borderTopColor, style: cs.borderTopStyle },
          shadow: cs.boxShadow, opacity: +cs.opacity, backdrop: cs.backdropFilter, clip: cs.overflow === 'hidden', children: [] };
        if (n.radius.some((v, i) => cs[['borderTopLeftRadius'][0]].includes('%'))) n.radius = n.radius.map(v => v);
        if (cs.borderTopLeftRadius.includes('%')) { const p = parseFloat(cs.borderTopLeftRadius) / 100; n.radius = [1, 1, 1, 1].map(() => Math.min(r.width, r.height) * p); }
        if (el.tagName === 'svg') {
          const id = 'r' + (rid++); rasters.push({ id, html: el.outerHTML, w: r.width, h: r.height, color: cs.color, radius: n.radius });
          n.raster = id; n.bg = 'rgba(0, 0, 0, 0)'; n.bgImage = 'none'; return n;
        }
        if (el.tagName === 'VIDEO') { n.video = el.getAttribute('src'); return n; }
        if (el.tagName === 'INPUT') {
          if (el.type === 'checkbox') return null;
          const ph = !el.value; const pcs = ph ? getComputedStyle(el, '::placeholder') : cs;
          const st = textStyle(cs); st.color = pcs.color;
          n.text = { runs: [{ text: el.value || el.placeholder, style: st }] };
          n.bg = 'rgba(0, 0, 0, 0)'; n.border.w = 0; return n;
        }
        // pseudo elements of the switch (thumb)
        if (el.classList.contains('sw')) {
          const a = getComputedStyle(el, '::after');
          const m = new DOMMatrix(a.transform === 'none' ? undefined : a.transform);
          n.children.push({ name: 'thumb', tag: 'div', x: parseFloat(a.left) + m.e, y: parseFloat(a.top), w: parseFloat(a.width), h: parseFloat(a.height), bg: a.backgroundColor, bgImage: 'none',
            radius: [99, 99, 99, 99], border: { w: 0 }, shadow: a.boxShadow, opacity: 1, backdrop: 'none', children: [] });
        }
        const hasText = [...el.childNodes].some(c => c.nodeType === 3 && c.textContent.trim());
        if (hasText && inlineOnly(el)) {
          const runs = collectRuns(el, []);
          // trim
          while (runs.length && !runs[0].text.trim()) runs.shift();
          if (runs.length) runs[0].text = runs[0].text.replace(/^\s+/, '');
          while (runs.length && !runs[runs.length - 1].text.trim()) runs.pop();
          if (runs.length) runs[runs.length - 1].text = runs[runs.length - 1].text.replace(/\s+$/, '');
          runs.forEach((ru, i) => { if (ru.text === '\n' && runs[i - 1]) runs[i - 1].text = runs[i - 1].text.replace(/ $/, ''); if (runs[i - 1]?.text === '\n') ru.text = ru.text.replace(/^ /, ''); });
          const rg = document.createRange(); rg.selectNodeContents(el); const tr = rg.getBoundingClientRect();
          n.text = { runs, x: tr.left - r.left, y: tr.top - r.top, w: tr.width, h: tr.height };
          return n;
        }
        for (const c of el.childNodes) {
          if (c.nodeType === 3 && c.textContent.trim()) {
            const rg = document.createRange(); rg.selectNodeContents(c); const tr = rg.getBoundingClientRect();
            n.children.push({ name: c.textContent.trim().slice(0, 40), tag: '#text', x: tr.left - r.left, y: tr.top - r.top, w: tr.width, h: tr.height, bg: 'rgba(0, 0, 0, 0)', bgImage: 'none', radius: [0, 0, 0, 0], border: { w: 0 }, shadow: 'none', opacity: 1, backdrop: 'none', children: [],
              text: { runs: [{ text: c.textContent.trim().replace(/\s+/g, ' '), style: textStyle(cs) }], x: 0, y: 0, w: tr.width, h: tr.height } });
          } else if (c.nodeType === 1) {
            const k = walk(c, r); if (k) n.children.push(k);
          }
        }
        return n;
      }
      const t = walk(root, R(root)); t.x = 0; t.y = 0;
      return { tree: t, rasters };
    }, sel);
    // rasterise svgs in isolation (2x)
    const rp = await b.newPage({ viewport: { width: 400, height: 400 }, deviceScaleFactor: 2 });
    for (const ra of tree.rasters) {
      await rp.setContent(`<html><body style="margin:0;background:transparent">${sprite}<div id="h" style="display:inline-block;color:${ra.color};line-height:0;border-radius:${ra.radius[0]}px;overflow:hidden">${ra.html.replace(/\s(width|height)="[^"]*"/g, '').replace(/<svg(\s|>)/, `<svg width="${ra.w}" height="${ra.h}"$1`)}</div></body></html>`);
      await rp.waitForTimeout(50);
      const file = path.join(outDir, `${frames.length}_${ra.id}.png`);
      await (await rp.$('#h')).screenshot({ path: file, omitBackground: true });
      ra.file = file; delete ra.html;
    }
    await rp.close();
    frames.push({ sel, ...tree });
  }
  fs.writeFileSync(out, JSON.stringify(frames, null, 1));
  // thumbnails of each frame
  await b.close();
})();
