"use client";
/* 04 Performance v2 (design/mockup-v2/04-performance): KPI drill-down from Circle Java to
   region, kabupaten, kecamatan and site, with MoM and YoY on every KPI, a 12-month trend
   against the year before, the kecamatan (or site) behind the revenue change and the site
   list with an inline detail. Numbers come from /api/performance, which reads the daily
   Performance dump (Parquet); the green or yellow label says where they came from. */
import { Fragment, Suspense, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell, { TopBar } from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { authFetch } from "@/lib/auth";
import { MONTHS_FULL } from "@/lib/format";
import { downloadXlsx } from "@/lib/xlsx";
import "../dashboard/dashboard.css";
import "./performance.css";

type Kpi = {
  key: string; label: string; format: string; value: number | null; prev?: number | null; yoy?: number | null;
  mom_pct?: number | null; yoy_pct?: number | null; mom_pp?: number | null; yoy_pp?: number | null; target?: number;
  kritis?: number; waspada?: number; normal?: number;
};
type Detail = { label: string; value: string; note: string; tone: "up" | "down" | null };
type Site = {
  site_id: string; site_name: string | null; kecamatan: string; kabupaten: string; lat: number | null; lon: number | null;
  payload_gb: number | null; revenue: number | null; availability: number | null;
  payload_mom: number | null; revenue_mom: number | null; status: "kritis" | "waspada" | "normal"; note?: string; detail?: Detail[];
};
type Level = "circle" | "region" | "kabupaten" | "kecamatan";
type Perf = {
  level: Level; child_level: Level | "site"; name: string;
  path: { level: Level; name: string; value: string }[];
  month_id: number; month_label: string; prev_label: string; yoy_label: string;
  kecamatan_count: number; site_count: number;
  kpis: Kpi[];
  trend: { months: number[]; labels: string[]; titles: string[];
    current: Record<Metric, (number | null)[]>; previous: Record<Metric, (number | null)[]> };
  contrib: { name: string; key: string; value: number; delta: number }[];
  contrib_total: number;
  sites: { rows: Site[]; total: number; page: number; pages: number; size: number; counts: { kritis: number; waspada: number; normal: number } };
  source: { kind: "dump" | "stale" | "bigquery"; label: string | null; created_at: string | null; age_hours?: number | null; queries: number };
};
type Metric = "revenue" | "payload" | "subs";
type Scope = { region: string; kabupaten: string; kecamatan: string };

const LOOK: Record<string, { icon: string; bg: string; fg: string }> = {
  revenue: { icon: "wallet", bg: "#FCEDD3", fg: "#B7791F" },
  payload: { icon: "db", bg: "#E3F7FA", fg: "#0E6F7C" },
  subs: { icon: "users", bg: "#E1ECFA", fg: "#2C6CB0" },
  availability: { icon: "tower", bg: "#ECE5FA", fg: "#6A4CB5" },
  sites: { icon: "pkg", bg: "#FBE2E8", fg: "#C23A5B" },
};
const LEVEL_LABEL: Record<string, string> = { circle: "Circle", region: "Region", kabupaten: "Kabupaten", kecamatan: "Kecamatan", site: "Site" };
const CHILD_SHORT: Record<string, string> = { region: "region", kabupaten: "kab.", kecamatan: "kec.", site: "site" };
const SEV: Record<string, [string, string]> = { kritis: ["k", "Kritis"], waspada: ["w", "Waspada"], normal: ["n", "Normal"] };
const MON = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

const id = (v: number, d: number) => v.toLocaleString("id-ID", { minimumFractionDigits: d, maximumFractionDigits: d });
const title = (s: string) => s.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\bDiy\b/, "DIY");
/** "Rp 38,2 M", "Rp 412 jt", "Rp 1,84 T". */
function rp(v: number | null | undefined): string {
  if (v == null) return "–";
  const a = Math.abs(v);
  if (a >= 1e12) return `Rp ${id(v / 1e12, 2)} T`;
  if (a >= 1e9) return `Rp ${id(v / 1e9, 1)} M`;
  if (a >= 1e6) return `Rp ${id(v / 1e6, 0)} jt`;
  return `Rp ${id(v, 0)}`;
}
/** GB to "1,62 PB", "96,2 TB". */
function vol(v: number | null | undefined): string {
  if (v == null) return "–";
  const a = Math.abs(v);
  if (a >= 1e6) return `${id(v / 1e6, 2)} PB`;
  if (a >= 1e3) return `${id(v / 1e3, 1)} TB`;
  return `${id(v, 1)} GB`;
}
/** "812 rb", "1,2 jt". */
function people(v: number | null | undefined): string {
  if (v == null) return "–";
  const a = Math.abs(v);
  if (a >= 1e6) return `${id(v / 1e6, 1)} jt`;
  if (a >= 1e3) return `${id(v / 1e3, 0)} rb`;
  return id(v, 0);
}
const fmtOf = (key: string) => (key === "revenue" ? rp : key === "payload" ? vol : people);
const arrow = (v: number) => (v >= 0 ? "▲" : "▼");
const chg = (v: number | null | undefined, pp = false) => (v == null ? "–" : `${arrow(v)} ${id(Math.abs(v), pp ? 2 : 1)}${pp ? " pp" : "%"}`);

