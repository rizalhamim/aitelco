"use client";
import { useEffect, useState, useCallback, useRef } from "react";
import { useRouter } from "next/navigation";
import { authFetch, isLoggedIn } from "@/lib/auth";

const C = {
  teal: "#15A697", tealDeep: "var(--ioh-teal-deep)", ink: "var(--ioh-ink)", mute: "var(--ioh-mute)",
  rule: "var(--ioh-rule)", panel: "var(--ioh-panel)", white: "var(--ioh-white)", zebra: "var(--ioh-zebra)",
  pos: "#13A58F", neg: "#E26A6A", band: "#15A697",
};

type SiteRow = { site_id: string; site_name: string; branch?: string; kecamatan?: string; kabupaten?: string; distance_km?: number; latitude?: number; longitude?: number };
type Metric = { code: string; lmtd: number | null; mtd: number | null; growth: number | null };
type Detail = {
  attributes: Record<string, unknown>;
  brand: string;
  month_id: string;
  metrics: Metric[];
  performance: Record<string, number | null>;
  funnel: { m1s: number | null; m2s: number | null; p1m: number | null; p2m: number | null; gross_add: number | null };
  ga_channels: { channel: string; ga: number; pct: number | null }[];
  history: Record<string, number | string | null>[];
  channels: { channel: string; detail: string; revenue: number }[];
  channel_metrics: { channel: string; lmtd: number; mtd: number; growth: number | null }[];
  channel_history: Record<string, number | string>[];
  price_slabs: { slab: string; revenue: number; hit: number }[];
  quota_slabs: { slab: string; revenue: number }[];
  validity_slabs: { slab: string; revenue: number }[];
  top_products: { product: string; family: string; revenue: number; hit: number }[];
  network: { mtd: Record<string, number | null> | null; lmtd: Record<string, number | null> | null; history: Record<string, number | string | null>[] };
  availability: { mtd: Record<string, number | null> | null; lmtd: Record<string, number | null> | null; history: Record<string, number | string | null>[] };
  fwa: { mtd: Record<string, number | null> | null; lmtd: Record<string, number | null> | null; history: Record<string, number | string | null>[] };
  error?: string;
};

// label rows for the new sections: [code, label, format]  (fmt: 'mn'|'num'|'pct')
const NET_ROWS: [string, string, string][] = [
  ["data_uu30_all", "Data UU (All)", "num"], ["data_uu30_dev_2g", "Data UU Dev 2G", "num"],
  ["data_uu30_dev_4g", "Data UU Dev 4G", "num"], ["data_uu30_dev_5g", "Data UU Dev 5G", "num"],
  ["traffic_2g", "Traffic 2G", "num"], ["traffic_4g", "Traffic 4G", "num"], ["traffic_5g", "Traffic 5G", "num"],
  ["traffic_total", "Traffic Total", "num"], ["dev_all", "Device Total", "num"],
  ["dev5g_total", "Device 5G", "num"], ["dev5g_with_traffic", "Device 5G w/ Traffic", "num"],
  ["dev5g_pct", "Device 5G % vs Total", "pct"], ["dev5g_traffic_pct", "Dev 5G w/Traffic % vs Dev 5G", "pct"],
];
const AVAIL_ROWS: [string, string, string][] = [
  ["avg_avail_pct_2g", "Availability 2G %", "pct"], ["avg_avail_pct_4g", "Availability 4G %", "pct"],
  ["avg_avail_pct_5g", "Availability 5G %", "pct"], ["days_down_2g", "Days Down 2G", "num"],
  ["days_down_4g", "Days Down 4G", "num"], ["days_down_5g", "Days Down 5G", "num"],
];
const FWA_ROWS: [string, string, string][] = [
  ["rev_fwa_total", "Revenue FWA Total", "mn"], ["rev_fwa_pack", "Revenue FWA Pack", "mn"],
  ["rev_fwa_sim", "Revenue FWA SIM", "mn"], ["rev_fwa_regular", "Revenue FWA Regular", "mn"],
  ["rev_fwa_non_broadband", "Revenue FWA Non-BB", "mn"], ["fwa_rgu90", "FWA RGU 90D", "num"],
  ["fwa_rgu_ga", "FWA Gross Add", "num"], ["fwa_grosschurn90", "FWA Gross Churn 90D", "num"],
  ["fwa_churnback90", "FWA Churn Back 90D", "num"], ["fwa_net_add_90_closing", "FWA Net Add 90D", "num"],
  ["fwa_pack_hits", "FWA Pack Hits", "num"], ["vlr_fwa_less_90d", "VLR FWA <90D", "num"],
  ["vlr_fwa_91_180d", "VLR FWA 91-180D", "num"], ["vlr_fwa_above_181d", "VLR FWA >181D", "num"],
];

