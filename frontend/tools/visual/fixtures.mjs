// API answers that reproduce the data shown in the approved mockups.
import { chatStream } from "./chat-fixture.mjs";
import { ALERTS, OVERVIEW } from "./dashboard-fixture.mjs";
import { PERFORMANCE } from "./performance-fixture.mjs";
import { MAP, UPLOAD, mapAsk } from "./map-fixture.mjs";
import { LIBRARY, OUTLOOK, RUNS, SCHEDULES } from "./report-fixture.mjs";
import { NOTIFS, PROFILE } from "./profile-fixture.mjs";
import { APP_STATS } from "./stats-fixture.mjs";
import { RULES, WATCH_ALERTS, WATCH_META, WATCH_PARSE, WATCH_STATS } from "./watchlist-fixture.mjs";
const HISTORY = [
  { session_id: "s1", title: "Revenue West Java vs bulan lalu", message_count: 4, updated_at: "2026-11-01T05:10:00" },
  { session_id: "s2", title: "Site availability East Java minggu ini", message_count: 2, updated_at: "2026-10-31T16:20:00" },
  { session_id: "s3", title: "Market share FWA Semarang", message_count: 6, updated_at: "2026-10-30T09:02:00" },
];

const STATIC = {
  "/api/history/sessions": HISTORY,
  "/api/app/version": { version_name: "1.50.0", version_code: 69, size_bytes: 24 * 1024 * 1024, available: true, min_android: "8.0", download_url: "/api/app/download",
    notes: "", mandatory: false, released_at: "2026-11-01", apk_filename: "AgentJava-1.50.0.apk",
    sha256: "7c41e09a3b2f8d6e0d1c5a9b7e3f40c2a6d8e1f9b0c3d5a7e9f1b2c4d6e84e7f2a83", summary: "Redesign v2, nama baru Agent Java",
    highlights: [
      { icon: "map", title: "Peta Agent", text: "Tanya lewat chat, jawaban muncul di peta. Warnai dengan Performance, Site productivity, atau Profile wilayah." },
      { icon: "pulse", title: "Performance kembali", text: "Drill-down Circle Java sampai site, data dari dump Parquet jadi lebih cepat." },
      { icon: "bell", title: "Watchlist dan alert push", text: "Pantau KPI dengan kalimat biasa, notifikasi masuk saat lewat ambang." },
      { icon: "user", title: "Profil dari semua tab", text: "Avatar di app bar membuka profil, tema, notifikasi, dan unduhan." },
    ] },
  "/api/app/releases": { releases: [
    { version_name: "1.50.0", version_code: 69, released_at: "2026-11-01", notes: [], summary: "Redesign v2, Agent Java", mandatory: false, latest: true, available: true, download_url: "/api/app/download" },
    { version_name: "1.49.1", version_code: 68, released_at: "2026-10-31", notes: [], summary: "Sesi kedaluwarsa kembali ke login", mandatory: false, latest: false, available: true, download_url: "/api/app/download?version=1.49.1" },
    { version_name: "1.49.0", version_code: 67, released_at: "2026-10-31", notes: [], summary: "Redesign v1, 5 tab, unduh APK setelah login", mandatory: false, latest: false, available: true, download_url: "/api/app/download?version=1.49.0" },
    { version_name: "1.48.3", version_code: 66, released_at: "2026-10-20", notes: [], summary: "Versi sebelum Redesign v1", mandatory: false, latest: false, available: true, download_url: "/api/app/download?version=1.48.3" },
  ] },
  "/api/watchlist/alerts/count": { active: 3 },
  "/api/dashboard/overview": OVERVIEW,
  "/api/performance": PERFORMANCE,
  "/api/watchlist/alerts": ALERTS,
  "/api/map/agent": MAP,
  "/api/map/agent/upload": UPLOAD,
  "/api/report-docs/library": LIBRARY,
  "/api/report-docs/doc": OUTLOOK,
  "/api/report-schedules": SCHEDULES,
  "/api/report-schedules/runs": RUNS,
  "/api/watchlist/rules": RULES,
  "/api/watchlist/stats": WATCH_STATS,
  "/api/watchlist/meta": WATCH_META,
  "/api/watchlist/parse": WATCH_PARSE,
  "/api/profile": PROFILE,
  "/api/admin/app-stats": APP_STATS,
  "/api/auth/me/notifications": NOTIFS,
};

export function fixtureFor(pathname, params, method, body) {
  if (pathname === "/api/chat/stream") return { __sse: chatStream() };
  if (pathname === "/api/map/agent/ask") return mapAsk(body);
  if (pathname === "/api/watchlist/alerts" && params.get("status") === "all") return WATCH_ALERTS;
  if (pathname in STATIC) return STATIC[pathname];
  return undefined;
}
