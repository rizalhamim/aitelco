// 06 Laporan: the data shown in the approved mockup (design/mockup-v2/06-laporan).
const up = (v) => ({ v, tone: "up" });
const down = (v) => ({ v, tone: "down" });
const bar = (v, w, c = "#22B8C9") => ({ v, bar: { w, c } });

export const LIBRARY = {
  month_id: 202610, month_label: "Oktober 2026", month_short: "Okt 2026",
  lead: [
    { id: "doc:outlook:", kind: "analis", title: "Performance Outlook Circle Java", meta: "9 bagian · termasuk Site productivity", doc: { kind: "outlook", region: "" }, pages: 6, sections: 9 },
    { id: "doc:bulanan:WEST JAVA", kind: "bulanan", title: "Performa Bulanan West Java", meta: "PDF 2 hlm · Okt 2026", doc: { kind: "bulanan", region: "WEST JAVA" } },
    { id: "doc:profile:GARUT", kind: "profile", title: "Profile Kab. Garut", meta: "24 bagian · revenue, site, FWA, 5G", doc: { kind: "profile", kabupaten: "GARUT" } },
    { id: "perf:GARUT", kind: "performance", title: "Site Performance Kab. Garut", meta: "214 site · dari dump Parquet", href: "/performance?kabupaten=GARUT" },
  ],
  rest: [
    { id: "doc:bulanan:CENTRAL JAVA", kind: "bulanan", title: "Performa Bulanan Central Java", meta: "PDF 2 hlm · Okt 2026", doc: { kind: "bulanan", region: "CENTRAL JAVA" } },
    { id: "doc:bulanan:EAST JAVA", kind: "bulanan", title: "Performa Bulanan East Java", meta: "PDF 2 hlm · Okt 2026", doc: { kind: "bulanan", region: "EAST JAVA" } },
    { id: "doc:bulanan:", kind: "bulanan", title: "Performa Bulanan Circle Java", meta: "PDF 2 hlm · Okt 2026", doc: { kind: "bulanan", region: "" } },
    { id: "doc:profile:KOTA SEMARANG", kind: "profile", title: "Profile Kota Semarang", meta: "24 bagian · revenue, site, FWA, 5G", doc: { kind: "profile", kabupaten: "KOTA SEMARANG" } },
    { id: "doc:profile:KOTA SURABAYA", kind: "profile", title: "Profile Kota Surabaya", meta: "24 bagian · revenue, site, FWA, 5G", doc: { kind: "profile", kabupaten: "KOTA SURABAYA" } },
  ],
};

const TOC = ["Ringkasan", "Performance per region", "Revenue dan channel", "Subscriber dan RGU", "Site productivity",
  "Network dan availability", "Profile wilayah", "Market share", "Catatan agent"].map((title, i) => ({ n: i + 1, title }));

