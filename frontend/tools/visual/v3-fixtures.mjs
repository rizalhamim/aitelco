// API answers for the Agent Java v3 pages that reproduce the numbers of the approved
// mockups in design/mockup-v3 (all "data ilustrasi" there). Shapes follow backend/app/*.py.
const b = (t) => ({ t, s: "b" }), e = (t) => ({ t, s: "e" }), p = (t) => ({ t });

export const BRIEF = {
  greeting: "Selamat pagi, Rizal",
  subtitle: "Disusun agent untuk Rizal · Kamis, 5 Nov 2026 06.00 WIB",
  date_short: "Kamis, 5 Nov · 06.00",
  month_chip: "Nov 2026",
  headline: [p("Revenue Circle Java MTD "), b("naik 1,4% vs LMTD"), p(", sejalan dengan target. Tiga hal butuh perhatian: "),
    e("payload Garut"), p(" masih turun, "), e("gross add FWA Semarang"), p(" tertinggal dari run-rate, dan 2 tindak lanjut jatuh tempo hari ini.")],
  audio: { text: "Selamat pagi.", seconds: 58 },
  basis: { dump: "Dump Performance 5 Nov 05.00 WIB", period: "MTD 1 sd 4 Nov vs LMTD 1 sd 4 Okt", focus: "Fokus: Circle Java, semua region" },
  source: { kind: "dump" },
  stories: [
    { n: 1, key: "k-payload-GARUT", tone: "k", tone_label: "Perlu tindakan", topic: "Performance", metric: "payload",
      title: "Payload Garut turun 4 hari berturut-turut", value_label: "−9,4%", value_note: "MTD vs LMTD",
      spark: [31.2, 31.0, 30.6, 30.9, 30.1, 29.4, 28.8, 28.5, 28.3, 28.2],
      text: "14 site di 3 kecamatan selatan menyumbang 71% penurunan. Availability normal, jadi kemungkinan bukan gangguan jaringan.",
      share: "", peek: "Garut −9,4% MTD", short_title: "Payload Garut", region: "WEST JAVA", kabupaten: "GARUT",
      diagnosa: { metric: "payload", region: "WEST JAVA", kabupaten: "GARUT", basis: "mtd" }, pin: {}, task: {} },
    { n: 2, key: "w-fwa_gross_add-CENTRAL JAVA", tone: "w", tone_label: "Waspada", topic: "Performance", metric: "fwa_gross_add",
      title: "Gross add FWA Semarang di bawah run-rate", value_label: "78%", value_note: "dari run-rate target",
      spark: [92, 90, 88, 86, 84, 83, 81, 80, 79, 78],
      text: "Perlu 48 gross add per hari sampai 30 Nov untuk menutup gap. Rata-rata 4 hari terakhir 36 per hari.",
      share: "", peek: "FWA Semarang 78% dari run-rate", short_title: "Gross add", region: "CENTRAL JAVA", kabupaten: null,
      simulasi: { metric: "fwa_gross_add", region: "CENTRAL JAVA" }, diagnosa: { metric: "subs", region: "CENTRAL JAVA", basis: "mtd" }, pin: {}, task: {} },
    { n: 3, key: "g-revenue-EAST JAVA", tone: "g", tone_label: "Kabar baik", topic: "Revenue", metric: "revenue",
      title: "East Java memimpin pertumbuhan revenue", value_label: "+2,1%", value_note: "MTD vs LMTD",
      spark: [24.1, 24.3, 24.2, 24.6, 24.8, 24.7, 25.0, 25.2, 25.3, 25.6],
      text: "Malang dan Sidoarjo naik paling tinggi. Pola yang sama bisa diuji di Central Java.",
      share: "", peek: "East Java +2,1% vs LMTD", short_title: "Revenue", region: "EAST JAVA", kabupaten: null,
      diagnosa: { metric: "revenue", region: "EAST JAVA", basis: "mtd" }, pin: {}, task: {} },
  ],
  target_title: "Posisi terhadap target November",
  target_sub: "Proyeksi akhir bulan dari run-rate 4 hari, rentang 80% ditunjukkan arsiran",
  targets: [
    { metric: "revenue", label: "Revenue", value_label: "Rp 1,87 T dari Rp 1,90 T", real_pct: 13, band_pct: 100, tick_pct: 98.6, color: "#0E8579",
      note: "Realisasi MTD Rp 246,8 M · proyeksi 98,6% (rentang 97,1% sd 100,1%)" },
    { metric: "subs", label: "Pelanggan aktif", value_label: "41,6 jt dari 41,5 jt", real_pct: 99, band_pct: 100, tick_pct: 99.7, color: "#22B8C9",
      note: "Proyeksi 100,2% · sudah di atas target" },
    { metric: "fwa_gross_add", label: "Gross add FWA", value_label: "1.080 dari 1.380", real_pct: 10, band_pct: 86, tick_pct: 78.3, color: "#F5A623",
      note: "Proyeksi 78,3% (rentang 72% sd 84%)" },
  ],
  agent_says: [b("Kata agent:"), p(" Revenue perlu Rp 63,6 M per hari sampai 30 Nov, di atas rata-rata 4 hari terakhir Rp 61,7 M. Estimasi akhir bulan Rp 1,87 T, gap sekitar Rp 27 M. Ini estimasi, bukan realisasi.")],
  agenda: [
    { kind: "task", icon: "check", title: "Cek 14 site Garut selatan", sub: "Tindak lanjut · PIC Dimas", time: "Hari ini", urgent: true, task_id: 1 },
    { kind: "task", icon: "check", title: "Program FWA Semarang", sub: "Tindak lanjut · PIC Sari", time: "Hari ini", urgent: true, task_id: 2 },
    { kind: "report", icon: "file", title: "Performance Outlook mingguan", sub: "Laporan terjadwal · 12 penerima", time: "09.00", urgent: false },
    { kind: "alert", icon: "bell", title: "Availability Cirebon 99,3%", sub: "Alert baru · Peringatan", time: "05.12", urgent: false },
  ],
  prefs: { send: true, push: true, email: false, send_label: "Kirim jam 06.00", days_label: "Senin sampai Sabtu", email_label: "rizal@... · versi lengkap" },
  topics: [{ key: "perf", label: "Performance", on: true }, { key: "prod", label: "Site productivity", on: true }, { key: "prof", label: "Profile wilayah", on: true }, { key: "ftth", label: "FTTH", on: false }],
  regions: [{ key: "JAVA", label: "Circle Java", on: true }, { key: "WEST JAVA", label: "West Java", on: false }, { key: "CENTRAL JAVA", label: "Central Java", on: false }, { key: "EAST JAVA", label: "East Java", on: false }],
  vote: null,
};

