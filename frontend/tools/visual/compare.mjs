// Visual gate for Redesign v2: renders app routes with fixture API data and compares
// them with the approved mockup PNGs in design/mockup-v2 (exported @2x).
//
//   npm run build && node tools/visual/compare.mjs [case ...]
//
// Starts `next start` on port 3100 (or uses VISUAL_URL), answers every /api/* call
// from tools/visual/fixtures.mjs, screenshots each case at the mockup frame size and
// writes tools/visual/out/<case>.png (mockup | app | difference) plus a score table.
// Score = share of pixels whose difference is above 24/255 on any channel. A case
// passes when the score is at or below its `max` (default 2%).
import { spawn } from "node:child_process";
import { mkdirSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import { CASES, USER } from "./cases.mjs";
import { fixtureFor } from "./fixtures.mjs";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "../../..");
const OUT = join(HERE, "out");

async function waitFor(url, ms = 60000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    try { const r = await fetch(url); if (r.status < 500) return; } catch { /* not up yet */ }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`server at ${url} did not start`);
}

/** "Data ilustrasi" chips of a v3 mockup frame, read from its render page:
    { render: "02-brief-pagi", frame: "web" | "droid" } -> [{x, y, w, h}] in frame CSS px. */
async function illusRects(browser, { render, frame = "web" }) {
  const page = await browser.newPage({ viewport: { width: 1900, height: 2600 } });
  await page.goto("file://" + join(ROOT, "design/mockup-v3/render", render + ".html"));
  await page.evaluate(() => document.fonts.ready);
  const rects = await page.evaluate((id) => {
    const f = document.getElementById(id), fb = f.getBoundingClientRect();
    return [...f.querySelectorAll(".illus")].map((n) => { const r = n.getBoundingClientRect(); return { x: r.x - fb.x - 2, y: r.y - fb.y - 2, w: r.width + 4, h: r.height + 4 }; });
  }, frame === "web" ? "webFrame" : "droidFrame");
  await page.close();
  return rects;
}

async function main() {
  const only = process.argv.slice(2);
  const cases = CASES.filter((c) => !only.length || only.includes(c.name));
  mkdirSync(OUT, { recursive: true });
  let server = null;
  let base = process.env.VISUAL_URL;
  if (!base) {
    base = "http://127.0.0.1:3100";
    server = spawn(process.execPath, ["node_modules/next/dist/bin/next", "start", "-p", "3100"], { cwd: resolve(HERE, "../.."), stdio: "ignore", detached: true });
    await waitFor(base + "/login");
  }
  const browser = await chromium.launch();
  const sharp = await import("./diff.mjs");
  let failed = 0;
  try {
    for (const c of cases) {
      const mock = join(ROOT, c.mockup);
      if (!existsSync(mock)) { console.log(`skip  ${c.name} (no mockup ${c.mockup})`); continue; }
      const page = await browser.newPage({ viewport: { width: c.width, height: c.height }, deviceScaleFactor: 2,
        reducedMotion: c.reducedMotion ? "reduce" : "no-preference" });
      if (c.clock) await page.clock.setFixedTime(new Date(c.clock));
      if (c.storage) await page.addInitScript((kv) => { for (const k in kv) localStorage.setItem(k, kv[k]); }, c.storage);
      if (!c.anonymous) await page.addInitScript((u) => {
        localStorage.setItem("access_token", "visual-test");
        localStorage.setItem("refresh_token", "visual-test");
        localStorage.setItem("user", JSON.stringify(u));
        localStorage.setItem("prefs", JSON.stringify({ theme: "light" }));
      }, USER);
      await page.route("**/api/**", async (route) => {
        const url = new URL(route.request().url());
        const body = fixtureFor(url.pathname, url.searchParams, route.request().method(), route.request().postData() || "");
        if (body === undefined) return route.fulfill({ status: 404, json: { detail: "no fixture" } });
        if (body && body.__sse) return route.fulfill({ status: 200, headers: { "content-type": "text/event-stream" }, body: body.__sse });
        return route.fulfill({ status: 200, json: body });
      });
      await page.goto(base + c.route, { waitUntil: "networkidle" });
      await page.evaluate(() => document.fonts.ready);
      if (c.prepare) await c.prepare(page);
      await page.waitForTimeout(c.settle ?? 600);
      const shot = join(OUT, `${c.name}.app.png`);
      await page.screenshot({ path: shot, clip: c.clip ?? { x: 0, y: 0, width: c.width, height: c.height } });
      await page.close();
      const mask = c.illus ? await illusRects(browser, c.illus) : c.mask;
      const res = await sharp.compare(mock, shot, join(OUT, `${c.name}.png`), c.clip, mask);
      const max = c.max ?? 2;
      const ok = res.score <= max;
      if (!ok) failed++;
      console.log(`${ok ? "pass" : "FAIL"}  ${res.score.toFixed(2).padStart(6)}%  (max ${max}%)  ${c.name}`);
    }
  } finally {
    await browser.close();
    if (server) { try { process.kill(-server.pid, "SIGKILL"); } catch { /* already gone */ } }
  }
  process.exit(failed ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(2); });
