"use client";
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import {
  AlertTriangle, BellRing, ChevronRight, Database, Layers, LocateFixed, Minus, Plus, Radio, Search, Sparkles,
  TrendingDown, TrendingUp, UserPlus, Wallet, X,
} from "lucide-react";
import AppShell from "../components/shell/AppShell";
import JavaMap, { type GeoFC, type MapControl, type MapSite } from "./JavaMap";
import { authFetch } from "@/lib/auth";
import { byFormat, pct } from "@/lib/format";
import { useThemeKey } from "../components/charts/SmartChart";
import "./map.css";

type Metric = "revenue" | "payload" | "availability";
type Item = { kabkot_id: string; kabupaten: string; provinsi: string; region: string; kecamatan: number; value: number | null; change?: number | null };
type Layer = { metric: Metric; label: string; month_label: string; prev_label: string; regions: string[]; items: Item[]; error?: string };
type Kpi = { key: string; label: string; format: string; icon: string; value: number | null; pct_change: number | null; change_unit?: string };
type Detail = {
  kabupaten: string; provinsi: string; region: string; month_label: string; prev_label: string; kecamatan: number; site_count: number;
  status: "kritis" | "perhatian" | "normal"; kpis: Kpi[]; sites: (MapSite & { site_name?: string })[];
  explanation: { text: string; actions: string[] }; error?: string;
};

const METRICS: { key: Metric; label: string }[] = [
  { key: "revenue", label: "Revenue MoM" }, { key: "payload", label: "Payload" }, { key: "availability", label: "Availability" },
];
// Diverging scale: red (down) → pale → teal (up). Same steps as the legend.
const CHANGE_STEPS = [-8, -3, 0, 2, 5];
const AVAIL_STEPS = [97, 98.5, 99, 99.5, 99.8];
const PALETTE = ["#E04848", "#F09595", "#F8D2D2", "#C9EEE9", "#5BCEC3", "#15A697"];
const ICONS: Record<string, typeof Wallet> = { wallet: Wallet, database: Database, radio: Radio, "user-plus": UserPlus };
const TONES: Record<string, string> = { wallet: "amber", database: "violet", radio: "teal", "user-plus": "green" };
const STATUS = { kritis: "Kritis", perhatian: "Perhatian", normal: "Normal" } as const;

const title = (s: string) => s.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\bDiy\b/, "DIY").replace(/^Kabupaten /, "Kab. ");
const shortName = (s: string) => title(s).replace(/^Kab\. /, "");
const core = (s: string) => s.toUpperCase().replace(/^(KABUPATEN|KAB\.?)\s+/, "").trim();