export const DIAG = {
  metric: "revenue", metric_label: "Revenue",
  scope: { level: "region", name: "West Java", region: "WEST JAVA", kabupaten: null },
  child_level: "kabupaten", child_noun: "kabupaten/kota",
  basis: { kind: "month", label: "Okt 2026 vs Sep 2026, bulan penuh", cur: "Okt 2026", prev: "Sep 2026" },
  source: { label_wib: "Dump Performance 1 Nov 05.00 WIB" },
  coverage_pct: 98.6, month_chip: "Nov 2026",
  title: "Kenapa revenue West Java turun 2,4%?",
  total: { delta: -10.1e9, delta_label: "−Rp 10,1 M", detail: "−2,4% · Rp 422,7 M ke Rp 412,6 M", label: "Perubahan revenue" },
  summary: [p("Revenue turun "), e("Rp 10,1 M"), p(" ke Rp 412,6 M. "), b("79% penurunan datang dari Garut dan Cianjur"), p(". Sebagian besar karena "),
    b("jumlah pelanggan aktif turun"), p(" (efek volume −Rp 6,8 M), bukan karena harga atau kualitas jaringan.")],
  waterfall: { unit: "Rp miliar", min: 400, max: 425, bars: [{ l: "Sep 2026", v: 422.7, t: "total" }, { l: "Garut", v: -4.6 }, { l: "Cianjur", v: -3.3 },
    { l: "Tasikmalaya", v: -1.4 }, { l: "Sukabumi", v: -0.9 }, { l: "Bandung", v: 1.2 }, { l: "Bekasi", v: 0.6 }, { l: "Lainnya|21 kab/kota", v: -1.7, dim: 1 }, { l: "Okt 2026", t: "end" }] },
  effects: { note: "Rp miliar, jumlahnya sama dengan −Rp 10,1 M", total_short: "−10,1", rows: [
    { key: "volume", label: "Efek volume", sub: "RGU 90D −2,8%", short: "−6,8", width_pct: 100 },
    { key: "rate", label: "Efek rate", sub: "Revenue per RGU −1,1%", short: "−2,9", width_pct: 43 },
    { key: "mix", label: "Efek mix", sub: "Pergeseran ke paket kecil", short: "−0,4", width_pct: 6 }] },
  tree: {
    level1: [{ key: "GARUT", name: "Garut", delta: -4.6e9, delta_label: "−Rp 4,6 M", share_pct: 45, on: true }, { key: "CIANJUR", name: "Cianjur", delta: -3.3e9, delta_label: "−Rp 3,3 M", share_pct: 33, on: false }],
    level2: [{ key: "CIKAJANG", name: "Cikajang", delta: -1.6e9, delta_label: "−Rp 1,6 M", on: true, sites: 6 }, { key: "PAMEUNGPEUK", name: "Pameungpeuk", delta: -1.3e9, delta_label: "−Rp 1,3 M", on: false, sites: 5 },
      { key: "BUNGBULANG", name: "Bungbulang", delta: -0.8e9, delta_label: "−Rp 0,8 M", on: false, sites: 3 }],
    level2_other: { count: 39, delta_label: "−Rp 0,9 M", noun: "kec." },
    sites: { count: 6, kecamatan: "Cikajang", note: "Rp miliar. Availability ke-6 site 99,6% sd 99,9%, normal.",
      items: [["CKJ-012", "−0,41"], ["CKJ-007", "−0,33"], ["CKJ-021", "−0,29"], ["CKJ-003", "−0,24"], ["CKJ-015", "−0,18"], ["CKJ-009", "−0,15"]].map(([site_id, short]) => ({ site_id, short })) },
  },
  hypotheses: [
    { key: "volume", n: 1, title: "Pelanggan pindah ke kompetitor", confidence: 2, confidence_label: "Sedang", evidence: [
      { kind: "p", text: "RGU 90D turun 3,8% di 3 kecamatan selatan" }, { kind: "p", text: "Payload per RGU tetap, kualitas tidak berubah" },
      { kind: "n", text: "Market share belum tersedia di dump untuk konfirmasi" }] },
    { key: "network", n: 2, title: "Gangguan jaringan", confidence: 1, confidence_label: "Rendah", evidence: [
      { kind: "m", text: "Availability 99,6% sd 99,9%, tidak ada site di bawah ambang" }] },
  ],
  missing: "distribusi voucher dan outlet. Data channel belum ada di Performance dump.",
  follow_ups: [{ label: "Bandingkan dengan Cianjur", question: "x" }, { label: "Tren 6 bulan Cikajang", question: "y" }],
  steps: 5, elapsed_s: 6.8,
  task_prefill: { title: "Cek 6 site Cikajang", origin: "diagnosa", region: "WEST JAVA", kabupaten: "GARUT", metric: "revenue", impact: -4.6e9 },
};

