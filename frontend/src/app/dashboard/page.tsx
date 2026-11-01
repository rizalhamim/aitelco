"use client";
/* 03 Dashboard v2 (design/mockup-v2/03-dashboard): daily monitoring of Circle Java.
   Numbers come from /api/dashboard/overview, which reads the daily Performance dump
   (Parquet, 05.00 WIB) and falls back to BigQuery; the source is always labelled. */
import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import AppShell, { TopBar } from "../components/shell/AppShell";
import SmartChart, { type ChartSpec } from "../components/charts/SmartChart";
import { Icon } from "../components/v2/Icon";
import { authFetch, getUser } from "@/lib/auth";
import { ago, byFormat, count, gb, idr, MONTHS_FULL, pct } from "@/lib/format";
import { downloadXlsx } from "@/lib/xlsx";
import "./dashboard.css";

type Kpi = {
  key: string; label: string; format: string; icon: string;
  value: number | null; prev: number | null; pct_change: number | null; change_unit?: string;
  spark: (number | null)[]; spark_daily?: number[] | null; spark_daily_labels?: string[] | null;
  spark_weekly?: number[] | null; spark_weekly_labels?: string[] | null;
  target?: number | null; below_sla?: number | null; note_prev_label: string;
};
type Region = {
  region: string; revenue: number; revenue_prev: number; mom_pct: number | null; subs: number; payload_gb: number;
  gross_add: number; availability: number | null; achievement_pct: number | null; share_pct: number | null; spark: number[];
};
type Series = { months: number[]; labels: string[]; series: { name: string; values: number[] }[]; total?: number };
type Overview = {
  month_id: number; month_label: string; prev_label: string; month_labels: string[];
  scope: { circle: string; region: string | null; regions: string[] };
  data_as_of?: string;
  kpis: Kpi[];
  revenue_by_region: Series;
  revenue_by_kabupaten?: Series | null;
  regions: Region[];
  has_targets: boolean;
  summary: { text: string; attention: string[] };
  activity?: { questions_today: number; active_users_today: number; validation_pct?: number | null };
  source?: { kind: "dump" | "bigquery"; label: string; created_at: string | null };
  kabupaten_count?: number | null;
  error?: string;
};
type Alert = { id: number; severity: string; title: string; message: string; created_at: string; scope_label: string | null; metric_label: string | null };
type Pin = { id: string; question: string; title: string; chart: ChartSpec; columns: string[]; rows: Record<string, unknown>[]; pinned_at: string };
type Grain = "daily" | "weekly" | "monthly";

const KPI_LOOK: Record<string, { icon: string; bg: string; fg: string; bar: string; spark: string }> = {
  revenue: { icon: "wallet", bg: "#FCEDD3", fg: "#B7791F", bar: "#0E8579", spark: "#0E8579" },
  subs: { icon: "users", bg: "#E1ECFA", fg: "#2C6CB0", bar: "#22B8C9", spark: "#1597A8" },
  payload: { icon: "db", bg: "#E3F7FA", fg: "#0E6F7C", bar: "#0E8579", spark: "#0E8579" },
  availability: { icon: "tower", bg: "#ECE5FA", fg: "#6A4CB5", bar: "#0E8579", spark: "#0E8579" },
  gross_add: { icon: "users", bg: "#E6F4EA", fg: "#1F7A3A", bar: "#0E8579", spark: "#0E8579" },
};
const REGION_COLOR: [RegExp, string][] = [[/east|timur/i, "#0E8579"], [/central|tengah/i, "#22B8C9"], [/west|barat/i, "#6A4CB5"]];
const EXTRA = ["#FF7A59", "#B7791F", "#C23A5B", "#2C6CB0", "#5E8A12"];
const RANGE_MONTHS = 6;

/** "EAST JAVA" → "East Java"; other names in title case. */
const title = (s: string) => s.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\bDiy\b/, "DIY");
const colorOf = (name: string, i: number) => REGION_COLOR.find(([re]) => re.test(name))?.[1] ?? EXTRA[i % EXTRA.length];
const id1 = (v: number, d = 1) => v.toLocaleString("id-ID", { minimumFractionDigits: d, maximumFractionDigits: d });
/** Target text without a trailing ",0": "86 PB", "Rp 1,90 T", "41,5 jt". */
const short = (fmt: string, v: number) => byFormat(fmt, v).replace(/,0( |$)/, "$1");

