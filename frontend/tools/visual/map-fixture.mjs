// Peta Agent fixture: the Kab. Garut frame of mockup 05. Geometry (map-fixture-geo.json) is the
// real kecamatan boundaries projected like map_agent.Frame; metric values and site positions are
// the mockup's illustration, generated with the mockup's own formulas.
import { readFileSync } from "node:fs";

const G = JSON.parse(readFileSync(new URL("./map-fixture-geo.json", import.meta.url), "utf8"));

const hash = (s) => { let h = 2166136261; for (const ch of s) h = Math.imul(h ^ ch.charCodeAt(0), 16777619); return ((h >>> 0) % 1000) / 1000; };
const URB = { "Garut Kota": 1, "Tarogong Kidul": 1, "Tarogong Kaler": .8, Karangpawitan: .8, Banyuresmi: .6, Cilawu: .6, Leles: .5, Kadungora: .5, Cibatu: .5, Bayongbong: .5, Wanaraja: .45, Samarang: .4, Malangbong: .45 };
const ur = (n) => URB[n] ?? .15;
const LBL = ["Garut Kota", "Tarogong Kidul", "Tarogong Kaler", "Karangpawitan", "Banyuresmi", "Cilawu", "Bayongbong", "Leles", "Wanaraja", "Samarang", "Cibatu", "Kadungora", "Sucinaraja", "Pasirwangi", "Cisurupan", "Sukawening", "Malangbong", "Cikajang", "Leuwigoong", "Bl. Limbangan"];

// map_agent.Frame for the Kab. Garut bbox
const LON0 = 107.42025, LON1 = 108.13606, LAT0 = -7.74014, LAT1 = -6.9457, W = 748, H = 824, PAD = 30;
const cx = Math.cos(((LAT0 + LAT1) / 2) * Math.PI / 180);
const s = Math.min((W - 2 * PAD) / ((LON1 - LON0) * cx), (H - 2 * PAD) / (LAT1 - LAT0));
const ox = (W - (LON1 - LON0) * cx * s) / 2, oy = (H - (LAT1 - LAT0) * s) / 2;
const inv = (x, y) => [+(LON0 + (x - ox) / (cx * s)).toFixed(6), +(LAT1 - (y - oy) / s).toFixed(6)];

const status = (v) => (v <= -10 ? "kritis" : v <= -6 ? "waspada" : "normal");
const units = G.kec.map((k) => {
  const n = k.n, v = k.v;
  return {
    n, d: k.d, cx: k.cx, cy: k.cy, sites: k.sites, crit: G.sites.filter((x) => x.crit && x.k === n).length,
    status: status(v), label: LBL.includes(n),
    m: {
      payload_mom: v,
      revenue_mom: +(v * .45 + (hash(n + "r") - .5) * 3).toFixed(1),
      availability: +(99.05 + hash(n + "a") * .85 - (v < -10 ? .4 : 0)).toFixed(2),
      rev_site: Math.round(105 + ur(n) * 120 + hash(n + "p") * 40) * 1e6,
      rgu_site: +(.8 + ur(n) * 1.4 + hash(n + "g") * .4).toFixed(2) * 1e3,
      vlr_site: +(1.1 + ur(n) * 1.8 + hash(n + "v") * .5).toFixed(2) * 1e3,
      market_share: +(30 + ur(n) * 14 + hash(n + "m") * 8).toFixed(1),
      subs: Math.round(8 + ur(n) * 80 + hash(n + "s") * 10) * 1e3,
      gross_add: Math.round(250 + ur(n) * 1900 + hash(n + "ga") * 300),
      fwa_pen: +(.6 + ur(n) * 3.2 + hash(n + "f")).toFixed(1),
    },
  };
});

let ci = 0, ni = 0;
const sites = G.sites.map((p) => {
  const [lon, lat] = inv(p.x, p.y);
  const id = p.crit ? `GRT-0${400 + ci * 7}` : `GRT-${1001 + ni}`;
  const i = p.crit ? ci++ : ni++;
  const pm = p.crit ? -(10.6 + (i === 10 ? 6 : hash(id) * 4)) : +((hash(id) - .6) * 12).toFixed(1);
  return { id, name: null, k: p.k, kab: "Garut", x: p.x, y: p.y, lat, lon, crit: p.crit, status: p.crit ? "kritis" : status(pm),
    payload_mom: +pm.toFixed(1), revenue_mom: +(pm * .55).toFixed(1), availability: 99.4, payload_gb: 1800, revenue: 2.6e8,
    payload_gb_prev: 2000, revenue_prev: 2.8e8 };
});