/* ── Trend chart: 12 months against the same months a year earlier ── */
const TREND: Record<Metric, { f: (v: number) => string; ax: (v: number) => string; div: number }> = {
  revenue: { f: (v) => `Rp ${id(v, 1)} M`, ax: (v) => id(v, 0), div: 1e9 },
  payload: { f: (v) => `${id(v, 2)} PB`, ax: (v) => id(v, 1), div: 1e6 },
  subs: { f: (v) => `${id(v, 0)} rb`, ax: (v) => id(v, 0), div: 1e3 },
};

function TrendChart({ cur, prev, labels, titles, metric, on, small, height }: {
  cur: (number | null)[]; prev: (number | null)[]; labels: string[]; titles: string[]; metric: Metric; on: boolean[]; small?: boolean; height: number;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [W, setW] = useState(0);
  const n = labels.length;
  const [hover, setHover] = useState(n - 1);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setW(Math.floor(el.clientWidth)));
    ro.observe(el);
    setW(Math.floor(el.clientWidth));
    return () => ro.disconnect();
  }, []);
  const t = TREND[metric];
  const c = cur.map((v) => (v == null ? null : v / t.div)), p = prev.map((v) => (v == null ? null : v / t.div));
  const H = height, pl = small ? 34 : 44, pr = small ? 8 : 18, pt = 12, pb = 26;
  const iw = Math.max(1, W - pl - pr), ih = H - pt - pb;
  const all = [...c, ...p].filter((v): v is number => v != null);
  const mn0 = all.length ? Math.min(...all) : 0, mx0 = all.length ? Math.max(...all) : 1;
  const pad = (mx0 - mn0) * 0.15 || 1, mn = mn0 - pad, mx = mx0 + pad;
  const X = (i: number) => pl + (iw * i) / Math.max(1, n - 1);
  const Y = (v: number) => pt + ih * (1 - (v - mn) / (mx - mn));
  const path = (vs: (number | null)[]) => {
    let d = "", pen = false;
    vs.forEach((v, i) => { if (v == null) { pen = false; return; } d += `${pen ? "L" : "M"}${X(i).toFixed(1)} ${Y(v).toFixed(1)} `; pen = true; });
    return d.trim();
  };
  const h = Math.min(hover, n - 1);
  const ch = c[h], ph = p[h];
  const yoy = ch != null && ph ? (ch / ph - 1) * 100 : null;
  const mom = h > 0 && ch != null && c[h - 1] ? (ch / c[h - 1]! - 1) * 100 : null;
  const tx = X(h) + 14, flip = tx + 190 > W;
  const up = Math.max(ch != null ? Y(ch) : 0, ph != null ? Y(ph) : 0) < pt + ih * 0.55;
  const gid = small ? "tgs" : "tgw";
  const last = c.reduce<number>((a, v, i) => (v != null ? i : a), -1);
  const tip = (
    <div className={`ctip ${small ? "st" : ""}`} style={small ? undefined : { left: flip ? X(h) - 204 : tx, top: up ? H - pb - 120 : 14 }}>
      <b>{titles[h]}</b>
      {on[0] && <div><i style={{ background: "#0E8579" }} />Nilai<span>{ch != null ? t.f(ch) : "–"}</span></div>}
      {on[1] && <div><i style={{ background: "#9AA8A5" }} />Setahun lalu<span>{ph != null ? t.f(ph) : "–"}</span></div>}
      {yoy != null && <div><i style={{ background: "transparent" }} />YoY<span style={{ color: yoy >= 0 ? "#8EE0A6" : "#FF9C9C" }}>{chg(yoy)}</span></div>}
      {mom != null && <div><i style={{ background: "transparent" }} />MoM<span style={{ color: mom >= 0 ? "#8EE0A6" : "#FF9C9C" }}>{chg(mom)}</span></div>}
    </div>
  );
  return (
    <div className="chartbox tchartbox" ref={box}
      onMouseMove={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        setHover(Math.max(0, Math.min(n - 1, Math.round(((e.clientX - r.left - pl) / iw) * (n - 1)))));
      }}>
      {W > 0 && n > 0 && (
        <svg className="tchart" width={W} height={H} role="img" aria-label={`Tren 12 bulan ${metric}`}>
          <defs>
            <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor="#0E8579" stopOpacity={0.18} /><stop offset="1" stopColor="#0E8579" stopOpacity={0} />
            </linearGradient>
          </defs>
          {[0, 1, 2, 3].map((g) => {
            const v = mn + ((mx - mn) * g) / 3;
            return (
              <g key={g}>
                <line x1={pl} x2={W - pr} y1={Y(v)} y2={Y(v)} stroke={g ? "#ECF3F1" : "#B9C6C3"} strokeWidth={1} />
                <text x={pl - 8} y={Y(v) + 4} textAnchor="end" fontFamily="Poppins, sans-serif" fontSize={small ? 10 : 11} fill="#5A6B68">{t.ax(v)}</text>
              </g>
            );
          })}
          <line x1={X(h)} x2={X(h)} y1={pt} y2={pt + ih} stroke="#8FDFD7" strokeWidth={1.5} strokeDasharray="3 3" />
          {on[0] && last > 0 && <path d={`${path(c)} L${X(last)} ${pt + ih} L${X(0)} ${pt + ih} Z`} fill={`url(#${gid})`} />}
          {on[1] && <path d={path(p)} fill="none" stroke="#9AA8A5" strokeWidth={2} strokeDasharray="5 4" />}
          {on[0] && <path d={path(c)} fill="none" stroke="#0E8579" strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" />}
          {on[1] && ph != null && <circle cx={X(h)} cy={Y(ph)} r={4} fill="#fff" stroke="#9AA8A5" strokeWidth={2} />}
          {on[0] && ch != null && <circle cx={X(h)} cy={Y(ch)} r={5} fill="#0E8579" stroke="#fff" strokeWidth={2} />}
          {labels.map((m, i) => (small && i % 2 && i !== h ? null : (
            <text key={i} x={X(i)} y={H - 7} textAnchor="middle" fontFamily="Poppins, sans-serif" fontSize={small ? 10 : 11.5}
              fontWeight={i === h ? 700 : 400} fill={i === h ? "#0F1F1D" : "#5A6B68"}>{m}</text>
          )))}
        </svg>
      )}
      {W > 0 && n > 0 && tip}
    </div>
  );
}

