"use client";
import { useEffect, useRef, useState } from "react";

export type SiteChannel = { label: string; key: string; value: number | null; share_pct: number | null; mom_pct: number | null; yoy_pct: number | null };
export type SiteHistory = { month_id: string; rev_prepaid: number; rev_data?: number; rgu_90d: number; net_add_90d?: number; usg_data_gb?: number; vlr_daily?: number };
export type SiteMetric = { full_month: number | null; llmtd: number | null; lmtd: number | null; mtd: number | null; mtd_growth: number | null; mtd_abs: number | null; llytd: number | null; lytd: number | null; ytd: number | null; yoy_growth: number | null; yoy_abs: number | null };
export type SiteChannelRow = { detail?: string; full_month: number | null; llmtd: number | null; lmtd: number | null; mtd: number | null; mtd_growth: number | null; mtd_abs: number | null; llytd: number | null; lytd: number | null; ytd: number | null; yoy_growth: number | null; yoy_abs: number | null };
export type SiteChannelGroup = SiteChannelRow & { channel_group: string; details: SiteChannelRow[] };
export type SiteDetail = {
  perf: Record<string, number | null>;
  mom: Record<string, number | null>;
  yoy: Record<string, number | null>;
  metrics?: Record<string, SiteMetric>;
  channels: SiteChannel[];
  channel_groups?: SiteChannelGroup[];
  history: SiteHistory[];
  attrs: { key: string; value: string }[];
  month_id?: string | null;
};

export type MapPoint = {
  lat: number;
  lon: number;
  title: string;
  metrics: { key: string; value: string }[];
  color?: string;       // AI-driven marker colour (overrides default red/teal)
  labelText?: string;   // persistent label shown under the marker (AI or fix label picker)
  fix?: boolean;        // fix-mode site: render a plain dot (no ranking number)
  detail?: SiteDetail;  // rich fix-mode site detail for the popup (MoM/YoY/trend/channels)
};

export type Choropleth = {
  // "id" = values keyed by kec_id/kabkot_id (direct geometry match)
  // "name" = values keyed by an operational territory name or administrative view.
  //          polygons are dissolved/grouped via the territory map.
  dissolveBy: "id" | "name";
  level: string; // kecamatan | kabupaten | kabkota | region | branch | circle | area | province
  idKey?: "kec_id" | "kabkot_id";
  metricKey: string;
  coloring?: "sign" | "range" | "favorable_sign";
  legend?: string;
  values: Record<string, { value: number; label: string; extra: Record<string, unknown> }>;
};

// kecamatan -> territory mapping (loaded once); shape: { "KEC|KABKOT": {region, branch, ...} }
let territoryMap: Record<string, Record<string, string>> | null = null;
async function loadTerritoryMap(): Promise<Record<string, Record<string, string>>> {
  if (territoryMap) return territoryMap;
  const res = await fetch(`/api/geo/territory-map?v=2026-10`, { cache: "force-cache" });
  if (!res.ok) throw new Error(`territory-map HTTP ${res.status}`);
  territoryMap = (await res.json()) as Record<string, Record<string, string>>;
  return territoryMap;
}

type Props = {
  points: MapPoint[];
  userLoc: { lat: number; lon: number; accuracy?: number } | null;
  choropleth?: Choropleth | null;
};

// cache fetched geojson by level for the session
const geoCache: Record<string, unknown> = {};
async function loadGeo(level: string): Promise<unknown> {
  if (geoCache[level]) return geoCache[level];
  const res = await fetch(`/api/geo/shapes/${level}`, { cache: "force-cache" });
  if (!res.ok) throw new Error(`geo ${level} HTTP ${res.status}`);
  const gj = await res.json();
  if (!gj || !Array.isArray((gj as { features?: unknown[] }).features)) {
    throw new Error(`geo ${level} invalid payload`);
  }
  geoCache[level] = gj;
  return gj;
}

