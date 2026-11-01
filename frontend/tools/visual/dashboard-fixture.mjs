// Dashboard data of mockup 03 (Circle Java, Oktober 2026) as /api/dashboard/overview
// and /api/watchlist/alerts answers. The clock of the case is 2026-11-01 06:00 UTC.
const T = 1e12, M = 1e9, JT = 1e6, PB = 1e6;
const LBL = ["Nov", "Des", "Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt"];
const DAYS = ["22 Okt", "23 Okt", "24 Okt", "25 Okt", "26 Okt", "27 Okt", "28 Okt", "29 Okt", "30 Okt", "31 Okt"];
const series = (vals, k) => vals.map((v) => v * k);

export const OVERVIEW = {
  month_id: 202610, month_label: "Okt 2026", prev_label: "Sep",
  months: [202511, 202512, 202601, 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609, 202610],
  month_labels: LBL,
  scope: { circle: "JAVA", region: null, regions: ["EAST JAVA", "CENTRAL JAVA", "WEST JAVA"] },
  data_as_of: "2026-10-31",
  kpis: [
    { key: "revenue", label: "Revenue", format: "currency", icon: "wallet", value: 1.84 * T, prev: 1.82 * T, pct_change: 1.2,
      spark: series([1.66, 1.67, 1.68, 1.70, 1.71, 1.74, 1.73, 1.77, 1.79, 1.78, 1.82, 1.84], T),
      spark_daily: series([1.71, 1.74, 1.73, 1.77, 1.79, 1.78, 1.81, 1.80, 1.82, 1.84], T), spark_daily_labels: DAYS,
      target: 1.9 * T, note_prev_label: "Sep" },
    { key: "subs", label: "Pelanggan aktif", format: "number", icon: "users", value: 41.3 * JT, prev: 41.3 * JT - 246000, pct_change: 0.6,
      spark: series([39.6, 39.8, 39.9, 40.1, 40.3, 40.2, 40.6, 40.7, 40.9, 41.0, 41.1, 41.3], JT),
      spark_daily: series([40.1, 40.3, 40.2, 40.6, 40.7, 40.9, 40.8, 41.0, 41.1, 41.3], JT), spark_daily_labels: DAYS,
      target: 41.5 * JT, note_prev_label: "Sep" },
    { key: "payload", label: "Payload data", format: "gb", icon: "database", value: 84.2 * PB, prev: 84.5 * PB, pct_change: -0.4,
      spark: series([86.4, 86.1, 85.9, 85.2, 85.6, 84.9, 85.1, 84.6, 84.8, 84.3, 84.5, 84.2], PB),
      spark_daily: series([85.9, 85.2, 85.6, 84.9, 85.1, 84.6, 84.8, 84.3, 84.5, 84.2], PB), spark_daily_labels: DAYS,
      target: 86 * PB, note_prev_label: "Sep" },
    { key: "availability", label: "Site availability", format: "percent", icon: "radio", value: 99.62, prev: 99.5, pct_change: 0.12, change_unit: "pp",
      spark: [99.38, 99.4, 99.41, 99.48, 99.45, 99.52, 99.5, 99.55, 99.53, 99.58, 99.6, 99.62],
      spark_daily: [99.41, 99.48, 99.45, 99.52, 99.5, 99.55, 99.53, 99.58, 99.6, 99.62], spark_daily_labels: DAYS,
      target: 99.5, below_sla: 37, note_prev_label: "Sep" },
  ],
  revenue_by_region: {
    months: [202605, 202606, 202607, 202608, 202609, 202610], labels: ["Mei", "Jun", "Jul", "Agu", "Sep", "Okt"],
    series: [
      { name: "EAST JAVA", values: series([742, 751, 760, 770, 772, 788], M) },
      { name: "CENTRAL JAVA", values: series([618, 622, 629, 636, 631, 640], M) },
      { name: "WEST JAVA", values: series([431, 428, 425, 420, 422.7, 412.6], M) },
    ],
  },
  regions: [
    { region: "EAST JAVA", revenue: 788 * M, revenue_prev: 772 * M, mom_pct: 2.1, subs: 17.6 * JT, payload_gb: 36.4 * PB, gross_add: 0, availability: 99.7, achievement_pct: 101.4, share_pct: 42.8, spark: [] },
    { region: "CENTRAL JAVA", revenue: 640 * M, revenue_prev: 631 * M, mom_pct: 1.4, subs: 14.2 * JT, payload_gb: 29.1 * PB, gross_add: 0, availability: 99.6, achievement_pct: 98.7, share_pct: 34.8, spark: [] },
    { region: "WEST JAVA", revenue: 412.6 * M, revenue_prev: 422.7 * M, mom_pct: -2.4, subs: 9.5 * JT, payload_gb: 18.7 * PB, gross_add: 0, availability: 99.5, achievement_pct: 93.2, share_pct: 22.4, spark: [] },
  ],
  has_targets: true,
  summary: {
    text: "Revenue Circle Java **naik 1,2% MoM** ke Rp 1,84 T, ditopang East Java. Perlu perhatian: **payload Garut turun 9,1%** dan **gross add FWA Semarang** di bawah target 5 hari.",
    attention: ["payload"],
  },
  activity: { questions_today: 126, active_users_today: 31, validation_pct: 98.4, answers_7d: 812 },
  source: { kind: "dump", label: "Dump Performance 1 Nov 05.00", created_at: "2026-10-31T22:00:00Z" },
  kabupaten_count: 119,
};

export const ALERTS = {
  alerts: [
    { id: 1, severity: "kritis", title: "Payload Garut turun 9,1%", message: "Di bawah ambang 5% selama 3 hari. 14 site terdampak.",
      created_at: "2026-11-01T05:48:00Z", scope_label: "West Java", metric_label: "Payload" },
    { id: 2, severity: "peringatan", title: "Gross add FWA Semarang", message: "Realisasi 78% dari target harian, 5 hari berturut-turut.",
      created_at: "2026-11-01T05:00:00Z", scope_label: "Central Java", metric_label: "Gross add" },
    { id: 3, severity: "peringatan", title: "Market share Cianjur −0,8 pp", message: "Kompetitor agresif di 6 kecamatan selatan.",
      created_at: "2026-11-01T03:00:00Z", scope_label: "West Java", metric_label: "Market share" },
  ],
};
