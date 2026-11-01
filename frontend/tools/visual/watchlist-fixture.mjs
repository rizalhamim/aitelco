// Mockup 07 (Watchlist dan Alert) data, as /api/watchlist/* would return it.
const G = { perf: "Performance", prod: "Site productivity", prof: "Profile wilayah" };

// [group, metric, micon, title, scope, kabupaten, value, value_sub, threshold, threshold_sub, status, notif, trend, line, condition]
const ROWS = [
  ["perf", "payload", "db", "Payload MoM", "Kab. Garut, West Java", "GARUT", "−9,1%", null, "< −5%", "selama 3 hari", "kritis", [1, 1, 1], [-1.2, -2.0, -3.5, -5.8, -7.4, -8.6, -9.1], -5, "turun"],
  ["perf", "revenue", "wallet", "Revenue MoM", "West Java", null, "−2,4%", "dekat ambang", "< −3%", "bulanan", "normal", [1, 1, 0], [-0.4, -0.9, -1.2, -1.8, -2.1, -2.2, -2.4], -3, "turun"],
  ["perf", "availability", "tower", "Availability", "Kab. Garut, West Java", "GARUT", "99,31%", null, "< 99,0%", "harian", "normal", [1, 0, 0], [99.5, 99.4, 99.45, 99.38, 99.3, 99.33, 99.31], 99.0, "di_bawah"],
  ["perf", "fwa_rgu", "users", "Gross add FWA", "Kota Semarang, Central Java", "KOTA SEMARANG", "78% target", null, "< 85% target", "5 hari beruntun", "peringatan", [1, 1, 1], [92, 88, 86, 83, 80, 79, 78], 85, "di_bawah"],
  ["prod", "rev_site", "tower", "Revenue / new site", "West Java", null, "Rp 71 jt", null, "< Rp 65 jt", "per titik, bulanan", "normal", [1, 0, 0], [76, 75, 74, 73, 72, 72, 71], 65, "di_bawah"],
  ["prod", "rgu_site", "users", "RGU 90D / site", "Kab. Garut, West Java", "GARUT", "1,9 rb", "dekat ambang", "< 1,8 rb", "bulanan", "normal", [1, 1, 0], [2.1, 2.05, 2.0, 1.98, 1.95, 1.92, 1.9], 1.8, "di_bawah"],
  ["prod", "vlr_site", "pulse", "VLR / site", "Central Java", null, "3,4 rb", null, "< 3,0 rb", "bulanan", "normal", [1, 0, 0], [3.3, 3.35, 3.3, 3.4, 3.38, 3.42, 3.4], 3.0, "di_bawah"],
  ["prof", "market_share", "pin", "Market share", "Kab. Cianjur, West Java", "CIANJUR", "41,2%", "▼ 0,8 pp MoM", "turun > 0,5 pp", "MoM", "peringatan", [1, 1, 0], [42.3, 42.2, 42.0, 41.8, 41.6, 41.4, 41.2], null, "turun"],
  ["prof", "fwa_pen", "wallet", "Penetrasi FWA", "Kota Semarang, Central Java", "KOTA SEMARANG", "3,4%", null, "< 3,0%", "bulanan", "normal", [1, 0, 0], [3.6, 3.55, 3.5, 3.48, 3.45, 3.42, 3.4], 3.0, "di_bawah"],
  ["prof", "subs", "users", "Pelanggan aktif", "Kab. Garut, West Java", "GARUT", "812 rb", "▼ 0,4% MoM", "turun > 1% MoM", "bulanan", "normal", [0, 0, 0], [818, 817, 816, 815, 814, 813, 812], null, "turun"],
];

export const RULES = {
  rules: ROWS.map(([group, metric, micon, title, scope, kab, value, sub, thr, thrSub, status, nt, trend, line, condition], i) => ({
    id: i + 1, name: `${title} ${scope}`, title, metric, metric_label: title, icon: "activity", micon, group, group_label: G[group],
    available: true, unit: "%", scope_level: kab ? "kabkota" : "region", scope_value: kab || scope.toUpperCase(), scope_label: scope,
    kabupaten: kab, condition, threshold: Math.abs(line ?? 1), threshold_label: thr, threshold_sub: thrSub, days: 1,
    notify_inapp: !!nt[0], notify_email: !!nt[1], notify_push: !!nt[2], active: true, status,
    near: sub === "dekat ambang", value: trend[6], value_label: value, value_sub: sub, level: null, level_label: null,
    breach_streak: status === "normal" ? 0 : 3, trend, trend_threshold: line, source_question: null,
    created_at: "2026-10-01T00:00:00Z",
  })),
};