function lerpColor(a: number[], b: number[], f: number): string {
  const c = a.map((ch, i) => Math.round(ch + (b[i] - ch) * f));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

const C_RED = [225, 56, 56];      // red — decline (#E13838)
const C_GREEN = [47, 168, 79];    // green — growth (#2FA84F)
const C_NEUTRAL = [236, 243, 241];
const C_TEAL = [21, 166, 151];    // teal-500 (#15A697)

// Sign-based diverging scale anchored at ZERO: negative -> red, ~0 -> neutral,
// positive -> green. Used for growth/change metrics ("hijau jika naik, merah jika turun").
function colorBySign(v: number, maxAbs: number): string {
  if (maxAbs <= 0) return `rgb(${C_NEUTRAL.join(",")})`;
  const t = Math.min(1, Math.abs(v) / maxAbs);
  if (v >= 0) return lerpColor(C_NEUTRAL, C_GREEN, t);
  return lerpColor(C_NEUTRAL, C_RED, t);
}

// Magnitude is sequential, not a red/green performance judgement.
function colorByRange(v: number, min: number, max: number): string {
  if (max === min) return `rgb(${C_TEAL.join(",")})`;
  return lerpColor(C_NEUTRAL, C_TEAL, Math.max(0, Math.min(1, (v - min) / (max - min))));
}

function htmlText(value: unknown): string {
  return String(value ?? "N/A").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[char]!));
}

function fmtNum(v: number): string {
  return Number.isInteger(v) ? v.toLocaleString("id-ID") : v.toLocaleString("id-ID", { maximumFractionDigits: 2 });
}

declare global {
  interface Window {
    L?: unknown;
  }
}

const IOH_TEAL = "#15A697";
const IOH_MAGENTA = "#0A6A5F";

function loadLeaflet(): Promise<void> {
  return new Promise((resolve, reject) => {
    if (typeof window === "undefined") return reject(new Error("no window"));
    if (window.L) return resolve();
    const cssId = "leaflet-css";
    if (!document.getElementById(cssId)) {
      const link = document.createElement("link");
      link.id = cssId;
      link.rel = "stylesheet";
      link.href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css";
      link.integrity = "sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=";
      link.crossOrigin = "";
      document.head.appendChild(link);
    }
    const scriptId = "leaflet-js";
    const existing = document.getElementById(scriptId) as HTMLScriptElement | null;
    if (existing) {
      existing.addEventListener("load", () => resolve());
      existing.addEventListener("error", () => reject(new Error("leaflet load failed")));
      return;
    }
    const script = document.createElement("script");
    script.id = scriptId;
    script.src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js";
    script.integrity = "sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=";
    script.crossOrigin = "";
    script.onload = () => resolve();
    script.onerror = () => reject(new Error("leaflet load failed"));
    document.head.appendChild(script);
  });
}

