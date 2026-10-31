"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  AlertCircle, AlertTriangle, Bell, ChevronDown, ChevronRight, CircleCheck, Database, FileSpreadsheet, Plus,
  Radio, RefreshCw, Sparkles, TrendingDown, TrendingUp, UserPlus, Users, Wallet, X,
} from "lucide-react";
import AppShell from "../components/shell/AppShell";
import SmartChart, { usePrefs, type ChartSpec } from "../components/charts/SmartChart";
import Sparkline from "../components/ui/Sparkline";
import { authFetch, getUser } from "@/lib/auth";
import { ago, byFormat, count, gb, idr, MONTHS_FULL, pct } from "@/lib/format";
import { downloadXlsx } from "@/lib/xlsx";
import "./dashboard.css";

type Kpi = {
  key: string; label: string; format: string; icon: string;
  value: number | null; prev: number | null; pct_change: number | null; change_unit?: string;
  spark: (number | null)[]; target?: number; below_sla?: number | null; note_prev_label: string;
};
type Region = {
  region: string; revenue: number; revenue_prev: number; mom_pct: number | null; subs: number; payload_gb: number;
  gross_add: number; availability: number | null; achievement_pct: number | null; share_pct: number | null; spark: number[];
};
type Overview = {
  month_id: number; month_label: string; prev_label: string; month_labels: string[];
  scope: { circle: string; region: string | null; regions: string[] };
  data_as_of?: string;
  kpis: Kpi[];
  revenue_by_region: { months: number[]; labels: string[]; series: { name: string; values: number[] }[] };
  regions: Region[];
  has_targets: boolean;
  summary: { text: string; attention: string[] };
  activity?: { questions_today: number; active_users_today: number };
  error?: string;
};
type Alert = { id: number; severity: string; title: string; message: string; created_at: string; scope_label: string | null; metric_label: string | null };
type Pin = { id: string; question: string; title: string; chart: ChartSpec; columns: string[]; rows: Record<string, unknown>[]; pinned_at: string };

const ICONS: Record<string, typeof Wallet> = { wallet: Wallet, users: Users, database: Database, radio: Radio, "user-plus": UserPlus };
const TONES: Record<string, string> = { wallet: "amber", users: "blue", database: "violet", radio: "teal", "user-plus": "green" };
const RANGES = [{ m: 3, label: "3 bulan" }, { m: 6, label: "6 bulan" }, { m: 12, label: "12 bulan" }];

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

const title = (s: string) => s.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\bDiy\b/, "DIY");

function Bold({ text }: { text: string }) {
  return <>{text.split(/(\*\*[^*]+\*\*)/g).map((p, i) => (p.startsWith("**") ? <b key={i}>{p.slice(2, -2)}</b> : <span key={i}>{p}</span>))}</>;
}

