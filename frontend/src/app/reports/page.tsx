"use client";
import { useEffect, useState, useCallback, useRef, Fragment } from "react";
import { useRouter } from "next/navigation";
import { authFetch, isLoggedIn } from "@/lib/auth";

const IOH = {
  teal: "#15A697", tealDeep: "var(--ioh-teal-deep)", tealDark: "#0A6A5F",
  yellow: "#F5A623",
  ink: "var(--ioh-ink)", mute: "var(--ioh-mute)", rule: "var(--ioh-rule)",
  panel: "var(--ioh-panel)", white: "var(--ioh-white)",
  zebra: "var(--ioh-zebra)",
  pos: "#13A58F", neg: "#E26A6A",
  varTint: "var(--ioh-var-tint)", growTint: "var(--ioh-grow-tint)",
  band_ioh: "#15A697", band_im3: "#F5A623", band_3id: "#EB008B",
} as const;

/* ─── types ─── */
type Metric = { code: string; name: string; unit: string; category: string };
type Category = { name: string; metrics: Metric[] };
type Row = Record<string, number | string | null>;
type Slabs = { total: number; declining: number; growing: number; decline_gt5: number; decline_3_5: number; decline_1_3: number; decline_0_1: number; growth_0_1: number; growth_1_3: number; growth_3_5: number; growth_gt5: number };
type RankSet = { columns: string[]; decline: Row[]; growth: Row[] };
type SnapDeck = { circle: { columns: string[]; rows: Row[] }; region: { columns: string[]; rows: Row[] }; branch: { columns: string[]; rows: Row[] }; microcluster: RankSet; kabkota: RankSet; kecamatan: RankSet; counts: Record<string, number> };
type Snapshot = {
  metric: Metric; scope: { circle: string; month_id: number; data_as_of?: string };
  display: { divisor: number; unit: string };
  totals: { mtd: number; lmtd: number; llmtd: number; mtd_im3: number; mtd_3id: number; abs_change: number; pct_change: number | null; trend: string };
  best: { name: string; var: number; pct: number } | null;
  worst: { name: string; var: number; pct: number } | null;
  slabs: { kecamatan: Slabs; branch: Slabs }; deck?: SnapDeck; error?: string;
};
type BrandVals = { llmtd: number; lmtd: number; mtd: number; var_mom: number; growth_mom_pct: number | null; ytd?: number; lytd?: number; var_yoy?: number; growth_yoy_pct?: number | null };
type CompMetric = { code: string; name: string; unit: string; network: boolean; computed?: boolean; snapshot?: boolean; ioh: BrandVals; im3: BrandVals; "3id": BrandVals };
type HierNode = { label: string; cells: (number | null)[]; children?: HierNode[] };
type CompSection = { title: string; group: string | null; cumulative_yoy?: boolean; layout: string; unit?: string; month_used?: number | null; columns?: string[]; metrics?: CompMetric[]; rows?: ({ actor?: string; label?: string; value?: number | null; cells?: (number | null)[]; children?: HierNode[] })[] };
type Comprehensive = { scope: { circle: string; month_id: number; data_as_of?: string }; sections: CompSection[]; error?: string };
type DRNode = { ioh: number; im3: number; "3id": number; lmtd: number; llmtd: number; var_mom: number; growth_mom_pct: number | null; ytd: number; lytd: number; var_yoy: number; growth_yoy_pct: number | null; contrib_pct?: number | null };
type DRDetail = DRNode & { detail: string };
type DRChannel = DRNode & { channel: string; details?: DRDetail[] };
type DRChunk = { name: string; headline: DRNode; channels: DRChannel[] };
type DRRatios = { atl_pct: number | null; btl_pct: number | null; atl_vs_btl: number | null; channel_pct: Record<string, number | null> };
type DRSlab = DRNode & { slab: string; hit: number };
type DataRev = { scope: { circle: string; month_id: number; data_as_of?: string }; unit: string; chunks: DRChunk[]; ratios?: DRRatios; price_slabs: DRSlab[]; price_slab_scopes?: Record<string, DRSlabScope>; error?: string };
type PDSlab = DRNode & { slab: string };
type PDDims = { quota: PDSlab[]; validity: PDSlab[]; top_products?: PDProduct[] };
type PDProduct = DRNode & { product: string; family: string; hit: number };
type DRSlabScope = { label: string; channel_group?: string; slabs: DRSlab[]; details?: Record<string, DRSlab[]> };
type PDSlabScope = { label: string; quota: PDSlab[]; validity: PDSlab[]; details?: Record<string, PDDims>; top_products?: PDProduct[] };
type ProductDemand = {
  scope: { circle: string; month_id: number; channel_scope: string; data_as_of?: string }; unit: string;
  quota_labels: string[]; validity_labels: string[];
  revenue_matrix: number[][]; growth_matrix: (number | null)[][];
  top_3: { rank: number; quota: string; validity: string; value: number }[];
  top_products: { product: string; family: string; rev: number; hit: number }[];
  slab_scopes?: Record<string, PDSlabScope>; error?: string;
};
type Benchmark = {
  scope: { circle: string; filter_type: string; filter_value: string; level_used: string; name_used: string };
  fb_benchmark: { month_prefix: string; dl_speed_im3_4g: number; latency_im3_4g: number; signal_im3_4g: number; dl_speed_tri_4g: number; latency_tri_4g: number; signal_tri_4g: number; dl_speed_tsel_4g: number; latency_tsel_4g: number; signal_tsel_4g: number; dl_speed_xl_4g: number; latency_xl_4g: number; signal_xl_4g: number; dl_speed_sf_4g: number; latency_sf_4g: number; signal_sf_4g: number }[];
  availability: { month_id: number; mean_avg_avail_pct_2g: number; mean_avg_avail_pct_4g: number; mean_avg_avail_pct_5g: number; min_avail_pct_2g: number; min_avail_pct_4g: number; min_avail_pct_5g: number; sites_below_sla99_4g: number; sites_below_sla95_4g: number; total_down_day_events_4g: number; total_downtime_hrs_4g: number }[];
  error?: string;
};
type MarketInsight = {
  scope: { circle: string; filter_type: string; filter_value: string; data_as_of: string };
  panels: {
    title: string;
    kind: string;
    months: string[];
    actors: {
      actor: string;
      history: { value: number | null; growth: number | null }[];
    }[];
  }[];
  error?: string;
};




const CIRCLES = ["JAVA", "KALISUMAPA", "JAKARTA RAYA", "SUMATERA"];
const SCOPE_LEVELS = [
  { key: "region", label: "Region" }, { key: "area", label: "Area" },
  { key: "district", label: "District" },
  { key: "kabkota", label: "Kab/Kota" }, { key: "kecamatan", label: "Kecamatan" },
];
// FTTH uses its own territory vocabulary (region_25 / province / city / kecamatan),
// not the IM3 ref_territory hierarchy.
const FTTH_SCOPE_LEVELS = [
  { key: "ftth_region", label: "Region" }, { key: "ftth_province", label: "Province" },
  { key: "ftth_kabkota", label: "Kab/Kota" }, { key: "ftth_kecamatan", label: "Kecamatan" },
];

const CHILD_LEVEL: Record<string, string> = { all: "region", circle: "region", region: "area", area: "district", district: "kecamatan", branch: "district", microcluster: "kecamatan", kabkota: "kecamatan" };
const BAND_BG: Record<string, string> = { ioh: IOH.band_ioh, im3: IOH.band_im3, "3id": IOH.band_3id };
const BAND_FG: Record<string, string> = { ioh: "#fff", im3: "#161616", "3id": "#fff" };