const METRIC_LABELS: Record<string, string> = {
  rev_prepaid: "Revenue Prepaid", rev_vsd: "Revenue VSD", rev_nonvsd: "Revenue Non-VSD",
  rev_data: "Revenue Data", rev_voice: "Revenue Voice", rev_sms: "Revenue SMS",
  rev_trade: "Revenue Trade", rev_organic: "Revenue Organic", rev_nontrade: "Revenue Non-Trade",
  rev_acquisition_m0: "Revenue Acq M0", subs_rgu_90d: "RGU 90D", subs_rgu_30d: "RGU 30D",
  subs_gross_add: "Gross Add", net_add_90d: "Net Add 90D", net_add_30d: "Net Add 30D",
  gross_churn_90d: "Gross Churn 90D", gross_churn_30d: "Gross Churn 30D", churn_back_90d: "Churn Back 90D",
  subs_net_churn_90d: "Net Churn 90D", subs_vlr_30d: "VLR 30D", subs_avg_vlr_daily: "VLR Daily",
  datauu: "Data Users", datauu30d: "Data Users 30D", usg_data_gb: "Usage Data (GB)",
  usg_og_voice_min: "Usage Voice (Min)", usg_og_sms_cnt: "Usage SMS", ga_m1s: "GA M1S", ga_m2s: "GA M2S",
  ga_p1m: "GA P1M", ga_p2m: "GA P2M", subs_hvc: "HVC Subs", subs_hvc_stay: "HVC Stay",
  subs_hvc_in: "HVC In", subs_hvc_out: "HVC Out",
};
const isRevMetric = (c: string) => c.startsWith("rev_") || c === "usg_data_gb";

function mn(v: number | null | undefined): string {
  if (v === null || v === undefined || isNaN(v as number)) return "—";
  if (Math.abs(v) >= 1e6) return `${(v / 1e6).toLocaleString("id-ID", { maximumFractionDigits: 1 })} Mn`;
  return v.toLocaleString("id-ID", { maximumFractionDigits: 0 });
}
function num(v: number | null | undefined): string {
  if (v === null || v === undefined || isNaN(v as number)) return "—";
  return v.toLocaleString("id-ID", { maximumFractionDigits: 0 });
}