const RC = { "EAST JAVA": "#0E8579", "CENTRAL JAVA": "#22B8C9", "WEST JAVA": "#6A4CB5" };
const RL = { "EAST JAVA": "East Java", "CENTRAL JAVA": "Central Java", "WEST JAVA": "West Java" };
const krow = (rank, name, rg, ach, g, abs, move, extra = {}) => ({
  rank, key: name.toUpperCase(), name, region: rg, region_label: RL[rg], region_color: RC[rg], growth_pct: g, achievement_pct: ach,
  small_base: false, move, mine: false, ach_label: ach.toLocaleString("id-ID", { minimumFractionDigits: 1 }) + "%",
  growth_label: (g > 0 ? "+" : "−") + Math.abs(g).toLocaleString("id-ID", { minimumFractionDigits: 1 }) + "%", abs_label: abs,
  move_label: move === 0 ? "tetap" : `${move > 0 ? "naik" : "turun"} ${Math.abs(move)} peringkat`, ...extra });
const KROWS = [
  krow(1, "Malang", "EAST JAVA", 104.2, 4.8, "+Rp 1,9 M", 1), krow(2, "Sidoarjo", "EAST JAVA", 103.1, 4.1, "+Rp 1,6 M", 3),
  krow(3, "Bandung", "WEST JAVA", 102.6, 3.2, "+Rp 2,4 M", 0), krow(4, "Semarang", "CENTRAL JAVA", 101.9, 2.7, "+Rp 1,5 M", -1),
  krow(5, "Surabaya", "EAST JAVA", 101.5, 2.2, "+Rp 2,8 M", -2), krow(6, "Kota Pekalongan", "CENTRAL JAVA", 101.2, 6.9, "+Rp 0,1 M", 9, { small_base: true }),
  ...Array.from({ length: 104 }, (_, i) => krow(7 + i, `Kab ${7 + i}`, "WEST JAVA", 100 - i * 0.03, 1, "+Rp 0,1 M", 0)),
  krow(111, "Sukabumi", "WEST JAVA", 96.3, -1.6, "−Rp 0,3 M", -5, { mine: true }),
  ...Array.from({ length: 5 }, (_, i) => krow(112 + i, `Kab ${112 + i}`, "WEST JAVA", 96 - i * 0.2, -2, "−Rp 0,1 M", 0)),
  krow(117, "Tasikmalaya", "WEST JAVA", 94.8, -3.1, "−Rp 0,4 M", -4), krow(118, "Cianjur", "WEST JAVA", 93.6, -5.2, "−Rp 0,8 M", -2),
  krow(119, "Garut", "WEST JAVA", 92.4, -6.1, "−Rp 0,7 M", -3),
];
export const KLAS = {
  level: "kabupaten", metric: "revenue", metric_label: "Revenue", sort: "achievement", title: "Klasemen kabupaten/kota, November 2026",
  month_chip: "Nov 2026", vs_label: "vs LMTD", basis: { kind: "mtd", label: "MTD 1 sd 4 Nov vs LMTD 1 sd 4 Okt" },
  source: { label_wib: "Dump Performance 5 Nov 05.00 WIB" }, small_base_label: "Basis kecil: revenue LMTD di bawah Rp 1 M",
  target_note: null, has_targets: true, total: 119, noun: "kab/kota", rows: KROWS,
  best: KROWS.slice(0, 3), worst: [KROWS[118], KROWS[117], KROWS[116]],
  mine: { rank: 111, total: 119, name: "Sukabumi", key: "SUKABUMI", region: "WEST JAVA", move_label: "turun 5 peringkat minggu ini",
    need_fmt: "Rp 0,4 M", need_label: "untuk masuk 100 besar", cause: "revenue per RGU −2,0%" },
  regions: [
    { rank: 1, key: "EAST JAVA", name: "East Java", color: "#0E8579", achievement_pct: 101.4, growth_pct: 2.1, ach_label: "101,4%", growth_label: "+2,1%", abs_label: "+Rp 5,2 M" },
    { rank: 2, key: "CENTRAL JAVA", name: "Central Java", color: "#22B8C9", achievement_pct: 98.7, growth_pct: 1.4, ach_label: "98,7%", growth_label: "+1,4%", abs_label: "+Rp 2,9 M" },
    { rank: 3, key: "WEST JAVA", name: "West Java", color: "#6A4CB5", achievement_pct: 93.2, growth_pct: -1.8, ach_label: "93,2%", growth_label: "−1,8%", abs_label: "−Rp 2,5 M" },
  ],
  badges: [{ kind: "climber", icon: "up", title: "Pendaki", text: "Sidoarjo naik 3" }, { kind: "network", icon: "tower", title: "Jaringan prima", text: "Malang 99,9%" },
    { kind: "rise", icon: "spark", title: "Bangkit", text: "Pekalongan +9" }],
};