const pinKey = () => `dash_pins::${getUser()?.username || "anon"}`;
function readPins(): Pin[] {
  if (typeof window === "undefined") return [];
  try {
    const all = JSON.parse(localStorage.getItem(pinKey()) || "[]");
    return Array.isArray(all) ? all.filter((p: Pin) => p?.chart && Array.isArray(p.rows)) : [];
  } catch {
    return [];
  }
}

/** Summary prose: the first **bold** is the headline move (lime), later ones need attention (coral). */
function HeroText({ text }: { text: string }) {
  let n = 0;
  return <>{text.split(/(\*\*[^*]+\*\*)/g).map((p, i) => {
    if (!p.startsWith("**")) return <span key={i}>{p}</span>;
    const body = p.slice(2, -2);
    return n++ === 0 ? <b key={i}>{body}</b> : <em key={i}>{body}</em>;
  })}</>;
}

function Spark({ values, color, labels, fmt }: { values: number[]; color: string; labels: string[]; fmt: string }) {
  const W = 220, H = 40;
  const gid = `ks${color.slice(1)}${values.length}`;
  if (values.length < 2) return <svg className="kspark" width={W} height={H} aria-hidden="true" />;
  const mn = Math.min(...values), mx = Math.max(...values);
  const X = (i: number) => 2 + ((W - 6) * i) / (values.length - 1);
  const Y = (a: number) => 3 + (H - 8) * (1 - (a - mn) / (mx - mn || 1));
  const d = values.map((a, i) => `${i ? "L" : "M"}${X(i).toFixed(1)} ${Y(a).toFixed(1)}`).join(" ");
  const last = values.length - 1;
  return (
    <svg className="kspark" width={W} height={H} role="img"
      aria-label={`Tren: ${labels[0] ?? ""} ${byFormat(fmt, values[0])} sampai ${labels[last] ?? ""} ${byFormat(fmt, values[last])}`}>
      <defs><linearGradient id={gid} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={color} stopOpacity={0.2} /><stop offset="1" stopColor={color} stopOpacity={0} /></linearGradient></defs>
      <path d={`${d} L${X(last)} ${H} L${X(0)} ${H} Z`} fill={`url(#${gid})`} />
      <path d={d} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={X(last)} cy={Y(values[last])} r={3} fill={color} />
      {values.map((v, i) => <rect key={i} x={X(i) - W / values.length / 2} y={0} width={W / values.length} height={H} fill="transparent"><title>{`${labels[i] ?? ""}: ${byFormat(fmt, v)}`}</title></rect>)}
    </svg>
  );
}

function axisSteps(max: number): number[] {
  if (max <= 0) return [0, 1];
  const raw = max / 3, mag = Math.pow(10, Math.floor(Math.log10(raw))), f = raw / mag;
  const step = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 3 ? 3 : f <= 5 ? 5 : 10) * mag;
  const out = [];
  for (let v = 0; v <= Math.ceil(max / step) * step + step / 2; v += step) out.push(+v.toFixed(6));
  return out;
}