export default function SitePerformancePage() {
  const router = useRouter();
  const [mode, setMode] = useState<"coordinate" | "search">("coordinate");
  const [query, setQuery] = useState("");
  const [list, setList] = useState<SiteRow[]>([]);
  const [loadingList, setLoadingList] = useState(false);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [selected, setSelected] = useState<string>("");
  const [brand, setBrand] = useState<"ioh" | "im3" | "3id">("ioh");
  const [err, setErr] = useState("");

  useEffect(() => {
    if (typeof window !== "undefined" && !isLoggedIn()) router.push("/login");
  }, [router]);

  const locate = useCallback(() => {
    setErr(""); setList([]); setLoadingList(true);
    if (!navigator.geolocation) { setErr("Geolocation tidak didukung."); setLoadingList(false); return; }
    navigator.geolocation.getCurrentPosition(async (pos) => {
      try {
        const r = await authFetch("/api/site/nearest", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ lat: pos.coords.latitude, lon: pos.coords.longitude }) });
        const d = await r.json();
        if (d.error) setErr(d.error); else setList(d.sites || []);
      } catch (e) { setErr(String(e)); }
      setLoadingList(false);
    }, (e) => { setErr("Gagal ambil lokasi: " + e.message); setLoadingList(false); }, { enableHighAccuracy: true, timeout: 15000 });
  }, []);

  // search debounce
  useEffect(() => {
    if (mode !== "search") return;
    const t = setTimeout(async () => {
      if (query.trim().length < 2) { setList([]); return; }
      setLoadingList(true);
      try {
        const r = await authFetch(`/api/site/search?q=${encodeURIComponent(query.trim())}`);
        const d = await r.json();
        setList(d.sites || []);
      } catch { /* ignore */ }
      setLoadingList(false);
    }, 350);
    return () => clearTimeout(t);
  }, [query, mode]);

  // Cache details per site+brand so brand switching is instant (no refetch).
  const cacheRef = useRef<Map<string, Detail>>(new Map());

  const openSite = useCallback(async (sid: string, br: string) => {
    setSelected(sid);
    const hit = cacheRef.current.get(`${sid}|${br}`);
    if (hit) { setDetail(hit); setLoadingDetail(false); }
    else { setLoadingDetail(true); setDetail(null); }
    try {
      // Fetch the requested brand first (render fast), then prefetch the others in background.
      const key = `${sid}|${br}`;
      if (!cacheRef.current.has(key)) {
        const r = await authFetch(`/api/site/detail?site_id=${encodeURIComponent(sid)}&brand=${br}`);
        const d: Detail = await r.json();
        cacheRef.current.set(key, d);
        setDetail(d);
        setLoadingDetail(false);
      }
      // Prefetch others asynchronously
      const others = ["ioh", "im3", "3id"].filter((b) => b !== br);
      setTimeout(() => {
        Promise.all(others.map(async (b) => {
          const k = `${sid}|${b}`;
          if (cacheRef.current.has(k)) return;
          try {
            const r = await authFetch(`/api/site/detail?site_id=${encodeURIComponent(sid)}&brand=${b}`);
            const d = await r.json();
            if (!d.error) cacheRef.current.set(k, d);
          } catch { /* ignore */ }
        }));
      }, 500);
    } catch (e) { setDetail({ error: String(e) } as Detail); setLoadingDetail(false); }
  }, []);

  const changeBrand = useCallback((b: "ioh" | "im3" | "3id") => {
    setBrand(b);
    const hit = selected ? cacheRef.current.get(`${selected}|${b}`) : null;
    if (hit) setDetail(hit);          // instant from cache
    else if (selected) openSite(selected, b);
  }, [selected, openSite]);

  // Deep-link: open a specific site when arriving with ?site_id=... (e.g. from Map Query).
  const deepLinkedRef = useRef(false);
  useEffect(() => {
    if (deepLinkedRef.current || typeof window === "undefined") return;
    const sid = new URLSearchParams(window.location.search).get("site_id");
    if (sid) {
      deepLinkedRef.current = true;
      setMode("search");
      setQuery(sid);
      openSite(sid, "ioh");
    }
  }, [openSite]);

  return (
    <div style={{ minHeight: "100vh", background: C.panel, fontFamily: "Prompt, sans-serif", color: C.ink }}>
      <header style={{ background: C.white, borderBottom: `1px solid ${C.rule}`, padding: "14px 20px", display: "flex", alignItems: "center", gap: 12, position: "sticky", top: 0, zIndex: 10 }}>
        <button onClick={() => router.push("/")} style={btnGhost}>← Chat</button>
        <div style={{ fontFamily: "Poppins, sans-serif", fontWeight: 700, fontSize: 18 }}>Site Performance</div>
      </header>

      <div style={{ maxWidth: 1100, margin: "0 auto", padding: 20 }}>
        {/* mode toggle */}
        <div style={{ display: "flex", gap: 8, marginBottom: 14 }}>
          {([["coordinate", "📍 Coordinate"], ["search", "🔎 Site Search"]] as const).map(([k, lbl]) => (
            <button key={k} onClick={() => { setMode(k); setList([]); setDetail(null); setSelected(""); }}
              style={{ ...tabBtn, ...(mode === k ? tabBtnActive : {}) }}>{lbl}</button>
          ))}
        </div>

        {/* controls */}
        {mode === "coordinate" ? (
          <button onClick={locate} style={{ ...btnPrimary, marginBottom: 14 }}>{loadingList ? "Mencari…" : "Gunakan Lokasi Saya"}</button>
        ) : (
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Masukkan Site ID atau Site Name…"
            style={{ width: "100%", maxWidth: 420, padding: "10px 12px", borderRadius: 10, border: `1px solid ${C.rule}`, background: C.white, color: C.ink, fontSize: 14, marginBottom: 14 }} />
        )}
        {err && <div style={{ color: C.neg, fontSize: 13, marginBottom: 12 }}>{err}</div>}

        <div style={{ display: "grid", gridTemplateColumns: detail || loadingDetail ? "300px 1fr" : "1fr", gap: 16, alignItems: "start" }}>
          {/* list */}
          <Panel title={mode === "coordinate" ? "Site Terdekat" : "Hasil Pencarian"}>
            {loadingList && <div style={{ color: C.mute, fontSize: 13 }}>Memuat…</div>}
            {!loadingList && list.length === 0 && <div style={{ color: C.mute, fontSize: 13 }}>{mode === "coordinate" ? "Tekan tombol di atas." : "Ketik minimal 2 karakter."}</div>}
            <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
              {list.map((s) => (
                <button key={s.site_id} onClick={() => openSite(s.site_id, brand)}
                  style={{ textAlign: "left", border: `1px solid ${selected === s.site_id ? C.teal : C.rule}`, background: selected === s.site_id ? "#EAF6F4" : C.white, borderRadius: 10, padding: "8px 10px", cursor: "pointer" }}>
                  <div style={{ fontWeight: 600, fontSize: 13 }}>{s.site_name}</div>
                  <div style={{ fontSize: 11, color: C.mute }}>{s.site_id}{s.distance_km != null ? ` · ${s.distance_km} km` : ""} · {s.branch}</div>
                </button>
              ))}
            </div>
          </Panel>

          {/* detail */}
          {(detail || loadingDetail) && (
            <div>
              {loadingDetail && <Panel title="Detail"><div style={{ color: C.mute }}>Memuat performa site…</div></Panel>}
              {detail && detail.error && <Panel title="Detail"><div style={{ color: C.neg }}>{detail.error}</div></Panel>}
              {detail && !detail.error && <SiteDetailView d={detail} brand={brand} setBrand={changeBrand} />}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function fmtBy(kind: string, v: number | null | undefined): string {
  if (v === null || v === undefined || isNaN(v as number)) return "—";
  if (kind === "mn") return mn(v);
  if (kind === "pct") return `${(v as number).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`;
  return num(v);
}

// LMTD · MTD · Growth from two snapshot dicts (mirrors MTD metric table).
function KVLMTDTable({ rows, mtd, lmtd }: { rows: [string, string, string][]; mtd: Record<string, number | null> | null; lmtd: Record<string, number | null> | null }) {
  const sg = (g: number | null) => ((g ?? 0) >= 0 ? C.pos : C.neg);
  return (
    <table style={tbl}>
      <thead><tr><th style={{ ...th, textAlign: "left" }}>Metric</th><th style={th}>LMTD</th><th style={th}>MTD</th><th style={th}>Growth</th></tr></thead>
      <tbody>{rows.map(([code, label, kind], i) => {
        const m = mtd?.[code] ?? null, l = lmtd?.[code] ?? null;
        const g = (m !== null && l !== null && l !== 0 && kind !== "pct") ? (m - l) / l * 100
          : (m !== null && l !== null && kind === "pct") ? m - l : null;
        return (
          <tr key={code} style={{ background: i % 2 ? C.zebra : C.white }}>
            <td style={{ ...td, textAlign: "left", fontWeight: 500 }}>{label}</td>
            <td style={td}>{fmtBy(kind, l)}</td>
            <td style={{ ...td, fontWeight: 700 }}>{fmtBy(kind, m)}</td>
            <td style={{ ...td, color: sg(g) }}>{g === null ? "—" : `${g >= 0 ? "▲" : "▼"} ${Math.abs(g).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}${kind === "pct" ? "pp" : "%"}`}</td>
          </tr>
        );
      })}</tbody>
    </table>
  );
}

// label rows × month columns for the new sections.
function MonthlyKVTable({ rows, history }: { rows: [string, string, string][]; history: Record<string, number | string | null>[] }) {
  const months = history.map((h) => String(h.month_id));
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ ...tbl, minWidth: 150 + months.length * 84 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 2, background: C.white, minWidth: 170 }}>Metric</th>
          {months.map((m) => <th key={m} style={th}>{m}</th>)}
        </tr></thead>
        <tbody>{rows.map(([code, label, kind], i) => {
          const bg = i % 2 ? C.zebra : C.white;
          return (
            <tr key={code} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", fontWeight: 500, position: "sticky", left: 0, zIndex: 1, background: bg, minWidth: 170 }}>{label}</td>
              {history.map((h, j) => <td key={j} style={td}>{fmtBy(kind, h[code] as number)}</td>)}
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}

// Full-month table: metric rows × month columns (mirrors the MTD metric table).
function MonthlyTable({ history, codes }: { history: Record<string, number | string | null>[]; codes: string[] }) {
  const months = history.map((h) => String(h.month_id));
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ ...tbl, minWidth: 120 + months.length * 90 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 2, background: C.white, minWidth: 150 }}>Metric</th>
          {months.map((m) => <th key={m} style={th}>{m}</th>)}
        </tr></thead>
        <tbody>{codes.map((c, i) => {
          const bg = i % 2 ? C.zebra : C.white;
          const fmt = (v: unknown) => (isRevMetric(c) ? mn(v as number) : num(v as number));
          return (
            <tr key={c} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", fontWeight: 500, position: "sticky", left: 0, zIndex: 1, background: bg, minWidth: 150 }}>{METRIC_LABELS[c] || c}</td>
              {history.map((h, j) => <td key={j} style={td}>{fmt(h[c])}</td>)}
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}

function MonthlyChannelTable({ history }: { history: Record<string, number | string>[] }) {
  const months = history.map((h) => String(h.month_id));
  const rows: [string, string][] = [["ORGANIC", "Organic"], ["DIGITAL DISTRIBUTION", "Digital"], ["MOBO TRADE", "MOBO Trade"]];
  return (
    <div style={{ overflowX: "auto" }}>
      <table style={{ ...tbl, minWidth: 120 + months.length * 90 }}>
        <thead><tr>
          <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, zIndex: 2, background: C.white, minWidth: 130 }}>Channel</th>
          {months.map((m) => <th key={m} style={th}>{m}</th>)}
        </tr></thead>
        <tbody>{rows.map(([key, lbl], i) => {
          const bg = i % 2 ? C.zebra : C.white;
          return (
            <tr key={key} style={{ background: bg }}>
              <td style={{ ...td, textAlign: "left", fontWeight: 600, position: "sticky", left: 0, zIndex: 1, background: bg }}>{lbl}</td>
              {history.map((h, j) => <td key={j} style={td}>{mn(h[key] as number)}</td>)}
            </tr>
          );
        })}</tbody>
      </table>
    </div>
  );
}

function MetricTable({ metrics, codes }: { metrics: Metric[]; codes: string[] }) {
  const byCode = Object.fromEntries(metrics.map((m) => [m.code, m]));
  const fmt = (m: Metric, v: number | null) => (isRevMetric(m.code) ? mn(v) : num(v));
  const sg = (g: number | null) => ((g ?? 0) >= 0 ? C.pos : C.neg);
  return (
    <table style={tbl}>
      <thead><tr>
        <th style={{ ...th, textAlign: "left" }}>Metric</th><th style={th}>LMTD</th><th style={th}>MTD</th><th style={th}>Growth</th>
      </tr></thead>
      <tbody>{codes.map((c, i) => {
        const m = byCode[c]; if (!m) return null;
        return (
          <tr key={c} style={{ background: i % 2 ? C.zebra : C.white }}>
            <td style={{ ...td, textAlign: "left", fontWeight: 500 }}>{METRIC_LABELS[c] || c}</td>
            <td style={td}>{fmt(m, m.lmtd)}</td>
            <td style={{ ...td, fontWeight: 700 }}>{fmt(m, m.mtd)}</td>
            <td style={{ ...td, color: sg(m.growth) }}>{m.growth === null ? "—" : `${m.growth >= 0 ? "▲" : "▼"} ${Math.abs(m.growth).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`}</td>
          </tr>
        );
      })}</tbody>
    </table>
  );
}

function SiteDetailView({ d, brand, setBrand }: { d: Detail; brand: "ioh" | "im3" | "3id"; setBrand: (b: "ioh" | "im3" | "3id") => void }) {
  const a = d.attributes;
  const [view, setView] = useState<"snapshot" | "fullmonth">("snapshot");
  const str = (v: unknown) => (v === null || v === undefined || v === "" ? "—" : String(v));
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
      {/* header */}
      <div style={{ background: C.white, borderRadius: 16, borderTop: `3px solid ${C.teal}`, padding: 18, boxShadow: "0 2px 10px rgba(15,31,29,.06)" }}>
        <div style={{ fontFamily: "Poppins, sans-serif", fontWeight: 700, fontSize: 20 }}>{str(a.site_name)} <span style={{ fontSize: 12, color: C.mute, fontWeight: 500 }}>{str(a.site_id)}</span></div>
        <div style={{ color: C.mute, fontSize: 12.5, marginTop: 4 }}>{str(a.site_type)} · {str(a.category)} · {str(a.kecamatan)}, {str(a.kabupaten)} · {str(a.branch)} · {str(a.micro_cluster)}</div>
        <div style={{ color: C.mute, fontSize: 11.5, marginTop: 2 }}>Region {str(a.region)} · Area {str(a.area)} · Addressable: {str(a.addressable)} · Profitability: {str(a.profitability_status_m1)} · Bulan {d.month_id}</div>
      </div>

      {/* brand tabs + view tabs */}
      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center" }}>
        <div style={{ display: "flex", gap: 4, background: C.panel, borderRadius: 999, padding: 3 }}>
          {([["ioh", "IOH"], ["im3", "IM3"], ["3id", "3ID"]] as const).map(([k, lbl]) => (
            <button key={k} onClick={() => setBrand(k)} style={{ border: "none", borderRadius: 999, padding: "6px 16px", fontSize: 12.5, fontWeight: 700, cursor: "pointer", background: brand === k ? (k === "ioh" ? "#15A697" : k === "im3" ? "#F5A623" : "#EB008B") : "transparent", color: brand === k ? (k === "im3" ? "#161616" : "#fff") : C.mute }}>{lbl}</button>
          ))}
        </div>
        <div style={{ display: "flex", gap: 4, background: C.panel, borderRadius: 999, padding: 3 }}>
          {([["snapshot", "Snapshot (MTD)"], ["fullmonth", "Full Month"]] as const).map(([k, lbl]) => (
            <button key={k} onClick={() => setView(k)} style={{ border: "none", borderRadius: 999, padding: "6px 16px", fontSize: 12.5, fontWeight: 600, cursor: "pointer", background: view === k ? C.white : "transparent", color: view === k ? C.ink : C.mute, boxShadow: view === k ? "0 1px 3px rgba(0,0,0,.1)" : "none" }}>{lbl}</button>
          ))}
        </div>
      </div>

      {view === "fullmonth" ? (
        <>
          <Panel title="Revenue · Full Month">
            <MonthlyTable history={d.history} codes={["rev_prepaid", "rev_vsd", "rev_nonvsd", "rev_data", "rev_voice", "rev_sms", "rev_trade", "rev_organic", "rev_nontrade", "rev_acquisition_m0"]} />
          </Panel>
          <Panel title="Subscriber & Usage · Full Month">
            <MonthlyTable history={d.history} codes={["subs_rgu_90d", "subs_rgu_30d", "subs_gross_add", "net_add_90d", "net_add_30d", "gross_churn_90d", "gross_churn_30d", "churn_back_90d", "subs_net_churn_90d", "subs_vlr_30d", "subs_avg_vlr_daily", "datauu", "datauu30d", "subs_hvc", "subs_hvc_stay", "subs_hvc_in", "subs_hvc_out", "usg_data_gb", "usg_og_voice_min", "usg_og_sms_cnt"]} />
          </Panel>
          {d.channel_history.length > 0 && (
            <Panel title="Revenue by Channel · Full Month">
              <MonthlyChannelTable history={d.channel_history} />
            </Panel>
          )}
          {(d.network?.history?.length ?? 0) > 0 && (
            <Panel title="Network (Data UU · Traffic · Device) · Full Month"><MonthlyKVTable rows={NET_ROWS} history={d.network.history} /></Panel>
          )}
          {(d.availability?.history?.length ?? 0) > 0 && (
            <Panel title="Availability · Full Month"><MonthlyKVTable rows={AVAIL_ROWS} history={d.availability.history} /></Panel>
          )}
          {(d.fwa?.history?.length ?? 0) > 0 && (
            <Panel title="FWA · Full Month"><MonthlyKVTable rows={FWA_ROWS} history={d.fwa.history} /></Panel>
          )}
        </>
      ) : (
        <>
      {/* Revenue (LMTD/MTD/Growth) */}
      <Panel title="Revenue (LMTD · MTD · Growth)">
        <MetricTable metrics={d.metrics} codes={["rev_prepaid", "rev_vsd", "rev_nonvsd", "rev_data", "rev_voice", "rev_sms", "rev_trade", "rev_organic", "rev_nontrade", "rev_acquisition_m0"]} />
      </Panel>

      {/* Subscriber & Usage (LMTD/MTD/Growth) */}
      <Panel title="Subscriber & Usage (LMTD · MTD · Growth)">
        <MetricTable metrics={d.metrics} codes={["subs_rgu_90d", "subs_rgu_30d", "subs_gross_add", "net_add_90d", "net_add_30d", "gross_churn_90d", "gross_churn_30d", "churn_back_90d", "subs_net_churn_90d", "subs_vlr_30d", "subs_avg_vlr_daily", "datauu", "datauu30d", "subs_hvc", "subs_hvc_stay", "subs_hvc_in", "subs_hvc_out", "usg_data_gb", "usg_og_voice_min", "usg_og_sms_cnt"]} />
      </Panel>

      {/* Acquisition by Channel */}
      {d.ga_channels.length > 0 && (
        <Panel title="Acquisition by Channel (GA)">
          <table style={tbl}>
            <thead><tr><th style={{ ...th, textAlign: "left" }}>Channel</th><th style={th}>GA</th><th style={th}>%</th></tr></thead>
            <tbody>{d.ga_channels.map((g, i) => (
              <tr key={i} style={{ background: i % 2 ? C.zebra : C.white }}><td style={{ ...td, textAlign: "left", fontWeight: 600 }}>{g.channel}</td><td style={td}>{num(g.ga)}</td><td style={{ ...td, color: C.mute }}>{g.pct === null ? "—" : `${g.pct.toLocaleString("id-ID", { maximumFractionDigits: 1 })}%`}</td></tr>
            ))}</tbody>
          </table>
        </Panel>
      )}

      {/* Funnel */}
      <Panel title="Acquisition Funnel">
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {[["M1S", d.funnel.m1s], ["M2S", d.funnel.m2s], ["P1M", d.funnel.p1m], ["P2M", d.funnel.p2m], ["Gross Add", d.funnel.gross_add]].map(([k, v]) => (
            <div key={k as string} style={{ flex: 1, minWidth: 90, textAlign: "center", background: C.zebra, borderRadius: 10, padding: "10px 6px" }}>
              <div style={{ fontFamily: "Poppins, sans-serif", fontWeight: 700, fontSize: 18 }}>{num(v as number)}</div>
              <div style={{ fontSize: 11, color: C.mute }}>{k as string}</div>
            </div>
          ))}
        </div>
      </Panel>

      {/* Network (Data UU / Traffic / Device + ratios) */}
      {d.network?.mtd && (
        <Panel title="Network · Data UU · Traffic · Device (LMTD · MTD · Growth)">
          <KVLMTDTable rows={NET_ROWS} mtd={d.network.mtd} lmtd={d.network.lmtd} />
        </Panel>
      )}

      {/* Availability */}
      {d.availability?.mtd && (
        <Panel title="Availability (LMTD · MTD · Growth)">
          <KVLMTDTable rows={AVAIL_ROWS} mtd={d.availability.mtd} lmtd={d.availability.lmtd} />
        </Panel>
      )}

      {/* FWA */}
      {d.fwa?.mtd && (
        <Panel title="FWA Performance (LMTD · MTD · Growth)">
          <KVLMTDTable rows={FWA_ROWS} mtd={d.fwa.mtd} lmtd={d.fwa.lmtd} />
        </Panel>
      )}

      {/* Channel breakdown */}
      {/* Channel LMTD/MTD/Growth */}
      {d.channel_metrics.length > 0 && (
        <Panel title="Revenue by Channel (LMTD · MTD · Growth)">
          <table style={tbl}>
            <thead><tr><th style={{ ...th, textAlign: "left" }}>Channel</th><th style={th}>LMTD</th><th style={th}>MTD</th><th style={th}>Growth</th></tr></thead>
            <tbody>{d.channel_metrics.map((c, i) => (
              <tr key={i} style={{ background: i % 2 ? C.zebra : C.white }}>
                <td style={{ ...td, textAlign: "left", fontWeight: 600 }}>{c.channel}</td>
                <td style={td}>{mn(c.lmtd)}</td>
                <td style={{ ...td, fontWeight: 700 }}>{mn(c.mtd)}</td>
                <td style={{ ...td, color: (c.growth ?? 0) >= 0 ? C.pos : C.neg }}>{c.growth === null ? "—" : `${c.growth >= 0 ? "▲" : "▼"} ${Math.abs(c.growth).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`}</td>
              </tr>
            ))}</tbody>
          </table>
        </Panel>
      )}

      {/* Channel monthly history */}
      {d.channel_history.length > 0 && (
        <Panel title="Revenue by Channel · Monthly">
          <div style={{ overflowX: "auto" }}>
            <table style={{ ...tbl, minWidth: 460 }}>
              <thead><tr>
                <th style={{ ...th, textAlign: "left", position: "sticky", left: 0, background: C.white }}>Bulan</th>
                <th style={th}>Organic</th><th style={th}>Digital</th><th style={th}>MOBO Trade</th>
              </tr></thead>
              <tbody>{d.channel_history.map((h, i) => (
                <tr key={i} style={{ background: i % 2 ? C.zebra : C.white }}>
                  <td style={{ ...td, textAlign: "left", fontWeight: 700, position: "sticky", left: 0, background: i % 2 ? C.zebra : C.white }}>{String(h.month_id)}</td>
                  <td style={td}>{mn(h["ORGANIC"] as number)}</td><td style={td}>{mn(h["DIGITAL DISTRIBUTION"] as number)}</td><td style={td}>{mn(h["MOBO TRADE"] as number)}</td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        </Panel>
      )}

      <Panel title="Data Revenue · Channel Detail">
        <table style={tbl}>
          <thead><tr><th style={{ ...th, textAlign: "left" }}>Channel</th><th style={{ ...th, textAlign: "left" }}>Detail</th><th style={th}>Revenue</th></tr></thead>
          <tbody>{d.channels.map((c, i) => (
            <tr key={i} style={{ background: i % 2 ? C.zebra : C.white }}><td style={{ ...td, textAlign: "left", fontWeight: 600 }}>{c.channel}</td><td style={{ ...td, textAlign: "left", color: C.mute }}>{c.detail}</td><td style={td}>{mn(c.revenue)}</td></tr>
          ))}</tbody>
        </table>
      </Panel>

      {/* Top products */}
      <Panel title="Top Products">
        <table style={tbl}>
          <thead><tr><th style={{ ...th, textAlign: "left" }}>Product</th><th style={{ ...th, textAlign: "left" }}>Family</th><th style={th}>Revenue</th><th style={th}>Hits</th></tr></thead>
          <tbody>{d.top_products.map((t, i) => (
            <tr key={i} style={{ background: i % 2 ? C.zebra : C.white }}><td style={{ ...td, textAlign: "left", fontWeight: 600 }}>{t.product}</td><td style={{ ...td, textAlign: "left", color: C.mute }}>{t.family}</td><td style={td}>{mn(t.revenue)}</td><td style={td}>{num(t.hit)}</td></tr>
          ))}</tbody>
        </table>
      </Panel>

      {/* Slabs */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit,minmax(240px,1fr))", gap: 14 }}>
        <SlabPanel title="Price Slab" rows={d.price_slabs} hit />
        <SlabPanel title="Slab Kuota" rows={d.quota_slabs} />
        <SlabPanel title="Slab Masa Aktif" rows={d.validity_slabs} />
      </div>
        </>
      )}
    </div>
  );
}

function SlabPanel({ title, rows, hit }: { title: string; rows: { slab: string; revenue: number; hit?: number }[]; hit?: boolean }) {
  return (
    <Panel title={title}>
      <table style={tbl}>
        <thead><tr><th style={{ ...th, textAlign: "left" }}>Slab</th><th style={th}>Revenue</th>{hit && <th style={th}>Hits</th>}</tr></thead>
        <tbody>{rows.map((r, i) => (
          <tr key={i} style={{ background: i % 2 ? C.zebra : C.white }}><td style={{ ...td, textAlign: "left" }}>{r.slab}</td><td style={td}>{mn(r.revenue)}</td>{hit && <td style={td}>{num(r.hit)}</td>}</tr>
        ))}</tbody>
      </table>
    </Panel>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div style={{ background: C.white, borderRadius: 16, boxShadow: "0 2px 10px rgba(15,31,29,.05)", padding: 16 }}>
      <div style={{ ...eyebrow, marginBottom: 10 }}>{title}</div>
      {children}
    </div>
  );
}

const eyebrow: React.CSSProperties = { color: C.tealDeep, fontSize: 10.5, fontWeight: 700, letterSpacing: 0.8, textTransform: "uppercase" };
const tabBtn: React.CSSProperties = { background: C.white, color: C.mute, border: `1px solid ${C.rule}`, borderRadius: 999, padding: "8px 18px", fontSize: 13, fontWeight: 600, cursor: "pointer" };
const tabBtnActive: React.CSSProperties = { background: C.teal, color: "#fff", borderColor: C.teal };
const btnPrimary: React.CSSProperties = { background: C.teal, color: "#fff", border: "none", borderRadius: 10, padding: "10px 18px", fontSize: 14, fontWeight: 700, cursor: "pointer" };
const btnGhost: React.CSSProperties = { background: "transparent", color: C.tealDeep, border: `1px solid ${C.rule}`, borderRadius: 10, padding: "6px 12px", fontSize: 13, cursor: "pointer" };
const tbl: React.CSSProperties = { borderCollapse: "collapse", width: "100%", fontSize: 12.5 };
const th: React.CSSProperties = { padding: "6px 8px", textAlign: "right", borderBottom: `1px solid ${C.rule}`, fontSize: 11, color: C.mute, whiteSpace: "nowrap" };
const td: React.CSSProperties = { padding: "5px 8px", textAlign: "right", borderBottom: `1px solid ${C.rule}`, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" };