const pin = (id, col, position, spec, title, subtitle, origin_label, data, ask = "q") => ({ id, board_id: 1, kind: "chart", title, subtitle, origin: "tanya",
  origin_label, spec, col, position, data, ask, notes_count: 0 });
const yv = (y) => ((96 - y) * 14 / 80) * 1e9;
export const BOARDS = { boards: [{ id: 1, name: "Pantauan West Java", pins: 7 }, { id: 2, name: "Rapat Senin", pins: 5 }, { id: 3, name: "FWA Semarang", pins: 3 }],
  shared: [{ id: 9, name: "Papan Sari", pins: 2 }], shared_pins: 2 };
export const BOARD = {
  id: 1, name: "Pantauan West Java", role: "owner", summary: "7 pin · dibagikan ke 3 orang · dikirim ke email setiap Senin 07.30", columns: 3, month_chip: "Nov 2026",
  members: [["R", "#0E8579"], ["S", "#6A4CB5"], ["D", "#FF7A59"], ["A", "#22B8C9"]].map(([initial, color], i) => ({ id: i + 1, name: initial, initial, color, role: i ? "view" : "owner" })),
  schedule: { weekday: 0, hour: 7, minute: 30, label: "Senin 07.30", recipients: 4, format: "PDF" },
  fresh: { ok: true, label: "Segar · dump 5 Nov 05.00" },
  pins: [
    pin(1, 0, 0, { type: "daily_compare" }, "Revenue harian West Java", "Nov MTD vs Okt, Rp miliar per hari", "Dari Tanya Agent, 1 Nov",
      { status: "ok", value_label: "Rp 52,8 M", growth_pct: -1.8, growth_label: "−1,8% vs LMTD", cur: [20, 21.5, 22.3, 21].map(yv), prev: [19, 18.5, 20, 19.2, 18].map(yv),
        days: 4, month: "Nov", prev_month: "Okt", scale: 1e9 }),
    pin(2, 0, 1, { type: "notes", for_pin: 5 }, "Catatan tim", null, "", { status: "ok", for_title: "Gross add FWA", notes: [
      { id: 1, user: "Sari", initial: "S", color: "#6A4CB5", text: "Program bundling FWA Semarang mulai 6 Nov. Pantau gross add 7 hari setelahnya.", at_label: "Kemarin 16.20" },
      { id: 2, user: "Rizal", initial: "R", color: "#0E8579", text: "Oke, saya buat tindak lanjut dan pasang alert jika di bawah 40 per hari.", at_label: "Kemarin 17.02" }] }, null),
    pin(3, 1, 0, { type: "map_change" }, "Peta payload Garut per kecamatan", "MTD vs LMTD, % perubahan", "Dari Peta Agent", { status: "ok", w: 370, h: 150,
      shapes: [
        { name: "Garut Kota", d: "M60 30 L118 18 L150 44 L132 78 L84 84 L52 60Z", fill: "#E6F4EA", x: 100, y: 56 },
        { name: "Tarogong", d: "M150 44 L206 26 L246 52 L232 92 L180 96 L132 78Z", fill: "#FAD0D0", x: 190, y: 62 },
        { name: "Banyuresmi", d: "M246 52 L300 40 L322 78 L292 106 L232 92Z", fill: "#FDECEC", x: 280, y: 74 },
        { name: "Pameungpeuk", d: "M84 84 L132 78 L180 96 L170 128 L110 136 L72 114Z", fill: "#EF5350", x: 120, y: 114 },
        { name: "Cikajang", d: "M180 96 L232 92 L292 106 L270 136 L200 140 L170 128Z", fill: "#C42B2B", x: 214, y: 124 }],
      labels: [{ name: "Cikajang", text: "Cikajang −12%", dark: true }, { name: "Pameungpeuk", text: "Pameungpeuk", dark: true }, { name: "Garut Kota", text: "Garut Kota", dark: false, good: true }],
      legend: [{ color: "#C42B2B", label: "turun > 10%" }, { color: "#FAD0D0", label: "0 sd −5%" }, { color: "#E6F4EA", label: "naik" }] }),
    pin(4, 1, 1, { type: "unavailable" }, "Market share FWA Semarang", "Pin dari pertanyaan 28 Okt", "Dari Tanya Agent, 28 Okt", { status: "unavailable",
      message: "Belum tersedia di Performance dump", detail: "Pin tetap disimpan dan akan terisi otomatis saat data market share masuk dump. Sementara itu tampilkan gross add FWA?" }),
    pin(5, 2, 0, { type: "kpi_watch" }, "KPI pantauan", "West Java · MTD 1 sd 4 Nov", "Dari Dashboard", { status: "ok", tiles: [
      { label: "Site di bawah target", value: "37", delta_label: "▲9", good: false }, { label: "Availability", value: "99,58%", delta_label: "+0,04 pp", good: true },
      { label: "RGU 90D", value: "9,4 jt", delta_label: "−0,8%", good: false }, { label: "Rev per site", value: "Rp 21,4 jt", delta_label: "−1,2%", good: false }] }),
    pin(6, 2, 1, { type: "rank_table", level: "kabupaten" }, "5 kabupaten turun terdalam", "Revenue MTD vs LMTD", "Dari Klasemen", { status: "ok", rows: [
      ["Garut", "−6,1%", "−0,7 M"], ["Cianjur", "−5,2%", "−0,8 M"], ["Tasikmalaya", "−3,1%", "−0,4 M"], ["Sukabumi", "−1,6%", "−0,3 M"], ["Ciamis", "−1,2%", "−0,1 M"]]
      .map(([name, pct_label, abs_label]) => ({ name, pct_label, abs_label, pct: -1 })) }),
  ],
};


