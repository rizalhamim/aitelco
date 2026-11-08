// Pixel comparison through a headless page canvas, so no extra npm dependency is needed.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

let browser;
export async function compare(mockPath, appPath, sheetPath, clip, mask) {
  browser ??= await chromium.launch();
  const page = await browser.newPage();
  const b64 = (p) => "data:image/png;base64," + readFileSync(p).toString("base64");
  const out = await page.evaluate(async ({ a, b, clip, mask }) => {
    const load = (src) => new Promise((ok) => { const i = new Image(); i.onload = () => ok(i); i.src = src; });
    const [ma, ap] = await Promise.all([load(a), load(b)]);
    // mockup PNG is the whole frame @2x; crop it to the clip region when one is given
    const sx = clip ? clip.x * 2 : 0, sy = clip ? clip.y * 2 : 0;
    const w = ap.width, h = ap.height;
    const cv = (W, H) => { const c = document.createElement("canvas"); c.width = W; c.height = H; return c; };
    const cm = cv(w, h), cx = cm.getContext("2d"); cx.fillStyle = "#fff"; cx.fillRect(0, 0, w, h); cx.drawImage(ma, sx, sy, w, h, 0, 0, w, h);
    const ca = cv(w, h), ax = ca.getContext("2d"); ax.drawImage(ap, 0, 0);
    // masked rectangles (frame CSS px) take the mockup pixels, so they never count
    for (const r of mask || []) ax.drawImage(ma, r.x * 2, r.y * 2, r.w * 2, r.h * 2, r.x * 2 - sx, r.y * 2 - sy, r.w * 2, r.h * 2);
    const A = cx.getImageData(0, 0, w, h).data, B = ax.getImageData(0, 0, w, h).data;
    const heat = cv(w, h), hx = heat.getContext("2d"), H = hx.createImageData(w, h);
    // The exported mockup PNGs can sit up to 1 CSS px (2 device px) off the frame edge,
    // so try small global shifts and keep the best one.
    const near = (i, j) => Math.max(Math.abs(A[i] - B[j]), Math.abs(A[i + 1] - B[j + 1]), Math.abs(A[i + 2] - B[j + 2])) <= 24;
    // A pixel only counts as different when no pixel within 1 device px in the other image
    // matches it: that tolerates anti-aliasing and sub-pixel text placement, but still
    // catches wrong colors, missing elements and anything shifted by more than 1 px.
    function score(dx, dy, paint) {
      let bad = 0;
      const st = paint ? 1 : 4; // the shift search samples every 4th pixel
      for (let y = 2; y < h - 2; y += st) for (let x = 2; x < w - 2; x += st) {
        const i = (y * w + x) * 4, yy = y + dy, xx = x + dx;
        let ok = false;
        for (let oy = -1; oy <= 1 && !ok; oy++) for (let ox = -1; ox <= 1 && !ok; ox++) {
          const ny = yy + oy, nx = xx + ox;
          if (ny < 0 || nx < 0 || ny >= h || nx >= w) continue;
          ok = near(((ny * w + nx) * 4), i);
        }
        if (!ok) bad++;
        if (paint) { H.data[i] = ok ? 255 : 230; H.data[i + 1] = ok ? 255 : 40; H.data[i + 2] = ok ? 255 : 40; H.data[i + 3] = 255; }
      }
      return bad;
    }
    let best = [0, 0, Infinity];
    for (let dy = -3; dy <= 3; dy++) for (let dx = -2; dx <= 2; dx++) {
      const b = score(dx, dy, false); if (b < best[2]) best = [dx, dy, b];
    }
    const bad = score(best[0], best[1], true);
    hx.putImageData(H, 0, 0);
    const sheet = cv(w * 3 + 40, h), sx2 = sheet.getContext("2d");
    sx2.fillStyle = "#fff"; sx2.fillRect(0, 0, sheet.width, h);
    sx2.drawImage(cm, 0, 0); sx2.drawImage(ca, w + 20, 0); sx2.drawImage(heat, w * 2 + 40, 0);
    return { score: (100 * bad) / (w * h), png: sheet.toDataURL("image/png") };
  }, { a: b64(mockPath), b: b64(appPath), clip, mask });
  await page.close();
  const { writeFileSync } = await import("node:fs");
  writeFileSync(sheetPath, Buffer.from(out.png.split(",")[1], "base64"));
  return { score: out.score };
}