function colorFor(metric: Metric, v: number | null | undefined): string | undefined {
  if (v == null || !Number.isFinite(v)) return undefined;
  const steps = metric === "availability" ? AVAIL_STEPS : CHANGE_STEPS;
  const i = steps.findIndex((s) => v < s);
  return PALETTE[i === -1 ? PALETTE.length - 1 : i];
}
function fmtValue(metric: Metric, v: number | null | undefined): string {
  if (v == null) return "–";
  if (metric === "availability") return pct(v, 2);
  return `${v > 0 ? "+" : v < 0 ? "−" : ""}${Math.abs(v).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
}

let geoPromise: Promise<GeoFC> | null = null;
function loadGeo(): Promise<GeoFC> {
  geoPromise ??= fetch("/api/geo/shapes/kabupaten?scope=java", { cache: "force-cache" }).then((r) => {
    if (!r.ok) throw new Error(`Peta belum tersedia (HTTP ${r.status})`);
    return r.json();
  }).catch((e) => { geoPromise = null; throw e; });
  return geoPromise;
}

function Delta({ v, unit }: { v: number | null; unit?: string }) {
  if (v == null) return null;
  const up = v >= 0;
  return (
    <span className={`ui-delta ${up ? "up" : "down"}`}>
      {up ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
      {Math.abs(v).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: unit === "pp" ? 2 : 1 })}{unit === "pp" ? " pp" : "%"}
    </span>
  );
}

function MapInner() {
  const router = useRouter();
  const params = useSearchParams();
  const themeKey = useThemeKey();
  const [, themeAttr, , systemDark] = themeKey.split("|");
  const dark = themeAttr === "dark" || (themeAttr !== "light" && systemDark === "true");
  const [geo, setGeo] = useState<GeoFC | null>(null);
  const [geoErr, setGeoErr] = useState("");
  const [metric, setMetric] = useState<Metric>("revenue");
  const [layer, setLayer] = useState<Layer | null>(null);
  const [layerFor, setLayerFor] = useState<Metric | null>(null);
  const [region, setRegion] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [detailFor, setDetailFor] = useState<string | null>(null);
  const [showSites, setShowSites] = useState(true);
  const [hoverSite, setHoverSite] = useState<MapSite | null>(null);
  const [search, setSearch] = useState("");
  const [panelOpen, setPanelOpen] = useState(true);
  const control = useRef<MapControl | null>(null);
  const [pending, setPending] = useState(() => ({ focus: params.get("focus"), level: params.get("level") }));
  const onControl = useCallback((c: MapControl) => { control.current = c; }, []);

  useEffect(() => { loadGeo().then(setGeo).catch((e) => setGeoErr(e.message)); }, []);

  useEffect(() => {
    let alive = true;
    authFetch(`/api/map/kabupaten?metric=${metric}`).then((r) => r.json())
      .then((d) => { if (alive) { setLayer(d); setLayerFor(metric); } })
      .catch(() => { if (alive) setLayerFor(metric); });
    return () => { alive = false; };
  }, [metric]);

  const byId = useMemo(() => Object.fromEntries((layer?.items ?? []).map((i) => [i.kabkot_id, i])), [layer]);

  // Links from Tanya Agent: /map?focus=<name>&level=<column>.
  if (layer && pending.focus) {
    const { focus, level } = pending;
    setPending({ focus: null, level: null });
    const f = core(focus);
    if (level && /region/i.test(level)) {
      const r = layer.regions.find((x) => x.toUpperCase() === focus.toUpperCase());
      if (r) setRegion(r);
    } else {
      const hit = layer.items.find((i) => core(i.kabupaten) === f) ?? layer.items.find((i) => core(i.kabupaten).includes(f));
      if (hit) { setSelected(hit.kabkot_id); setRegion(hit.region); }
    }
  }

  const sel = selected ? byId[selected] : null;
  useEffect(() => {
    if (!sel) return;
    let alive = true;
    const key = sel.kabkot_id;
    authFetch(`/api/map/kabupaten/detail?kabupaten=${encodeURIComponent(sel.kabupaten)}&provinsi=${encodeURIComponent(sel.provinsi)}`)
      .then((r) => r.json()).then((d) => { if (alive) { setDetail(d); setDetailFor(key); } })
      .catch(() => { if (alive) setDetailFor(key); });
    return () => { alive = false; };
  }, [sel]);
  const det = detail && detailFor === selected && !detail.error ? detail : null;
  const detLoading = !!selected && detailFor !== selected;

  const colors = useMemo(() => {
    const out: Record<string, string> = {};
    for (const it of layer?.items ?? []) {
      if (region && it.region !== region) continue;
      const c = colorFor(metric, it.value);
      if (c) out[it.kabkot_id] = c;
    }
    return out;
  }, [layer, metric, region]);
  const labels = useMemo(() => {
    // Names only once zoomed into a region; all of Java is too dense to label.
    const out: Record<string, string> = {};
    if (!region) return out;
    for (const it of layer?.items ?? []) if (it.region === region) out[it.kabkot_id] = shortName(it.kabupaten);
    return out;
  }, [layer, region]);
  const focus = useMemo(() => {
    if (selected) return [selected];
    if (region) return (layer?.items ?? []).filter((i) => i.region === region).map((i) => i.kabkot_id);
    return [];
  }, [selected, region, layer]);

  const ranked = useMemo(() => {
    const list = (layer?.items ?? []).filter((i) => i.value != null && (!region || i.region === region));
    const q = search.trim().toLowerCase();
    const filtered = q ? list.filter((i) => i.kabupaten.toLowerCase().includes(q)) : list;
    return [...filtered].sort((a, b) => (a.value ?? 0) - (b.value ?? 0));
  }, [layer, region, search]);

  function selectKab(id: string) {
    const it = byId[id];
    if (!it) return;
    setSelected(id);
    setRegion(it.region);
    setPanelOpen(true);
  }
  function tooltip(id: string) {
    const it = byId[id];
    if (!it) return "";
    const extra = metric === "availability" && it.change != null ? ` (${it.change >= 0 ? "+" : "−"}${Math.abs(it.change).toLocaleString("id-ID", { maximumFractionDigits: 2 })} pp)` : "";
    return `<b>${title(it.kabupaten)}</b><br/><span style="color:#C0EDE8">${layer?.label ?? ""} ${fmtValue(metric, it.value)}${extra}</span>`;
  }

  const legendTicks = metric === "availability" ? ["97%", "98,5%", "99%", "99,5%", "99,8%"] : ["-8%", "-3%", "0", "+2%", "+5%"];
  const legendTitle = metric === "availability" ? "Availability 4G per kabupaten" : `${metric === "revenue" ? "Revenue" : "Payload"} MoM per kabupaten`;
  const loading = layerFor !== metric || !geo;

  return (
    <AppShell mainClassName="pm-main">
      <div className="pm">
        <div className="pm-mapwrap">
          {geo && layer && !layer.error && (
            <JavaMap geo={geo} colors={colors} labels={labels} tooltip={tooltip} selected={selected} focus={focus}
              sites={det?.sites ?? []} showSites={showSites} onSelect={selectKab} onSiteHover={setHoverSite} onControl={onControl} dark={dark} />
          )}
          {(loading && !geoErr) && <div className="pm-loading"><span className="ui-skel" /> Memuat peta…</div>}
          {(geoErr || layer?.error) && (
            <div className="pm-loading pm-err"><AlertTriangle size={18} /> {geoErr || `Data peta belum bisa dimuat: ${layer?.error}`}</div>
          )}

          <div className="pm-float pm-scope">
            <nav className="pm-crumb" aria-label="Cakupan">
              <button className="ui-link" onClick={() => { setRegion(""); setSelected(null); }}>Jawa</button>
              {region && <><ChevronRight size={14} /><button className={selected ? "ui-link" : "pm-crumb-cur"} onClick={() => setSelected(null)}>{title(region)}</button></>}
              {sel && <><ChevronRight size={14} /><b>{title(sel.kabupaten)}</b></>}
            </nav>
            <div className="pm-metrics" role="group" aria-label="Metrik peta">
              {METRICS.map((m) => (
                <button key={m.key} className={`ui-chip ${metric === m.key ? "teal" : ""}`} aria-pressed={metric === m.key} onClick={() => setMetric(m.key)}>{m.label}</button>
              ))}
            </div>
          </div>

          <div className="pm-float pm-controls" role="group" aria-label="Kontrol peta">
            <button onClick={() => control.current?.zoomBy(1.5)} aria-label="Perbesar"><Plus size={18} /></button>
            <button onClick={() => control.current?.zoomBy(1 / 1.5)} aria-label="Perkecil"><Minus size={18} /></button>
            <button onClick={() => { setSelected(null); setRegion(""); control.current?.reset(); }} aria-label="Kembali ke seluruh Jawa"><LocateFixed size={18} /></button>
            <button onClick={() => setShowSites((v) => !v)} aria-pressed={showSites} aria-label={showSites ? "Sembunyikan site" : "Tampilkan site"} className={showSites ? "on" : ""}><Layers size={18} /></button>
          </div>

          {hoverSite && (
            <div className="pm-float pm-sitetip" role="status">
              <b>{hoverSite.site_id}{hoverSite.kecamatan ? ` · ${hoverSite.kecamatan}` : ""}</b>
              <span>
                {hoverSite.availability != null ? `Availability ${pct(hoverSite.availability)}` : ""}
                {hoverSite.payload_pct != null ? ` · payload ${hoverSite.payload_pct > 0 ? "+" : ""}${Math.round(hoverSite.payload_pct)}%` : ""}
              </span>
            </div>
          )}

          <div className="pm-float pm-legend">
            <b>{legendTitle}</b>
            <div className="pm-legend-bar">{PALETTE.map((c) => <span key={c} style={{ background: c }} />)}</div>
            <div className="pm-legend-ticks">{legendTicks.map((t) => <span key={t}>{t}</span>)}</div>
            {det && det.sites.length > 0 && (
              <div className="pm-legend-sites">
                <span><i className="bad" /> Site bermasalah</span><span><i /> Site normal</span>
              </div>
            )}
          </div>

          <div className="pm-float pm-mini" aria-hidden="true">
            <span>Jawa{region ? ` · ${title(region)} dipilih` : " · semua region"}</span>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/illustrations/java_glow_dots.svg" alt="" />
          </div>
        </div>

        <aside className={`pm-panel ${panelOpen ? "open" : ""}`} aria-label="Detail wilayah">
          {!sel ? (
            <>
              <div className="pm-panel-head">
                <div>
                  <h1>{region ? title(region) : "Jawa"}</h1>
                  <p>{layer?.month_label ? `${layer.label} · ${layer.month_label} vs ${layer.prev_label}` : "Memuat data…"}</p>
                </div>
              </div>
              <label className="pm-search">
                <Search size={18} aria-hidden="true" />
                <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Cari kabupaten/kota…" aria-label="Cari kabupaten atau kota" />
              </label>
              <h2 className="pm-h2">{metric === "availability" ? "Availability terendah" : "Paling turun"}</h2>
              <ul className="pm-rank">
                {ranked.slice(0, 6).map((i) => (
                  <li key={i.kabkot_id}>
                    <button onClick={() => selectKab(i.kabkot_id)}>
                      <span className="pm-swatch" style={{ background: colorFor(metric, i.value) }} />
                      <span className="pm-rank-name"><b>{title(i.kabupaten)}</b><small>{title(i.region)}</small></span>
                      <span className={`pm-rank-val ${(metric === "availability" ? (i.value ?? 100) < 99 : (i.value ?? 0) < 0) ? "bad" : ""}`}>{fmtValue(metric, i.value)}</span>
                    </button>
                  </li>
                ))}
                {!loading && ranked.length === 0 && <li className="pm-empty">Tidak ada kabupaten yang cocok.</li>}
              </ul>
              <h2 className="pm-h2">{metric === "availability" ? "Availability tertinggi" : "Paling naik"}</h2>
              <ul className="pm-rank">
                {ranked.slice(-3).reverse().map((i) => (
                  <li key={i.kabkot_id}>
                    <button onClick={() => selectKab(i.kabkot_id)}>
                      <span className="pm-swatch" style={{ background: colorFor(metric, i.value) }} />
                      <span className="pm-rank-name"><b>{title(i.kabupaten)}</b><small>{title(i.region)}</small></span>
                      <span className="pm-rank-val">{fmtValue(metric, i.value)}</span>
                    </button>
                  </li>
                ))}
              </ul>
              <p className="pm-hint">Klik kabupaten di peta untuk melihat KPI, penjelasan agent dan site yang terdampak.{" "}
                <Link href="/map/query" className="ui-link">Map Query</Link>
              </p>
            </>
          ) : (
            <>
              <div className="pm-panel-head">
                <div>
                  <h1>{title(sel.kabupaten)} {det && <span className={`pm-status ${det.status}`}>{STATUS[det.status]}</span>}</h1>
                  <p>{title(sel.region)} · {det ? `${det.kecamatan} kecamatan · ${det.site_count} site` : `${sel.kecamatan} kecamatan`}</p>
                </div>
                <button className="ui-iconbtn ghost" onClick={() => setSelected(null)} aria-label="Tutup detail"><X size={20} /></button>
              </div>

              <div className="pm-kpis">
                {(det?.kpis ?? Array.from({ length: 4 }, () => null)).map((k, i) => {
                  if (!k) return <div key={i} className="pm-kpi"><span className="ui-skel" style={{ height: 88 }} /></div>;
                  const Icon = ICONS[k.icon] ?? Wallet;
                  return (
                    <div key={k.key} className="pm-kpi">
                      <div className="pm-kpi-top">
                        <span className="ui-tile" data-tone={TONES[k.icon] ?? "teal"}><Icon size={20} strokeWidth={1.7} /></span>
                        <Delta v={k.pct_change} unit={k.change_unit} />
                      </div>
                      <span className="pm-kpi-label">{k.label}</span>
                      <b className="pm-kpi-value">{k.format === "percent" ? pct(k.value) : byFormat(k.format, k.value)}</b>
                      <span className="pm-kpi-note">vs {det?.prev_label}</span>
                    </div>
                  );
                })}
              </div>

              {det && (
                <div className="pm-explain">
                  <span><Sparkles size={16} /> Penjelasan agent</span>
                  <p>{det.explanation.text}</p>
                  {det.explanation.actions.length > 0 && <ul>{det.explanation.actions.map((a) => <li key={a}>{a}</li>)}</ul>}
                </div>
              )}
              {detLoading && <div className="pm-explain"><span className="ui-skel" style={{ height: 90 }} /></div>}

              {det && det.sites.length > 0 && (
                <>
                  <h2 className="pm-h2">{det.sites.some((s) => s.status === "bad") ? "Site terdampak" : "Site di wilayah ini"}</h2>
                  <ul className="pm-sites">
                    {det.sites.slice(0, 6).map((s, i) => (
                      <li key={s.site_id} className={i === 0 && s.status === "bad" ? "hl" : ""}
                        onMouseEnter={() => setHoverSite(s)} onMouseLeave={() => setHoverSite(null)}>
                        <span className={`pm-dot ${s.status}`} />
                        <Link href={`/site?id=${encodeURIComponent(s.site_id)}`} className="pm-site-id">{s.site_id}</Link>
                        <span className="pm-site-kec">{s.kecamatan || s.site_name || "–"}</span>
                        <span className={`pm-site-val ${(s.payload_pct ?? 0) < 0 ? "bad" : ""}`}>
                          {s.payload_pct != null ? `${s.payload_pct > 0 ? "+" : "−"}${Math.abs(s.payload_pct).toLocaleString("id-ID", { maximumFractionDigits: 1 })}%` : s.availability != null ? pct(s.availability) : "–"}
                        </span>
                      </li>
                    ))}
                  </ul>
                </>
              )}

              <div className="pm-actions">
                <button className="ui-btn lg primary" onClick={() => router.push(`/?q=${encodeURIComponent(`Kenapa performa ${title(sel.kabupaten)} ${det?.month_label ?? ""} berubah? Site dan kecamatan mana yang paling berpengaruh, dan apa rekomendasinya?`)}`)}>
                  <Sparkles size={20} strokeWidth={1.7} /> Tanya agent
                </button>
                <button className="ui-btn lg" onClick={() => router.push(`/watchlist?new=1&q=${encodeURIComponent(`${metric === "availability" ? "availability" : metric} ${title(sel.kabupaten)} turun`)}`)}>
                  <BellRing size={20} strokeWidth={1.7} /> Buat alert
                </button>
              </div>
            </>
          )}
        </aside>
      </div>
    </AppShell>
  );
}

export default function MapPage() {
  return <Suspense fallback={<div className="ui-boot" />}><MapInner /></Suspense>;
}
