// One entry per mockup frame (or region of a frame) the app must match.
// mockup: path from the repo root; clip: CSS-pixel region of the frame to compare.
// anonymous: no stored session; reducedMotion: emulate prefers-reduced-motion.
export const USER = {
  id: 1, username: "rizal", email: "rizal@bizplan-java.com", full_name: "Rizal", role: "admin",
  is_active: true, created_at: "2026-01-05T08:00:00", last_login: "2026-11-01T05:40:00", login_count: 412,
};

import { QUESTION } from "./chat-fixture.mjs";
import { Q1, Q2 } from "./map-fixture.mjs";
import { PINS } from "./report-fixture.mjs";

const M = "design/mockup-v2";

export const CASES = [
  // Fondasi: the sidebar is shared by every web page; checked on the Dashboard frame.
  { name: "shell-sidebar", route: "/dashboard", width: 1440, height: 1420,
    mockup: `${M}/03-dashboard/png/Web - Dashboard@2x.png`, clip: { x: 0, y: 0, width: 272, height: 1420 } },
  // 01 Login. Reduced motion keeps the poster and an empty seconds bar, like the
  // reference export, so the video frame is deterministic.
  { name: "login-web", route: "/login", width: 1440, height: 900, anonymous: true, reducedMotion: true,
    mockup: `${M}/01-login/png/Web - Login@2x.png` },
  // 02 Tanya Agent: one question, the streamed answer of the mockup, chart hovered on day 16.
  { name: "tanya-web", route: "/", width: 1440, height: 1080, clock: "2026-10-31T09:12:00",
    storage: { "telco_ai_session_id::rizal": "s1" },
    mockup: `${M}/02-tanya-agent/png/Web - Tanya Agent@2x.png`,
    prepare: async (page) => {
      await page.fill("textarea[aria-label=Pertanyaan]", QUESTION);
      await page.click("button[aria-label=Kirim]");
      await page.waitForSelector(".chartbox svg");
      await page.evaluate(() => window.scrollTo(0, 0));
      const box = await page.locator(".chartbox").boundingBox();
      await page.mouse.move(box.x + 44 + ((box.width - 56) * 15) / 30, box.y + 60);
    } },
  // 03 Dashboard: Circle Java, Oktober 2026, region chart hovered on Agu.
  { name: "dashboard-web", route: "/dashboard", width: 1440, height: 1420, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/03-dashboard/png/Web - Dashboard@2x.png`,
    prepare: async (page) => {
      await page.waitForSelector(".rchart");
      const box = await page.locator(".rchart").boundingBox();
      await page.mouse.move(box.x + 46 + ((box.width - 52) / 6) * 3.5, box.y + 200);
    } },
  // 04 Performance: Kab. Garut, trend hovered on Okt (default), first site row open.
  { name: "performance-web", route: "/performance?region=WEST%20JAVA&kabupaten=GARUT", width: 1440, height: 1591, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/04-performance/png/Web - Performance@2x.png`,
    prepare: async (page) => {
      await page.waitForSelector(".tchart");
      await page.mouse.move(5, 1580);
    } },
  // 05 Peta Agent: Kab. Garut, payload question, SHP upload, area question.
  { name: "peta-web", route: "/map?kabupaten=GARUT", width: 1440, height: 901, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/05-peta-agent/png/Web - Peta Agent@2x.png`,
    prepare: async (page) => {
      await page.waitForSelector(".mapwrap svg path[data-u]");
      await page.fill("textarea[aria-label='Pertanyaan peta']", Q1);
      await page.click(".mcomp .snd");
      await page.waitForSelector(".lchip");
      await page.setInputFiles("input[aria-label='File peta']", { name: "area_ekspansi_q1.zip", mimeType: "application/zip", buffer: Buffer.alloc(48 * 1024) });
      await page.waitForSelector(".mcomp .att");
      await page.fill("textarea[aria-label='Pertanyaan peta']", Q2);
      await page.click(".mcomp .snd");
      await page.waitForSelector(".mstat");
      await page.mouse.move(5, 890);
      await page.waitForTimeout(150);
    } },
  // 06 Laporan: Performance Outlook selected, one pinned agent answer in the library.
  { name: "laporan-web", route: "/reports", width: 1440, height: 1041, clock: "2026-11-01T06:00:00Z",
    storage: { "dash_pins::rizal": JSON.stringify(PINS) },
    mockup: `${M}/06-laporan/png/Web - Laporan@2x.png`,
    prepare: async (page) => {
      await page.waitForSelector(".lpage .pk");
      await page.mouse.move(5, 1030);
      await page.waitForTimeout(400);
    } },
  { name: "watchlist-web", route: "/watchlist", width: 1440, height: 1157, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/07-watchlist-alert/png/Web - Watchlist dan Alert@2x.png`,
    prepare: async (page) => {
      await page.waitForSelector(".wfoot");
      await page.waitForSelector(".parse");
      await page.mouse.move(5, 1150);
      await page.waitForTimeout(400);
    } },
];
