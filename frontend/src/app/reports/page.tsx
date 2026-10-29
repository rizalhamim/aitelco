"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  CalendarDays, ChevronLeft, ChevronRight, Download, FileBarChart, FileSpreadsheet, FileText, MoreHorizontal,
  Pin, PinOff, Plus, Search, Send, Sparkles, Trash2, TrendingDown, TrendingUp, ZoomIn, ZoomOut,
} from "lucide-react";
import AppShell from "../components/shell/AppShell";
import PageHero from "../components/ui/PageHero";
import SmartChart, { type ChartSpec } from "../components/charts/SmartChart";
import ResultTable from "../components/ResultTable";
import ScheduleDialog, { type Schedule } from "./ScheduleDialog";
import { authFetch, getUser } from "@/lib/auth";
import { byFormat, count, gb, idr, MONTHS_FULL, pct } from "@/lib/format";
import { downloadXlsx } from "@/lib/xlsx";
import "../watchlist/watchlist.css";
import "./reports.css";

type Kpi = { key: string; label: string; format: string; value: number | null; pct_change: number | null; change_unit?: string; target?: number; below_sla?: number | null };
type Region = { region: string; revenue: number; mom_pct: number | null; subs: number; payload_gb: number; availability: number | null; achievement_pct: number | null; share_pct: number | null };
type Overview = {
  month_id: number; month_label: string; prev_label: string; data_as_of?: string;
  scope: { region: string | null; regions: string[] };
  kpis: Kpi[]; regions: Region[]; has_targets: boolean;
  revenue_by_region: { labels: string[]; series: { name: string; values: number[] }[] };
  summary: { text: string }; error?: string;
};
type PinItem = { id: string; question: string; title: string; chart: ChartSpec; columns: string[]; rows: Record<string, unknown>[]; pinned_at: string };
type Run = { id: number; title: string; kind: string; region: string; recipients: number; status: string; created_at: string };
type Kind = "bulanan" | "mingguan" | "adhoc" | "analis";
type Item = { id: string; kind: Kind; title: string; meta: string; region?: string; pin?: PinItem; href?: string };
type Filter = "semua" | "bulanan" | "mingguan" | "adhoc" | "pinned";

const KIND: Record<Kind, { label: string; tone: string; icon: typeof FileText }> = {
  bulanan: { label: "Bulanan", tone: "teal", icon: FileText },
  mingguan: { label: "Mingguan", tone: "blue", icon: FileText },
  adhoc: { label: "Ad-hoc", tone: "violet", icon: FileSpreadsheet },
  analis: { label: "Analis", tone: "amber", icon: FileBarChart },
};
const FILTERS: { key: Filter; label: string }[] = [
  { key: "semua", label: "Semua" }, { key: "bulanan", label: "Bulanan" }, { key: "mingguan", label: "Mingguan" },
  { key: "adhoc", label: "Ad-hoc dari agent" }, { key: "pinned", label: "Disematkan" },
];

const title = (s: string) => s.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\bDiy\b/, "DIY");
const shortDate = (iso: string) => new Date(iso).toLocaleDateString("id-ID", { day: "numeric", month: "short" });
const userKey = (k: string) => `${k}::${getUser()?.username || "anon"}`;

function readJson<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try { return JSON.parse(localStorage.getItem(userKey(key)) || "null") ?? fallback; } catch { return fallback; }
}

function Bold({ text }: { text: string }) {
  return <>{text.split(/(\*\*[^*]+\*\*)/g).map((p, i) => (p.startsWith("**") ? <b key={i}>{p.slice(2, -2)}</b> : <span key={i}>{p}</span>))}</>;
}

