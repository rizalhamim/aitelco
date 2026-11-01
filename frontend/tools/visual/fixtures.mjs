// API answers that reproduce the data shown in the approved mockups.
import { chatStream } from "./chat-fixture.mjs";
import { ALERTS, OVERVIEW } from "./dashboard-fixture.mjs";
import { PERFORMANCE } from "./performance-fixture.mjs";
const HISTORY = [
  { session_id: "s1", title: "Revenue West Java vs bulan lalu", message_count: 4, updated_at: "2026-11-01T05:10:00" },
  { session_id: "s2", title: "Site availability East Java minggu ini", message_count: 2, updated_at: "2026-10-31T16:20:00" },
  { session_id: "s3", title: "Market share FWA Semarang", message_count: 6, updated_at: "2026-10-30T09:02:00" },
];

const STATIC = {
  "/api/history/sessions": HISTORY,
  "/api/app/version": { version_name: "1.50.0", version_code: 69 },
  "/api/watchlist/alerts/count": { active: 3 },
  "/api/dashboard/overview": OVERVIEW,
  "/api/performance": PERFORMANCE,
  "/api/watchlist/alerts": ALERTS,
};

export function fixtureFor(pathname /*, params, method */) {
  if (pathname === "/api/chat/stream") return { __sse: chatStream() };
  if (pathname in STATIC) return STATIC[pathname];
  return undefined;
}
