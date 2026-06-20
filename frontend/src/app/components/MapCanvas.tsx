"use client";
import { useEffect, useRef, useState } from "react";

export type MapPoint = {
  lat: number;
  lon: number;
  title: string;
  metrics: { key: string; value: string }[];
  color?: string;       // AI-driven marker colour (overrides default red/teal)
  labelText?: string;   // AI-driven persistent label shown on/under the marker
};

export type Choropleth = {
  // "id" = values keyed by kec_id/kabkot_id (direct geometry match)
  // "name" = values keyed by a territory NAME (region/branch/circle/area/kabkota);
  //          polygons are dissolved/grouped via the territory map.
  dissolveBy: "id" | "name";
  level: string; // kecamatan | kabupaten | kabkota | region | branch | circle | area | province
  idKey?: "kec_id" | "kabkot_id";
  metricKey: string;
  coloring?: "sign" | "range";
  legend?: string;
  values: Record<string, { value: number; label: string; extra: Record<string, unknown> }>;
};

// kecamatan -> territory mapping (loaded once); shape: { "KEC|KABKOT": {region, branch, ...} }
let territoryMap: Record<string, Record<string, string>> | null = null;
async function loadTerritoryMap(): Promise<Record<string, Record<string, string>>> {
  if (territoryMap) return territoryMap;
  const res = await fetch(`/api/geo/territory-map`, { cache: "force-cache" });
  if (!res.ok) throw new Error(`territory-map HTTP ${res.status}`);
  territoryMap = (await res.json()) as Record<string, Record<string, string>>;
  return territoryMap;
}