function Delta({ v, unit }: { v: number | null; unit?: string }) {
  if (v == null) return null;
  const up = v >= 0;
  return (
    <span className={`rp-delta ${up ? "up" : "down"}`}>
      {up ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
      {Math.abs(v).toLocaleString("id-ID", { minimumFractionDigits: unit === "pp" ? 2 : 1, maximumFractionDigits: unit === "pp" ? 2 : 1 })}{unit === "pp" ? " pp" : "%"}
    </span>
  );
}

function PageHead({ eyebrow, heading }: { eyebrow: string; heading: string }) {
  return (
    <header className="rp-doc-head">
      <div><span className="rp-doc-eyebrow">{eyebrow}</span><h2>{heading}</h2></div>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/brand/logo-ioh-color.png" alt="Indosat Ooredoo Hutchison" height={30} />
    </header>
  );
}

/** Pages of the live performance report built from the dashboard overview. */
function liveReportPages(ov: Overview, kind: Kind): React.ReactNode[] {
  const scope = ov.scope.region ? title(ov.scope.region) : "Region Jawa";
  const month = `${MONTHS_FULL[(ov.month_id % 100) - 1]} ${Math.floor(ov.month_id / 100)}`;
  const eyebrow = kind === "mingguan" ? "Laporan performa mingguan" : "Laporan performa bulanan";
  const rows: Record<string, unknown>[] = [];
  ov.revenue_by_region.labels.forEach((m, i) => ov.revenue_by_region.series.forEach((s) => rows.push({ bulan: m, region: title(s.name), revenue: s.values[i] })));
  const spec: ChartSpec = {
    type: "bar", x: "bulan", y: ["revenue"], y2: [], series_by: "region", label: null, formats: { revenue: "currency" },
    sort: null, top_n: null, map_key: null, alternatives: ["stacked_bar", "line"], title: "Revenue per region",
  };
  const avail = ov.kpis.find((k) => k.key === "availability");
  return [
    <>
      <PageHead eyebrow={eyebrow} heading={`${scope} · ${month}`} />
      <div className="rp-doc-kpis">
        {ov.kpis.filter((k) => k.key !== "availability").slice(0, 3).map((k) => (
          <div key={k.key} className="rp-doc-kpi">
            <span>{k.key === "subs" ? "Pelanggan" : k.key === "payload" ? "Payload" : k.label}</span>
            <b>{byFormat(k.format, k.value)}</b>
            <Delta v={k.pct_change} unit={k.change_unit} />
          </div>
        ))}
      </div>
      <SmartChart spec={spec} rows={rows} height={190} bare subtitle="" className="rp-doc-chart" />
      <div className="rp-doc-summary">
        <span><Sparkles size={14} /> Ringkasan oleh agent</span>
        <p><Bold text={ov.summary.text} /></p>
      </div>
    </>,
    <>
      <PageHead eyebrow={eyebrow} heading="Performa per region" />
      <table className="rp-doc-table">
        <thead><tr><th>Region</th><th>Revenue</th><th>MoM</th><th>Pelanggan</th><th>Payload</th><th>{ov.has_targets ? "Target" : "Kontribusi"}</th></tr></thead>
        <tbody>
          {ov.regions.map((r) => (
            <tr key={r.region}>
              <td>{title(r.region)}</td><td>{idr(r.revenue)}</td><td><Delta v={r.mom_pct} /></td>
              <td>{count(r.subs)}</td><td>{gb(r.payload_gb)}</td><td>{pct(ov.has_targets ? r.achievement_pct : r.share_pct)}</td>
            </tr>
          ))}
        </tbody>
      </table>
      {avail && (
        <div className="rp-doc-note">
          <b>Site availability 4G {pct(avail.value, 2)}</b>
          <span>
            Target {pct(avail.target ?? 99.5)} · {avail.pct_change != null ? `${avail.pct_change >= 0 ? "naik" : "turun"} ${Math.abs(avail.pct_change).toLocaleString("id-ID", { maximumFractionDigits: 2 })} pp dari ${ov.prev_label}` : ""}
            {avail.below_sla ? ` · ${avail.below_sla} site di bawah SLA 99%` : ""}
          </span>
        </div>
      )}
      <p className="rp-doc-foot">
        Angka month-to-date dibandingkan periode yang sama bulan lalu. Sumber: rham_mkt_highlevel_mtd dan rham_avail_stat_territory_monthly (BigQuery).
      </p>
    </>,
  ];
}

function pinPages(p: PinItem): React.ReactNode[] {
  return [
    <>
      <PageHead eyebrow="Hasil ad-hoc dari agent" heading={p.title} />
      <p className="rp-doc-q"><Sparkles size={14} /> {p.question}</p>
      {p.chart && p.chart.type !== "none" && <SmartChart spec={p.chart} rows={p.rows} height={230} bare subtitle="" className="rp-doc-chart" />}
      <p className="rp-doc-foot">Disematkan {new Date(p.pinned_at).toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" })} · {p.rows.length} baris data</p>
    </>,
    <>
      <PageHead eyebrow="Hasil ad-hoc dari agent" heading="Data" />
      <ResultTable columns={p.columns} rows={p.rows} spec={p.chart} initialRows={14} />
    </>,
  ];
}

export default function ReportsPage() {
  const router = useRouter();
  const [overview, setOverview] = useState<Overview | null>(null);
  const [regions, setRegions] = useState<string[]>([]);
  const [runs, setRuns] = useState<Run[]>([]);
  const [schedules, setSchedules] = useState<Schedule[]>([]);
  const [pins] = useState<PinItem[]>(() => readJson<PinItem[]>("dash_pins", []).filter((p) => p?.rows));
  const [stars, setStars] = useState<string[]>(() => readJson<string[]>("report_stars", ["live:"]));
  const [filter, setFilter] = useState<Filter>("semua");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState("live:");
  const [page, setPage] = useState(0);
  const [zoom, setZoom] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);
  const [schedDialog, setSchedDialog] = useState<{ edit?: Schedule | null } | null>(null);
  const [createMenu, setCreateMenu] = useState(false);
  const [itemMenu, setItemMenu] = useState<string | null>(null);
  const [sending, setSending] = useState<Schedule | null>(null);
  const [notice, setNotice] = useState("");
  const [version, setVersion] = useState(0);
  const docRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    authFetch("/api/report-schedules").then((r) => (r.ok ? r.json() : null)).then((d) => d?.schedules && setSchedules(d.schedules)).catch(() => {});
    authFetch("/api/report-schedules/runs").then((r) => (r.ok ? r.json() : null)).then((d) => d?.runs && setRuns(d.runs)).catch(() => {});
  }, [version]);

  const items = useMemo<Item[]>(() => {
    const month = overview?.month_label ?? "";
    const live: Item[] = [{ id: "live:", kind: "bulanan", title: "Performa Bulanan Region Jawa", meta: `PDF · 2 hlm${month ? ` · ${month}` : ""}`, region: "" }];
    regions.forEach((r) => live.push({ id: `live:${r}`, kind: "bulanan", title: `Performa Bulanan ${title(r)}`, meta: `PDF · 2 hlm${month ? ` · ${month}` : ""}`, region: r }));
    const sent: Item[] = runs.map((r) => ({
      id: `run:${r.id}`, kind: r.kind === "bulanan" ? "bulanan" : "mingguan", title: r.title, region: r.region,
      meta: `${r.status === "gagal" ? "Gagal terkirim" : `Email · ${r.recipients} penerima`} · ${shortDate(r.created_at)}`,
    }));
    const adhoc: Item[] = pins.map((p) => ({ id: `pin:${p.id}`, kind: "adhoc", title: p.title, meta: `XLSX · ${p.rows.length} baris · ${shortDate(p.pinned_at)}`, pin: p }));
    const outlook: Item = { id: "outlook", kind: "analis", title: "Performance Outlook", meta: "Komprehensif · data revenue · benchmark", href: "/reports/outlook" };
    return [...live.slice(0, 1), ...sent, ...adhoc, ...live.slice(1), outlook];
  }, [overview?.month_label, regions, runs, pins]);

  const shown = items.filter((i) => {
    if (query.trim() && !i.title.toLowerCase().includes(query.trim().toLowerCase())) return false;
    if (filter === "pinned") return stars.includes(i.id);
    if (filter === "adhoc") return i.kind === "adhoc";
    if (filter === "semua") return true;
    return i.kind === filter;
  });
  const current = items.find((i) => i.id === selected) ?? items[0];
  const region = current?.pin ? null : current?.region ?? "";

  // Live report data for the selected region.
  const [loadedFor, setLoadedFor] = useState<string | null>(null);
  useEffect(() => {
    if (region == null) return;
    let alive = true;
    authFetch(`/api/dashboard/overview?region=${encodeURIComponent(region)}&months=6`).then((r) => r.json())
      .then((d) => {
        if (!alive) return;
        setOverview(d.error ? null : d);
        if (!d.error && !region) setRegions(d.scope.regions);
        setLoadedFor(region);
      }).catch(() => { if (alive) setLoadedFor(region); });
    return () => { alive = false; };
  }, [region]);

  const pages = useMemo(() => {
    if (current?.pin) return pinPages(current.pin);
    if (overview && loadedFor === region && current?.kind !== "analis") return liveReportPages(overview, current.kind);
    return [];
  }, [current, overview, loadedFor, region]);
  const loading = !current?.pin && loadedFor !== region;

  function select(id: string) {
    const it = items.find((i) => i.id === id);
    if (it?.href) { router.push(it.href); return; }
    setSelected(id);
    setPage(0);
    setMobileOpen(true);
    docRef.current?.scrollTo({ top: 0 });
  }
  function toggleStar(id: string) {
    const next = stars.includes(id) ? stars.filter((s) => s !== id) : [...stars, id];
    setStars(next);
    try { localStorage.setItem(userKey("report_stars"), JSON.stringify(next)); } catch { /* ignore */ }
  }
  function goPage(n: number) {
    const p = Math.max(0, Math.min(pages.length - 1, n));
    setPage(p);
    const el = docRef.current?.querySelectorAll<HTMLElement>(".rp-sheet")[p];
    if (el && docRef.current) docRef.current.scrollTo({ top: el.offsetTop - 24, behavior: "smooth" });
  }
  function exportXlsx() {
    if (current?.pin) {
      downloadXlsx(`bizplan-${current.pin.title.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 40)}`, current.pin.columns, current.pin.rows, "Hasil");
    } else if (overview) {
      downloadXlsx(`laporan-performa-${overview.scope.region ? overview.scope.region.toLowerCase().replace(/[^a-z0-9]+/g, "-") : "jawa"}-${overview.month_id}`,
        ["region", "revenue", "mom_pct", "pelanggan_rgu90", "payload_gb", "availability_4g", overview.has_targets ? "pencapaian_target_pct" : "kontribusi_pct"],
        overview.regions.map((r) => ({
          region: title(r.region), revenue: r.revenue, mom_pct: r.mom_pct, pelanggan_rgu90: r.subs, payload_gb: r.payload_gb,
          availability_4g: r.availability, [overview.has_targets ? "pencapaian_target_pct" : "kontribusi_pct"]: overview.has_targets ? r.achievement_pct : r.share_pct,
        })), "Performa region");
    }
  }
  async function sendNow(s: Schedule) {
    setSending(s);
    setNotice("");
    try {
      const r = await authFetch(`/api/report-schedules/${s.id}/send-now`, { method: "POST" });
      const d = await r.json();
      setNotice(r.ok ? `Laporan "${s.name}" terkirim ke ${d.sent} penerima.` : d.detail || "Laporan gagal dikirim.");
    } catch {
      setNotice("Laporan gagal dikirim.");
    }
    setSending(null);
    setVersion((v) => v + 1);
  }
  async function patchSchedule(s: Schedule, body: Partial<Schedule>) {
    setSchedules((cur) => cur.map((x) => (x.id === s.id ? { ...x, ...body } : x)));
    await authFetch(`/api/report-schedules/${s.id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }).catch(() => {});
  }
  async function deleteSchedule(s: Schedule) {
    if (!confirm(`Hapus jadwal "${s.name}"?`)) return;
    await authFetch(`/api/report-schedules/${s.id}`, { method: "DELETE" }).catch(() => {});
    setVersion((v) => v + 1);
  }

  useEffect(() => {
    if (!createMenu && !itemMenu) return;
    const close = () => { setCreateMenu(false); setItemMenu(null); };
    document.addEventListener("click", close);
    return () => document.removeEventListener("click", close);
  }, [createMenu, itemMenu]);

  const docTitle = current?.title ?? "Laporan";
  const docSub = current?.pin ? `Agent · ${new Date(current.pin.pinned_at).toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" })}`
    : overview ? `Agent · data ${overview.month_label}` : "Agent";

  return (
    <AppShell>
      <div className="ui-page rp">
        <PageHero
          icon="/illustrations/duo_report.svg"
          art="/illustrations/iso_dashboard.svg"
          eyebrow="Pustaka laporan"
          title="Laporan"
          sub="Laporan terjadwal dan hasil percakapan agent, siap diekspor PDF atau XLSX."
          actions={
            <>
              <label className="rp-search">
                <Search size={18} aria-hidden="true" />
                <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Cari laporan…" aria-label="Cari laporan" />
              </label>
              <div className="rp-create">
                <button className="ph-cta" onClick={(e) => { e.stopPropagation(); setCreateMenu((v) => !v); }} aria-expanded={createMenu}>
                  <Plus size={18} /> Buat laporan
                </button>
                {createMenu && (
                  <div className="ui-popover rp-create-menu" role="menu">
                    <button role="menuitem" onClick={() => router.push("/?new=1")}><Sparkles size={16} /> Minta agent (ad-hoc)</button>
                    <button role="menuitem" onClick={() => setSchedDialog({})}><CalendarDays size={16} /> Jadwalkan otomatis</button>
                    <Link role="menuitem" href="/reports/outlook"><FileBarChart size={16} /> Performance Outlook</Link>
                  </div>
                )}
              </div>
            </>
          }
        />

        <div className="rp-filters" role="group" aria-label="Filter laporan">
          {FILTERS.map((f) => (
            <button key={f.key} className={`ui-chip ${filter === f.key ? "teal" : ""}`} aria-pressed={filter === f.key} onClick={() => setFilter(f.key)}>{f.label}</button>
          ))}
        </div>

        <div className="rp-body">
          <div className="rp-list">
            {shown.length === 0 && (
              <div className="ui-card ui-empty rp-empty">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src="/illustrations/empty_reports.svg" alt="" />
                <span>
                  {filter === "pinned" ? "Belum ada laporan yang disematkan. Klik ikon pin di sebuah laporan."
                    : filter === "adhoc" ? "Belum ada hasil dari agent. Klik \"Pin ke dashboard\" di jawaban Tanya Agent."
                    : filter === "mingguan" ? "Belum ada laporan mingguan. Atur jadwal agar agent mengirimkannya otomatis."
                    : "Tidak ada laporan yang cocok."}
                </span>
              </div>
            )}
            {shown.map((it) => {
              const k = KIND[it.kind];
              const Icon = k.icon;
              const starred = stars.includes(it.id);
              return (
                <div key={it.id} className={`rp-item ${it.id === current?.id ? "active" : ""}`}>
                  <button className="rp-item-main" onClick={() => select(it.id)}>
                    <span className="ui-tile rp-item-ico" data-tone={k.tone}><Icon size={22} strokeWidth={1.6} /></span>
                    <span className="rp-item-text">
                      <b>{it.title}</b>
                      <span><span className={`rp-kind ${k.tone}`}>{k.label}</span>{it.meta}</span>
                    </span>
                  </button>
                  {it.kind !== "analis" && (
                    starred || it.id === current?.id ? (
                      <button className={`ui-iconbtn ghost sm rp-star ${starred ? "on" : ""}`} onClick={() => toggleStar(it.id)} aria-label={starred ? "Lepas sematan" : "Sematkan"} aria-pressed={starred}>
                        {starred ? <Pin size={18} /> : <PinOff size={18} />}
                      </button>
                    ) : (
                      <div className="rp-item-more">
                        <button className="ui-iconbtn ghost sm" aria-label="Aksi" onClick={(e) => { e.stopPropagation(); setItemMenu(itemMenu === it.id ? null : it.id); }}><MoreHorizontal size={18} /></button>
                        {itemMenu === it.id && (
                          <div className="ui-popover rp-item-menu" role="menu">
                            <button role="menuitem" onClick={() => select(it.id)}><FileText size={16} /> Buka</button>
                            <button role="menuitem" onClick={() => toggleStar(it.id)}><Pin size={16} /> Sematkan</button>
                          </div>
                        )}
                      </div>
                    )
                  )}
                </div>
              );
            })}

            {sending && (
              <div className="rp-item rp-progress">
                <span className="rp-ring" aria-hidden="true"><span /></span>
                <span className="rp-item-text">
                  <b>Agent menyusun: {sending.name}</b>
                  <span className="rp-bar"><span /></span>
                </span>
              </div>
            )}
            {notice && <p className="rp-notice" role="status">{notice}</p>}

            <div className="rp-schedule">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/illustrations/iso_dashboard.svg" alt="" />
              <div>
                <b>Jadwalkan laporan otomatis</b>
                <p>{schedules.length
                  ? `${schedules.filter((s) => s.active).length} jadwal aktif. Agent menyusun dan mengirim laporan lewat email.`
                  : "Agent menyusun dan mengirim laporan performa tiap Senin 08.00, atau sesuai jadwal Anda."}</p>
                {schedules.map((s) => (
                  <div key={s.id} className="rp-sched">
                    <button className="ui-switch wl-switch" role="switch" aria-checked={s.active} aria-label={`Aktifkan ${s.name}`} onClick={() => patchSchedule(s, { active: !s.active })} />
                    <span className="rp-sched-text"><b>{s.name}</b><small>{s.description} · {s.recipients.length} penerima</small></span>
                    <button className="ui-iconbtn ghost sm" title="Kirim sekarang" aria-label={`Kirim ${s.name} sekarang`} onClick={() => sendNow(s)} disabled={!!sending}><Send size={16} /></button>
                    <button className="ui-iconbtn ghost sm" title="Ubah" aria-label={`Ubah ${s.name}`} onClick={() => setSchedDialog({ edit: s })}><CalendarDays size={16} /></button>
                    <button className="ui-iconbtn ghost sm" title="Hapus" aria-label={`Hapus ${s.name}`} onClick={() => deleteSchedule(s)}><Trash2 size={16} /></button>
                  </div>
                ))}
                <button className="ui-btn lg" onClick={() => setSchedDialog({})}><CalendarDays size={20} strokeWidth={1.6} /> Atur jadwal</button>
              </div>
            </div>
          </div>

          <section className={`rp-preview ${mobileOpen ? "open" : ""}`} aria-label="Pratinjau laporan">
            <div className="rp-toolbar">
              <button className="ui-iconbtn ghost rp-back" onClick={() => setMobileOpen(false)} aria-label="Kembali ke daftar"><ChevronLeft size={20} /></button>
              <div className="rp-toolbar-title"><b>{docTitle}</b><span>{docSub}</span></div>
              <div className="rp-pager">
                <button onClick={() => goPage(page - 1)} disabled={page === 0} aria-label="Halaman sebelumnya"><ChevronLeft size={16} /></button>
                <span>{pages.length ? page + 1 : 0} / {pages.length}</span>
                <button onClick={() => goPage(page + 1)} disabled={page >= pages.length - 1} aria-label="Halaman berikutnya"><ChevronRight size={16} /></button>
              </div>
              <button className="ui-iconbtn rp-zoom" onClick={() => setZoom((z) => !z)} aria-label={zoom ? "Perkecil" : "Perbesar"} aria-pressed={zoom}>
                {zoom ? <ZoomOut size={20} /> : <ZoomIn size={20} />}
              </button>
              <button className="ui-btn lg" onClick={exportXlsx} disabled={!pages.length}><FileSpreadsheet size={20} strokeWidth={1.6} /> XLSX</button>
              <button className="ui-btn lg primary" onClick={() => window.print()} disabled={!pages.length}><Download size={20} /> Export PDF</button>
            </div>
            <div className={`rp-canvas ${zoom ? "zoomed" : ""}`} ref={docRef}
              onScroll={(e) => {
                const sheets = e.currentTarget.querySelectorAll<HTMLElement>(".rp-sheet");
                const top = e.currentTarget.scrollTop + 120;
                let p = 0;
                sheets.forEach((s, i) => { if (s.offsetTop <= top) p = i; });
                if (p !== page) setPage(p);
              }}>
              <div className="rp-doc">
                {loading && (
                  <article className="rp-sheet">
                    <span className="ui-skel" style={{ height: 28, width: "60%" }} />
                    <span className="ui-skel" style={{ height: 80 }} />
                    <span className="ui-skel" style={{ height: 200 }} />
                    <span className="ui-skel" style={{ height: 70 }} />
                  </article>
                )}
                {!loading && pages.length === 0 && (
                  <article className="rp-sheet rp-sheet-empty"><span>Data laporan belum tersedia. Coba muat ulang beberapa saat lagi.</span></article>
                )}
                {!loading && pages.map((p, i) => (
                  <article key={`${current?.id}-${i}`} className="rp-sheet">
                    {p}
                    <span className="rp-sheet-no">{i + 1} / {pages.length}</span>
                  </article>
                ))}
              </div>
            </div>
          </section>
        </div>
      </div>

      {schedDialog && (
        <ScheduleDialog regions={regions} edit={schedDialog.edit} onClose={() => setSchedDialog(null)}
          onSaved={() => { setSchedDialog(null); setVersion((v) => v + 1); }} />
      )}
    </AppShell>
  );
}