const P = (id, name, color, unit = null) => ({ id, name, full_name: name, unit, initial: name[0], color });
const DIMAS = P(4, "Dimas", "#FF7A59", "Branch Garut"), ANDI = P(5, "Andi", "#22B8C9"), SARI = P(6, "Sari", "#6A4CB5"), RIZAL = P(1, "Rizal", "#0E8579");
const TK = (o) => ({ items_done: 0, items_total: 0, photos: 0, progress: null, criterion: null, verify: null, region: null, kabupaten: null, priority: "sedang", impact: null, mine: false, origin: "manual", due: { label: null, urgent: false }, ...o });
const ORG = { alert: ["Dari alert", "bell", "a"], diagnosa: ["Dari Diagnosa", "spark", "d"], brief: ["Dari Brief Pagi", "sun", "b"], ruang: ["Dari Ruang Saya", "layers", "p"] };
const tk = (id, origin, title, status, o) => TK({ id, origin, title, status, origin_label: ORG[origin][0], origin_icon: ORG[origin][1], origin_tone: ORG[origin][2], ...o });
const GARUT = tk(3, "diagnosa", "Cek 14 site Garut selatan", "dikerjakan", { criterion: "Selesai jika payload Garut kembali ≥ −3% vs periode sebelum", progress: 0.5, items_done: 2, items_total: 4, photos: 3, pic: DIMAS, due: { label: "Hari ini", long: "Hari ini, 5 Nov", urgent: true }, region: "WEST JAVA", kabupaten: "GARUT", priority: "tinggi", impact: -4.6e9 });
const OTHER = (id) => tk(id, "alert", `Tugas lain ${id}`, "dikerjakan", { pic: ANDI, due: { label: "20 Nov", urgent: false } });
export const TINDAK = {
  stats: { open: 12, open_mine: 5, due_today: 2, late: 1, late_days: 2, waiting: 3, proven: 8, verified: 11 },
  lanes: {
    baru: [
      tk(1, "alert", "Availability Cirebon di bawah 99,5%", "baru", { criterion: "Selesai jika availability ≥ 99,5% selama 7 hari", pic: ANDI, due: { label: "8 Nov", urgent: false } }),
      tk(2, "brief", "Uji program Malang di Central Java", "baru", { criterion: "Selesai jika revenue 2 kabupaten uji naik ≥ 2%", pic: SARI, due: { label: "15 Nov", urgent: false } }),
    ],
    dikerjakan: [GARUT,
      tk(4, "ruang", "Program bundling FWA Semarang", "dikerjakan", { criterion: "Selesai jika gross add FWA ≥ 48 per hari", progress: 0.25, items_done: 1, items_total: 4, pic: SARI, due: { label: "Hari ini", urgent: true } }),
      OTHER(7), OTHER(8), OTHER(9)],
    verifikasi: [
      tk(5, "alert", "Optimasi 6 site Cianjur selatan", "verifikasi", { verify: { text: "Data sesudah: 9 dari 14 hari", ok: null }, pic: RIZAL, done_label: "Selesai 27 Okt" }),
      tk(6, "diagnosa", "Promo ulang paket 30 hari Sukabumi", "verifikasi", { verify: { text: "Terbukti: RGU 90D +1,9% vs sebelum", ok: true }, pic: ANDI, done_label: "Selesai 18 Okt" }),
    ],
  },
  done_total: 18, done: [], mine: 5, today: "2026-11-05", month_chip: "Nov 2026",
};
export const TINDAK_TASK = { ...GARUT, origin_long: "Dari Diagnosa 4 Nov", scope_label: "Garut · 3 kecamatan", priority_label: "Tinggi · −Rp 4,6 M",
  items: [{ id: 1, text: "Cek availability dan alarm 14 site", done: true }, { id: 2, text: "Kunjungi 6 site Cikajang", done: true },
    { id: 3, text: "Cek aktivitas kompetitor di outlet sekitar", done: false }, { id: 4, text: "Usulkan program retensi ke Sales", done: false }],
  photos_list: [{ id: 11, caption: "CKJ-012 · 4 Nov", created_at: "2026-11-04T09:00:00" }, { id: 12, caption: "CKJ-007 · 4 Nov", created_at: "2026-11-04T10:00:00" }],
  kpi: { metric: "payload" },
  verify_detail: { metric_label: "Payload", before_label: "Sebelum · 21 Okt sd 3 Nov", after_label: "Sesudah · 6 Nov sd 19 Nov", before_pct: -9.4, after_pct: null, after_days: 0, result: null, window: 14 },
  history: [{ user: "Rizal", text: "membuat tugas dari Diagnosa revenue West Java", at_label: "4 Nov 08.12" }, { user: "Dimas", text: "menyelesaikan 2 item checklist dan menambah 2 foto", at_label: "4 Nov 15.40" }],
};

