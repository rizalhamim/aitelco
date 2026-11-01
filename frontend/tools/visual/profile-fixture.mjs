// Mockup 08 (Profil) data, as /api/profile would return it.
export const PROFILE = {
  user: { id: 1, username: "rizal", full_name: "Rizal", email: "rizal@bizplan-java.com", department: "Business Planning", role: "admin",
    default_region: "JAVA", default_region_label: "Circle Java", updated_at: "2026-10-28T03:10:00Z" },
  stats: { last_login: "2026-11-01T05:40:00Z", login_count: 412, questions_month: 86, month_short: "Nov" },
  security: { password_changed_at: "2026-08-29T02:00:00Z", password_days: 64 },
  devices: [
    { id: null, kind: "web", name: "Chrome · Windows", sub: "aktif sekarang", current: true, can_sign_out: false },
    { id: 7, kind: "android", name: "Android · Agent Java", sub: "Galaxy A55 · 2 jam lalu", current: false, can_sign_out: true, app_version: "1.50.0" },
  ],
  apk: { installed_devices: 1 },
  prefs: { theme: "light", accent: "teal", density: "standar", lang: "id", targetLine: true, animation: true, default_region: "JAVA",
    notify: { alert_kritis: { email: true, push: true }, alert_peringatan: { email: false, push: true }, laporan: { email: true, push: false }, versi: { email: false, push: true } },
    quiet_hours: true },
  options: { regions: [{ key: "JAVA", label: "Circle Java" }, { key: "WEST JAVA", label: "West Java" }, { key: "CENTRAL JAVA", label: "Central Java" }, { key: "EAST JAVA", label: "East Java" }],
    departments: ["Business Planning", "Finance", "Marketing", "Network", "Operations", "Sales"] },
  admin: { active_users_7d: 48, version_name: "1.50.0", downloads_current: 126, accounts: 63, inactive: 3, pending: 3 },
};
export const NOTIFS = { notifications: [], unread_count: 0 };