/** Grouped bars (or lines) per month, hover band and tooltip, legend toggles, click to drill down. */
function RegionChart({ data, labels, tips, mode, on, onDrill, initialHover }: {
  data: { name: string; color: string; values: number[] }[]; labels: string[]; tips: string[]; mode: "bar" | "line"; on: boolean[];
  onDrill?: (name: string) => void; initialHover?: number;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [W, setW] = useState(0);
  const [hover, setHover] = useState(initialHover ?? labels.length - 1);
  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setW(Math.floor(el.clientWidth)));
    ro.observe(el);
    setW(Math.floor(el.clientWidth));
    return () => ro.disconnect();
  }, []);
  const H = 330, pl = 46, pr = 6, pt = 10, pb = 26;
  const iw = Math.max(1, W - pl - pr), ih = H - pt - pb;
  const shown = data.map((s, i) => ({ ...s, i })).filter((s) => on[s.i]);
  const max = Math.max(1, ...shown.flatMap((s) => s.values)) / 1e9;
  const ticks = axisSteps(max), top = ticks[ticks.length - 1];
  const y = (v: number) => pt + ih * (1 - v / 1e9 / top);
  const n = labels.length, gw = iw / Math.max(1, n);
  const bw = Math.min(26, (gw - 16) / Math.max(1, shown.length) - 4);
  const h = Math.min(hover, n - 1);
  const tx = pl + gw * (h + 1) + 4, flip = tx + 180 > W;
  const hit = (e: React.MouseEvent) => {
    const r = e.currentTarget.getBoundingClientRect();
    return Math.max(0, Math.min(n - 1, Math.floor((e.clientX - r.left - pl) / gw)));
  };
  return (
    <div className="rchartbox" ref={box}>
      {W > 0 && (
        <svg className="rchart" width={W} height={H} role="img" aria-label={`Revenue ${data.map((s) => s.name).join(", ")} per bulan`}
          onMouseMove={(e) => setHover(hit(e))}
          onClick={(e) => {
            if (!onDrill || mode !== "bar") return;
            const j = hit(e), r = e.currentTarget.getBoundingClientRect(), x = e.clientX - r.left;
            const x0 = pl + gw * j + gw / 2 - (shown.length * (bw + 4) - 4) / 2;
            const k = Math.floor((x - x0) / (bw + 4));
            if (k >= 0 && k < shown.length) onDrill(shown[k].name);
          }}>
          <rect x={pl + gw * h + 4} y={pt} width={Math.max(0, gw - 8)} height={ih} rx={10} fill="#E6F7F5" />
          {ticks.map((v) => (
            <g key={v}>
              <line x1={pl} x2={W - pr} y1={y(v * 1e9)} y2={y(v * 1e9)} stroke={v ? "#ECF3F1" : "#B9C6C3"} strokeWidth={1} />
              <text x={pl - 8} y={y(v * 1e9) + 4} textAnchor="end" fontFamily="Poppins, sans-serif" fontSize={11} fill="#5A6B68">{v.toLocaleString("id-ID")}</text>
            </g>
          ))}
          {mode === "line" && shown.map((s) => {
            const cx = (j: number) => pl + gw * j + gw / 2;
            return (
              <g key={s.name}>
                <path d={s.values.map((v, j) => `${j ? "L" : "M"}${cx(j).toFixed(1)} ${y(v).toFixed(1)}`).join(" ")} fill="none" stroke={s.color} strokeWidth={2.5} strokeLinejoin="round" />
                {s.values.map((v, j) => <circle key={j} cx={cx(j)} cy={y(v)} r={j === h ? 5 : 3} fill={j === h ? s.color : "#fff"} stroke={s.color} strokeWidth={2} />)}
              </g>
            );
          })}
          {labels.map((m, j) => (
            <g key={m + j}>
              {mode === "bar" && shown.map((s, k) => {
                const x0 = pl + gw * j + gw / 2 - (shown.length * (bw + 4) - 4) / 2 + k * (bw + 4);
                return <rect key={s.name} x={x0.toFixed(1)} y={y(s.values[j]).toFixed(1)} width={Math.max(1, bw).toFixed(1)}
                  height={Math.max(0, y(0) - y(s.values[j])).toFixed(1)} rx={5} fill={s.color} />;
              })}
              <text x={pl + gw * j + gw / 2} y={H - 7} textAnchor="middle" fontFamily="Poppins, sans-serif" fontSize={12}
                fontWeight={j === h ? 700 : 400} fill={j === h ? "#0F1F1D" : "#5A6B68"}>{m}</text>
            </g>
          ))}
        </svg>
      )}
      {W > 0 && shown.length > 0 && (
        <div className="ctip" style={{ left: flip ? pl + gw * h - 185 : tx, top: 20 }}>
          <b>{tips[h] ?? labels[h]}</b>
          {shown.map((s) => <div key={s.name}><i style={{ background: s.color }} />{s.name}<span>Rp {id1(s.values[h] / 1e9)} M</span></div>)}
        </div>
      )}
    </div>
  );
}