type Props = {
  points: MapPoint[];
  userLoc: { lat: number; lon: number } | null;
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
const C_YELLOW = [245, 166, 35];  // amber (#F5A623)
const C_TEAL = [21, 166, 151];    // teal-500 (#15A697)

// Sign-based diverging scale anchored at ZERO: negative -> red, ~0 -> neutral,
// positive -> green. Used for growth/change metrics ("hijau jika naik, merah jika turun").
function colorBySign(v: number, maxAbs: number): string {
  if (maxAbs <= 0) return `rgb(${C_NEUTRAL.join(",")})`;
  const t = Math.min(1, Math.abs(v) / maxAbs);
  if (v >= 0) return lerpColor(C_NEUTRAL, C_GREEN, t);
  return lerpColor(C_NEUTRAL, C_RED, t);
}

// Plain min-max scale (red -> yellow -> teal) for non-signed magnitude metrics.
function colorByRange(v: number, min: number, max: number): string {
  if (max === min) return `rgb(${C_YELLOW.join(",")})`;
  const t = (v - min) / (max - min);
  if (t <= 0.5) return lerpColor(C_RED, C_YELLOW, t / 0.5);
  return lerpColor(C_YELLOW, C_TEAL, (t - 0.5) / 0.5);
}

function fmtNum(v: number): string {
  return Number.isInteger(v) ? v.toLocaleString("id-ID") : v.toLocaleString("id-ID", { maximumFractionDigits: 2 });
}

declare global {
  interface Window {
    L?: unknown;
  }
}

const IOH_RED = "#E13838";
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
  const choroLayerRef = useRef<any>(null);
  const readyRef = useRef(false);
  const [legend, setLegend] = useState<{ min: number; max: number; metric: string; mode: "sign" | "range" } | null>(null);

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

  function renderPoints() {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const L = window.L as any;
    if (!L || !mapRef.current) return;
    markersRef.current.forEach((m) => mapRef.current.removeLayer(m));
    markersRef.current = [];
    if (points.length === 0) return;

    const latlngs: [number, number][] = [];
    points.forEach((p, order) => {
      latlngs.push([p.lat, p.lon]);
      const color = p.color || (order === 0 ? IOH_RED : IOH_TEAL);
      const icon = L.divIcon({
        className: "mq-marker",
        html: `<div style="width:26px;height:26px;border-radius:50% 50% 50% 0;background:${color};transform:rotate(-45deg);border:2px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.4);display:flex;align-items:center;justify-content:center;"><span style="transform:rotate(45deg);color:#fff;font-weight:800;font-size:10px;font-family:Poppins,sans-serif;">${order + 1}</span></div>`,
        iconSize: [26, 26],
        iconAnchor: [13, 26],
        popupAnchor: [0, -26],
      });
      const marker = L.marker([p.lat, p.lon], { icon }).addTo(mapRef.current);
      const metricRows = p.metrics
        .map(
          (m) =>
            `<div style="display:flex;justify-content:space-between;gap:12px;padding:2px 0;"><span style="color:#5A6B68;font-size:11px;">${m.key}</span><span style="color:#0F1F1D;font-weight:700;font-size:12px;">${m.value}</span></div>`
        )
        .join("");
      const popupHtml = `<div style="font-family:Prompt,sans-serif;min-width:180px;"><div style="font-family:Poppins,sans-serif;font-weight:700;font-size:13px;color:${color};margin-bottom:5px;border-bottom:1px solid #E1E9E7;padding-bottom:4px;">#${order + 1} ${p.title}</div><div style="font-size:10px;color:#5A6B68;margin-bottom:5px;">${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}</div>${metricRows}<a href="${gmapsUrl(p.lat, p.lon)}" target="_blank" rel="noopener noreferrer" style="display:inline-block;margin-top:8px;padding:5px 10px;background:#33BCAD;color:#fff;border-radius:8px;font-family:Poppins,sans-serif;font-weight:700;font-size:11px;text-decoration:none;">🧭 Google Maps</a></div>`;
      marker.bindPopup(popupHtml);
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

    if (userLoc) latlngs.push([userLoc.lat, userLoc.lon]);
    if (latlngs.length === 1) {
      mapRef.current.setView(latlngs[0], 15);
    } else if (latlngs.length > 1) {
      mapRef.current.fitBounds(latlngs, { padding: [60, 60], maxZoom: 16 });
    }
  }

  async function renderChoropleth() {
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
    const vals = Object.values(choropleth.values).map((x) => x.value);
    if (vals.length === 0) return;
    const min = Math.min(...vals);
    const max = Math.max(...vals);
    const mode: "sign" | "range" = choropleth.coloring || "range";
    const maxAbs = Math.max(Math.abs(min), Math.abs(max));
    const colorOf = (v: number) => (mode === "sign" ? colorBySign(v, maxAbs) : colorByRange(v, min, max));
    setLegend({ min, max, metric: choropleth.legend || choropleth.metricKey, mode });

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
          fillColor: entry ? colorOf(entry.value) : "#999",
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
          .filter(([k]) => !/_id$/i.test(k))
          .slice(0, 6)
          .map(
            ([k, v]) =>
              `<div style="display:flex;justify-content:space-between;gap:12px;padding:2px 0;"><span style="color:#5A6B68;font-size:11px;">${k}</span><span style="color:#0F1F1D;font-weight:700;font-size:12px;">${typeof v === "number" ? fmtNum(v) : String(v)}</span></div>`
          )
          .join("");
        lyr.bindPopup(
          `<div style="font-family:Prompt,sans-serif;min-width:170px;"><div style="font-family:Poppins,sans-serif;font-weight:700;font-size:13px;color:#15A697;margin-bottom:5px;border-bottom:1px solid #E1E9E7;padding-bottom:4px;">${label}</div>${extraRows}</div>`
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
                legend.mode === "sign"
                  ? "linear-gradient(to right, rgb(237,28,36), rgb(245,245,247), rgb(34,168,90))"
                  : "linear-gradient(to right, rgb(237,28,36), rgb(255,203,5), rgb(50,188,173))",
            }}
          />
          <div className="mq-legend-scale">
            <span>{fmtNum(legend.min)}</span>
            {legend.mode === "sign" ? <span>0</span> : <span>{fmtNum((legend.min + legend.max) / 2)}</span>}
            <span>{fmtNum(legend.max)}</span>
          </div>
          {legend.mode === "sign" && (
            <div className="mq-legend-hint">🟥 turun · 🟩 naik</div>
          )}
        </div>
      )}
    </>
  );
}