/* ─── helpers ─── */
function fmtNum(v: number | null | undefined, divisor = 1, dec = 1): string {
  if (v === null || v === undefined || isNaN(v as number)) return "—";
  return ((v as number) / divisor).toLocaleString("id-ID", { minimumFractionDigits: dec, maximumFractionDigits: dec });
}
function fmtPct(v: number | null | undefined): string {
  if (v === null || v === undefined || isNaN(v as number)) return "—";
  return `${(v as number) >= 0 ? "+" : ""}${(v as number).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
}
function fmtVar(v: number | null | undefined, divisor = 1): string {
  if (v === null || v === undefined || isNaN(v as number)) return "—";
  return `${(v as number) >= 0 ? "▲" : "▼"} ${fmtNum(Math.abs(v as number), divisor)}`;
}
function fmtMn(v: number): string { return (v / 1e6).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 }); }
function scaleUnit(peak: number, unit: string): { divisor: number; unit: string } {
  if (unit === "GB" && peak >= 1e5) return { divisor: 1e3, unit: "K GB" };
  if (peak >= 1e8) return { divisor: 1e6, unit: `Mn ${unit}` };
  if (peak >= 1e5) return { divisor: 1e3, unit: `K ${unit}` };
  return { divisor: 1, unit };
}

/* ─── main page ─── */
export default function ReportsPage() {
  const router = useRouter();
  const [mode, setMode] = useState<"mycoord" | "territory" | "snapshot">("mycoord");
  const [subTab, setSubTab] = useState<"comprehensive" | "datarev" | "product" | "benchmark" | "insight" | "ftth">("comprehensive");
  const tab = mode === "snapshot" ? "snapshot" : subTab;
  const [mcLevels, setMcLevels] = useState<{ level: string; label: string; name: string; value?: string }[] | null>(null);
  const [mcPick, setMcPick] = useState("");
  const [cats, setCats] = useState<Category[]>([]);
  const [metric, setMetric] = useState("rev_prepaid");
  const [circle, setCircle] = useState("JAVA");
  const [scopeType, setScopeType] = useState("all");
  const [scopeValue, setScopeValue] = useState("");
  const pdScope = "total";
  const [scopeOptions, setScopeOptions] = useState<string[]>([]);
  const [breakdownOptions, setBreakdownOptions] = useState<string[]>([]);
  const [breakdownValue, setBreakdownValue] = useState("Total");
  const [brand, setBrand] = useState<"ioh" | "im3" | "3id">("ioh");
  const [showFilters, setShowFilters] = useState(true);
  const [data, setData] = useState<Snapshot | null>(null);
  const [comp, setComp] = useState<Comprehensive | null>(null);
  const [drev, setDrev] = useState<DataRev | null>(null);
  const [prod, setProd] = useState<ProductDemand | null>(null);
  const [bench, setBench] = useState<Benchmark | null>(null);
  const [insight, setInsight] = useState<MarketInsight | null>(null);
  const [ftthData, setFtthData] = useState<Comprehensive | null>(null);
  const [geoErr, setGeoErr] = useState("");
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState("");
  const cacheRef = useRef<Map<string, unknown>>(new Map());
  const [dataVer, setDataVer] = useState("");

  useEffect(() => {
    if (typeof window !== "undefined" && !isLoggedIn()) { router.push("/login"); return; }
    (async () => { const r = await authFetch("/api/reports/metrics"); if (r.ok) { const d = await r.json(); setCats(d.categories || []); } })();
  }, [router]);

  // FTTH and IM3 use different territory level keys; reset scope when crossing
  // the FTTH boundary so a stale (incompatible) level is never sent.
  const prevFtthRef = useRef(false);
  useEffect(() => {
    const isFtth = subTab === "ftth";
    if (isFtth !== prevFtthRef.current) {
      prevFtthRef.current = isFtth;
      setScopeType("all"); setScopeValue(""); setBreakdownValue("Total"); setScopeOptions([]);
    }
  }, [subTab]);

  useEffect(() => {
    let stop = false;
    const tick = async () => { try { const r = await authFetch("/api/reports/data-version"); if (r.ok && !stop) { const d = await r.json(); setDataVer(`${d.highlevel ?? ""}|${d.data ?? ""}`); } } catch {} };
    tick(); const id = setInterval(tick, 120000); return () => { stop = true; clearInterval(id); };
  }, []);

  useEffect(() => {
    let ignore = false;
    (async () => {
      if (scopeType === "all") { if (!ignore) setScopeOptions([]); return; }
      const isFtth = tab === "ftth";
      const ep = isFtth ? "/api/reports/ftth/scope-options" : "/api/reports/scope-options";
      const r = await authFetch(`${ep}?circle=${encodeURIComponent(circle)}&level=${scopeType}`);
      if (r.ok && !ignore) setScopeOptions((await r.json()).values || []);
    })();
    return () => { ignore = true; };
  }, [circle, scopeType, tab]);

  useEffect(() => {
    let ignore = false;
    const childLevel = tab === "ftth" ? undefined : CHILD_LEVEL[scopeType];
    (async () => {
      if (!childLevel) {
        if (!ignore) { setBreakdownOptions([]); setBreakdownValue("Total"); }
        return;
      }
      const pf = scopeType !== "all" && scopeValue ? `&parent_type=${scopeType}&parent_value=${encodeURIComponent(scopeValue)}` : "";
      const r = await authFetch(`/api/reports/scope-options?circle=${encodeURIComponent(circle)}&level=${childLevel}${pf}`);
      if (r.ok && !ignore) { const d = await r.json(); setBreakdownOptions(d.values || []); if (breakdownValue !== "Total" && !d.values?.includes(breakdownValue)) setBreakdownValue("Total"); }
    })();
    return () => { ignore = true; };
  }, [circle, scopeType, scopeValue, breakdownValue, tab]);

  const pickLevel = useCallback((lv: { level: string; name: string; value?: string }) => {
    const val = lv.value ?? lv.name; setMcPick(lv.level); setScopeType(lv.level); setScopeValue(val); setBreakdownValue("Total");
  }, []);

  const locateMe = useCallback(() => {
    setGeoErr(""); setMcLevels(null);
    if (!navigator.geolocation) { setGeoErr("Geolocation tidak didukung."); return; }
    setLoading(true);
    navigator.geolocation.getCurrentPosition(async (pos) => {
      try {
        const r = await authFetch(`/api/reports/locate?lat=${pos.coords.latitude}&lon=${pos.coords.longitude}`);
        const d = await r.json();
        if (d.error) { setGeoErr(d.error); setLoading(false); } else {
          if (d.circle) setCircle(d.circle);
          const lvls = (d.levels || []).filter((x: { name?: string }) => x.name);
          setMcLevels(lvls);
          if (lvls[0]) { 
            const v0 = lvls[0].value ?? lvls[0].name; 
            setMcPick(lvls[0].level); setScopeType(lvls[0].level); setScopeValue(v0); setBreakdownValue("Total");
            // Do not call setLoading(false) here. The main useEffect will trigger and handle it.
          } else {
            setLoading(false);
          }
        }
      } catch (e) { setGeoErr(String(e)); setLoading(false); }
    }, (e) => { setGeoErr("Gagal: " + e.message); setLoading(false); }, { enableHighAccuracy: true, timeout: 15000 });
  }, []);

  const [reloadKey, setReloadKey] = useState(0);
  const activeScopeType = breakdownValue !== "Total" ? CHILD_LEVEL[scopeType] : scopeType;
  const activeScopeValue = breakdownValue !== "Total" ? breakdownValue : scopeValue;
  // Only send a scope filter once the typed value matches a real option, so
  // partial keystrokes in the searchable input don't fire invalid queries.
  const scopeValueValid = breakdownValue !== "Total" || scopeOptions.length === 0 || scopeOptions.includes(scopeValue);
  const scopeParams = (activeScopeType !== "all" && activeScopeValue && scopeValueValid) ? `&filter_type=${activeScopeType}&filter_value=${encodeURIComponent(activeScopeValue)}` : "";

  useEffect(() => {
    let ignore = false;
    if (mode === "mycoord" && (!scopeValue || !mcPick)) return;
    const cache = cacheRef.current;
    const key = tab === "snapshot" ? `snap|${dataVer}|${circle}|${metric}|${scopeParams}`
      : tab === "comprehensive" ? `comp|${dataVer}|${circle}|${scopeParams}`
      : tab === "datarev" ? `drev|${dataVer}|${circle}|${brand}|${scopeParams}`
      : tab === "benchmark" ? `bench|${dataVer}|${circle}|${scopeParams}`
      : tab === "insight" ? `ins|${dataVer}|${circle}|${scopeParams}`
      : tab === "ftth" ? `ftth|${dataVer}|${circle}|${scopeParams}`
      : `prod|${dataVer}|${circle}|${pdScope}|${brand}|${scopeParams}`;

    const setFromData = (d: unknown) => {
      if (tab === "snapshot") setData(d as Snapshot);
      else if (tab === "comprehensive") setComp(d as Comprehensive);
      else if (tab === "datarev") setDrev(d as DataRev);
      else if (tab === "benchmark") setBench(d as Benchmark);
      else if (tab === "insight") setInsight(d as MarketInsight);
      else if (tab === "ftth") setFtthData(d as Comprehensive);
      else setProd(d as ProductDemand);
    };
    if (cache.has(key)) { setErr(""); setFromData(cache.get(key)); setLoading(false); return; }
    (async () => {
      setLoading(true); setErr("");
      try {
        let url = "";
        if (tab === "snapshot") url = `/api/reports/snapshot?metric=${metric}&circle=${encodeURIComponent(circle)}${scopeParams}`;
        else if (tab === "comprehensive") url = `/api/reports/comprehensive?circle=${encodeURIComponent(circle)}${scopeParams}`;
        else if (tab === "datarev") url = `/api/reports/data-revenue?circle=${encodeURIComponent(circle)}&brand=${brand}${scopeParams}`;
        else if (tab === "benchmark") url = `/api/reports/network-benchmark?circle=${encodeURIComponent(circle)}${scopeParams}`;
        else if (tab === "insight") url = `/api/reports/market-insight?circle=${encodeURIComponent(circle)}${scopeParams}`;
        else if (tab === "ftth") url = `/api/reports/ftth?circle=${encodeURIComponent(circle)}${scopeParams}`;
        else url = `/api/reports/product-demand?circle=${encodeURIComponent(circle)}&scope=${pdScope}&brand=${brand}${scopeParams}`;
        const r = await authFetch(url); const d = await r.json();
        if (ignore) return;
        if (d.error) setErr(d.error); else { cache.set(key, d); setFromData(d); }
      } catch (e) { if (!ignore) setErr(String(e)); }
      if (!ignore) setLoading(false);
    })();
    return () => { ignore = true; };
  }, [tab, mode, mcPick, scopeValue, breakdownValue, metric, circle, brand, scopeParams, dataVer, reloadKey]);

  const load = useCallback(() => { cacheRef.current.clear(); authFetch("/api/reports/cache/clear", { method: "POST" }).catch(() => {}); setReloadKey((k) => k + 1); }, []);

  const disp = data?.display ?? { divisor: 1, unit: data?.metric.unit ?? "" };
  const up = (data?.totals.trend ?? "up") === "up";
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const activeScope = (tab === "snapshot" ? data?.scope : tab === "comprehensive" ? comp?.scope : tab === "datarev" ? drev?.scope : tab === "benchmark" ? bench?.scope : tab === "insight" ? insight?.scope : tab === "ftth" ? ftthData?.scope : prod?.scope) as any;
  const monthLabel = activeScope?.month_id;
  const dataAsOf = activeScope?.data_as_of;

  return (
    <div style={{ minHeight: "100vh", background: IOH.panel, fontFamily: "Prompt, sans-serif", color: IOH.ink }}>
      <header style={{ background: IOH.white, borderBottom: `1px solid ${IOH.rule}`, padding: "14px 20px", display: "flex", alignItems: "center", gap: 12, position: "sticky", top: 0, zIndex: 10 }}>
        <button onClick={() => router.push("/")} style={btnGhost}>← Chat</button>
        <div style={{ fontFamily: "Poppins, sans-serif", fontWeight: 700, fontSize: 18 }}>Performance Outlook</div>
      </header>
      <div style={{ maxWidth: 1180, margin: "0 auto", padding: 20, paddingBottom: 80 }}>
        {/* mode tabs */}
        <div style={{ display: "flex", gap: 6, overflowX: "auto", paddingBottom: 4, marginBottom: 12 }}>
          {([["mycoord", "◉", "My Coordinate"], ["territory", "▤", "Territory Wise"], ["snapshot", "◧", "Daily Snapshot"]] as const).map(([k, ic, lbl]) => (
            <button key={k} onClick={() => setMode(k)} style={{ ...iconTab, ...(mode === k ? iconTabActive : {}) }}><span style={{ fontSize: 15 }}>{ic}</span> <span style={{ fontSize: 12.5, fontWeight: 600 }}>{lbl}</span></button>
          ))}
        </div>
        {/* sub-tabs */}
        {mode !== "snapshot" && (
          <div style={{ ...seg, flexWrap: "nowrap", overflowX: "auto", maxWidth: "100%" }}>
            {([["comprehensive", "Comprehensive"], ["datarev", "Data Revenue"], ["product", "Product Demand"], ["benchmark", "Network Benchmark"], ["insight", "Market Insight"], ["ftth", "Indosat HiFi (FTTH)"]] as const).map(([k, lbl]) => (
              <button key={k} onClick={() => setSubTab(k)} style={{ ...segBtn, ...(subTab === k ? segBtnActive : {}) }}>{lbl}</button>
            ))}
          </div>
        )}
        {/* breakdown tabs (1 level below) */}
        {mode !== "snapshot" && CHILD_LEVEL[scopeType] && breakdownOptions.length > 0 && (
          <div style={{ ...seg, marginBottom: 12 }}>
            <button onClick={() => setBreakdownValue("Total")} style={{ ...segBtn, ...(breakdownValue === "Total" ? segBtnActive : {}) }}>Total ({scopeType === "all" ? circle : scopeValue})</button>
            {breakdownOptions.map((opt) => <button key={opt} onClick={() => setBreakdownValue(opt)} style={{ ...segBtn, ...(breakdownValue === opt ? segBtnActive : {}) }}>{opt}</button>)}
          </div>
        )}
        {/* info strip */}
        <div style={{ display: "flex", alignItems: "center", flexWrap: "wrap", gap: 10, marginBottom: showFilters ? 10 : 16 }}>
          {mode !== "mycoord" && (
            <button onClick={() => setShowFilters((v) => !v)} style={{ ...btnGhost, display: "flex", alignItems: "center", gap: 6 }}>
              <span>⚙</span> Filter {showFilters ? "▲" : "▼"}
              {scopeType !== "all" && scopeValue ? <span style={{ ...pill, padding: "1px 8px" }}>{scopeValue}</span> : null}
            </button>
          )}
          <div style={{ flex: 1 }} />
          {monthLabel && <span style={{ ...pill }}>Month {monthLabel}</span>}
          {dataAsOf && <span style={{ ...pill, background: "#EAF6F4", color: IOH.tealDeep, borderColor: "#CFE9E4" }}>Data as of {dataAsOf}</span>}
        </div>
        {/* my-coordinate locate */}
        {mode === "mycoord" && (
          <div style={{ background: IOH.white, border: `1px solid ${IOH.rule}`, borderRadius: 14, padding: 12, marginBottom: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
              <button onClick={locateMe} style={{ ...btnPrimary }}>{loading && !mcLevels ? "Mencari lokasi…" : "◉ Gunakan Lokasi Saya"}</button>
              {geoErr && <span style={{ color: IOH.neg, fontSize: 12.5 }}>{geoErr}</span>}
            </div>
            {mcLevels && (
              <div style={{ display: "flex", gap: 6, flexWrap: "nowrap", overflowX: "auto", marginTop: 10 }}>
                {mcLevels.map((lv) => (
                  <button key={lv.level} onClick={() => pickLevel(lv)} style={{ ...chipBtn, flex: "0 0 auto", ...(mcPick === lv.level ? chipBtnActive : {}) }}>{lv.label}: {lv.name}</button>
                ))}
              </div>
            )}
          </div>
        )}
        {/* filters */}
        {showFilters && mode !== "mycoord" && (
          <div style={{ background: IOH.white, border: `1px solid ${IOH.rule}`, borderRadius: 14, padding: 12, marginBottom: 16, display: "flex", alignItems: "flex-end", flexWrap: "wrap", gap: 10 }}>
            {tab === "snapshot" && (
              <label style={ctrlWrap}><span style={ctrlLbl}>Metric</span>
                <select value={metric} onChange={(e) => setMetric(e.target.value)} style={{ ...select, minWidth: 170 }}>
                  {cats.map((c) => <optgroup key={c.name} label={c.name}>{c.metrics.map((m) => <option key={m.code} value={m.code}>{m.name}</option>)}</optgroup>)}
                </select>
              </label>
            )}
            <label style={ctrlWrap}><span style={ctrlLbl}>Circle</span>
              <select value={circle} onChange={(e) => setCircle(e.target.value)} style={select}>
                <option value="ALL">All Circles</option>
                {CIRCLES.map((c) => <option key={c} value={c}>{c}</option>)}
              </select>
            </label>
            {mode === "territory" && (<>
              <label style={ctrlWrap}><span style={ctrlLbl}>View</span>
                <select value={scopeType} onChange={(e) => { setScopeType(e.target.value); setScopeValue(""); setBreakdownValue("Total"); }} style={select}>
                  <option value="all">Circle</option>
                  {(tab === "ftth" ? FTTH_SCOPE_LEVELS : SCOPE_LEVELS).map((l) => <option key={l.key} value={l.key}>{l.label}</option>)}
                </select>
              </label>
              {scopeType !== "all" && (
                <label style={ctrlWrap}><span style={ctrlLbl}>{(tab === "ftth" ? FTTH_SCOPE_LEVELS : SCOPE_LEVELS).find((l) => l.key === scopeType)?.label}</span>
                  <input
                    list="scope-options-list"
                    value={scopeValue}
                    placeholder="Ketik untuk mencari..."
                    onChange={(e) => { const v = e.target.value; setBreakdownValue("Total"); if (scopeOptions.includes(v) || v === "") setScopeValue(v); else setScopeValue(v); }}
                    style={{ ...select, minWidth: 180 }}
                  />
                  <datalist id="scope-options-list">
                    {scopeOptions.map((v) => <option key={v} value={v} />)}
                  </datalist>
                </label>
              )}
            </>)}
            <div style={{ flex: 1 }} />
            <button onClick={load} style={{ ...btnPrimary }}>↻</button>
          </div>
        )}
        {err && <div style={{ background: "#FDECEC", color: IOH.neg, padding: 12, borderRadius: 12, marginBottom: 16, fontSize: 13 }}>{err}</div>}
        {mode === "mycoord" && !scopeValue && !loading && <Panel title="My Coordinate"><div style={{ color: IOH.mute, fontSize: 13 }}>Tekan &quot;Gunakan Lokasi Saya&quot;, lalu pilih level wilayah.</div></Panel>}
        {loading && !data && !comp && !drev && !prod && !bench && !insight && <div style={{ padding: 40, textAlign: "center", color: IOH.mute }}>Memuat data…</div>}

        {/* ──── Snapshot ──── */}
        {tab === "snapshot" && data && (<>
          <div style={{ background: IOH.white, borderRadius: 16, borderTop: `3px solid ${BAND_BG[brand]}`, padding: 20, marginBottom: 16, boxShadow: "0 2px 10px rgba(15,31,29,.06)" }}>
            <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 12 }}>
              <div>
                <div style={eyebrow}>{data.metric.name.toUpperCase()} · {brand.toUpperCase()} · MTD</div>
                <div style={{ fontFamily: "Poppins, sans-serif", fontWeight: 700, fontSize: 34, lineHeight: 1.1, marginTop: 4 }}>
                  {fmtNum(brand === "ioh" ? data.totals.mtd : brand === "im3" ? data.totals.mtd_im3 : data.totals.mtd_3id, disp.divisor)} <span style={{ fontSize: 15, color: IOH.mute, fontWeight: 500 }}>{disp.unit}</span>
                </div>
                <div style={{ marginTop: 6, color: IOH.mute, fontSize: 13 }}>IOH {fmtNum(data.totals.mtd, disp.divisor)} · IM3 {fmtNum(data.totals.mtd_im3, disp.divisor)} · 3ID {fmtNum(data.totals.mtd_3id, disp.divisor)}</div>
              </div>
              <div style={{ textAlign: "right" }}>
                <div style={{ fontFamily: "Poppins, sans-serif", fontWeight: 700, fontSize: 26, color: up ? IOH.pos : IOH.neg }}>{up ? "▲" : "▼"} {fmtPct(data.totals.pct_change)}</div>
                <div style={{ color: up ? IOH.pos : IOH.neg, fontSize: 13, marginTop: 2 }}>{fmtVar(data.totals.abs_change, disp.divisor)} {disp.unit} vs LMTD</div>
              </div>
            </div>
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 16 }}>
            <Chip label="Best Area" name={data.best?.name} v={data.best?.var} pct={data.best?.pct} divisor={disp.divisor} good />
            <Chip label="Worst Area" name={data.worst?.name} v={data.worst?.var} pct={data.worst?.pct} divisor={disp.divisor} />
          </div>
          <Panel title={`Kecamatan Health Distribution · ${data.slabs.kecamatan.total} kecamatan`}><SlabBars s={data.slabs.kecamatan} /></Panel>
          {data.deck && <SnapshotDeck deck={data.deck} divisor={disp.divisor} />}
        </>)}

        {tab === "comprehensive" && comp && <ComprehensiveView comp={comp} brand={brand} />}
        {tab === "datarev" && drev && <DataRevView d={drev} brand={brand} />}
        {tab === "product" && prod && <ProductDemandView p={prod} brand={brand} />}
        {tab === "benchmark" && bench && <BenchmarkView b={bench} />}
        {tab === "insight" && insight && <MarketInsightView ins={insight} />}
        {tab === "ftth" && ftthData && <ComprehensiveView comp={ftthData} brand="ioh" />}
      </div>
      {/* sticky brand bar — hidden on the FTTH page (no brand split) */}
      {tab !== "ftth" && (
        <div style={{ position: "sticky", bottom: 0, zIndex: 20, background: IOH.white, borderTop: `1px solid ${IOH.rule}`, padding: "8px 12px", display: "flex", justifyContent: "center", gap: 8, boxShadow: "0 -2px 10px rgba(15,31,29,.06)" }}>
          {([["ioh", "IOH"], ["im3", "IM3"], ["3id", "3ID"]] as const).map(([k, lbl]) => (
            <button key={k} onClick={() => setBrand(k as "ioh" | "im3" | "3id")}
              style={{ ...segBtn, padding: "8px 22px", border: `1px solid ${IOH.rule}`, ...(brand === k ? { background: k === "ioh" ? IOH.band_ioh : k === "im3" ? IOH.band_im3 : IOH.band_3id, color: k === "im3" ? "#161616" : "#fff", borderColor: "transparent" } : {}) }}>{lbl}</button>
          ))}
        </div>
      )}
    </div>
  );
}

/* ─── sub-components ─── */
function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (<div style={{ background: IOH.white, borderRadius: 16, boxShadow: "0 2px 10px rgba(15,31,29,.05)", padding: 16, marginBottom: 16 }}><div style={{ ...eyebrow, marginBottom: 10 }}>{title}</div>{children}</div>);
}
function Chip({ label, name, v, pct, divisor, good }: { label: string; name?: string; v?: number; pct?: number; divisor: number; good?: boolean }) {
  const c = good ? IOH.pos : IOH.neg;
  return (<div style={{ background: IOH.white, borderRadius: 14, padding: "12px 16px", boxShadow: "0 1px 6px rgba(15,31,29,.05)", borderLeft: `4px solid ${c}` }}>
    <div style={eyebrow}>{label}</div>
    <div style={{ fontFamily: "Poppins, sans-serif", fontWeight: 700, fontSize: 16, marginTop: 2 }}>{name ?? "—"}</div>
    <div style={{ color: c, fontSize: 13, marginTop: 2 }}>{fmtVar(v, divisor)} · {fmtPct(pct)}</div>
  </div>);
}
function SlabBars({ s }: { s: Slabs }) {
  const buckets = [
    { k: "decline_gt5", lbl: "≤ -5%", color: "#B91C1C" }, { k: "decline_3_5", lbl: "-5..-3%", color: "#DC2626" },
    { k: "decline_1_3", lbl: "-3..-1%", color: "#EF4444" }, { k: "decline_0_1", lbl: "-1..0%", color: "#F87171" },
    { k: "growth_0_1", lbl: "0..1%", color: "#5EEAD4" }, { k: "growth_1_3", lbl: "1..3%", color: "#2DD4BF" },
    { k: "growth_3_5", lbl: "3..5%", color: "#14B8A6" }, { k: "growth_gt5", lbl: "≥ 5%", color: "#0E8579" },
  ] as { k: keyof Slabs; lbl: string; color: string }[];
  const max = Math.max(1, ...buckets.map((b) => s[b.k] as number));
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 5 }}>
      {buckets.map((b) => (
        <div key={b.k} style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 12 }}>
          <span style={{ width: 64, color: IOH.mute, textAlign: "right" }}>{b.lbl}</span>
          <div style={{ flex: 1, background: IOH.panel, borderRadius: 4, height: 16, overflow: "hidden" }}>
            <div style={{ width: `${((s[b.k] as number) / max) * 100}%`, background: b.color, height: "100%" }} />
          </div>
          <span style={{ width: 28 }}>{s[b.k] as number}</span>
        </div>
      ))}
    </div>
  );
}
function BrandTable({ rows, divisor }: { rows: Row[]; divisor: number }) {
  const bands = [
    { key: "ioh", label: "IOH", bg: IOH.band_ioh, fg: "#fff" },
    { key: "im3", label: "IM3", bg: IOH.band_im3, fg: "#161616" },
    { key: "3id", label: "3ID", bg: IOH.band_3id, fg: "#fff" },
  ] as const;
  const subs = ["LLMTD", "LMTD", "MTD", "Var", "%"];
  const sign = (v?: number | null) => ((v ?? 0) >= 0 ? IOH.pos : IOH.neg);
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 760 }}>
        <thead><tr>
          <th rowSpan={2} style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 130, boxShadow: `1px 0 0 ${IOH.rule}` }}>Name</th>
          {bands.map((b) => <th key={b.key} colSpan={5} style={{ ...th, background: b.bg, color: b.fg }}>{b.label}</th>)}
        </tr><tr>
          {bands.map((b) => subs.map((s) => <th key={b.key + s} style={{ ...th, background: b.bg, color: b.fg, fontWeight: 500, opacity: 0.9 }}>{s}</th>))}
        </tr></thead>
        <tbody>{rows.map((r, i) => {
          const cells = bands.map((b) => [
            fmtNum(r[`llmtd_${b.key}`] as number, divisor), fmtNum(r[`lmtd_${b.key}`] as number, divisor),
            <b key="m">{fmtNum(r[`mtd_${b.key}`] as number, divisor)}</b>,
            <span key="v" style={{ color: sign(r[`abs_growth_${b.key}`] as number) }}>{fmtVar(r[`abs_growth_${b.key}`] as number, divisor)}</span>,
            <span key="p" style={{ color: sign((b.key === "ioh" ? r["growth_pct"] : r[`growth_pct_${b.key}`]) as number) }}>{fmtPct((b.key === "ioh" ? r["growth_pct"] : r[`growth_pct_${b.key}`]) as number)}</span>,
          ]);
          const bg = i % 2 ? IOH.zebra : IOH.white;
          return (
            <tr key={i} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", whiteSpace: "nowrap", fontWeight: 500, position: "sticky", left: 0, zIndex: 1, background: bg, boxShadow: `1px 0 0 ${IOH.rule}`, minWidth: 130 }}>
                <div>{String(r.name)}</div>
                {r.parent != null && <div style={{ fontSize: 10, color: IOH.mute }}>{String(r.parent)}</div>}
              </td>
              {cells.map((grp, bi) => grp.map((c, ci) => (
                <td key={`${bi}-${ci}`} style={{ ...td, background: ci === 3 ? IOH.varTint : ci === 4 ? IOH.growTint : undefined }}>{c}</td>
              )))}
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}
function SnapshotDeck({ deck, divisor }: { deck: SnapDeck; divisor: number }) {
  const sections: [string, string][] = [["circle", "Circle"], ["region", "Region"], ["branch", "Area"], ["microcluster", "District"], ["kabkota", "Kab/Kota"], ["kecamatan", "Kecamatan"]];
  const FULL = ["circle", "region", "branch"];
  const [sub, setSub] = useState("circle");
  const count = deck.counts[sub] ?? 0;
  let body: React.ReactNode;
  if (FULL.includes(sub)) {
    body = <BrandTable rows={(deck as unknown as Record<string, { rows: Row[] }>)[sub].rows} divisor={divisor} />;
  } else {
    const set = (deck as unknown as Record<string, RankSet>)[sub];
    body = (<>
      <div style={{ ...eyebrow, color: IOH.neg, margin: "4px 0 6px" }}>▼ Top 10 Decline</div>
      <BrandTable rows={set.decline} divisor={divisor} />
      <div style={{ ...eyebrow, color: IOH.pos, margin: "16px 0 6px" }}>▲ Top 10 Growth</div>
      <BrandTable rows={set.growth} divisor={divisor} />
    </>);
  }
  return (
    <div style={{ background: IOH.white, borderRadius: 16, boxShadow: "0 2px 10px rgba(15,31,29,.05)", padding: 16, marginBottom: 16 }}>
      <div style={{ display: "flex", gap: 6, overflowX: "auto", marginBottom: 12 }}>
        {sections.map(([k, lbl]) => <button key={k} onClick={() => setSub(k)} style={{ ...segBtn, border: `1px solid ${sub === k ? IOH.teal : IOH.rule}`, ...(sub === k ? { background: IOH.teal, color: "#fff" } : { background: IOH.white }) }}>{lbl}</button>)}
      </div>
      <div style={{ ...eyebrow, marginBottom: 8 }}>{sections.find((s) => s[0] === sub)?.[1]} · {count} total{FULL.includes(sub) ? "" : " — Top Decline / Growth"}</div>
      {body}
    </div>
  );
}
function ComprehensiveView({ comp, brand }: { comp: Comprehensive; brand: "ioh" | "im3" | "3id" }) {
  const showGroupAt = comp.sections.map((s, i) => !!s.group && s.group !== (comp.sections[i - 1]?.group ?? null));
  return (
    <div>
      {comp.sections.map((s, si) => (
        <div key={si}>
          {showGroupAt[si] && <div style={{ ...eyebrow, fontSize: 11, marginTop: si ? 18 : 0, marginBottom: 6, borderBottom: `1px solid ${IOH.ink}`, paddingBottom: 4 }}>{s.group}</div>}
          {s.layout === "flat"
            ? <FlatTable s={s} />
            : s.layout === "ftth_counts"
            ? <Panel title={s.title}><FtthCountTable s={s} /></Panel>
            : s.layout === "hierarchy"
            ? <Panel title={s.title}><FtthHierarchyTable s={s} /></Panel>
            : <Panel title={s.title}><CompTable metrics={s.metrics ?? []} brand={brand} /></Panel>}
        </div>
      ))}
    </div>
  );
}
function CompTable({ metrics, brand }: { metrics: CompMetric[]; brand: "ioh" | "im3" | "3id" }) {
  const subs = ["LLMTD", "LMTD", "MTD", "Var", "%", "LYTD", "YTD", "Var YoY", "YoY%"];
  const bandBg = BAND_BG[brand], bandFg = BAND_FG[brand];
  const sign = (v?: number | null) => ((v ?? 0) >= 0 ? IOH.pos : IOH.neg);
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 760 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 180, boxShadow: `1px 0 0 ${IOH.rule}` }}>Metric</th>
          {subs.map((h) => <th key={h} style={{ ...th, background: bandBg, color: bandFg, fontWeight: 600 }}>{h}</th>)}
        </tr></thead>
        <tbody>{metrics.map((m, i) => {
          const b = m[brand];
          const peak = Math.max(Math.abs(b.mtd), Math.abs(b.lmtd), Math.abs(b.llmtd));
          const isComp = !!m.computed;
          const sc = isComp ? { divisor: 1, unit: m.unit } : scaleUnit(peak, m.unit);
          const fmtR = (v?: number | null) => { if (v === null || v === undefined || isNaN(v as number)) return "—"; if (m.unit === "%") return fmtPct(v); if (m.unit === "GB") return (v as number).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 }); return (v as number).toLocaleString("id-ID", { maximumFractionDigits: 0 }); };
          const fNum = (v?: number | null) => isComp ? fmtR(v) : fmtNum(v, sc.divisor);
          const fVar = (v?: number | null) => isComp ? (v == null ? "—" : `${(v as number) >= 0 ? "▲" : "▼"} ${fmtR(Math.abs(v as number))}`) : fmtVar(v, sc.divisor);
          const bg = i % 2 ? IOH.zebra : IOH.white;
          return (
            <tr key={i} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", whiteSpace: "nowrap", fontWeight: 500, position: "sticky", left: 0, zIndex: 1, background: bg, boxShadow: `1px 0 0 ${IOH.rule}`, fontStyle: isComp ? "italic" : "normal", color: isComp ? IOH.tealDeep : IOH.ink }}>
                {m.name} <span style={{ color: IOH.mute, fontSize: 10 }}>{sc.unit}</span>
              </td>
              <td style={td}>{fNum(b.llmtd)}</td>
              <td style={td}>{fNum(b.lmtd)}</td>
              <td style={{ ...td, fontWeight: 700 }}>{fNum(b.mtd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sign(b.var_mom) }}>{fVar(b.var_mom)}</td>
              <td style={{ ...td, background: IOH.growTint, color: sign(b.growth_mom_pct) }}>{fmtPct(b.growth_mom_pct)}</td>
              <td style={td}>{fNum(b.lytd)}</td>
              <td style={{ ...td, fontWeight: 700 }}>{fNum(b.ytd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sign(b.var_yoy) }}>{fVar(b.var_yoy)}</td>
              <td style={{ ...td, background: IOH.growTint, color: sign(b.growth_yoy_pct) }}>{fmtPct(b.growth_yoy_pct)}</td>
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}
function DataRevView({ d, brand }: { d: DataRev; brand: "ioh" | "im3" | "3id" }) {
  const bandBg = BAND_BG[brand], bandFg = BAND_FG[brand];
  const r = d.ratios;
  return (
    <div>
      {r && (
        <Panel title="Ratios — Channel Mix & ATL/BTL">
          <div style={{ display: "flex", flexWrap: "wrap", gap: 10 }}>
            {Object.entries(r.channel_pct).map(([k, v]) => (
              <span key={k} style={{ ...pill, background: "#EAF6F4", color: IOH.tealDeep, borderColor: "#CFE9E4" }}>{k}: {fmtPct(v)}</span>
            ))}
            <span style={{ ...pill }}>ATL: {fmtPct(r.atl_pct)}</span>
            <span style={{ ...pill }}>BTL: {fmtPct(r.btl_pct)}</span>
            <span style={{ ...pill, background: "#FDF3E2", color: "#9A6B00", borderColor: "#F0DFB8" }}>ATL/BTL: {r.atl_vs_btl == null ? "—" : r.atl_vs_btl.toLocaleString("id-ID", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}×</span>
          </div>
        </Panel>
      )}
      {d.chunks.map((c, i) => <DRChunkTable key={i} c={c} brand={brand} bandBg={bandBg} bandFg={bandFg} />)}
      <PriceSlabPanel d={d} brand={brand} bandBg={bandBg} bandFg={bandFg} />
    </div>
  );
}
function DRChunkTable({ c, brand, bandBg, bandFg }: { c: DRChunk; brand: "ioh" | "im3" | "3id"; bandBg: string; bandFg: string }) {
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const subs = ["LLMTD", "LMTD", "MTD", "Var", "%", "LYTD", "YTD", "Var YoY", "YoY%", "Contrib%"];
  const sign = (v?: number | null) => ((v ?? 0) >= 0 ? IOH.pos : IOH.neg);
  const v = (row: DRNode) => row[brand];
  const share = (row: DRNode) => (row.ioh ? (row[brand] as number) / row.ioh : 1);
  const cells = (row: DRNode) => {
    const s = share(row); const mtd = v(row) as number; const lmtd = row.lmtd * s; const llmtd = row.llmtd * s; const ytd = row.ytd * s; const lytd = row.lytd * s;
    const vM = mtd - lmtd, vY = ytd - lytd;
    return (<>
      <td style={td}>{fmtMn(llmtd)}</td><td style={td}>{fmtMn(lmtd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(mtd)}</td>
      <td style={{ ...td, background: IOH.varTint, color: sign(vM) }}>{(vM >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vM))}</td>
      <td style={{ ...td, background: IOH.growTint, color: sign(lmtd ? vM / lmtd : null) }}>{fmtPct(lmtd ? vM / lmtd * 100 : null)}</td>
      <td style={td}>{fmtMn(lytd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(ytd)}</td>
      <td style={{ ...td, background: IOH.varTint, color: sign(vY) }}>{(vY >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vY))}</td>
      <td style={{ ...td, background: IOH.growTint, color: sign(lytd ? vY / lytd : null) }}>{fmtPct(lytd ? vY / lytd * 100 : null)}</td>
      <td style={{ ...td, color: IOH.mute }}>{fmtPct(row.contrib_pct)}</td>
    </>);
  };
  const nameCell = (label: string, bg: string, extra?: React.CSSProperties) => (
    <td style={{ ...td, textAlign: "left", whiteSpace: "nowrap", position: "sticky", left: 0, zIndex: 1, background: bg, boxShadow: `1px 0 0 ${IOH.rule}`, ...extra }}>{label}</td>
  );
  return (
    <Panel title={`${c.name} (Mn IDR)`}>
      <div style={{ overflowX: "auto" }}>
        <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 1100 }}>
          <thead><tr>
            <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 170, boxShadow: `1px 0 0 ${IOH.rule}` }}>Channel</th>
            {subs.map((h) => <th key={h} style={{ ...th, background: bandBg, color: bandFg, fontWeight: 600 }}>{h}</th>)}
          </tr></thead>
          <tbody>
            <tr style={{ background: "#EFF4F3" }}>
              {nameCell("TOTAL", "#EFF4F3", { fontWeight: 700 })}{cells(c.headline)}
            </tr>
            {c.channels.map((ch, j) => {
              const hasD = (ch.details?.length ?? 0) > 0; const isOpen = !!open[ch.channel]; const bg = j % 2 ? IOH.zebra : IOH.white;
              return (
                <Fragment key={j}>
                  <tr style={{ background: bg, cursor: hasD ? "pointer" : "default" }} onClick={() => hasD && setOpen((o) => ({ ...o, [ch.channel]: !o[ch.channel] }))}>
                    {nameCell(`${hasD ? (isOpen ? "▾ " : "▸ ") : ""}${ch.channel}`, bg, { fontWeight: 600 })}{cells(ch)}
                  </tr>
                  {isOpen && (ch.details ?? []).map((dt, k) => (
                    <tr key={`${j}-${k}`} style={{ background: IOH.zebra }}>{nameCell(dt.detail, IOH.zebra, { paddingLeft: 22, color: IOH.mute })}{cells(dt)}</tr>
                  ))}
                </Fragment>
              );
            })}
          </tbody>
        </table>
      </div>
    </Panel>
  );
}
function SlabTable({ slabs, brand, bandBg, bandFg }: { slabs: DRSlab[]; brand: "ioh" | "im3" | "3id"; bandBg: string; bandFg: string }) {
  const sg = (x: number | null) => ((x ?? 0) >= 0 ? IOH.pos : IOH.neg);
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 1100 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 120, boxShadow: `1px 0 0 ${IOH.rule}` }}>Price Slab</th>
          {["LLMTD", "LMTD", "MTD", "Var", "%", "LYTD", "YTD", "Var YoY", "YoY%", "Hits"].map((h) => <th key={h} style={{ ...th, background: bandBg, color: bandFg, fontWeight: 600 }}>{h}</th>)}
        </tr></thead>
        <tbody>{slabs.map((s, i) => {
          const bg = i % 2 ? IOH.zebra : IOH.white; const sh = s.ioh ? (s[brand] as number) / s.ioh : 1;
          const mtd = s[brand] as number, lmtd = s.lmtd * sh, llmtd = s.llmtd * sh, ytd = s.ytd * sh, lytd = s.lytd * sh;
          const vM = mtd - lmtd, vY = ytd - lytd;
          return (
            <tr key={i} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", whiteSpace: "nowrap", fontWeight: 500, position: "sticky", left: 0, zIndex: 1, background: bg, boxShadow: `1px 0 0 ${IOH.rule}` }}>{s.slab}</td>
              <td style={td}>{fmtMn(llmtd)}</td><td style={td}>{fmtMn(lmtd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(mtd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sg(vM) }}>{(vM >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vM))}</td>
              <td style={{ ...td, background: IOH.growTint, color: sg(lmtd ? vM / lmtd : null) }}>{fmtPct(lmtd ? vM / lmtd * 100 : null)}</td>
              <td style={td}>{fmtMn(lytd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(ytd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sg(vY) }}>{(vY >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vY))}</td>
              <td style={{ ...td, background: IOH.growTint, color: sg(lytd ? vY / lytd : null) }}>{fmtPct(lytd ? vY / lytd * 100 : null)}</td>
              <td style={td}>{s.hit.toLocaleString("id-ID")}</td>
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}
function PriceSlabPanel({ d, brand, bandBg, bandFg }: { d: DataRev; brand: "ioh" | "im3" | "3id"; bandBg: string; bandFg: string }) {
  const scopes = d.price_slab_scopes;
  const [scope, setScope] = useState("total");
  const [detail, setDetail] = useState("");
  if (!scopes) return <Panel title="Price Slab Breakdown (Mn IDR)"><SlabTable slabs={d.price_slabs} brand={brand} bandBg={bandBg} bandFg={bandFg} /></Panel>;
  const order = ["total", "organic", "digital", "trade"].filter((k) => scopes[k]);
  const cur = scopes[scope] ?? scopes["total"];
  const detailNames = Object.keys(cur.details || {});
  const slabs = (detail && cur.details?.[detail]) ? cur.details[detail] : cur.slabs;
  return (
    <Panel title="Price Slab Breakdown (Mn IDR)">
      <div style={{ ...seg, marginBottom: 10 }}>
        {order.map((k) => <button key={k} onClick={() => { setScope(k); setDetail(""); }} style={{ ...segBtn, ...(scope === k ? segBtnActive : {}) }}>{scopes[k].label}</button>)}
      </div>
      {detailNames.length > 0 && (
        <div style={{ display: "flex", flexWrap: "nowrap", overflowX: "auto", gap: 6, marginBottom: 10 }}>
          <button onClick={() => setDetail("")} style={{ ...chipBtn, flex: "0 0 auto", ...(detail === "" ? chipBtnActive : {}) }}>All {cur.label}</button>
          {detailNames.map((dn) => <button key={dn} onClick={() => setDetail(dn)} style={{ ...chipBtn, flex: "0 0 auto", ...(detail === dn ? chipBtnActive : {}) }}>{dn}</button>)}
        </div>
      )}
      <SlabTable slabs={slabs} brand={brand} bandBg={bandBg} bandFg={bandFg} />
    </Panel>
  );
}
function PDSlabPanel({ p, brand, bandBg, bandFg }: { p: ProductDemand; brand: "ioh" | "im3" | "3id"; bandBg: string; bandFg: string }) {
  const scopes = p.slab_scopes;
  const [scope, setScope] = useState("total");
  const [detail, setDetail] = useState("");
  const [dim, setDim] = useState<"quota" | "validity">("quota");
  if (!scopes) return null;
  const order = ["total", "organic", "digital", "trade"].filter((k) => scopes[k]);
  const cur = scopes[scope] ?? scopes["total"];
  const detailNames = Object.keys(cur.details || {});
  const dimSrc = (detail && cur.details?.[detail]) ? cur.details[detail] : cur;
  const rows: DRSlab[] = (dim === "quota" ? dimSrc.quota : dimSrc.validity).map((s) => ({ ...s, hit: 0 }));
  const tops = dimSrc.top_products || [];
  return (
    <Panel title={`Slab Breakdown (Mn IDR) — ${dim === "quota" ? "Kuota Data" : "Masa Aktif"}`}>
      <div style={{ ...seg, marginBottom: 8 }}>
        {order.map((k) => <button key={k} onClick={() => { setScope(k); setDetail(""); }} style={{ ...segBtn, ...(scope === k ? segBtnActive : {}) }}>{scopes[k].label}</button>)}
      </div>
      {detailNames.length > 0 && (
        <div style={{ display: "flex", flexWrap: "nowrap", overflowX: "auto", gap: 6, marginBottom: 8 }}>
          <button onClick={() => setDetail("")} style={{ ...chipBtn, flex: "0 0 auto", ...(detail === "" ? chipBtnActive : {}) }}>All {cur.label}</button>
          {detailNames.map((dn) => <button key={dn} onClick={() => setDetail(dn)} style={{ ...chipBtn, flex: "0 0 auto", ...(detail === dn ? chipBtnActive : {}) }}>{dn}</button>)}
        </div>
      )}
      <div style={{ display: "flex", gap: 6, marginBottom: 10 }}>
        {(["quota", "validity"] as const).map((dk) => <button key={dk} onClick={() => setDim(dk)} style={{ ...chipBtn, ...(dim === dk ? chipBtnActive : {}) }}>{dk === "quota" ? "Slab Kuota" : "Slab Masa Aktif"}</button>)}
      </div>
      <PDSlabTable rows={rows} brand={brand} dimLabel={dim === "quota" ? "Quota" : "Validity"} />
      {tops.length > 0 && (<>
        <div style={{ ...eyebrow, margin: "16px 0 8px" }}>Top Products · {detail || cur.label}</div>
        <PDTopProductTable rows={tops} brand={brand} bandBg={bandBg} bandFg={bandFg} />
      </>)}
    </Panel>
  );
}
function PDTopProductTable({ rows, brand, bandBg, bandFg }: { rows: PDProduct[]; brand: "ioh" | "im3" | "3id"; bandBg: string; bandFg: string }) {
  const sg = (x: number | null) => ((x ?? 0) >= 0 ? IOH.pos : IOH.neg);
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 1050 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 200, boxShadow: `1px 0 0 ${IOH.rule}` }}>Product</th>
          {["LLMTD", "LMTD", "MTD", "Var", "%", "LYTD", "YTD", "Var YoY", "YoY%", "Hits"].map((h) => <th key={h} style={{ ...th, background: bandBg, color: bandFg, fontWeight: 600 }}>{h}</th>)}
        </tr></thead>
        <tbody>{rows.map((s, i) => {
          const bg = i % 2 ? IOH.zebra : IOH.white; const sh = s.ioh ? (s[brand] as number) / s.ioh : 1;
          const mtd = s[brand] as number, lmtd = s.lmtd * sh, llmtd = s.llmtd * sh, ytd = s.ytd * sh, lytd = s.lytd * sh;
          const vM = mtd - lmtd, vY = ytd - lytd;
          return (
            <tr key={i} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", whiteSpace: "nowrap", fontWeight: 500, position: "sticky", left: 0, zIndex: 1, background: bg, boxShadow: `1px 0 0 ${IOH.rule}` }}>{s.product} <span style={{ color: IOH.mute, fontSize: 10 }}>{s.family}</span></td>
              <td style={td}>{fmtMn(llmtd)}</td><td style={td}>{fmtMn(lmtd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(mtd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sg(vM) }}>{(vM >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vM))}</td>
              <td style={{ ...td, background: IOH.growTint, color: sg(lmtd ? vM / lmtd : null) }}>{fmtPct(lmtd ? vM / lmtd * 100 : null)}</td>
              <td style={td}>{fmtMn(lytd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(ytd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sg(vY) }}>{(vY >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vY))}</td>
              <td style={{ ...td, background: IOH.growTint, color: sg(lytd ? vY / lytd : null) }}>{fmtPct(lytd ? vY / lytd * 100 : null)}</td>
              <td style={td}>{s.hit.toLocaleString("id-ID")}</td>
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}
function PDSlabTable({ rows, brand, dimLabel }: { rows: DRSlab[]; brand: "ioh" | "im3" | "3id"; dimLabel: string }) {
  const bandBg = BAND_BG[brand], bandFg = BAND_FG[brand];
  const sg = (x: number | null) => ((x ?? 0) >= 0 ? IOH.pos : IOH.neg);
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 1000 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 120, boxShadow: `1px 0 0 ${IOH.rule}` }}>{dimLabel}</th>
          {["LLMTD", "LMTD", "MTD", "Var", "%", "LYTD", "YTD", "Var YoY", "YoY%"].map((h) => <th key={h} style={{ ...th, background: bandBg, color: bandFg, fontWeight: 600 }}>{h}</th>)}
        </tr></thead>
        <tbody>{rows.map((s, i) => {
          const bg = i % 2 ? IOH.zebra : IOH.white; const sh = s.ioh ? (s[brand] as number) / s.ioh : 1;
          const mtd = s[brand] as number, lmtd = s.lmtd * sh, llmtd = s.llmtd * sh, ytd = s.ytd * sh, lytd = s.lytd * sh;
          const vM = mtd - lmtd, vY = ytd - lytd;
          return (
            <tr key={i} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", whiteSpace: "nowrap", fontWeight: 500, position: "sticky", left: 0, zIndex: 1, background: bg, boxShadow: `1px 0 0 ${IOH.rule}` }}>{s.slab}</td>
              <td style={td}>{fmtMn(llmtd)}</td><td style={td}>{fmtMn(lmtd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(mtd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sg(vM) }}>{(vM >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vM))}</td>
              <td style={{ ...td, background: IOH.growTint, color: sg(lmtd ? vM / lmtd : null) }}>{fmtPct(lmtd ? vM / lmtd * 100 : null)}</td>
              <td style={td}>{fmtMn(lytd)}</td><td style={{ ...td, fontWeight: 700 }}>{fmtMn(ytd)}</td>
              <td style={{ ...td, background: IOH.varTint, color: sg(vY) }}>{(vY >= 0 ? "▲ " : "▼ ") + fmtMn(Math.abs(vY))}</td>
              <td style={{ ...td, background: IOH.growTint, color: sg(lytd ? vY / lytd : null) }}>{fmtPct(lytd ? vY / lytd * 100 : null)}</td>
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}
function ProductDemandView({ p, brand }: { p: ProductDemand; brand: "ioh" | "im3" | "3id" }) {
  const bandBg = BAND_BG[brand], bandFg = BAND_FG[brand];
  const flatMax = Math.max(1, ...p.revenue_matrix.flat());
  const rankOf = (q: string, v: string) => p.top_3.findIndex((t) => t.quota === q && t.validity === v);
  const gMax = Math.max(1, ...p.growth_matrix.flat().map((x) => Math.abs(x ?? 0)));
  return (
    <div>
      <PDSlabPanel p={p} brand={brand} bandBg={bandBg} bandFg={bandFg} />
      <Panel title="Rank Legend">
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
          {p.top_3.map((t) => <span key={t.rank} style={{ background: ["#ED1C24", "#EC008C", "#FFCB05"][t.rank - 1], color: t.rank === 3 ? "#161616" : "#fff", borderRadius: 8, padding: "4px 10px", fontSize: 12, fontWeight: 600 }}>#{t.rank} {t.quota} × {t.validity} · {fmtMn(t.value)} Mn</span>)}
        </div>
      </Panel>
      <Panel title="Revenue Heatmap · Quota × Validity (Mn IDR)">
        <div style={{ overflowX: "auto" }}>
          <table style={{ borderCollapse: "collapse", fontSize: 11, minWidth: 560 }}>
            <thead><tr>
              <th style={{ ...th, textAlign: "left", background: IOH.white }}></th>
              {p.validity_labels.map((v) => <th key={v} style={th}>{v}</th>)}
            </tr></thead>
            <tbody>{p.quota_labels.map((q, ri) => (
              <tr key={q}><td style={{ ...td, textAlign: "left", fontWeight: 600, whiteSpace: "nowrap" }}>{q}</td>
                {p.validity_labels.map((v, ci) => {
                  const val = p.revenue_matrix[ri][ci]; const rank = rankOf(q, v);
                  const alpha = 0.1 + 0.8 * (val / flatMax);
                  const bg = rank >= 0 ? ["#ED1C24", "#EC008C", "#FFCB05"][rank] : `rgba(21,166,151,${alpha.toFixed(3)})`;
                  const fg = rank >= 0 ? (rank === 2 ? "#161616" : "#fff") : (alpha > 0.55 ? "#fff" : IOH.ink);
                  return <td key={v} style={{ ...td, background: bg, color: fg, textAlign: "center", minWidth: 56 }}>{val > 0 ? fmtMn(val) : "—"}</td>;
                })}
              </tr>
            ))}</tbody>
          </table>
        </div>
      </Panel>
      <Panel title="Growth MoM% Heatmap (diverging)">
        <div style={{ overflowX: "auto" }}>
          <table style={{ borderCollapse: "collapse", fontSize: 11, minWidth: 560 }}>
            <thead><tr>
              <th style={{ ...th, textAlign: "left", background: IOH.white }}></th>
              {p.validity_labels.map((v) => <th key={v} style={th}>{v}</th>)}
            </tr></thead>
            <tbody>{p.quota_labels.map((q, ri) => (
              <tr key={q}><td style={{ ...td, textAlign: "left", fontWeight: 600, whiteSpace: "nowrap" }}>{q}</td>
                {p.validity_labels.map((v, ci) => {
                  const g = p.growth_matrix[ri][ci]; let bg: string = IOH.white;
                  if (g !== null) { const a = (Math.abs(g) / gMax).toFixed(3); bg = g >= 0 ? `rgba(14,133,121,${a})` : `rgba(185,28,28,${a})`; }
                  return <td key={v} style={{ ...td, background: bg, textAlign: "center", minWidth: 52 }}>{g === null ? "—" : fmtPct(g)}</td>;
                })}
              </tr>
            ))}</tbody>
          </table>
        </div>
      </Panel>
    </div>
  );
}
function BenchmarkView({ b }: { b: Benchmark }) {
  const OPS = [
    { key: "im3", label: "IM3", bg: IOH.band_im3, fg: "#161616" },
    { key: "tri", label: "3ID", bg: IOH.band_3id, fg: "#fff" },
    { key: "tsel", label: "TSEL", bg: "#00549F", fg: "#fff" },
    { key: "xl", label: "XL", bg: "#0058A3", fg: "#fff" },
    { key: "sf", label: "SF", bg: "#7B2D8B", fg: "#fff" },
  ];
  return (
    <div>
      <Panel title={`Network Benchmark (FB) · ${b.scope.name_used}`}>
        <div style={{ overflowX: "auto" }}>
          <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 640 }}>
            <thead><tr>
              <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 80 }}>Month</th>
              {OPS.map((op) => <th key={op.key} colSpan={3} style={{ ...th, background: op.bg, color: op.fg }}>{op.label}</th>)}
            </tr><tr>
              <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 2, background: IOH.white }}></th>
              {OPS.map((op) => (["DL (Mbps)", "Latency", "Signal"].map((s) => <th key={op.key + s} style={{ ...th, background: op.bg, color: op.fg, fontWeight: 400, opacity: 0.9 }}>{s}</th>)))}
            </tr></thead>
            <tbody>{b.fb_benchmark.map((r, ri) => {
              const bg = ri % 2 ? IOH.zebra : IOH.white;
              return (
                <tr key={ri} style={{ background: bg }}>
                  <td style={{ ...td, textAlign: "left", fontWeight: 600, position: "sticky", left: 0, zIndex: 1, background: bg }}>{r.month_prefix}</td>
                  {OPS.map((op) => {
                    const rd = r as Record<string, unknown>;
                    const dl = rd[`dl_speed_${op.key}_4g`] as number; const lat = rd[`latency_${op.key}_4g`] as number; const sig = rd[`signal_${op.key}_4g`] as number;
                    return ([
                      <td key={op.key + "dl"} style={{ ...td, fontWeight: op.key === "im3" ? 700 : 400 }}>{dl?.toLocaleString("id-ID", { maximumFractionDigits: 1 }) ?? "—"}</td>,
                      <td key={op.key + "lat"} style={td}>{lat?.toLocaleString("id-ID", { maximumFractionDigits: 0 }) ?? "—"}</td>,
                      <td key={op.key + "sig"} style={td}>{sig?.toLocaleString("id-ID", { maximumFractionDigits: 1 }) ?? "—"}</td>,
                    ]);
                  })}
                </tr>
              );
            })}</tbody>
          </table>
        </div>
      </Panel>
      {b.availability.length > 0 && (
        <Panel title={`Network Availability · ${b.scope.name_used}`}>
          <div style={{ overflowX: "auto" }}>
            <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 640 }}>
              <thead><tr>
                <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 2, background: IOH.white }}>Month</th>
                <th style={th}>Avg Avail 2G %</th><th style={th}>Avg Avail 4G %</th><th style={th}>Avg Avail 5G %</th>
                <th style={th}>Min 2G %</th><th style={th}>Min 4G %</th><th style={th}>Min 5G %</th>
                <th style={th}>SLA 99%</th><th style={th}>SLA 95%</th><th style={th}>Down Events 4G</th><th style={th}>Downtime 4G (hrs)</th>
              </tr></thead>
              <tbody>{b.availability.map((r, i) => {
                const bg = i % 2 ? IOH.zebra : IOH.white;
                const nv = (v: unknown) => v == null ? "—" : Number(v).toLocaleString("id-ID", { maximumFractionDigits: 2 });
                return (
                  <tr key={i} style={{ background: bg }}>
                    <td style={{ ...td, textAlign: "left", fontWeight: 600, position: "sticky", left: 0, zIndex: 1, background: bg }}>{String(r.month_id)}</td>
                    <td style={td}>{nv(r.mean_avg_avail_pct_2g)}</td><td style={td}>{nv(r.mean_avg_avail_pct_4g)}</td><td style={td}>{nv(r.mean_avg_avail_pct_5g)}</td>
                    <td style={td}>{nv(r.min_avail_pct_2g)}</td><td style={td}>{nv(r.min_avail_pct_4g)}</td><td style={td}>{nv(r.min_avail_pct_5g)}</td>
                    <td style={td}>{nv(r.sites_below_sla99_4g)}</td><td style={td}>{nv(r.sites_below_sla95_4g)}</td>
                    <td style={td}>{nv(r.total_down_day_events_4g)}</td><td style={td}>{nv(r.total_downtime_hrs_4g)}</td>
                  </tr>
                );
              })}</tbody>
            </table>
          </div>
        </Panel>
      )}
    </div>
  );
}
function MarketInsightView({ ins }: { ins: MarketInsight }) {
  const sg = (x: number | null) => ((x ?? 0) >= 0 ? IOH.pos : IOH.neg);
  return (
    <div>
      {ins.panels.map((p, pi) => (
        <Panel key={pi} title={p.title}>
          <div style={{ overflowX: "auto" }}>
            <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 400 + p.months.length * 100 }}>
              <thead>
                <tr>
                  <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 150 }}>Operator</th>
                  {p.months.map((m) => (
                    <th key={m} style={{ ...th, textAlign: "right" }}>{m}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {p.actors.map((actor, ri) => {
                  const bg = ri % 2 ? IOH.zebra : IOH.white;
                  const isIndustry = actor.actor === "Industry";
                  return (
                    <tr key={ri} style={{ background: bg }}>
                      <td style={{ ...td, textAlign: "left", fontWeight: isIndustry ? 700 : 600, position: "sticky", left: 0, zIndex: 1, background: bg }}>
                        {actor.actor}
                      </td>
                      {actor.history.map((h, ci) => {
                        const isPct = p.kind.startsWith("pct");
                        const val = h.value;
                        const growth = h.growth;
                        return (
                          <td key={ci} style={td}>
                            <div style={{ fontWeight: isIndustry ? 700 : 500 }}>
                              {val == null ? "—" : (isPct ? fmtPct(val) : val.toLocaleString("id-ID", { maximumFractionDigits: 0 }))}
                            </div>
                            {growth != null && (
                              <div style={{ fontSize: 10, color: sg(growth), marginTop: 2 }}>
                                {(growth >= 0 ? "▲" : "▼")} {Math.abs(growth).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}{p.kind.startsWith("pct") ? "pp" : "%"}
                              </div>
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Panel>
      ))}
    </div>
  );
}
function FlatTable({ s }: { s: CompSection }) {
  const columns = s.columns ?? ["Share %"];
  const fmtCell = (v: number | null, ci: number) => {
    if (v === null || v === undefined) return "—";
    if (ci === 0) return `${v.toLocaleString("id-ID", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}%`;
    return v.toLocaleString("id-ID");
  };
  return (
    <Panel title={`${s.title}${s.month_used ? ` · ${s.month_used}` : ""}`}>
      <div style={{ overflowX: "auto" }}>
        <table style={{ borderCollapse: "collapse", fontSize: 12.5, minWidth: 360 }}>
          <thead><tr>
            <th style={{ ...th, textAlign: "left" }}>Operator</th>
            {columns.map((c) => <th key={c} style={th}>{c}</th>)}
          </tr></thead>
          <tbody>{(s.rows ?? []).map((r, i) => {
            const cells = r.cells ?? [r.value];
            return (
              <tr key={i} style={{ background: i % 2 ? IOH.zebra : IOH.white }}>
                <td style={{ ...td, textAlign: "left", fontWeight: r.actor === "IOH" || r.actor === "Industry" ? 700 : 500 }}>{r.actor}</td>
                {columns.map((_c, ci) => <td key={ci} style={{ ...td, fontWeight: ci === 0 ? 600 : 400 }}>{fmtCell(cells[ci] ?? null, ci)}</td>)}
              </tr>
            );
          })}</tbody>
        </table>
      </div>
    </Panel>
  );
}

function FtthCountTable({ s }: { s: CompSection }) {
  const columns = s.columns ?? ["Count"];
  const fmtN = (v: number | null | undefined) => (v === null || v === undefined || isNaN(v as number)) ? "—" : (v as number).toLocaleString("id-ID", { maximumFractionDigits: 0 });
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12.5, minWidth: 320 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left" }}>Item</th>
          {columns.map((c) => <th key={c} style={th}>{c}</th>)}
        </tr></thead>
        <tbody>{(s.rows ?? []).map((r, i) => {
          const cells = r.cells ?? [r.value ?? null];
          return (
            <tr key={i} style={{ background: i % 2 ? IOH.zebra : IOH.white }}>
              <td style={{ ...td, textAlign: "left", fontWeight: 600, whiteSpace: "nowrap" }}>{r.label ?? r.actor}</td>
              {columns.map((_c, ci) => <td key={ci} style={{ ...td, fontWeight: 700 }}>{fmtN(cells[ci] ?? null)}</td>)}
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}
function FtthHierRows({ nodes, depth, columns }: { nodes: HierNode[]; depth: number; columns: string[] }) {
  const [open, setOpen] = useState<Record<number, boolean>>({});
  const fmtN = (v: number | null | undefined) => (v === null || v === undefined || isNaN(v as number)) ? "—" : (v as number).toLocaleString("id-ID", { maximumFractionDigits: 0 });
  return (<>
    {nodes.map((n, i) => {
      const hasKids = (n.children?.length ?? 0) > 0;
      const isOpen = !!open[i];
      const bg = depth === 0 ? IOH.white : depth === 1 ? IOH.zebra : "var(--ioh-panel)";
      return (
        <Fragment key={i}>
          <tr style={{ background: bg, cursor: hasKids ? "pointer" : "default" }} onClick={() => hasKids && setOpen((o) => ({ ...o, [i]: !o[i] }))}>
            <td style={{ ...td, textAlign: "left", whiteSpace: "nowrap", fontWeight: depth === 0 ? 700 : depth === 1 ? 600 : 400, paddingLeft: 8 + depth * 16, position: "sticky", left: 0, zIndex: 1, background: bg, boxShadow: `1px 0 0 ${IOH.rule}` }}>
              {hasKids ? (isOpen ? "▾ " : "▸ ") : depth > 0 ? "• " : ""}{n.label}
            </td>
            {n.cells.map((c, ci) => <td key={ci} style={{ ...td, fontWeight: ci === n.cells.length - 1 ? 700 : 500 }}>{fmtN(c)}</td>)}
          </tr>
          {isOpen && hasKids && <FtthHierRows nodes={n.children!} depth={depth + 1} columns={columns} />}
        </Fragment>
      );
    })}
  </>);
}
function FtthHierarchyTable({ s }: { s: CompSection }) {
  const columns = s.columns ?? ["SO", "SA", "PA"];
  const nodes = (s.rows ?? []) as HierNode[];
  return (
    <div style={{ overflowX: "auto" }}>
      <div style={{ ...eyebrow, fontSize: 10, color: IOH.mute, marginBottom: 6 }}>Tap a row to drill down · sorted by MTD</div>
      <table style={{ borderCollapse: "collapse", width: "100%", fontSize: 12, minWidth: 420 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 3, background: IOH.white, minWidth: 200, boxShadow: `1px 0 0 ${IOH.rule}` }}>SM / TL / AE</th>
          {columns.map((c) => <th key={c} style={{ ...th, background: IOH.band_ioh, color: "#fff" }}>{c}</th>)}
        </tr></thead>
        <tbody><FtthHierRows nodes={nodes} depth={0} columns={columns} /></tbody>
      </table>
    </div>
  );
}

/* ─── styles ─── */
const seg: React.CSSProperties = { display: "flex", gap: 3, padding: 3, background: "var(--ioh-panel)", borderRadius: 999, marginBottom: 14, flexWrap: "nowrap", overflowX: "auto", maxWidth: "100%" };
const segBtn: React.CSSProperties = { background: "transparent", color: "var(--ioh-mute)", border: "1px solid transparent", borderRadius: 999, padding: "7px 16px", fontSize: 13, fontWeight: 600, cursor: "pointer", whiteSpace: "nowrap", flex: "0 0 auto" };
const segBtnActive: React.CSSProperties = { background: "var(--ioh-white)", color: "var(--ioh-ink)", boxShadow: "0 1px 3px rgba(15,31,29,.12)" };
const chipBtn: React.CSSProperties = { background: "var(--ioh-white)", color: "var(--ioh-mute)", border: "1px solid var(--ioh-rule)", borderRadius: 999, padding: "4px 12px", fontSize: 11.5, fontWeight: 600, cursor: "pointer", whiteSpace: "nowrap" };
const chipBtnActive: React.CSSProperties = { background: "#15A697", color: "#fff", borderColor: "#15A697" };
const iconTab: React.CSSProperties = { display: "inline-flex", alignItems: "center", gap: 6, background: "var(--ioh-white)", color: "var(--ioh-mute)", border: "1px solid var(--ioh-rule)", borderRadius: 10, padding: "7px 12px", cursor: "pointer", whiteSpace: "nowrap", flex: "0 0 auto" };
const iconTabActive: React.CSSProperties = { background: "#15A697", color: "#fff", borderColor: "#15A697" };
const pill: React.CSSProperties = { background: "var(--ioh-panel)", color: "var(--ioh-mute)", borderRadius: 999, padding: "4px 12px", fontSize: 11.5, fontWeight: 600, border: "1px solid var(--ioh-rule)" };
const eyebrow: React.CSSProperties = { color: "var(--ioh-teal-deep)", fontSize: 10.5, fontWeight: 700, letterSpacing: 0.8, textTransform: "uppercase" };
const ctrlWrap: React.CSSProperties = { display: "flex", flexDirection: "column", gap: 3 };
const ctrlLbl: React.CSSProperties = { ...eyebrow, fontSize: 9.5 };
const select: React.CSSProperties = { padding: "6px 8px", borderRadius: 9, border: "1px solid var(--ioh-rule)", background: "var(--ioh-white)", fontSize: 12.5, fontFamily: "Prompt, sans-serif", color: "var(--ioh-ink)", minWidth: 120, maxWidth: 220 };
const btnPrimary: React.CSSProperties = { background: "#15A697", color: "#fff", border: "none", borderRadius: 9, padding: "8px 14px", fontSize: 14, fontWeight: 700, cursor: "pointer" };
const btnGhost: React.CSSProperties = { background: "transparent", color: "var(--ioh-teal-deep)", border: "1px solid var(--ioh-rule)", borderRadius: 10, padding: "6px 12px", fontSize: 13, cursor: "pointer" };
const th: React.CSSProperties = { padding: "6px 8px", textAlign: "right", border: "1px solid var(--ioh-rule)", fontSize: 11, whiteSpace: "nowrap" };
const td: React.CSSProperties = { padding: "5px 8px", textAlign: "right", borderBottom: "1px solid var(--ioh-rule)", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" };
