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
const M3 = "design/mockup-v3/png";
/* Since v3 the sidebar is the grouped v3 one (checked by "v3-sidebar"), so the v2 page cases
   compare the page area right of the 272 px sidebar. */
/* The v3 mockups mark their numbers with a "Data ilustrasi" chip that production does not
   show; `mask` copies those rectangles (CSS px) from the mockup so they never count. */

export const CASES = [
  // 01 Login. Reduced motion keeps the poster and an empty seconds bar, like the
  // reference export, so the video frame is deterministic.
  { name: "login-web", route: "/login", width: 1440, height: 900, anonymous: true, reducedMotion: true,
    mockup: `${M}/01-login/png/Web - Login@2x.png` },
  // 02 Tanya Agent: one question, the streamed answer of the mockup, chart hovered on day 16.
  { name: "tanya-web", route: "/", width: 1440, height: 1080, clock: "2026-10-31T09:12:00",
    storage: { "telco_ai_session_id::rizal": "s1" },
    mockup: `${M}/02-tanya-agent/png/Web - Tanya Agent@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1080 },
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
    mockup: `${M}/03-dashboard/png/Web - Dashboard@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1420 },
    prepare: async (page) => {
      await page.waitForSelector(".rchart");
      const box = await page.locator(".rchart").boundingBox();
      await page.mouse.move(box.x + 46 + ((box.width - 52) / 6) * 3.5, box.y + 200);
    } },
  // 04 Performance: Kab. Garut, trend hovered on Okt (default), first site row open.
  { name: "performance-web", route: "/performance?region=WEST%20JAVA&kabupaten=GARUT", width: 1440, height: 1591, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/04-performance/png/Web - Performance@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1591 },
    prepare: async (page) => {
      await page.waitForSelector(".tchart");
      await page.mouse.move(5, 1580);
    } },
  // 05 Peta Agent: Kab. Garut, payload question, SHP upload, area question.
  { name: "peta-web", route: "/map?kabupaten=GARUT", width: 1440, height: 901, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/05-peta-agent/png/Web - Peta Agent@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 901 },
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
    mockup: `${M}/06-laporan/png/Web - Laporan@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1041 },
    prepare: async (page) => {
      await page.waitForSelector(".lpage .pk");
      await page.mouse.move(5, 1030);
      await page.waitForTimeout(400);
    } },
  { name: "watchlist-web", route: "/watchlist", width: 1440, height: 1157, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/07-watchlist-alert/png/Web - Watchlist dan Alert@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1157 },
    prepare: async (page) => {
      await page.waitForSelector(".wfoot");
      await page.waitForSelector(".parse");
      await page.mouse.move(5, 1150);
      await page.waitForTimeout(400);
    } },
  { name: "profil-web", route: "/profile", width: 1440, height: 1267, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/08-profil/png/Web - Profil@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1267 },
    prepare: async (page) => {
      await page.waitForSelector(".nm .cb");
      await page.waitForSelector(".ses");
      await page.mouse.move(5, 1260);
      await page.waitForTimeout(400);
    } },
  { name: "statistik-web", route: "/statistik", width: 1440, height: 1745, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/09-statistik-unduh/png/Web - Statistik@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1745 },
    prepare: async (page) => {
      await page.waitForSelector(".stx .ut tbody tr");
      await page.mouse.move(5, 1740);
      await page.waitForTimeout(400);
    } },
  { name: "unduh-web", route: "/unduh", width: 1440, height: 1273, clock: "2026-11-01T06:00:00Z",
    mockup: `${M}/09-statistik-unduh/png/Web - Unduh APK@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1273 },
    prepare: async (page) => {
      await page.waitForSelector(".dlx .vh .vr");
      await page.mouse.move(5, 1270);
      await page.waitForTimeout(400);
    } },
  // v3 sidebar (grouped Pantau / Analisis / Bertindak, Ctrl K), checked on the Brief Pagi frame.
  { name: "v3-sidebar", route: "/brief", width: 1440, height: 1200, clock: "2026-11-05T06:00:00+07:00",
    mockup: `${M3}/02-brief-pagi/Web - Brief Pagi@2x.png`, clip: { x: 0, y: 0, width: 272, height: 1200 } },
  { name: "brief-web", route: "/brief", width: 1440, height: 1200, clock: "2026-11-05T06:00:00+07:00",
    mockup: `${M3}/02-brief-pagi/Web - Brief Pagi@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1200 }, illus: { render: "02-brief-pagi" },
    prepare: async (page) => { await page.waitForSelector(".f-02-brief-pagi .stories .st"); await page.mouse.move(1435, 1195); } },
  { name: "diagnosa-web", route: "/diagnosa?metric=revenue&region=WEST%20JAVA", width: 1440, height: 1210, clock: "2026-11-01T06:00:00+07:00",
    mockup: `${M3}/01-diagnosa/Web - Diagnosa Kenapa@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1210 }, illus: { render: "01-diagnosa" },
    prepare: async (page) => { await page.waitForSelector(".f-01-diagnosa .tree"); await page.mouse.move(1435, 1205); } },
  { name: "klasemen-web", route: "/klasemen", width: 1440, height: 1160, clock: "2026-11-05T06:00:00+07:00",
    mockup: `${M3}/03-klasemen/Web - Klasemen@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1160 }, illus: { render: "03-klasemen" },
    prepare: async (page) => { await page.waitForSelector(".f-03-klasemen .kt tbody tr"); await page.mouse.move(1435, 1155); } },
  // Ruang Saya mid drag: the map pin is picked up and hovers over the slot under it.
  { name: "ruang-web", route: "/ruang", width: 1440, height: 1120, clock: "2026-11-05T06:00:00+07:00",
    mockup: `${M3}/04-ruang-saya/Web - Ruang Saya@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1120 }, illus: { render: "04-ruang-saya" },
    prepare: async (page) => {
      await page.waitForSelector(".f-04-ruang-saya .pin");
      const box = await page.locator("[data-pin='3'] h4").boundingBox();
      await page.mouse.move(box.x + 20, box.y + 6);
      await page.mouse.down();
      await page.mouse.move(box.x + 20, box.y + 14, { steps: 2 });
      await page.mouse.move(box.x + 20, box.y + 6, { steps: 2 });
    } },
  // Tindak Lanjut with the Garut task open in the drawer.
  { name: "tindak-web", route: "/tindak?task=3", width: 1440, height: 1080, clock: "2026-11-05T06:00:00+07:00",
    mockup: `${M3}/05-tindak-lanjut/Web - Tindak Lanjut@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1080 }, illus: { render: "05-tindak-lanjut" },
    prepare: async (page) => { await page.waitForSelector(".f-05-tindak-lanjut .dr h2"); await page.mouse.move(1435, 1075); } },
  // Simulasi Target with the mockup scenario (+1,5% revenue per RGU, recover West Java, 20 new sites).
  { name: "simulasi-web", route: "/simulasi?s=rate:1.5,recover:1,sites:20", width: 1440, height: 1130, clock: "2026-11-05T06:00:00+07:00",
    mockup: `${M3}/06-simulasi-target/Web - Simulasi Target@2x.png`, clip: { x: 272, y: 0, width: 1168, height: 1130 }, illus: { render: "06-simulasi-target" },
    prepare: async (page) => { await page.waitForSelector(".f-06-simulasi-target .rt2 tbody tr"); await page.mouse.move(1435, 1125); } },
];
