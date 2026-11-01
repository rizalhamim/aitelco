// Performance data of mockup 04 (Kab. Garut, Oktober 2026) as the /api/performance answer.
const M = 1e9, JT = 1e6;
const months = [202511, 202512, 202601, 202602, 202603, 202604, 202605, 202606, 202607, 202608, 202609, 202610];
const LBL = ["Nov", "Des", "Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt"];
const x = (v, k) => v.map((a) => a * k);
const card = (label, value, note, tone) => ({ label, value, note, tone });

const S = [
  ["GRT-0412", "Tarogong Kidul 2", "Tarogong Kidul", 412, -8.4, 96200, -14.7, 99.10, "kritis",
    [card("Gross add harian", "46 /hari", "▼ 18,0% MoM", "down"), card("Pelanggan aktif", "9,8 rb", "▼ 1,2% MoM", "down"),
      card("Porsi trafik 5G", "22%", "dari payload site", null), card("Pelanggan FWA", "312", "aktif bulan ini", null)],
    "Payload turun sejak 26 Okt, bersamaan dengan gangguan 3 jam di sektor 2. Revenue data ikut turun 8,4%; pelanggan relatif stabil, jadi kemungkinan besar masalah kualitas jaringan, bukan churn."],
  ["GRT-0388", "Garut Kota Pasar", "Garut Kota", 386, -6.1, 88400, -12.2, 98.42, "kritis"],
  ["GRT-0217", "Karangpawitan 1", "Karangpawitan", 301, -4.0, 70100, -9.6, 99.71, "waspada"],
  ["GRT-0155", "Tarogong Kaler 3", "Tarogong Kaler", 288, -2.2, 66300, -7.1, 99.80, "waspada"],
  ["GRT-0098", "Cibatu Stasiun", "Cibatu", 254, -1.5, 58000, -5.2, 99.92, "normal"],
  ["GRT-0301", "Bayongbong 1", "Bayongbong", 240, 1.2, 54900, -1.0, 99.95, "normal"],
  ["GRT-0064", "Kadungora Pasar", "Kadungora", 226, 2.8, 51600, 0.8, 99.97, "normal"],
].map(([site_id, site_name, kecamatan, rev, rm, pl, pm, av, status, detail, note]) => ({
  site_id, site_name, kecamatan, kabupaten: "Garut", lat: -7.2, lon: 107.9,
  revenue: rev * JT, revenue_mom: rm, payload_gb: pl, payload_mom: pm, availability: av, status,
  detail: detail ?? [], note: note ?? "",
}));

const named = [["Tarogong Kidul", -420], ["Garut Kota", -310], ["Karangpawitan", -185], ["Cibatu", -120], ["Leles", -60],
  ["Bayongbong", 45], ["Kadungora", 80], ["Malangbong", 95]];
// 34 other kecamatan, together −325 jt
const others = [...Array.from({ length: 25 }, (_, i) => [`Kec ${i + 1}`, -15]), ...Array.from({ length: 9 }, (_, i) => [`Kec ${i + 26}`, 50 / 9])];
const contrib = [...named, ...others].map(([name, d]) => ({ name, key: name.toUpperCase(), value: 0, delta: d * JT })).sort((a, b) => a.delta - b.delta);

export const PERFORMANCE = {
  level: "kabupaten", child_level: "kecamatan", name: "Kab. Garut",
  path: [{ level: "circle", name: "Circle Java", value: "" }, { level: "region", name: "West Java", value: "WEST JAVA" }, { level: "kabupaten", name: "Garut", value: "GARUT" }],
  month_id: 202610, month_label: "Okt 2026", prev_label: "Sep 2026", yoy_label: "Okt 2025",
  kecamatan_count: 42, site_count: 214,
  kpis: [
    { key: "revenue", label: "Revenue", format: "currency", value: 38.2 * M, prev: 39.4 * M, yoy: 38.2 * M / 1.041, mom_pct: -3.0, yoy_pct: 4.1 },
    { key: "payload", label: "Payload", format: "gb", value: 1.62e6, prev: 1.78e6, yoy: 1.62e6 / 1.059, mom_pct: -9.1, yoy_pct: 5.9 },
    { key: "subs", label: "Pelanggan", format: "number", value: 812e3, prev: 815e3, yoy: 812e3 / 1.028, mom_pct: -0.37, yoy_pct: 2.8 },
    { key: "availability", label: "Availability", format: "percent", value: 99.31, prev: 99.53, yoy: 99.26, mom_pp: -0.22, yoy_pp: 0.05, target: 99.5 },
    { key: "sites", label: "Site", format: "number", value: 214, kritis: 14, waspada: 23, normal: 177 },
  ],
  trend: {
    months, labels: LBL, titles: months.map((m, i) => `${LBL[i]} ${Math.floor(m / 100)}`),
    current: {
      revenue: x([36.1, 36.8, 36.0, 35.4, 36.6, 37.2, 38.0, 38.9, 39.6, 39.9, 39.4, 38.2], M),
      payload: x([1.58, 1.60, 1.555, 1.54, 1.59, 1.62, 1.66, 1.70, 1.745, 1.78, 1.782, 1.62], 1e6),
      subs: x([790, 795, 792, 788, 796, 801, 806, 810, 814, 816, 815, 812], 1e3),
    },
    previous: {
      revenue: x([34.0, 34.6, 34.1, 33.5, 34.4, 35.0, 35.6, 36.2, 36.8, 37.0, 36.9, 36.7], M),
      payload: x([1.30, 1.33, 1.31, 1.29, 1.34, 1.38, 1.41, 1.44, 1.48, 1.50, 1.51, 1.53], 1e6),
      subs: x([760, 764, 762, 760, 766, 770, 774, 778, 782, 786, 788, 790], 1e3),
    },
  },
  contrib, contrib_total: -1200 * JT,
  sites: { rows: S, total: 214, page: 1, pages: 31, size: 7, counts: { kritis: 14, waspada: 23, normal: 177 } },
  source: { kind: "dump", label: "Dump Performance 1 Nov 05.00", created_at: "2026-10-31T22:00:00Z", age_hours: 8, queries: 0 },
};