const METRICS = [
  { key: "payload_mom", cat: "perf", name: "Payload MoM", short: "Payload MoM", kind: "div", unit: "%", d: 1 },
  { key: "revenue_mom", cat: "perf", name: "Revenue MoM", short: "Rev. MoM", kind: "div", unit: "%", d: 1 },
  { key: "availability", cat: "perf", name: "Availability", short: "Availability", kind: "seq", unit: "%", d: 2 },
  { key: "rev_site", cat: "prod", name: "Revenue / site", short: "Rev/site", kind: "seq", pre: "Rp ", unit: " jt", d: 0, scale: 1e6 },
  { key: "rgu_site", cat: "prod", name: "RGU 90D / site", short: "RGU 90D/site", kind: "seq", unit: " rb", d: 2, scale: 1e3 },
  { key: "vlr_site", cat: "prod", name: "VLR / site", short: "VLR/site", kind: "seq", unit: " rb", d: 2, scale: 1e3 },
  { key: "market_share", cat: "prof", name: "Market share", short: "Market share", kind: "seq", unit: "%", d: 1 },
  { key: "subs", cat: "prof", name: "Pelanggan aktif", short: "Pelanggan", kind: "seq", unit: " rb", d: 0, scale: 1e3 },
  { key: "gross_add", cat: "prof", name: "Gross add", short: "Gross add", kind: "seq", unit: "", d: 0 },
  { key: "fwa_pen", cat: "prof", name: "Penetrasi FWA", short: "Penetrasi FWA", kind: "seq", unit: "%", d: 1 },
].map((m) => ({ ...m, available: true }));

export const MAP = {
  scope: { level: "kabupaten", kabupaten: "GARUT", name: "Kab. Garut", province: "West Java", region: "" },
  frame: { w: W, h: H, lon0: LON0, lat1: LAT1, cx, s, ox, oy },
  bbox: [LON0, LAT0, LON1, LAT1],
  month: 202610, month_label: "Okt 2026", month_short: "Okt",
  unit_level: "kecamatan", units, sites, sites_without_coord: 0,
  neighbors: G.nb, outline: G.outline, metrics: METRICS,
  source: { kind: "dump", label: "Dump Performance 1 Nov 05.00", created_at: "2026-11-01T05:00:00+07:00", queries: 0 },
};

const crit = sites.filter((x) => x.crit);
const inArea = ["Garut Kota", "Tarogong Kidul"];
const areaSites = sites.filter((x) => inArea.includes(x.k)).slice(0, 12).concat(sites.filter((x) => x.k === "Karangpawitan").slice(0, 5));

export const Q1 = "Tampilkan payload MoM per kecamatan di Garut, tandai site yang turun lebih dari 10%";
export const Q2 = "Berapa site dan revenue di dalam area ini?";

export const ANSWER1 = {
  time: "05.42",
  text: "Payload Kab. Garut turun **9,1% MoM**. Paling dalam di **Tarogong Kidul (−14,2%)** dan **Garut Kota (−12,2%)**. Dua layer saya tambahkan ke peta:",
  layers: [
    { kind: "chor", metric: "payload_mom", label: "Choropleth 42 kecamatan" },
    { kind: "sites", metric: "payload_mom", threshold: -10, label: "14 site turun > 10%" },
  ],
  stats: [], actions: [], site_ids: crit.map((x) => x.id), metric: "payload_mom",
  focus: [418.79, 177.69, 565.51, 398.21],
  suggestions: ["Site productivity per kecamatan", "Profile wilayah", "Upload SHP area"],
};

export const UPLOAD = {
  name: "area_ekspansi_q1.zip", label: "area_ekspansi_q1.shp", kind: "SHP", desc: "Shapefile", size_kb: 48, count: "1 poligon",
  polygons: 1, points_count: 0, area_km2: 55.5, d: G.upload, points: [],
  rings: [[...G.upload.slice(1, -1).split(" ").map((p) => inv(...p.split(",").map(Number))), inv(...G.upload.slice(1, -1).split(" ")[0].split(",").map(Number))]],
};

export const ANSWER2 = {
  time: "05.43",
  text: "Area seluas **55,5 km²** ini mencakup Garut Kota, Tarogong Kidul, dan sebagian Karangpawitan.",
  text_short: "Area **55,5 km²**: Garut Kota, Tarogong Kidul, sebagian Karangpawitan.",
  layers: [],
  stats: [
    { label: "Site di area", short: "Site", value: "17", sub: "5 kritis", tone: "down" },
    { label: "Revenue Okt", short: "Revenue", value: "Rp 4,6 M", sub: "▼ 6,2% MoM", tone: "down" },
    { label: "Payload Okt", short: "Payload", value: "392 TB", sub: "▼ 12,6% MoM", tone: "down" },
  ],
  actions: ["sites", "geojson", "png"], site_ids: areaSites.map((x) => x.id),
  focus: [390.92, 209.0, 607.08, 399.88],
  suggestions: ["Site productivity per kecamatan", "Profile Kec. Tarogong Kidul", "Revenue MoM di area ini"],
  suggestions_short: ["Site productivity", "Profile area", "Revenue MoM"],
};

export function mapAsk(body) {
  let q = "";
  try { q = JSON.parse(body || "{}").q || ""; } catch { /* empty */ }
  return /area/i.test(q) ? ANSWER2 : ANSWER1;
}