const ACTIVE = [
  { id: 24, rule_id: 1, severity: "kritis", title: "Payload Garut turun 9,1%", message: "Di bawah ambang −5% selama 3 hari. 14 site terdampak.",
    created_at: "2026-11-01T05:48:00Z", metric: "payload", group: "perf", kabupaten: "GARUT", scope_label: "Kab. Garut", value_label: "−9,1%", rule_title: "Payload MoM" },
  { id: 23, rule_id: 4, severity: "peringatan", title: "Gross add FWA Semarang", message: "78% dari target harian, 5 hari berturut-turut.",
    created_at: "2026-11-01T05:00:00Z", metric: "fwa_rgu", group: "perf", kabupaten: "KOTA SEMARANG", scope_label: "Kota Semarang", value_label: "78% target", rule_title: "Gross add FWA" },
  { id: 22, rule_id: 8, severity: "peringatan", title: "Market share Cianjur −0,8 pp", message: "Kompetitor agresif di 6 kecamatan selatan.",
    created_at: "2026-11-01T03:00:00Z", metric: "market_share", group: "prof", kabupaten: "CIANJUR", scope_label: "Kab. Cianjur", value_label: "41,2%", rule_title: "Market share" },
];
const PAST = [
  [3, "2026-10-28T00:05:00Z", "98,42%", "2026-10-28T02:20:00Z", null],
  [5, "2026-10-20T23:30:00Z", "Rp 64 jt", null, "2026-10-24T00:00:00Z"],
  [8, "2026-10-13T22:15:00Z", "−0,7 pp", "2026-10-15T03:02:00Z", null],
];
const extra = Array.from({ length: 18 }, (_, i) => [[1, 2, 3, 4, 1, 4, 5, 6, 1, 4, 2, 3, 7, 9, 10, 1, 2, 6][i], `2026-10-${String(27 - i).padStart(2, "0")}T01:00:00Z`, "", `2026-10-${String(27 - i).padStart(2, "0")}T04:00:00Z`, null]);
export const WATCH_ALERTS = {
  alerts: [
    ...ACTIVE.map((a) => ({ ...a, value: null, resolved: false, acknowledged: false, resolved_at: null, acknowledged_at: null, group_label: G[a.group], notify_push: true, metric_label: a.rule_title })),
    ...[...PAST, ...extra].map(([rid, at, val, ack, res], i) => {
      const r = RULES.rules[rid - 1];
      return { id: 21 - i, rule_id: rid, severity: "peringatan", title: `${r.title} ${r.scope_label}`, message: "", value: null, created_at: at,
        resolved: true, acknowledged: !!ack, resolved_at: res || ack, acknowledged_at: ack, metric: r.metric, group: r.group, group_label: r.group_label,
        kabupaten: r.kabupaten, scope_label: r.scope_label.split(",")[0], value_label: val || r.value_label, rule_title: r.title, metric_label: r.title, notify_push: r.notify_push };
    }),
  ],
};

export const WATCH_STATS = {
  alerts_30d: 24,
  by_group: [{ key: "perf", label: G.perf, count: 14 }, { key: "prod", label: G.prod, count: 6 }, { key: "prof", label: G.prof, count: 4 }],
  handled_hours: 3.2, handled_prev_hours: 4.3, handled_delta_hours: -1.1,
  repeating: [{ rule_id: 1, title: "Payload MoM Kab. Garut" }, { rule_id: 4, title: "Gross add FWA" }],
};

export const WATCH_META = {
  metrics: ROWS.map((r) => ({ key: r[1], label: r[3], short: r[3], unit: "%", icon: "activity", micon: r[2], group: r[0], group_label: G[r[0]], available: true })),
  groups: Object.entries(G).map(([key, label]) => ({ key, label })),
  levels: [], conditions: ["turun", "naik", "berubah", "di_bawah", "di_atas"],
};

export const WATCH_PARSE = {
  metric: "rev_site", scope_level: "kabkota", scope_value: "GARUT", condition: "di_bawah", threshold: 180000000, days: 60, missing: [],
  metric_label: "Revenue / site", group: "prod", group_label: "Site productivity", available: true,
  scope_label: "Kab. Garut, West Java", condition_label: "< Rp 180 jt, 2 bulan", name: "Revenue / site Kab. Garut",
  source_question: "Kabari saya kalau revenue per site di Kab. Garut turun di bawah Rp 180 jt selama 2 bulan",
};