export const OUTLOOK = {
  kind: "outlook", kind_label: "Analis", title: "Performance Outlook Circle Java",
  meta: "Analis · 6 hlm · Agent Java, 1 Nov 05.30 WIB",
  eyebrow: "Performance Outlook · data ilustrasi", heading: "Circle Java, Oktober 2026",
  byline: "Disusun Agent Java · 1 Nov 2026 05.30 WIB · sumber dump Parquet",
  month_id: 202610, month_label: "Oktober 2026", month_short: "Okt 2026", toc: TOC,
  pages: [
    [
      { n: 1, title: "Ringkasan", type: "summary",
        text: "Revenue **naik 1,2% MoM** ke Rp 1,84 T, ditopang East Java. Productivity site baru masih **31% dari site base**. Perhatian: payload Garut turun 9,1% dan West Java di bawah target (93,2%).",
        kpis: [
          { label: "Revenue", value: "Rp 1,84 T", delta: "▲ 1,2% MoM", tone: "up" },
          { label: "Pelanggan aktif", value: "41,3 jt", delta: "▲ 0,6%", tone: "up" },
          { label: "Payload", value: "84,2 PB", delta: "▼ 0,4%", tone: "down" },
          { label: "Availability", value: "99,62%", delta: "target 99,5%", tone: "up" },
        ] },
      { n: 2, title: "Performance per region", sub: "MoM terhadap Sep 2026", type: "table",
        cols: ["Region", "Revenue", "MoM", "Payload", "MoM", "Capaian target"],
        rows: [
          ["East Java", "Rp 788,0 M", up("▲ 2,1%"), "36,4 PB", up("▲ 0,3%"), bar("101,4%", 50, "#0E8579")],
          ["Central Java", "Rp 640,0 M", up("▲ 1,4%"), "29,1 PB", down("▼ 0,2%"), bar("98,7%", 48, "#22B8C9")],
          ["West Java", "Rp 412,6 M", down("▼ 2,4%"), "18,7 PB", down("▼ 2,1%"), bar("93,2%", 44, "#F5A623")],
        ] },
      { n: 5, title: "Site productivity", sub: "point-in-time Okt 2026, bukan akumulasi", type: "table",
        cols: ["Region", "Rev / base site", "Rev / new site", "RGU 90D / site", "VLR / site"],
        rows: [
          ["East Java", bar("Rp 312 jt", 44), "Rp 96 jt", "2,9 rb", "3,8 rb"],
          ["Central Java", bar("Rp 278 jt", 39), "Rp 84 jt", "2,6 rb", "3,4 rb"],
          ["West Java", bar("Rp 241 jt", 34), "Rp 71 jt", "2,1 rb", "2,9 rb"],
        ] },
      { n: 7, title: "Profile wilayah", sub: "kabupaten/kota yang perlu perhatian", type: "table",
        cols: ["Kabupaten/kota", "Market share", "Pelanggan", "Gross add", "Site", "Penetrasi FWA"],
        rows: [
          ["Kab. Garut", down("38,6% ▼ 0,8 pp"), "812 rb", "21,4 rb", "214", "2,1%"],
          ["Kota Semarang", "44,2%", "1,32 jt", "36,8 rb", "402", down("3,4% ▼")],
          ["Kota Surabaya", up("47,9% ▲ 0,4 pp"), "2,41 jt", "61,2 rb", "688", "4,8%"],
        ],
        note: "Profil lengkap tiap kabupaten (revenue, channel, slab, produk, site, FWA, FTTH, 5G, network, market share) bisa dibuka sebagai laporan Profile wilayah tersendiri." },
    ],
    [{ n: 3, title: "Revenue dan channel", type: "table", cols: ["Bulan", "Total"], rows: [["Okt 2026", "Rp 1,84 T"]] }],
    [{ n: 4, title: "Subscriber dan RGU", type: "table", cols: ["Region", "RGU 90D"], rows: [["East Java", "17,2 jt"]] }],
    [{ n: 6, title: "Network dan availability", type: "table", cols: ["Region", "Availability"], rows: [["East Java", "99,71%"]] }],
    [{ n: 8, title: "Market share", type: "note", text: "Market share Circle Java Oktober 2026." }],
    [{ n: 9, title: "Catatan agent", type: "list", items: ["Kab. Garut: payload turun 9,1% MoM."] }],
  ],
};

const mails = (n) => Array.from({ length: n }, (_, i) => `user${i + 1}@bizplan-java.com`);
export const SCHEDULES = {
  schedules: [
    { id: 1, name: "Performance Outlook Circle Java", region: "", frequency: "bulanan", weekday: 0, monthday: 2, hour: 7, recipients: mails(12), active: true, description: "", last_sent_on: "2026-10-02" },
    { id: 2, name: "Performa Mingguan per region", region: "", frequency: "mingguan", weekday: 0, monthday: 1, hour: 7, recipients: mails(8), active: true, description: "", last_sent_on: "2026-10-27" },
    { id: 3, name: "Profile Kab. Garut", region: "WEST JAVA", frequency: "bulanan", weekday: 0, monthday: 5, hour: 7, recipients: mails(3), active: false, description: "", last_sent_on: null },
  ],
};
export const RUNS = {
  runs: [
    { id: 12, schedule_id: 2, title: "Performa Mingguan Central Java", kind: "mingguan", region: "CENTRAL JAVA", recipients: 8, failed: 0, status: "terkirim", created_at: "2026-10-26T00:00:00Z" },
    { id: 9, schedule_id: 1, title: "Performance Outlook Circle Java", kind: "bulanan", region: "", recipients: 12, failed: 1, status: "terkirim", created_at: "2026-10-02T00:00:00Z" },
  ],
};

const MONTHS = ["Nov 2025", "Des 2025", "Jan 2026", "Feb 2026", "Mar 2026", "Apr 2026", "Mei 2026", "Jun 2026", "Jul 2026", "Agu 2026", "Sep 2026", "Okt 2026"];
export const PINS = [{
  id: "p1", question: "Revenue West Java bulan ini dibanding bulan lalu per kabupaten", title: "Revenue West Java vs bulan lalu",
  chart: { type: "none", x: "bulan", y: ["revenue"], y2: [], series_by: null, label: null, formats: { revenue: "currency" }, sort: null, top_n: null, map_key: null, alternatives: [], title: "" }, columns: ["bulan", "revenue"], rows: MONTHS.map((bulan, i) => ({ bulan, revenue: 4e11 + i * 1e9 })),
  pinned_at: "2026-10-31T09:00:00Z",
}];