function Delta({ v, unit = "%" }: { v: number | null; unit?: string }) {
  if (v == null) return null;
  const up = v >= 0;
  return (
    <span className={`ui-delta ${up ? "up" : "down"}`}>
      {up ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
      {Math.abs(v).toLocaleString("id-ID", { minimumFractionDigits: unit === "pp" ? 2 : 1, maximumFractionDigits: unit === "pp" ? 2 : 1 })}{unit === "pp" ? " pp" : "%"}
    </span>
  );
}

function Ring({ value }: { value: number }) {
  const r = 15, c = 2 * Math.PI * r;
  const ok = value >= 100, warn = value >= 95;
  const color = ok ? "var(--ds-teal600)" : warn ? "var(--ds-teal400)" : "var(--ds-warning)";
  return (
    <svg width="36" height="36" viewBox="0 0 36 36" aria-hidden="true">
      <circle cx="18" cy="18" r={r} fill="none" stroke="var(--ds-surface-muted)" strokeWidth="3" />
      <circle cx="18" cy="18" r={r} fill="none" stroke={color} strokeWidth="3" strokeLinecap="round"
        strokeDasharray={`${(Math.min(value, 100) / 100) * c} ${c}`} transform="rotate(-90 18 18)" />
    </svg>
  );
}

export default function DashboardPage() {
  const router = useRouter();
  const prefs = usePrefs();
  const [months, setMonths] = useState(6);
  const [region, setRegion] = useState("");
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState("");
  const [nonce, setNonce] = useState(0);
  const [doneKey, setDoneKey] = useState("");
  const forceRefresh = useRef(false);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [regionOpen, setRegionOpen] = useState(false);
  const [pins, setPins] = useState<Pin[]>(readPins);

  const reqKey = `${months}|${region}|${nonce}`;
  const loading = doneKey !== reqKey;

  useEffect(() => {
    let alive = true;
    const qs = new URLSearchParams({ months: String(months), region });
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
  }, [months, region, reqKey]);

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
  const scopeName = region ? title(region) : "Jawa";
  const updated = data?.data_as_of ? new Date(data.data_as_of) : null;
  const updatedLabel = updated && !Number.isNaN(updated.getTime())
    ? `Diperbarui ${updated.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit", timeZone: "Asia/Jakarta" })} WIB`
    : "Data bulan berjalan (MTD)";

  const barRows = useMemo(() => {
    if (!data) return [];
    const out: Record<string, unknown>[] = [];
    data.revenue_by_region.labels.forEach((m, i) => {
      data.revenue_by_region.series.forEach((s) => out.push({ bulan: m, region: title(s.name), revenue: s.values[i] }));
    });
    return out;
  }, [data]);
  const barSpec: ChartSpec = {
    type: "bar", x: "bulan", y: ["revenue"], y2: [], series_by: "region", label: null,
    formats: { revenue: "currency" }, sort: null, top_n: null, map_key: "region",
    alternatives: ["stacked_bar", "line"], title: `Revenue per region, ${months} bulan`,
  };

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

  return (
    <AppShell>
      <div className="ui-page dash">
        <header className="ui-page-head dash-head">
          <div className="ui-page-title">
            <span className="ui-eyebrow">Monitoring · sumber BigQuery</span>
            <h1 className="ui-h1">Performa {scopeName}{monthName ? `, ${monthName}` : ""}</h1>
            <p className="ui-sub">{updatedLabel} · {data ? `${data.scope.regions.length} region` : "memuat…"} · MTD vs bulan lalu</p>
          </div>
          <div className="dash-actions">
            <div className="ui-seg dash-range" role="group" aria-label="Rentang grafik">
              {RANGES.map((r) => (
                <button key={r.m} aria-pressed={months === r.m} onClick={() => setMonths(r.m)}>{r.label}</button>
              ))}
            </div>
            <div className="dash-region">
              <button className="ui-btn lg" onClick={() => setRegionOpen((v) => !v)} aria-expanded={regionOpen}>
                <ChevronDown size={20} strokeWidth={1.8} /> {region ? title(region) : "Semua region"}
              </button>
              {regionOpen && (
                <div className="ui-popover dash-region-menu" role="menu" onMouseLeave={() => setRegionOpen(false)}>
                  <button role="menuitemradio" aria-checked={!region} onClick={() => { setRegion(""); setRegionOpen(false); }}>Semua region</button>
                  {(data?.scope.regions ?? []).map((r) => (
                    <button key={r} role="menuitemradio" aria-checked={region === r} onClick={() => { setRegion(r); setRegionOpen(false); }}>{title(r)}</button>
                  ))}
                </div>
              )}
            </div>
            <button className="ui-iconbtn dash-refresh" onClick={() => reload()} aria-label="Muat ulang data" disabled={loading}>
              <RefreshCw size={20} className={loading ? "spin" : ""} />
            </button>
          </div>
        </header>

        {error && !data && (
          <div className="ui-card ui-card-pad dash-error">
            <AlertTriangle size={20} /> <span>Data dashboard belum bisa dimuat: {error}</span>
            <button className="ui-btn" onClick={() => reload()}>Coba lagi</button>
          </div>
        )}

        <section className="dash-hero">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="dash-hero-still" src="/media/still_wide.jpg" alt="" />
          <div className="dash-hero-fade" />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="dash-hero-city" src="/illustrations/iso_city.svg" alt="" />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="dash-hero-orb" src="/illustrations/hero_ai_orb.svg" alt="" />
          <div className="dash-hero-text">
            <span className="dash-glass-pill"><Sparkles size={14} /> Ringkasan agent · {data ? data.month_label : "memuat"}</span>
            {data ? <p><Bold text={data.summary.text} /></p> : <p className="dash-hero-skel"><span className="ui-skel" /><span className="ui-skel" /></p>}
            <div className="dash-hero-actions">
              <button className="ui-btn lg tint" onClick={askDetail}><Sparkles size={20} strokeWidth={1.7} /> Tanya detail</button>
              <Link className="ui-btn lg dash-glass-btn" href="/watchlist"><Bell size={18} /> {alerts.length ? `Lihat ${alerts.length} alert` : "Watchlist"}</Link>
            </div>
          </div>
          <div className="dash-hero-stats">
            <div className="dash-glass-stat"><span>Pertanyaan hari ini</span><b>{data?.activity ? data.activity.questions_today.toLocaleString("id-ID") : "–"}</b></div>
            <div className="dash-glass-stat"><span>Pengguna aktif hari ini</span><b>{data?.activity ? data.activity.active_users_today.toLocaleString("id-ID") : "–"}</b></div>
          </div>
        </section>

        <section className="dash-kpis">
          {(data?.kpis ?? Array.from({ length: 4 }, () => null)).map((k, i) => {
            if (!k) return <div key={i} className="ui-kpi card dash-kpi"><span className="ui-skel" style={{ height: 36, width: 36 }} /><span className="ui-skel" style={{ height: 14, width: "50%" }} /><span className="ui-skel" style={{ height: 30, width: "70%" }} /><span className="ui-skel" style={{ height: 44 }} /></div>;
            const Icon = ICONS[k.icon] ?? Wallet;
            const down = (k.pct_change ?? 0) < 0;
            const note = k.key === "availability"
              ? `Target ${pct(k.target ?? 99.5)}${k.below_sla ? ` · ${k.below_sla} site < SLA` : ""}`
              : k.key === "subs" && k.value != null && k.prev != null
                ? `${k.value - k.prev >= 0 ? "+" : "−"}${count(Math.abs(k.value - k.prev))} bulan ini`
                : `vs ${k.note_prev_label} ${byFormat(k.format, k.prev)}`;
            return (
              <div key={k.key} className={`ui-kpi card dash-kpi ${data?.summary.attention.includes(k.key) ? "attn" : ""}`}>
                <div className="ui-kpi-top">
                  <span className="ui-tile dash-kpi-tile" data-tone={TONES[k.icon] ?? "teal"}><Icon size={k.icon === "wallet" ? 18 : 22} strokeWidth={1.8} /></span>
                  <Delta v={k.pct_change} unit={k.change_unit} />
                </div>
                <span className="ui-kpi-label">{k.label}</span>
                <span className="ui-kpi-value lg">{byFormat(k.format, k.value)}</span>
                <span className="ui-kpi-note">{note}</span>
                <Sparkline values={k.spark} labels={data?.month_labels} color={down ? "var(--ds-danger-solid)" : "var(--ds-teal600)"}
                  format={(v) => byFormat(k.format, v)} reference={prefs.targetLine && k.key === "availability" ? k.target ?? null : null} />
              </div>
            );
          })}
        </section>

        <section className="dash-row">
          {data && barRows.length > 0 ? (
            <SmartChart
              className="dash-card dash-bars"
              spec={barSpec}
              rows={barRows}
              height={300}
              subtitle="Rupiah · klik batang untuk fokus ke region"
              onDrill={(_, value) => {
                const hit = data.scope.regions.find((r) => title(r) === value || r === value);
                if (hit) setRegion(hit);
              }}
              toolbar={
                <div className="dash-drill">
                  <nav className="dash-crumb" aria-label="Cakupan">
                    <button className="ui-link" onClick={() => setRegion("")}>Jawa</button>
                    <ChevronRight size={14} />
                    <b>{region ? title(region) : "Semua region"}</b>
                  </nav>
                  {prefs.animation && <span className="dash-badge">Animasi transisi aktif</span>}
                </div>
              }
            />
          ) : (
            <div className="ui-card dash-card dash-bars dash-skel-card"><span className="ui-skel" /></div>
          )}

          <aside className="ui-card dash-card dash-alerts">
            <div className="dash-alerts-head">
              <h2 className="ui-card-title">Alert aktif</h2>
              {alerts.length > 0 && <span className="ui-badge">{alerts.length}</span>}
            </div>
            {alerts.length === 0 && (
              <div className="ui-empty dash-alerts-empty">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src="/illustrations/empty_state_alert.svg" alt="" />
                <span>Belum ada alert aktif. Pantau KPI penting agar agent memberi tahu saat ambang terlampaui.</span>
              </div>
            )}
            {alerts.slice(0, 3).map((a) => (
              <Link key={a.id} href="/watchlist?tab=alert" className={`dash-alert ${a.severity}`}>
                <span className="dash-alert-ico">{a.severity === "kritis" ? <AlertTriangle size={18} /> : <AlertCircle size={18} />}</span>
                <span className="dash-alert-body">
                  <span className="dash-alert-title"><b>{a.title}</b><time>{ago(a.created_at)}</time></span>
                  <span className="dash-alert-msg">{a.message}</span>
                  <span className="dash-alert-meta">
                    <span className={`dash-sev ${a.severity}`}>{a.severity === "kritis" ? "Kritis" : "Peringatan"}</span>
                    {[a.scope_label, a.metric_label].filter(Boolean).join(" · ")}
                  </span>
                </span>
              </Link>
            ))}
            <Link href="/watchlist?new=1" className="dash-newalert"><Plus size={18} /> Buat alert baru</Link>
          </aside>
        </section>

        <section className="ui-card dash-table">
          <div className="dash-table-head">
            <div>
              <h2 className="ui-card-title">Performa per region</h2>
              <p className="ui-card-sub">{data?.has_targets ? "Pencapaian terhadap target bulanan" : "Kontribusi tiap region terhadap revenue Jawa"}</p>
            </div>
            <button className="ui-btn" onClick={exportRegions} disabled={!data}><FileSpreadsheet size={20} strokeWidth={1.6} /> Export XLSX</button>
          </div>
          <div className="ui-table-wrap">
            <table className="ui-table">
              <thead>
                <tr>
                  <th>Region</th><th>Revenue</th><th>MoM</th><th>Pelanggan</th><th>Payload</th>
                  <th>{data?.has_targets ? "Pencapaian target" : "Kontribusi revenue"}</th>
                </tr>
              </thead>
              <tbody>
                {(data?.regions ?? []).map((r) => {
                  const p = data?.has_targets ? r.achievement_pct : r.share_pct;
                  const tone = data?.has_targets ? (p != null && p >= 100 ? "ok" : p != null && p >= 95 ? "mid" : "low") : "ok";
                  return (
                    <tr key={r.region} className={region === r.region ? "hl" : ""} onClick={() => setRegion(region === r.region ? "" : r.region)} style={{ cursor: "pointer" }}>
                      <td>
                        <span className="dash-region-cell">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <span className="dash-minimap"><img src="/illustrations/java_glow_dots.svg" alt="" /></span>
                          {title(r.region)}
                        </span>
                      </td>
                      <td>{idr(r.revenue)}</td>
                      <td><Delta v={r.mom_pct} /></td>
                      <td>{count(r.subs)}</td>
                      <td>{gb(r.payload_gb)}</td>
                      <td>
                        {p != null ? (
                          <span className={`dash-target ${tone}`}>
                            {data?.has_targets ? <Ring value={p} /> : null}
                            <span className="dash-bar"><span style={{ width: `${Math.min(100, p)}%` }} /></span>
                            <b>{pct(p)}</b>
                          </span>
                        ) : "–"}
                      </td>
                    </tr>
                  );
                })}
                {!data && Array.from({ length: 3 }, (_, i) => (
                  <tr key={i}><td colSpan={6}><span className="ui-skel" style={{ display: "block", height: 20 }} /></td></tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>

        {pins.length > 0 && (
          <section className="dash-pins">
            <div className="dash-pins-head">
              <h2 className="ui-card-title">Disematkan dari Tanya Agent</h2>
              <span className="ui-card-sub">{pins.length} grafik · tersimpan di browser ini</span>
            </div>
            <div className="dash-pins-grid">
              {pins.map((p) => (
                <div key={p.id} className="dash-pin">
                  <button className="ui-iconbtn ghost dash-unpin" onClick={() => unpin(p.id)} aria-label="Lepas sematan"><X size={16} /></button>
                  <SmartChart spec={{ ...p.chart, title: p.title }} rows={p.rows} height={200}
                    subtitle={`Ditanyakan ${new Date(p.pinned_at).toLocaleDateString("id-ID", { day: "numeric", month: "short" })}: ${p.question.slice(0, 70)}${p.question.length > 70 ? "…" : ""}`} />
                </div>
              ))}
            </div>
          </section>
        )}

        {data && !error && (
          <p className="dash-foot"><CircleCheck size={14} /> Angka MTD dari rham_mkt_highlevel_mtd dan availability 4G dari rham_avail_stat_territory_monthly.</p>
        )}
      </div>
    </AppShell>
  );
}