function gmapsUrl(lat: number, lon: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lon}`;
}

export default function MapCanvas({ points, userLoc, choropleth }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const mapRef = useRef<any>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const markersRef = useRef<any[]>([]);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const userMarkerRef = useRef<any>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const userAccuracyRef = useRef<any>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const choroLayerRef = useRef<any>(null);
  const readyRef = useRef(false);
  const choroGeneration = useRef(0);
  const [legend, setLegend] = useState<{ min: number; max: number; metric: string; mode: "sign" | "range" | "favorable_sign" } | null>(null);

  // init map once
  useEffect(() => {
    let cancelled = false;
    loadLeaflet().then(() => {
      if (cancelled || !containerRef.current || mapRef.current) return;
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const L = window.L as any;
      const satellite = L.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        { attribution: "&copy; Esri", maxZoom: 19 }
      );
      const labels = L.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}",
        { maxZoom: 19, opacity: 0.9 }
      );
      const satGroup = L.layerGroup([satellite, labels]);
      const street = L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: "&copy; OpenStreetMap", maxZoom: 19,
      });
      const map = L.map(containerRef.current, {
        scrollWheelZoom: true,
        zoomControl: true,
        layers: [satGroup],
        center: userLoc ? [userLoc.lat, userLoc.lon] : [-7.25, 112.75],
        zoom: 12,
      });
      mapRef.current = map;
      L.control.layers(
        { "🛰️ Satellite": satGroup, "🗺️ Street": street },
        {},
        { position: "topright", collapsed: true }
      ).addTo(map);
      readyRef.current = true;
      setTimeout(() => map.invalidateSize(), 120);
      renderUser();
      renderPoints();
      renderChoropleth();
    }).catch(() => {});
    return () => {
      cancelled = true;
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
        readyRef.current = false;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function renderUser() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const L = window.L as any;
    if (!L || !mapRef.current || !userLoc) return;
    if (userMarkerRef.current) {
      mapRef.current.removeLayer(userMarkerRef.current);
      userMarkerRef.current = null;
    }
    if (userAccuracyRef.current) mapRef.current.removeLayer(userAccuracyRef.current);
    if (userLoc.accuracy && Number.isFinite(userLoc.accuracy) && userLoc.accuracy > 0) {
      userAccuracyRef.current = L.circle([userLoc.lat, userLoc.lon], {
        radius: userLoc.accuracy, color: IOH_MAGENTA, fillOpacity: .1, weight: 1,
      }).addTo(mapRef.current);
    }
    const icon = L.divIcon({
      className: "mq-user-marker",
      html: `<div style="width:18px;height:18px;border-radius:50%;background:${IOH_MAGENTA};border:3px solid #fff;box-shadow:0 0 0 4px rgba(198,22,141,.3);"></div>`,
      iconSize: [18, 18],
      iconAnchor: [9, 9],
    });
    userMarkerRef.current = L.marker([userLoc.lat, userLoc.lon], { icon, zIndexOffset: 1000 })
      .addTo(mapRef.current)
      .bindTooltip("Lokasi Anda", { direction: "top" });
  }

  function fmtMnHtml(v: number | null | undefined): string {
    if (v === null || v === undefined) return "—";
    if (Math.abs(v) >= 1e6) return `${(v / 1e6).toLocaleString("id-ID", { maximumFractionDigits: 1 })} Mn`;
    return v.toLocaleString("id-ID", { maximumFractionDigits: 0 });
  }
  function pctChip(v: number | null | undefined): string {
    if (v === null || v === undefined) return `<span class="mq-pill mq-pill--flat">—</span>`;
    const cls = v > 0 ? "mq-pill--up" : (v < 0 ? "mq-pill--dn" : "mq-pill--flat");
    const arrow = v > 0 ? "▲" : (v < 0 ? "▼" : "•");
    return `<span class="mq-pill ${cls}">${arrow} ${Math.abs(v).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%</span>`;
  }
  // Inline SVG sparkline over a history window, using a value accessor.
  function sparkline(hist: SiteHistory[], pick: (h: SiteHistory) => number, stroke?: string): string {
    const vals = hist.map((h) => pick(h) || 0);
    if (vals.length < 2) return "";
    const w = 280, h = 46, pad = 3;
    const min = Math.min(...vals), max = Math.max(...vals);
    const rng = max - min || 1;
    const pts = vals.map((v, i) => {
      const x = pad + (i / (vals.length - 1)) * (w - 2 * pad);
      const y = h - pad - ((v - min) / rng) * (h - 2 * pad);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    });
    const col = stroke || (vals[vals.length - 1] >= vals[0] ? "#15A697" : "#E26A6A");
    const dots = pts.map((p) => { const [x, y] = p.split(","); return `<circle cx="${x}" cy="${y}" r="1.6" fill="${col}"/>`; }).join("");
    return `<svg width="100%" viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" style="display:block;margin-top:4px;"><polyline points="${pts.join(" ")}" fill="none" stroke="${col}" stroke-width="1.8"/>${dots}</svg>`;
  }
  function fixPopupHtml(p: MapPoint): string {
    const d = p.detail!;
    const M = d.metrics || {};
    const rp = d.perf.rev_prepaid ?? null;
    // Per-metric: Full-Month | MTD | LMTD | MoM% | YTD | LYTD | YoY%
    const metricList: [string, string][] = [
      ["Rev Prepaid", "rev_prepaid"], ["Rev Data", "rev_data"], ["RGU 90D", "rgu_90d"],
      ["Net Add 90D", "net_add_90d"], ["VLR Daily", "vlr_daily"], ["Usage GB", "usg_data_gb"],
    ];
    const cell = (v: number | null | undefined, hi = false) => `<td class="${hi ? "mq-hi" : "mq-num"}">${fmtMnHtml(v ?? null)}</td>`;
    // Signed absolute delta, coloured by sign.
    const absCell = (v: number | null | undefined) => {
      if (v == null) return `<td class="mq-abs--flat">—</td>`;
      const sign = v > 0 ? "+" : (v < 0 ? "-" : "");
      const cls = v > 0 ? "mq-abs--up" : (v < 0 ? "mq-abs--dn" : "mq-abs--flat");
      return `<td class="${cls}">${sign}${fmtMnHtml(Math.abs(v))}</td>`;
    };
    const gcell = (v: number | null | undefined) => `<td>${pctChip(v)}</td>`;
    // MTD is the emphasised (current) column; YTD likewise in the YoY block.
    const perfRows = metricList.map(([lbl, k]) => {
      const m = M[k] || ({} as SiteMetric);
      return `<tr><td>${lbl}</td>${cell(m.full_month)}${cell(m.llmtd)}${cell(m.lmtd)}${cell(m.mtd, true)}${gcell(m.mtd_growth)}${absCell(m.mtd_abs)}</tr>`;
    }).join("");
    const yoyRows = metricList.map(([lbl, k]) => {
      const m = M[k] || ({} as SiteMetric);
      return `<tr><td>${lbl}</td>${cell(m.llytd)}${cell(m.lytd)}${cell(m.ytd, true)}${gcell(m.yoy_growth)}${absCell(m.yoy_abs)}</tr>`;
    }).join("");
    const chRows = d.channels.filter((c) => (c.value || 0) > 0).map((c) =>
      `<tr><td>${c.label}</td>${cell(c.value, true)}<td class="mq-num">${c.share_pct ?? "—"}%</td>${gcell(c.mom_pct)}</tr>`
    ).join("");
    // Revenue Data per channel group: group header row (bold) + detail rows, for
    // both the MTD vs LMTD and YTD vs LYTD blocks. Apple-to-apple from backend.
    const cgrps = d.channel_groups || [];
    const cgRow = (label: string, m: SiteChannelRow, header: boolean, cols: "mtd" | "ytd") => {
      const cs = cols === "mtd"
        ? `${cell(m.full_month)}${cell(m.llmtd)}${cell(m.lmtd)}${cell(m.mtd, true)}${gcell(m.mtd_growth)}${absCell(m.mtd_abs)}`
        : `${cell(m.llytd)}${cell(m.lytd)}${cell(m.ytd, true)}${gcell(m.yoy_growth)}${absCell(m.yoy_abs)}`;
      return `<tr class="${header ? "mq-cg-grp" : "mq-cg-det"}"><td>${label}</td>${cs}</tr>`;
    };
    const cgBody = (cols: "mtd" | "ytd") => cgrps.map((g) =>
      cgRow(g.channel_group, g, true, cols) + (g.details || []).map((dt) => cgRow(dt.detail || "", dt, false, cols)).join("")
    ).join("");
    const attrRows = d.attrs
      .filter((a) => a.key !== "Site ID")
      .map((a) => `<div class="mq-attr"><span class="mq-attr__k">${a.key}</span><span class="mq-attr__v">${a.value}</span></div>`)
      .join("");
    const sect = (t: string) => `<div class="mq-sect">${t}</div>`;
    const th = (t: string) => `<th>${t}</th>`;
    const sid = (d.attrs.find((a) => a.key === "Site ID")?.value || "").trim();
    const sitePerfBtn = sid && sid !== "—"
      ? `<a href="/site?site_id=${encodeURIComponent(sid)}" class="mq-btn" style="background:#15A697;">📊 Site Performance</a>`
      : "";
    const trendCap = d.history.length
      ? `${d.history[0].month_id} → ${d.history[d.history.length - 1].month_id}${rp != null ? ` · now ${fmtMnHtml(rp)}` : ""}`
      : "";
    return `<div class="mq-fixpop">
      <div class="mq-fixpop__hd">
        <div class="mq-fixpop__title">📡 ${p.title}</div>
        <div class="mq-fixpop__sub">
          ${sid && sid !== "—" ? `<span class="mq-fixpop__chip">${sid}</span>` : ""}
          <span>${p.lat.toFixed(4)}, ${p.lon.toFixed(4)}</span>
          ${d.month_id ? `<span class="mq-fixpop__chip">${d.month_id}</span>` : ""}
        </div>
      </div>
      <div class="mq-fixpop__body">
        ${attrRows ? sect("Profil Site") + `<div class="mq-attrs">${attrRows}</div>` : ""}
        ${sect("Monthly Absolute")}
        <table class="mq-tbl"><thead><tr><th></th>${th("Full")}${th("LLMTD")}${th("LMTD")}${th("MTD")}${th("Growth")}${th("Abs")}</tr></thead><tbody>${perfRows}</tbody></table>
        ${sect("Year on Year (YTD)")}
        <table class="mq-tbl"><thead><tr><th></th>${th("LLYTD")}${th("LYTD")}${th("YTD")}${th("Growth")}${th("Abs")}</tr></thead><tbody>${yoyRows}</tbody></table>
        ${sect("Trend Rev Prepaid · 12 bln")}${sparkline(d.history, (h) => h.rev_prepaid)}
        ${trendCap ? `<div class="mq-trend-cap">${trendCap}</div>` : ""}
        ${sect("Trend VLR Daily · 12 bln")}${sparkline(d.history, (h) => h.vlr_daily || 0, "#C6168D")}
        ${chRows ? sect("Revenue per Channel") + `<table class="mq-tbl"><thead><tr><th></th>${th("Nilai")}${th("Share")}${th("MoM")}</tr></thead><tbody>${chRows}</tbody></table>` : ""}
        ${cgrps.length ? sect("Revenue Data / Channel · Monthly") + `<table class="mq-tbl"><thead><tr><th></th>${th("Full")}${th("LLMTD")}${th("LMTD")}${th("MTD")}${th("Growth")}${th("Abs")}</tr></thead><tbody>${cgBody("mtd")}</tbody></table>` : ""}
        ${cgrps.length ? sect("Revenue Data / Channel · YoY") + `<table class="mq-tbl"><thead><tr><th></th>${th("LLYTD")}${th("LYTD")}${th("YTD")}${th("Growth")}${th("Abs")}</tr></thead><tbody>${cgBody("ytd")}</tbody></table>` : ""}
        <div class="mq-fixpop__actions">
          <a href="${gmapsUrl(p.lat, p.lon)}" target="_blank" rel="noopener noreferrer" class="mq-btn" style="background:#33BCAD;">🧭 Google Maps</a>
          ${sitePerfBtn}
        </div>
      </div>
    </div>`;
  }

  function renderPoints() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const L = window.L as any;
    if (!L || !mapRef.current) return;
    markersRef.current.forEach((m) => mapRef.current.removeLayer(m));
    markersRef.current = [];
    if (points.length === 0) return;

    const latlngs: [number, number][] = [];
    points.forEach((p, order) => {
      if (!Number.isFinite(p.lat) || !Number.isFinite(p.lon) || Math.abs(p.lat) > 90 || Math.abs(p.lon) > 180) return;
      latlngs.push([p.lat, p.lon]);
      const color = p.color || IOH_TEAL;
      // Fix-mode sites render as plain dots (one marker = one physical site, no
      // ranking number / grouping). AI-mode keeps the numbered teardrop.
      const icon = p.fix
        ? L.divIcon({
            className: "mq-marker mq-dot",
            html: `<div style="width:14px;height:14px;border-radius:50%;background:${color};border:2px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.5);"></div>`,
            iconSize: [14, 14],
            iconAnchor: [7, 7],
            popupAnchor: [0, -8],
          })
        : L.divIcon({
            className: "mq-marker",
            html: `<div style="width:26px;height:26px;border-radius:50% 50% 50% 0;background:${color};transform:rotate(-45deg);border:2px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.4);display:flex;align-items:center;justify-content:center;"><span style="transform:rotate(45deg);color:#fff;font-weight:800;font-size:10px;font-family:Poppins,sans-serif;">${order + 1}</span></div>`,
            iconSize: [26, 26],
            iconAnchor: [13, 26],
            popupAnchor: [0, -26],
          });
      const marker = L.marker([p.lat, p.lon], { icon }).addTo(mapRef.current);
      let popupHtml: string;
      if (p.detail) {
        popupHtml = fixPopupHtml(p);
      } else {
        const metricRows = p.metrics
          .map(
            (m) =>
              `<div style="display:flex;justify-content:space-between;gap:12px;padding:2px 0;"><span style="color:#5A6B68;font-size:11px;">${m.key}</span><span style="color:#0F1F1D;font-weight:700;font-size:12px;">${m.value}</span></div>`
          )
          .join("");
        const head = p.fix ? p.title : `#${order + 1} ${p.title}`;
        popupHtml = `<div style="font-family:Prompt,sans-serif;min-width:180px;"><div style="font-family:Poppins,sans-serif;font-weight:700;font-size:13px;color:${color};margin-bottom:5px;border-bottom:1px solid #E1E9E7;padding-bottom:4px;">${head}</div><div style="font-size:10px;color:#5A6B68;margin-bottom:5px;">${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}</div>${metricRows}<a href="${gmapsUrl(p.lat, p.lon)}" target="_blank" rel="noopener noreferrer" style="display:inline-block;margin-top:8px;padding:5px 10px;background:#33BCAD;color:#fff;border-radius:8px;font-family:Poppins,sans-serif;font-weight:700;font-size:11px;text-decoration:none;">🧭 Google Maps</a></div>`;
      }
      marker.bindPopup(popupHtml, p.detail ? { maxWidth: 342, minWidth: 340, className: "mq-fixpop-wrap" } : undefined);
      if (p.labelText) {
        // persistent value label (AI-driven, e.g. revenue in Mn)
        marker.bindTooltip(p.labelText, {
          permanent: true,
          direction: "bottom",
          offset: [0, 0],
          className: "mq-node-label",
        });
      } else {
        marker.bindTooltip(p.title, { direction: "top", offset: [0, -26] });
      }
      markersRef.current.push(marker);
    });

    if (userLoc && points.some((point) => point.fix)) latlngs.push([userLoc.lat, userLoc.lon]);
    if (latlngs.length === 1) {
      mapRef.current.setView(latlngs[0], 15);
    } else if (latlngs.length > 1) {
      mapRef.current.fitBounds(latlngs, { padding: [60, 60], maxZoom: 16 });
    }
  }

  async function renderChoropleth() {
    const generation = ++choroGeneration.current;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const L = window.L as any;
    if (!L || !mapRef.current) return;
    if (choroLayerRef.current) {
      mapRef.current.removeLayer(choroLayerRef.current);
      choroLayerRef.current = null;
    }
    if (!choropleth) {
      setLegend(null);
      return;
    }
    const vals = Object.values(choropleth.values).map((x) => x.value).filter(Number.isFinite);
    if (vals.length === 0) return;
    const min = Math.min(...vals);
    const max = Math.max(...vals);
    const mode = choropleth.coloring || "range";
    const maxAbs = Math.max(Math.abs(min), Math.abs(max));
    const colorOf = (v: number, extra: Record<string, unknown>) => mode === "favorable_sign"
      ? maxAbs > 0 && typeof extra.favorable === "boolean"
        ? lerpColor(C_NEUTRAL, extra.favorable ? C_GREEN : C_RED, Math.min(1, Math.abs(v) / maxAbs))
        : `rgb(${C_NEUTRAL.join(",")})`
      : mode === "sign" ? colorBySign(v, maxAbs) : colorByRange(v, min, max);

    // Geometry: kabupaten polygons only when matching directly by kabkot_id;
    // otherwise always kecamatan polygons (dissolved by territory map for "name").
    const geoLevel = choropleth.dissolveBy === "id" && choropleth.idKey === "kabkot_id" ? "kabupaten" : "kecamatan";
    let gj: unknown;
    try {
      gj = await loadGeo(geoLevel);
      if (choropleth.dissolveBy === "name") await loadTerritoryMap();
    } catch {
      return;
    }
    if (generation !== choroGeneration.current || !mapRef.current) return;
    setLegend({ min: mode === "range" ? min : -maxAbs, max: mode === "range" ? max : maxAbs, metric: choropleth.legend || choropleth.metricKey, mode });
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const fc = gj as { features: any[] };

    // Resolve a polygon feature -> its value entry (by id, or by territory name).
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const resolveEntry = (feat: any) => {
      if (choropleth.dissolveBy === "id") {
        const idProp = choropleth.idKey || "kec_id";
        const id = String(feat.properties?.[idProp] ?? "").toUpperCase();
        return choropleth.values[id];
      }
      // dissolve by territory name: map kec_id -> territory value -> entry
      const kecId = String(feat.properties?.kec_id ?? "").toUpperCase();
      const terr = territoryMap?.[kecId]?.[choropleth.level];
      if (!terr) return undefined;
      return choropleth.values[String(terr).toUpperCase()];
    };

    const matched: [number, number][] = [];
    const layer = L.geoJSON(fc, {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      filter: (feat: any) => resolveEntry(feat) !== undefined,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      style: (feat: any) => {
        const entry = resolveEntry(feat);
        return {
          fillColor: entry ? colorOf(entry.value, entry.extra) : "#999",
          fillOpacity: 0.72,
          color: "#fff",
          weight: choropleth.dissolveBy === "name" ? 0.4 : 1,
        };
      },
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      onEachFeature: (feat: any, lyr: any) => {
        const entry = resolveEntry(feat);
        if (!entry) return;
        const label = entry.label || feat.properties?.kabupaten || feat.properties?.kecamatan || "";
        const extraRows = Object.entries(entry.extra)
          .map(
            ([k, v]) =>
              `<div style="display:flex;justify-content:space-between;gap:12px;padding:2px 0;overflow-wrap:anywhere;"><span style="color:#5A6B68;font-size:11px;">${htmlText(k)}</span><span style="color:#0F1F1D;font-weight:700;font-size:12px;">${htmlText(typeof v === "number" ? fmtNum(v) : v)}</span></div>`
          )
          .join("");
        lyr.bindPopup(
          `<div style="font-family:Prompt,sans-serif;min-width:170px;max-height:50vh;overflow:auto;"><div style="font-family:Poppins,sans-serif;font-weight:700;font-size:13px;color:#15A697;margin-bottom:5px;border-bottom:1px solid #E1E9E7;padding-bottom:4px;">${htmlText(label)}</div>${extraRows}</div>`
        );
        lyr.bindTooltip(`${label}: ${fmtNum(entry.value)}`, { sticky: true });
      },
    }).addTo(mapRef.current);
    choroLayerRef.current = layer;
    try {
      const b = layer.getBounds();
      if (b.isValid()) mapRef.current.fitBounds(b, { padding: [30, 30] });
    } catch {}
    // collect for typings unused
    void matched;
  }

  // re-render points when they change
  useEffect(() => {
    if (readyRef.current) renderPoints();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [points]);

  // render choropleth when it changes
  useEffect(() => {
    if (readyRef.current) renderChoropleth();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [choropleth]);

  // re-center on user when obtained
  useEffect(() => {
    if (readyRef.current) {
      renderUser();
      if (points.length === 0 && userLoc && mapRef.current) {
        mapRef.current.setView([userLoc.lat, userLoc.lon], 13);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userLoc]);

  return (
    <>
      <div ref={containerRef} className="mq-canvas" />
      {legend && (
        <div className="mq-legend">
          <div className="mq-legend-title">{legend.metric}</div>
          <div
            className="mq-legend-bar"
            style={{
              background:
                legend.mode !== "range"
                  ? "linear-gradient(to right, rgb(225,56,56), rgb(236,243,241), rgb(47,168,79))"
                  : "linear-gradient(to right, rgb(236,243,241), rgb(21,166,151))",
            }}
          />
          <div className="mq-legend-scale">
            <span>{legend.mode === "favorable_sign" ? "Tidak favorable" : fmtNum(legend.min)}</span>
            {legend.mode === "sign" ? <span>0</span> : legend.mode === "range" ? <span>{fmtNum((legend.min + legend.max) / 2)}</span> : null}
            <span>{legend.mode === "favorable_sign" ? "Favorable" : fmtNum(legend.max)}</span>
          </div>
          {legend.mode === "sign" && (
            <div className="mq-legend-hint">🟥 turun · 🟩 naik</div>
          )}
        </div>
      )}
    </>
  );
}