/* ── Contribution: top falls, top rises, the rest grouped ── */
function contribRows(items: Perf["contrib"], falls: number, rises: number) {
  const neg = items.filter((c) => c.delta < 0).slice(0, falls);
  const pos = items.filter((c) => c.delta > 0).slice(-rises);
  const named = new Set([...neg, ...pos].map((c) => c.key));
  const rest = items.filter((c) => !named.has(c.key));
  const rows = [...neg, ...pos].map((c) => ({ ...c, other: false }));
  if (rest.length) rows.push({ name: String(rest.length), key: "__rest", value: 0, delta: rest.reduce((a, c) => a + c.delta, 0), other: true });
  const mx = Math.max(1, ...[...neg, ...pos].map((c) => Math.abs(c.delta)));
  return { rows, mx };
}
const juta = (v: number) => `${v > 0 ? "+" : v < 0 ? "−" : ""}${Math.round(Math.abs(v) / 1e6).toLocaleString("id-ID")}`;

function PerformanceView() {
  const router = useRouter();
  const params = useSearchParams();
  const [scope, setScope] = useState<Scope>(() => ({
    region: params.get("region") || "", kabupaten: params.get("kabupaten") || "", kecamatan: params.get("kecamatan") || "",
  }));
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<Perf | null>(null);
  const [error, setError] = useState("");
  const [metric, setMetric] = useState<Metric>("revenue");
  const [on, setOn] = useState([true, true]);
  const [sel, setSel] = useState<string | null>(null);
  const [nextOpen, setNextOpen] = useState(false);
  const [srcOpen, setSrcOpen] = useState(false);
  const [q, setQ] = useState("");
  const [hits, setHits] = useState<{ type: string; name: string; site_name?: string; region?: string; kabupaten?: string; kecamatan?: string }[]>([]);
  const search = useRef<HTMLInputElement>(null);

  useEffect(() => {
    let alive = true;
    const qs = new URLSearchParams({ ...scope, status, page: String(page), size: "7" });
    authFetch(`/api/performance?${qs}`)
      .then(async (res) => {
        const d = await res.json();
        if (!res.ok || d.error) throw new Error(d.error || d.detail || `HTTP ${res.status}`);
        if (alive) {
          setData(d); setError("");
          setSel((s) => (s && d.sites.rows.some((r: Site) => r.site_id === s) ? s : d.sites.rows[0]?.site_id ?? null));
        }
      })
      .catch((e) => { if (alive) setError(e instanceof Error ? e.message : "Gagal memuat"); });
    return () => { alive = false; };
  }, [scope, status, page]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "/" && document.activeElement?.tagName !== "INPUT" && document.activeElement?.tagName !== "TEXTAREA") { e.preventDefault(); search.current?.focus(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (q.trim().length < 2) return;
    const t = setTimeout(() => {
      authFetch(`/api/performance/search?q=${encodeURIComponent(q.trim())}`).then((r) => (r.ok ? r.json() : null))
        .then((d) => setHits(d?.results ?? [])).catch(() => setHits([]));
    }, 220);
    return () => clearTimeout(t);
  }, [q]);

  function go(next: Scope) {
    setScope(next); setStatus(""); setPage(1); setNextOpen(false);
    const qs = new URLSearchParams(Object.entries(next).filter(([, v]) => v));
    router.replace(`/performance${qs.toString() ? `?${qs}` : ""}`, { scroll: false });
  }
  function drill(key: string) {
    if (!data) return;
    if (data.child_level === "site") { setSel(key); return; }
    go({ ...scope, [data.child_level]: key });
  }
  function upTo(level: Level) {
    const order: Level[] = ["circle", "region", "kabupaten", "kecamatan"];
    const k = order.indexOf(level);
    go({ region: k >= 1 ? scope.region : "", kabupaten: k >= 2 ? scope.kabupaten : "", kecamatan: k >= 3 ? scope.kecamatan : "" });
  }
  function pick(h: (typeof hits)[number]) {
    setQ(""); setHits([]);
    if (h.type === "site") { router.push(`/map?focus=${encodeURIComponent(h.name)}&level=site`); return; }
    go({ region: h.region || "", kabupaten: h.kabupaten || "", kecamatan: h.type === "kecamatan" ? h.kecamatan || "" : "" });
  }

  const k = useMemo(() => Object.fromEntries((data?.kpis ?? []).map((x) => [x.key, x])), [data]);
  const monthFull = data ? `${MONTHS_FULL[(data.month_id % 100) - 1]} ${Math.floor(data.month_id / 100)}` : "";
  const src = data?.source;
  const srcTime = src?.created_at ? new Date(src.created_at) : null;
  const wib = (d: Date) => `${d.toLocaleString("id-ID", { day: "numeric", month: "short", year: "numeric", timeZone: "Asia/Jakarta" })} ${d.toLocaleString("id-ID", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Jakarta" }).replace(":", ".")} WIB`;
  const green = src?.kind === "dump";
  const parent = data && data.path.length > 1 ? data.path[data.path.length - 2] : null;
  const trendYears = data ? (() => {
    const a = data.trend.months[0], b = data.trend.months[data.trend.months.length - 1];
    const s = (m: number) => `${MON[(m % 100) - 1]} ${String(Math.floor(m / 100) % 100).padStart(2, "0")}`;
    const ly = (m: number) => m - 100;
    return { cur: `${s(a)} sampai ${s(b)}`, prev: `${s(ly(a))} sampai ${s(ly(b))}`, curLong: `${MON[(a % 100) - 1]} ${Math.floor(a / 100)} sampai ${MON[(b % 100) - 1]} ${Math.floor(b / 100)}` };
  })() : null;
  const contrib = data ? contribRows(data.contrib, 5, 3) : null;
  const counts = data?.sites.counts;
  const childShort = CHILD_SHORT[data?.child_level ?? "kecamatan"];

  function exportXlsx() {
    if (!data) return;
    downloadXlsx(`performance-${data.name.replace(/\W+/g, "-").toLowerCase()}-${data.month_id}`,
      ["site_id", "site_name", "kecamatan", "kabupaten", "revenue", "revenue_mom_pct", "payload_gb", "payload_mom_pct", "availability_pct", "status"],
      data.sites.rows.map((s) => ({
        site_id: s.site_id, site_name: s.site_name, kecamatan: s.kecamatan, kabupaten: s.kabupaten, revenue: s.revenue,
        revenue_mom_pct: s.revenue_mom, payload_gb: s.payload_gb, payload_mom_pct: s.payload_mom, availability_pct: s.availability, status: s.status,
      })), "Site");
  }

  const pageNums = (() => {
    if (!data) return [] as (number | "…")[];
    const P = data.sites.pages, cur = data.sites.page;
    const set = new Set([1, 2, 3, cur, P].filter((x) => x >= 1 && x <= P));
    const out: (number | "…")[] = [];
    [...set].sort((a, b) => a - b).forEach((x, i, arr) => { if (i && x - arr[i - 1] > 1) out.push("…"); out.push(x); });
    return out;
  })();

  return (
    <AppShell>
      <TopBar title="Performance" subtitle="Analisis KPI dari region sampai site"
        actions={<span className="chip"><Icon name="cal" />{data?.month_label ?? "Bulan ini"}</span>} />
      <div className="page dash perf">
        <div className="dhead">
          <div>
            <div className="eb">Performance · {green ? "dump harian" : src?.kind === "stale" ? "dump terlambat" : "BigQuery langsung"}</div>
            <h1>{data ? `${data.name}, ${monthFull}` : "Performance"}</h1>
            <p>{data
              ? [parent && parent.level !== "circle" ? parent.name : data.level === "circle" ? "3 region" : parent?.name,
                data.level !== "kecamatan" ? `${data.kecamatan_count} kecamatan` : null, `${data.site_count} site`,
                `MoM terhadap ${data.prev_label}, YoY terhadap ${data.yoy_label}`].filter(Boolean).join(" · ")
              : "memuat…"}</p>
          </div>
          <div className="grow" />
          {src && (
            <span className={`dsrc ${green ? "" : "warn"}`}>
              <i />{green || src.kind === "stale" ? <>Dump Parquet <b>{srcTime ? wib(srcTime) : "-"}</b> · {src.queries} query BigQuery</> : <>BigQuery langsung · dump belum tersedia</>}
              <button onClick={() => setSrcOpen((v) => !v)} aria-expanded={srcOpen}>Status dump</button>
              {srcOpen && (
                <span className="pop" role="status">
                  {green ? `Dump harian dibuat ${srcTime ? wib(srcTime) : "-"} (${src.age_hours ?? "-"} jam lalu). Halaman ini tidak menjalankan query BigQuery.`
                    : src.kind === "stale" ? `Dump terakhir berumur ${src.age_hours ?? "-"} jam, lewat batas 30 jam. Angka tetap ditampilkan dari dump lama sampai dump berikutnya selesai.`
                    : "Belum ada dump di server, jadi angka diambil langsung dari BigQuery dan disimpan sementara selama 6 jam."}
                </span>
              )}
            </span>
          )}
        </div>

        <div className="filt">
          <nav className="path" aria-label="Drill-down">
            {(data?.path ?? [{ level: "circle" as Level, name: "Circle Java", value: "" }]).map((p, i, arr) => (
              <Fragment key={p.level}>
                {i > 0 && <Icon name="chevr" />}
                <button className={i === arr.length - 1 ? "cur" : ""} aria-current={i === arr.length - 1 ? "page" : undefined}
                  onClick={() => i < arr.length - 1 && upTo(p.level)}>
                  <small className="lv">{LEVEL_LABEL[p.level]}</small>{p.name}
                </button>
              </Fragment>
            ))}
            {data && data.child_level !== "site" && (
              <>
                <Icon name="chevr" />
                <button className="next" onClick={() => setNextOpen((v) => !v)} aria-expanded={nextOpen} aria-haspopup="menu">Pilih {LEVEL_LABEL[data.child_level].toLowerCase()}</button>
                {nextOpen && (
                  <div className="menu" role="menu" onMouseLeave={() => setNextOpen(false)}>
                    {[...data.contrib].sort((a, b) => a.name.localeCompare(b.name)).map((c) => (
                      <button key={c.key} role="menuitem" onClick={() => drill(c.key)}>{c.name}</button>
                    ))}
                  </div>
                )}
              </>
            )}
          </nav>
          <div className="grow" />
          <div className="sbox">
            <Icon name="search" />
            <input ref={search} value={q} onChange={(e) => setQ(e.target.value)} placeholder="Cari site, kecamatan, atau kabupaten" aria-label="Cari site, kecamatan, atau kabupaten"
              onKeyDown={(e) => { if (e.key === "Escape") { setQ(""); setHits([]); } if (e.key === "Enter" && hits[0]) pick(hits[0]); }} />
            {!q && <kbd>/</kbd>}
            {q.trim().length >= 2 && hits.length > 0 && (
              <div className="sres" role="listbox">
                {hits.map((h) => (
                  <button key={`${h.type}-${h.name}-${h.kabupaten}`} role="option" aria-selected={false} onClick={() => pick(h)}>
                    {h.type === "site" ? `${h.name}${h.site_name ? ` · ${h.site_name}` : ""}` : h.name}
                    <small>{h.type === "site" ? `Site · ${title(h.kecamatan || "")}` : h.type === "kecamatan" ? `Kecamatan · ${title(h.kabupaten || "")}` : `Kabupaten · ${title(h.region || "")}`}</small>
                  </button>
                ))}
              </div>
            )}
          </div>
          <button className="linkbtn" style={{ height: 40 }} onClick={exportXlsx} disabled={!data}><Icon name="dl" />Ekspor</button>
        </div>

        {error && !data && (
          <div className="card perr"><Icon name="warn" /><span>Data Performance belum bisa dimuat: {error}</span></div>
        )}

        <div className="krow k5">
          {(["revenue", "payload", "subs", "availability"] as const).map((key) => {
            const x = k[key];
            const look = LOOK[key];
            if (!x) return <div key={key} className="kc skel" style={{ minHeight: 133 }} />;
            const av = key === "availability";
            const mom = av ? x.mom_pp : x.mom_pct, yoy = av ? x.yoy_pp : x.yoy_pct;
            const val = av ? (x.value != null ? `${id(x.value, 2)}%` : "–") : fmtOf(key)(x.value);
            return (
              <div key={key} className="kc">
                <div className="t"><i style={{ background: look.bg, color: look.fg }}><Icon name={look.icon} /></i>{x.label}
                  {mom != null && <span className={`dl ${mom < 0 ? "dn" : "up"}`}>{chg(mom, av)}</span>}</div>
                <div className="v">{val}</div>
                <div className="yy">YoY {yoy != null ? <b className={yoy < 0 ? "m" : "p"}>{chg(yoy, av)}</b> : "–"} · {av ? `target ${id(x.target ?? 99.5, 1)}%` : `${data?.prev_label.split(" ")[0]} ${fmtOf(key)(x.prev)}`}</div>
              </div>
            );
          })}
          {k.sites ? (
            <div className="kc">
              <div className="t"><i style={{ background: LOOK.sites.bg, color: LOOK.sites.fg }}><Icon name="pkg" /></i>Site</div>
              <div className="v">{(k.sites.value ?? 0).toLocaleString("id-ID")}</div>
              <div className="yy"><b className="m">{k.sites.kritis} kritis</b> · {k.sites.waspada} waspada · {k.sites.normal} normal</div>
            </div>
          ) : <div className="kc skel" style={{ minHeight: 133 }} />}
        </div>

        <div className="row2 pf">
          <section className="card">
            <div className="ch">
              <div><h3>Tren 12 bulan</h3><p>Garis penuh: {trendYears?.curLong ?? "12 bulan terakhir"} · putus-putus: periode setahun sebelumnya</p></div>
              <div className="grow" />
              <div className="seg" role="group" aria-label="Metrik tren" style={{ margin: 0 }}>
                {([["revenue", "Revenue"], ["payload", "Payload"], ["subs", "Pelanggan"]] as [Metric, string][]).map(([m, l]) => (
                  <button key={m} className={metric === m ? "on" : ""} aria-pressed={metric === m} onClick={() => setMetric(m)}>{l}</button>
                ))}
              </div>
            </div>
            <div className="legend">
              {[["#0E8579", trendYears?.cur ?? "Tahun ini"], ["#9AA8A5", trendYears?.prev ?? "Tahun lalu"]].map(([c, l], i) => (
                <button key={i} type="button" className={`lg ${on[i] ? "" : "off"}`} aria-pressed={on[i]}
                  onClick={() => setOn((o) => (o.filter(Boolean).length > 1 || !o[i] ? o.map((b, j) => (j === i ? !b : b)) : o))}>
                  <i style={{ background: c }} />{l}
                </button>
              ))}
            </div>
            {data && <TrendChart cur={data.trend.current[metric]} prev={data.trend.previous[metric]} labels={data.trend.labels} titles={data.trend.titles} metric={metric} on={on} height={290} />}
          </section>
          <section className="card">
            <div className="ch"><div><h3>Penyebab perubahan revenue</h3>
              <p>Selisih MoM per {data?.child_level === "site" ? "site" : LEVEL_LABEL[data?.child_level ?? "kecamatan"].toLowerCase()}, Rp juta · {data?.child_level === "site" ? "klik untuk lihat site" : "klik untuk turun level"}</p></div></div>
            <div className="contrib">
              {contrib?.rows.map((c) => {
                const w = (Math.abs(c.delta) / contrib.mx) * 48;
                const pos = c.delta > 0;
                return (
                  <button key={c.key} className={`cb ${c.other ? "oth" : ""}`} disabled={c.other} onClick={() => drill(c.key)}
                    aria-label={`${c.other ? `${c.name} ${childShort} lain` : c.name}: ${juta(c.delta)} juta`}>
                    <span>{c.other ? `${c.name} ${childShort} lain` : c.name}</span>
                    <div className="tr"><i style={pos ? { left: "50%", width: `${Math.min(48, w)}%`, background: "#2E9E57" } : { right: "50%", width: `${Math.min(48, w)}%`, background: "#E5484D" }} /></div>
                    <b style={{ color: pos ? "#1F7A3A" : "#C42B2B" }}>{juta(c.delta)}</b>
                  </button>
                );
              })}
            </div>
            {data && (
              <div className="cfoot"><span>Total perubahan {data.name}</span>
                <b style={{ color: data.contrib_total < 0 ? "#C42B2B" : "#1F7A3A" }}>{data.contrib_total < 0 ? "−" : "+"}Rp {Math.round(Math.abs(data.contrib_total) / 1e6).toLocaleString("id-ID")} jt</b></div>
            )}
          </section>
        </div>

        <section className="card">
          <div className="ch">
            <div><h3>Site di {data?.name ?? "…"}</h3><p>{data ? `${data.site_count.toLocaleString("id-ID")} site · diurutkan dari penurunan payload terbesar · klik baris untuk detail` : "memuat…"}</p></div>
            <div className="grow" />
            <div className="seg" role="group" aria-label="Status site" style={{ margin: 0 }}>
              {([["", "Semua"], ["kritis", `Kritis ${counts?.kritis ?? ""}`], ["waspada", `Waspada ${counts?.waspada ?? ""}`], ["normal", `Normal ${counts?.normal ?? ""}`]] as [string, string][]).map(([s, l]) => (
                <button key={s} className={status === s ? "on" : ""} aria-pressed={status === s} onClick={() => { setStatus(s); setPage(1); }}>{l.trim()}</button>
              ))}
            </div>
          </div>
          <div className="rtwrap">
            <table className="rt st">
              <thead><tr><th>Site</th><th>Kecamatan</th><th className="n">Revenue</th><th className="n">MoM</th><th className="n">Payload</th>
                <th className="n sort" aria-sort="ascending">MoM ↑</th><th className="n">Availability</th><th>Status</th></tr></thead>
              <tbody>
                {(data?.sites.rows ?? []).map((s) => {
                  const open = sel === s.site_id;
                  const toggle = () => setSel(open ? null : s.site_id);
                  const dchip = (v: number | null) => v == null ? "–" : (
                    <span className="dchip" style={{ background: v >= 0 ? "#E6F4EA" : "#FDECEC", color: v >= 0 ? "#1F7A3A" : "#C42B2B" }}>{chg(v)}</span>);
                  return [
                    <tr key={s.site_id} className={`row ${open ? "sel" : ""}`} onClick={toggle} tabIndex={0} aria-expanded={open}
                      onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); toggle(); } }}>
                      <td><div className="sid">{s.site_id}<small>{s.site_name || "-"}</small></div></td>
                      <td>{s.kecamatan}</td>
                      <td className="n">{rp(s.revenue)}</td>
                      <td className="n">{dchip(s.revenue_mom)}</td>
                      <td className="n">{vol(s.payload_gb)}</td>
                      <td className="n">{dchip(s.payload_mom)}</td>
                      <td className="n" style={{ color: s.availability != null && s.availability < 99.5 ? "#C42B2B" : "inherit" }}>{s.availability != null ? `${id(s.availability, 2)}%` : "–"}</td>
                      <td><span className={`sev ${SEV[s.status][0]}`}>{SEV[s.status][1]}</span></td>
                    </tr>,
                    open && (
                      <tr key={`${s.site_id}-d`} className="sdet"><td colSpan={8}><div className="in">
                        {(s.detail ?? []).slice(0, 4).map((m) => (
                          <div key={m.label} className="mm"><small>{m.label}</small><b>{m.value}</b><em className={m.tone ?? ""}>{m.note}</em></div>
                        ))}
                        <div className="act">
                          <button className="a1" onClick={() => router.push(`/?q=${encodeURIComponent(`Kenapa site ${s.site_id} (${s.site_name || s.kecamatan}) ${s.payload_mom != null && s.payload_mom < 0 ? "turun" : "berubah"} di ${data?.month_label}? Bandingkan payload, revenue dan availability dengan bulan lalu.`)}`)}>
                            <Icon name="spark" />Tanya Agent soal site ini</button>
                          <button className="a2" onClick={() => router.push(`/map?focus=${encodeURIComponent(s.site_id)}&level=site`)}><Icon name="map" />Lihat di Peta Agent</button>
                          <button className="a2" onClick={() => router.push(`/watchlist?new=1&q=${encodeURIComponent(`Payload site ${s.site_id} turun lebih dari 10% MoM`)}`)}><Icon name="bellplus" />Pantau site ini</button>
                        </div>
                        {s.note && <div className="why"><Icon name="spark" /><span><b>Catatan agent:</b> {s.note}</span></div>}
                      </div></td></tr>
                    ),
                  ];
                })}
              </tbody>
            </table>
          </div>
          {data && (
            <div className="pg">
              <span className="info">Menampilkan {data.sites.total ? (data.sites.page - 1) * data.sites.size + 1 : 0} sampai {Math.min(data.sites.total, data.sites.page * data.sites.size)} dari {data.sites.total.toLocaleString("id-ID")} site</span>
              <div className="grow" />
              <button onClick={() => setPage((p) => p - 1)} disabled={data.sites.page <= 1} aria-label="Halaman sebelumnya">‹</button>
              {pageNums.map((x, i) => x === "…" ? <span key={`g${i}`} className="gap">…</span> : (
                <button key={x} className={x === data.sites.page ? "on" : ""} aria-current={x === data.sites.page ? "page" : undefined} onClick={() => setPage(x)}>{x}</button>
              ))}
              <button onClick={() => setPage((p) => p + 1)} disabled={data.sites.page >= data.sites.pages} aria-label="Halaman berikutnya">›</button>
            </div>
          )}
        </section>
      </div>
    </AppShell>
  );
}

export default function PerformancePage() {
  return <Suspense fallback={null}><PerformanceView /></Suspense>;
}
