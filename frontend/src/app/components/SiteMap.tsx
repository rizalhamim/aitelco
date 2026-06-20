"use client";
import { useEffect, useRef, useState } from "react";

type Row = Record<string, unknown>;

type Props = {
  columns: string[];
  rows: Row[];
  latKey: string;
  lonKey: string;
};

// Leaflet types are loaded at runtime from CDN
declare global {
  interface Window {
    L?: unknown;
  }
}

const IOH_RED = "#E13838";
const IOH_TEAL = "#15A697";

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

function fmtVal(v: unknown): string {
  if (v === null || v === undefined) return "—";
  if (typeof v === "number") {
    if (Number.isInteger(v)) return v.toLocaleString("id-ID");
    return v.toLocaleString("id-ID", { maximumFractionDigits: 2 });
  }
  return String(v);
}

function gmapsUrl(lat: number, lon: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lon}`;
}

export default function SiteMap({ columns, rows, latKey, lonKey }: Props) {
  const [open, setOpen] = useState(false);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState("");
  const containerRef = useRef<HTMLDivElement>(null);
  const wrapRef = useRef<HTMLDivElement>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const mapRef = useRef<any>(null);

  const points = rows
    .map((r, i) => ({
      idx: i,
      lat: typeof r[latKey] === "number" ? (r[latKey] as number) : parseFloat(String(r[latKey])),
      lon: typeof r[lonKey] === "number" ? (r[lonKey] as number) : parseFloat(String(r[lonKey])),
      row: r,
    }))
    .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon) && p.lat !== 0 && p.lon !== 0);

  // identify label + metric columns (exclude lat/lon)
  const labelKey = columns.find((c) => /site_n|site_name|name|nama|kec|kab|territory/i.test(c)) || columns[0];
  const metricKeys = columns.filter(
    (c) => c !== latKey && c !== lonKey && c !== labelKey && !/^(lat|lon|longitude|latitude)/i.test(c)
  );

  useEffect(() => {
    if (!open || ready) return;
    let cancelled = false;
    loadLeaflet()
      .then(() => { if (!cancelled) setReady(true); })
      .catch(() => { if (!cancelled) setError("Gagal memuat peta. Cek koneksi internet."); });
    return () => { cancelled = true; };
  }, [open, ready]);

  useEffect(() => {
    if (!open || !ready || !containerRef.current || points.length === 0) return;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const L = window.L as any;
    if (!L) return;

    if (mapRef.current) {
      mapRef.current.remove();
      mapRef.current = null;
    }

    // ---- base layers: Satellite (default) + Street ----
    const satellite = L.tileLayer(
      "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
      { attribution: "&copy; Esri", maxZoom: 19 }
    );
    const labels = L.tileLayer(
      "https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}",
      { maxZoom: 19, opacity: 0.9 }
    );
    // satellite as a group with place labels on top
    const satGroup = L.layerGroup([satellite, labels]);
    const street = L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      attribution: "&copy; OpenStreetMap", maxZoom: 19,
    });

    const map = L.map(containerRef.current, {
      scrollWheelZoom: true,
      layers: [satGroup],   // satellite by default
    });
    mapRef.current = map;

    L.control.layers(
      { "🛰️ Satellite": satGroup, "🗺️ Street": street },
      {},
      { position: "topright", collapsed: false }
    ).addTo(map);

    // ---- custom fullscreen control ----
    const FsControl = L.Control.extend({
      options: { position: "topleft" },
      onAdd: function () {
        const btn = L.DomUtil.create("a", "leaflet-bar leaflet-control site-fs-btn");
        btn.href = "#";
        btn.title = "Fullscreen";
        btn.innerHTML = "⛶";
        L.DomEvent.on(btn, "click", (e: Event) => {
          L.DomEvent.stop(e);
          const el = wrapRef.current;
          if (!el) return;
          if (!document.fullscreenElement) {
            el.requestFullscreen?.().then(() => setTimeout(() => map.invalidateSize(), 200));
          } else {
            document.exitFullscreen?.().then(() => setTimeout(() => map.invalidateSize(), 200));
          }
        });
        return btn;
      },
    });
    map.addControl(new FsControl());

    const latlngs: [number, number][] = [];
    points.forEach((p, order) => {
      latlngs.push([p.lat, p.lon]);
      const isFirst = order === 0;
      const color = isFirst ? IOH_RED : IOH_TEAL;

      const icon = L.divIcon({
        className: "site-map-marker",
        html: `<div style="
          width:28px;height:28px;border-radius:50% 50% 50% 0;
          background:${color};transform:rotate(-45deg);
          border:2px solid #fff;box-shadow:0 2px 6px rgba(0,0,0,.4);
          display:flex;align-items:center;justify-content:center;">
          <span style="transform:rotate(45deg);color:#fff;font-weight:800;font-size:11px;font-family:Poppins,sans-serif;">${order + 1}</span>
        </div>`,
        iconSize: [28, 28],
        iconAnchor: [14, 28],
        popupAnchor: [0, -28],
      });

      const marker = L.marker([p.lat, p.lon], { icon }).addTo(map);

      const title = fmtVal(p.row[labelKey]);
      const metricRows = metricKeys
        .map(
          (k) =>
            `<div style="display:flex;justify-content:space-between;gap:12px;padding:2px 0;">
              <span style="color:#5A6B68;font-size:11px;">${k}</span>
              <span style="color:#0F1F1D;font-weight:700;font-size:12px;font-variant-numeric:tabular-nums;">${fmtVal(p.row[k])}</span>
            </div>`
        )
        .join("");

      const popupHtml = `
        <div style="font-family:Prompt,sans-serif;min-width:190px;">
          <div style="font-family:Poppins,sans-serif;font-weight:700;font-size:14px;color:${color};margin-bottom:6px;border-bottom:1px solid #E1E9E7;padding-bottom:4px;">
            ${isFirst ? "📍 " : "#" + (order + 1) + " "}${title}
          </div>
          <div style="font-size:10px;color:#5A6B68;margin-bottom:6px;">${p.lat.toFixed(5)}, ${p.lon.toFixed(5)}</div>
          ${metricRows}
          <a href="${gmapsUrl(p.lat, p.lon)}" target="_blank" rel="noopener noreferrer"
             style="display:inline-block;margin-top:8px;padding:6px 12px;background:#33BCAD;color:#fff;
             border-radius:8px;font-family:Poppins,sans-serif;font-weight:700;font-size:11px;text-decoration:none;">
            🧭 Buka di Google Maps
          </a>
        </div>`;

      marker.bindPopup(popupHtml);
      marker.bindTooltip(title, { direction: "top", offset: [0, -28] });
      if (isFirst) marker.openPopup();
    });

    if (latlngs.length === 1) {
      map.setView(latlngs[0], 15);
    } else {
      map.fitBounds(latlngs, { padding: [40, 40] });
    }

    setTimeout(() => map.invalidateSize(), 100);

    return () => {
      if (mapRef.current) {
        mapRef.current.remove();
        mapRef.current = null;
      }
    };
  }, [open, ready, points, labelKey, metricKeys]);

  if (points.length === 0) return null;

  return (
    <div className="site-map-wrap" ref={wrapRef}>
      <button className="site-map-toggle" onClick={() => setOpen((v) => !v)}>
        <svg viewBox="0 0 16 16" width="13" height="13" fill="currentColor" style={{ marginRight: 5 }}>
          <path d="M8 0a5 5 0 0 0-5 5c0 3.5 5 11 5 11s5-7.5 5-11a5 5 0 0 0-5-5zm0 7a2 2 0 1 1 0-4 2 2 0 0 1 0 4z" />
        </svg>
        {open ? "Sembunyikan Peta" : `Tampilkan Peta (${points.length} lokasi)`}
      </button>

      {open && (
        <div className="site-map-panel">
          {error && <div className="site-map-error">{error}</div>}
          {!error && !ready && <div className="site-map-loading">Memuat peta…</div>}
          <div
            ref={containerRef}
            className="site-map-canvas"
            style={{ display: ready && !error ? "block" : "none" }}
          />
          {ready && !error && (
            <div className="site-map-legend">
              <span className="site-map-legend-item">
                <span className="site-map-dot" style={{ background: IOH_RED }} />
                Terdekat / Utama
              </span>
              <span className="site-map-legend-item">
                <span className="site-map-dot" style={{ background: IOH_TEAL }} />
                Lokasi lainnya
              </span>
              <span className="site-map-legend-hint">Klik marker → buka di Google Maps · ⛶ fullscreen</span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