const B = (xs) => xs.map((v) => v * 1e9);
export const SIM = {
  metric: "revenue", metric_label: "Revenue", unit: "IDR", region: null, scope_label: "Circle Java", month: 202611, month_label: "Nov 2026", title: "Revenue Circle Java, Nov 2026",
  basis: { data_until: "4 Nov", source_note: "dump 5 Nov 05.00", remaining_days: 26, weekend_days: 8, target_source: "targets.json Nov 2026" },
  days_elapsed: 4, days_in_month: 30, mtd: 246.8e9, per_day: 61.7e9,
  estimate: { mid: 1873e9, lo: 1850e9, hi: 1900e9, pct: 98.58 }, target: 1900e9, target_vs_prev_pct: 3.3, prev_month_label: "Okt",
  gap: -27e9, need_per_day: 63.58e9,
  path: { days: 30, today: 4, target_per_day: 63.33e9, month_short: "Nov", act: B([-4.1, -5.3, -5.4, -6.5]),
    mid: B([-6.5,-7.3,-8.1,-8.9,-9.7,-10.4,-11.2,-12.0,-12.8,-13.6,-14.4,-15.2,-16.0,-16.8,-17.5,-18.3,-19.1,-19.9,-20.7,-21.5,-22.3,-23.1,-23.8,-24.6,-25.4,-26.2,-27.0]),
    lo: B([-6.5,-8.4,-10.2,-12.1,-14.0,-15.8,-17.7,-19.6,-21.4,-23.3,-25.2,-27.0,-28.9,-30.8,-32.6,-34.5,-36.3,-38.2,-40.1,-41.9,-43.8,-45.7,-47.5,-49.4,-51.3,-53.1,-55.0]),
    hi: B([-6.5,-6.2,-5.8,-5.5,-5.2,-4.9,-4.5,-4.2,-3.9,-3.6,-3.2,-2.9,-2.6,-2.2,-1.9,-1.6,-1.3,-0.9,-0.6,-0.3,0.0,0.4,0.7,1.0,1.3,1.7,2.0]) },
  regions: [
    { region: "EAST JAVA", label: "East Java", color: "#0E8579", mtd: 106.0e9, estimate: 816e9, target: 805e9, gap: 11e9, per_day: 26.5e9, need_per_day: 26.9e9 },
    { region: "CENTRAL JAVA", label: "Central Java", color: "#22B8C9", mtd: 88.0e9, estimate: 647e9, target: 655e9, gap: -8e9, per_day: 22.0e9, need_per_day: 21.8e9 },
    { region: "WEST JAVA", label: "West Java", color: "#6A4CB5", mtd: 52.8e9, estimate: 410e9, target: 440e9, gap: -30e9, per_day: 13.2e9, need_per_day: 14.9e9 },
  ],
  levers: [
    { key: "rate", kind: "slider", label: "Revenue per RGU", unit: "%", min: 0, max: 3, step: 0.1, value: 0, note: "Dari program paket atau upsell, untuk 26 hari tersisa", effect: { type: "pct_of", base: 1626.2e9 } },
    { key: "recover", kind: "toggle", label: "Pulihkan RGU West Java", value_label: "Level Sep", value: 0, note: "Mengembalikan efek volume −Rp 6,8 M per bulan dari Diagnosa", effect: { type: "fixed", amount: 5.9e9 } },
    { key: "sites", kind: "slider", label: "Site baru on air", unit: "site", min: 0, max: 40, step: 1, value: 0, note: "Rata-rata site baru Rp 25 jt per bulan, prorata", effect: { type: "per_unit", amount: 15e6 } },
    { key: "churn", kind: "locked", label: "Churn dan ARPU paket", note: "Belum tersedia di Performance dump. Akan aktif saat data masuk." },
  ],
  target_note: null, agent_says: null,
  method: "Metode: run-rate harian disesuaikan pola hari dalam seminggu 8 minggu terakhir. Diuji balik 6 bulan, rata-rata meleset 1,2%.",
};

export const V3_STATIC = {
  "/api/simulasi": SIM,
  "/api/tindak/tasks": TINDAK,
  "/api/tindak/tasks/3": TINDAK_TASK,
  "/api/tindak/people": { people: [{ id: 4, name: "Dimas" }] },
  "/api/ruang/boards": BOARDS,
  "/api/ruang/boards/1": BOARD,
  "/api/klasemen": KLAS,
  "/api/diagnosa": DIAG,
  "/api/brief": BRIEF,
  "/api/tindak/count": { open_mine: 5 },
};
