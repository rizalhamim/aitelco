// One entry per mockup frame (or region of a frame) the app must match.
// mockup: path from the repo root; clip: CSS-pixel region of the frame to compare.
// anonymous: no stored session; reducedMotion: emulate prefers-reduced-motion.
export const USER = {
  id: 1, username: "rizal", email: "rizal@bizplan-java.com", full_name: "Rizal", role: "admin",
  is_active: true, created_at: "2026-01-05T08:00:00", last_login: "2026-11-01T05:40:00", login_count: 412,
};

const M = "design/mockup-v2";

export const CASES = [
  // Fondasi: the sidebar is shared by every web page; checked on the Dashboard frame.
  { name: "shell-sidebar", route: "/dashboard", width: 1440, height: 1420,
    mockup: `${M}/03-dashboard/png/Web - Dashboard@2x.png`, clip: { x: 0, y: 0, width: 272, height: 1420 } },
  // 01 Login. Reduced motion keeps the poster and an empty seconds bar, like the
  // reference export, so the video frame is deterministic.
  { name: "login-web", route: "/login", width: 1440, height: 900, anonymous: true, reducedMotion: true,
    mockup: `${M}/01-login/png/Web - Login@2x.png` },
];