export default function DashboardPage() {
  const router = useRouter();
  const [region, setRegion] = useState("");
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState("");
  const [nonce, setNonce] = useState(0);
  const [doneKey, setDoneKey] = useState("");
  const forceRefresh = useRef(false);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [regionOpen, setRegionOpen] = useState(false);
  const [pins, setPins] = useState<Pin[]>(readPins);
  const [grain, setGrain] = useState<Grain>("daily");
  const [mode, setMode] = useState<"bar" | "line">("bar");
  const [off, setOff] = useState<string[]>([]);

  const reqKey = `${region}|${nonce}`;
  const loading = doneKey !== reqKey;

  useEffect(() => {
    let alive = true;
    const qs = new URLSearchParams({ months: String(RANGE_MONTHS), region });
    if (forceRefresh.current) qs.set("refresh", "1");
    forceRefresh.current = false;
    authFetch(`/api/dashboard/overview?${qs}`)
      .then(async (res) => {
        const d = await res.json();
        if (!res.ok || d.error) throw new Error(d.error || d.detail || `HTTP ${res.status}`);
        if (alive) { setData(d); setError(""); }
      })
      .catch((e) => { if (alive) setError(e instanceof Error ? e.message : "Gagal memuat"); })
      .finally(() => { if (alive) setDoneKey(reqKey); });
    return () => { alive = false; };
  }, [region, reqKey]);

  useEffect(() => {
    authFetch("/api/watchlist/alerts?status=open&limit=10").then((r) => (r.ok ? r.json() : null))
      .then((d) => d?.alerts && setAlerts(d.alerts)).catch(() => {});
  }, []);

  const reload = () => { forceRefresh.current = true; setNonce((n) => n + 1); };

  function unpin(id: string) {
    const next = pins.filter((p) => p.id !== id);
    setPins(next);
    try {
      const all: Pin[] = JSON.parse(localStorage.getItem(pinKey()) || "[]");
      localStorage.setItem(pinKey(), JSON.stringify(all.filter((p) => p.id !== id)));
    } catch { /* ignore */ }
  }

  const monthName = data ? `${MONTHS_FULL[(data.month_id % 100) - 1]} ${Math.floor(data.month_id / 100)}` : "";
  const monthShort = data?.month_label ?? "";
  const scopeName = region ? title(region) : "Circle Java";
  const src = data?.source;
  const srcTime = src?.created_at ? new Date(src.created_at) : data?.data_as_of ? new Date(data.data_as_of) : null;
  const wib = (d: Date, o: Intl.DateTimeFormatOptions) => d.toLocaleString("id-ID", { ...o, timeZone: "Asia/Jakarta" }).replace(/\./g, ".");
  const updated = srcTime && !Number.isNaN(srcTime.getTime())
    ? `Diperbarui ${wib(srcTime, { day: "numeric", month: "short", year: "numeric" })} ${wib(srcTime, { hour: "2-digit", minute: "2-digit", hour12: false })} WIB`
    : "Data bulan berjalan (MTD)";
  const fromDump = src?.kind === "dump";

  // drill-down: a selected region shows its kabupaten when the dump has them
  const chartSrc = region && data?.revenue_by_kabupaten ? data.revenue_by_kabupaten : data?.revenue_by_region;
  const chartData = useMemo(() => (chartSrc?.series ?? []).map((s, i) => ({
    name: title(s.name), color: chartSrc === data?.revenue_by_region ? colorOf(s.name, i) : [...REGION_COLOR.map((c) => c[1]), ...EXTRA][i % 8], values: s.values,
  })), [chartSrc, data]);
  const chartLabels = (chartSrc?.months ?? []).map((m) => `${["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"][(m % 100) - 1]}`);
  const tipLabels = (chartSrc?.months ?? []).map((m, i) => `${chartLabels[i]} ${Math.floor(m / 100)}`);
  const on = chartData.map((s) => !off.includes(s.name));

  function exportRegions() {
    if (!data) return;
    downloadXlsx(`performa-region-${data.month_id}`,
      ["region", "revenue", "revenue_bulan_lalu", "mom_pct", "pelanggan_rgu90", "payload_gb", "gross_add", "availability_4g", data.has_targets ? "pencapaian_target_pct" : "kontribusi_pct"],
      data.regions.map((r) => ({
        region: title(r.region), revenue: r.revenue, revenue_bulan_lalu: r.revenue_prev, mom_pct: r.mom_pct,
        pelanggan_rgu90: r.subs, payload_gb: r.payload_gb, gross_add: r.gross_add, availability_4g: r.availability,
        [data.has_targets ? "pencapaian_target_pct" : "kontribusi_pct"]: data.has_targets ? r.achievement_pct : r.share_pct,
      })), "Performa region");
  }

  const askDetail = () => router.push(`/?q=${encodeURIComponent(`Jelaskan performa ${scopeName} ${monthName}: apa yang mendorong revenue, payload dan gross add, dan wilayah mana yang perlu perhatian?`)}`);
  const summaryTime = srcTime && !Number.isNaN(srcTime.getTime()) ? `${wib(srcTime, { hour: "2-digit", minute: "2-digit", hour12: false })} WIB` : "";

  return (
    <AppShell>
      <TopBar
        title="Dashboard"
        subtitle={`Monitoring harian ${scopeName}`}
        actions={<>
          <div className="dmenu">
            <button className="chip teal" onClick={() => setRegionOpen((v) => !v)} aria-expanded={regionOpen} aria-haspopup="menu">
              <Icon name="pin" />{region ? title(region) : "Semua region"}
            </button>
            {regionOpen && (
              <div className="menu" role="menu" onMouseLeave={() => setRegionOpen(false)}>
                <button role="menuitemradio" aria-checked={!region} onClick={() => { setRegion(""); setRegionOpen(false); }}>Semua region</button>
                {(data?.scope.regions ?? []).map((r) => (
                  <button key={r} role="menuitemradio" aria-checked={region === r} onClick={() => { setRegion(r); setRegionOpen(false); }}>{title(r)}</button>
                ))}
              </div>
            )}
          </div>
          <span className="chip"><Icon name="cal" />{monthShort || "Bulan ini"}</span>
          <button className="btn-ic" onClick={reload} aria-label="Muat ulang data" disabled={loading}>
            <Icon name="refresh" className={`ic ${loading ? "spin" : ""}`} />
          </button>
        </>}
      />
      <div className="page dash">
        <div className="dhead">
          <div>
            <div className="eb">Monitoring · {fromDump ? "dump Performance" : "BigQuery langsung"}</div>
            <h1>Performa {scopeName}{monthName ? `, ${monthName}` : ""}</h1>
            <p>
              {updated}{fromDump ? " dari dump Performance" : src ? <span className="warn"> dari BigQuery langsung{src.label.includes("terlambat") ? ", dump terlambat" : ""}</span> : ""}
              {data ? ` · ${data.scope.regions.length} region${data.kabupaten_count ? `, ${data.kabupaten_count} kabupaten/kota` : ""}` : " · memuat…"}
            </p>
          </div>
          <div className="grow" />
          <div className="seg" role="group" aria-label="Tren KPI">
            {([["daily", "Harian"], ["weekly", "Mingguan"], ["monthly", "Bulanan"]] as [Grain, string][]).map(([g, l]) => (
              <button key={g} className={grain === g ? "on" : ""} aria-pressed={grain === g} onClick={() => setGrain(g)}>{l}</button>
            ))}
          </div>
        </div>

        {error && !data && (
          <div className="card derr"><Icon name="warn" /> <span>Data dashboard belum bisa dimuat: {error}</span>
            <button className="linkbtn" onClick={reload}>Coba lagi</button></div>
        )}

        <section className="hero" aria-label="Ringkasan agent">
          <div>
            <span className="tag"><Icon name="spark" />Ringkasan agent hari ini{summaryTime ? ` · ${summaryTime}` : ""}</span>
            {data ? <p><HeroText text={data.summary.text} /></p> : <><span className="skel" /><span className="skel" style={{ width: "70%" }} /></>}
            <div className="btns">
              <button className="b1" onClick={askDetail}><Icon name="spark" />Tanya detail</button>
              <Link className="b2" href="/watchlist?tab=alert"><Icon name="bell" />{alerts.length ? `Lihat ${alerts.length} alert` : "Watchlist dan Alert"}</Link>
            </div>
          </div>
          <div className="mini">
            <div><small>Akurasi validasi agent</small><b>{data?.activity?.validation_pct != null ? pct(data.activity.validation_pct) : "–"}</b></div>
            <div><small>Pertanyaan hari ini</small><b>{data?.activity ? data.activity.questions_today.toLocaleString("id-ID") : "–"}</b></div>
          </div>
        </section>

        <div className="krow">
          {(data?.kpis ?? Array.from({ length: 4 }, () => null)).map((k, i) => {
            if (!k) return <div key={i} className="kc skel" />;
            const look = KPI_LOOK[k.key] ?? KPI_LOOK.revenue;
            const pp = k.change_unit === "pp";
            const down = (k.pct_change ?? 0) < 0;
            const series = grain === "daily" && k.spark_daily?.length ? { v: k.spark_daily, l: k.spark_daily_labels ?? [] }
              : grain === "weekly" && k.spark_weekly?.length ? { v: k.spark_weekly, l: k.spark_weekly_labels ?? [] }
              : { v: k.spark.slice(-10).filter((x): x is number => x != null), l: (data?.month_labels ?? []).slice(-10) };
            const tgt = k.key === "availability" ? (k.target ?? 99.5) : k.target ?? null;
            const reach = tgt && k.value != null ? Math.min(100, (k.value / tgt) * 100) : null;
            const note = k.key === "availability"
              ? `Target ${pct(tgt ?? 99.5)}${k.below_sla != null ? ` · ${count(k.below_sla)} site di bawah target` : ""}`
              : [
                  k.key === "subs" && k.value != null && k.prev != null
                    ? `${k.value - k.prev >= 0 ? "+" : "−"}${count(Math.abs(k.value - k.prev))} bulan ini`
                    : `vs ${k.note_prev_label} ${byFormat(k.format, k.prev)}`,
                  tgt ? `target ${short(k.format, tgt)}` : "",
                ].filter(Boolean).join(" · ");
            const barColor = k.key === "availability" ? (k.value != null && k.value >= (tgt ?? 99.5) ? "#2E9E57" : "#F5A623") : down ? "#F5A623" : look.bar;
            return (
              <div key={k.key} className="kc">
                <div className="t">
                  <i style={{ background: look.bg, color: look.fg }}><Icon name={look.icon} /></i>{k.label}
                  {k.pct_change != null && (
                    <span className={`dl ${down ? "dn" : "up"}`}>{down ? "▼" : "▲"} {id1(Math.abs(k.pct_change), pp ? 2 : 1)}{pp ? " pp" : "%"}</span>
                  )}
                </div>
                <div className="v">{byFormat(k.format, k.value)}</div>
                <div className="s">{note}</div>
                {reach != null && <div className="bar" role="meter" aria-valuenow={Math.round(reach)} aria-valuemin={0} aria-valuemax={100} aria-label={`Pencapaian target ${k.label}`}><i style={{ width: `${reach}%`, background: barColor }} /></div>}
                <Spark values={series.v} labels={series.l} fmt={k.format} color={down ? "#C42B2B" : look.spark} />
              </div>
            );
          })}
        </div>

        <div className="row2">
          <section className="card">
            <div className="ch">
              <div>
                <h3>Revenue per {region && data?.revenue_by_kabupaten ? "kabupaten" : "region"}, {RANGE_MONTHS} bulan</h3>
                <p>Rp miliar · arahkan kursor untuk detail{region ? "" : ", klik batang untuk drill-down ke kabupaten"}</p>
              </div>
              <div className="grow" />
              <div className="seg" role="group" aria-label="Bentuk grafik">
                <button className={mode === "bar" ? "on" : ""} aria-pressed={mode === "bar"} onClick={() => setMode("bar")}><Icon name="bars" />Batang</button>
                <button className={mode === "line" ? "on" : ""} aria-pressed={mode === "line"} onClick={() => setMode("line")}><Icon name="line" />Garis</button>
              </div>
            </div>
            <div className="crow">
              <nav className="crumb" aria-label="Cakupan">
                <button onClick={() => setRegion("")}>Circle Java</button><Icon name="chev" /><span>{region ? title(region) : "Semua region"}</span>
              </nav>
              <div className="grow" />
              <div className="legend">
                {chartData.map((s, i) => (
                  <button key={s.name} type="button" className={`lg ${on[i] ? "" : "off"}`} aria-pressed={on[i]}
                    onClick={() => setOff((o) => (o.includes(s.name) ? o.filter((x) => x !== s.name) : on.filter(Boolean).length > 1 ? [...o, s.name] : o))}>
                    <i style={{ background: s.color }} />{s.name}
                  </button>
                ))}
              </div>
            </div>
            {chartData.length > 0
              ? <RegionChart key={chartData.map((s) => s.name).join()} data={chartData} labels={chartLabels} tips={tipLabels} mode={mode} on={on}
                  onDrill={region ? undefined : (name) => {
                    const hit = data?.scope.regions.find((r) => title(r) === name);
                    if (hit) setRegion(hit);
                  }} />
              : <div style={{ height: 330 }} />}
          </section>

          <section className="card alerts" aria-label="Alert aktif">
            <div className="ch"><h3>Alert aktif</h3><div className="grow" />{alerts.length > 0 && <span className="cnt">{alerts.length}</span>}</div>
            {alerts.length === 0 && <p className="alempty">Belum ada alert aktif. Pantau KPI Performance, Site productivity atau Profile wilayah agar agent memberi tahu saat ambang terlampaui.</p>}
            {alerts.slice(0, 3).map((a) => {
              const k = a.severity === "kritis";
              return (
                <Link key={a.id} href="/watchlist?tab=alert" className={`al ${k ? "k" : "w"}`}>
                  <span className="ai"><Icon name={k ? "warn" : "info"} /></span>
                  <b>{a.title}<small>{ago(a.created_at)}</small></b>
                  <p>{a.message}</p>
                  <div className="tg"><span className={`sev ${k ? "k" : "w"}`}>{k ? "Kritis" : "Peringatan"}</span>{[a.scope_label, a.metric_label].filter(Boolean).join(" · ")}</div>
                </Link>
              );
            })}
            {alerts.length > 3 && <Link className="linkbtn" href="/watchlist?tab=alert">Lihat semua {alerts.length} alert</Link>}
            <Link href="/watchlist?new=1" className="addal"><Icon name="plus" />Buat alert baru</Link>
          </section>
        </div>

        <section className="card">
          <div className="ch">
            <div><h3>Performa per region</h3><p>{data?.has_targets ? "Pencapaian terhadap target bulanan" : "Kontribusi tiap region terhadap revenue Circle Java"}</p></div>
            <div className="grow" />
            <Link className="linkbtn" prefetch={false} href={region ? `/performance?region=${encodeURIComponent(region)}` : "/performance"}><Icon name="pulse" />Buka di Performance</Link>
            <button className="linkbtn" onClick={exportRegions} disabled={!data}><Icon name="dl" />Ekspor XLSX</button>
          </div>
          <div className="rtwrap">
            <table className="rt">
              <thead>
                <tr><th>Region</th><th className="n">Revenue</th><th className="n">MoM</th><th className="n">Pelanggan</th><th className="n">Payload</th>
                  <th style={{ width: 300 }}>{data?.has_targets ? "Pencapaian target" : "Kontribusi revenue"}</th></tr>
              </thead>
              <tbody>
                {(data?.regions ?? []).map((r, i) => {
                  const p = data?.has_targets ? r.achievement_pct : r.share_pct;
                  const c = colorOf(r.region, i);
                  const low = data?.has_targets && p != null && p < 95;
                  const barC = low ? "#F5A623" : c;
                  const txtC = !data?.has_targets ? "#0F1F1D" : p != null && p >= 100 ? "#1F7A3A" : low ? "#B7791F" : "#0E6F7C";
                  const up = (r.mom_pct ?? 0) >= 0;
                  return (
                    <tr key={r.region} className={region === r.region ? "hl" : ""} onClick={() => setRegion(region === r.region ? "" : r.region)}
                      tabIndex={0} onKeyDown={(e) => { if (e.key === "Enter") setRegion(region === r.region ? "" : r.region); }}>
                      <td><span className="rn"><i style={{ background: c }} />{title(r.region)}</span></td>
                      <td className="n">{idr(r.revenue)}</td>
                      <td className="n">{r.mom_pct != null && <span className="dchip" style={{ background: up ? "#E6F4EA" : "#FDECEC", color: up ? "#1F7A3A" : "#C42B2B" }}>{up ? "▲" : "▼"} {id1(Math.abs(r.mom_pct))}%</span>}</td>
                      <td className="n">{count(r.subs)}</td>
                      <td className="n">{gb(r.payload_gb)}</td>
                      <td>{p != null ? <div className="prog"><div className="bar"><i style={{ width: `${Math.min(100, p)}%`, background: barC }} /></div><b style={{ color: txtC }}>{pct(p)}</b></div> : "–"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </section>

        {pins.length > 0 && (
          <section className="card">
            <div className="ch"><div><h3>Disematkan dari Tanya Agent</h3><p>{pins.length} grafik · tersimpan di browser ini</p></div></div>
            <div className="pins">
              {pins.map((p) => (
                <div key={p.id} className="pin">
                  <button className="btn-ic unpin" onClick={() => unpin(p.id)} aria-label="Lepas sematan"><Icon name="minus" /></button>
                  <SmartChart spec={{ ...p.chart, title: p.title }} rows={p.rows} height={200}
                    subtitle={`Ditanyakan ${new Date(p.pinned_at).toLocaleDateString("id-ID", { day: "numeric", month: "short" })}: ${p.question.slice(0, 70)}${p.question.length > 70 ? "…" : ""}`} />
                </div>
              ))}
            </div>
          </section>
        )}
      </div>
    </AppShell>
  );
}
