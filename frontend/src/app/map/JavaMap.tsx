"use client";
import { useEffect, useRef, useState } from "react";
import type { ECharts } from "echarts";

type Feature = { type: "Feature"; properties: Record<string, string>; geometry: { type: string; coordinates: unknown } };
export type GeoFC = { type: "FeatureCollection"; features: Feature[] };
export type MapSite = { site_id: string; site_name?: string | null; kecamatan?: string; lat: number | null; lon: number | null; status: string; availability: number | null; payload_pct: number | null };
export type MapControl = { zoomBy: (f: number) => void; reset: () => void };

type Props = {
  geo: GeoFC;
  /** Fill colour per kabkot_id; ids without an entry are drawn grey. */
  colors: Record<string, string>;
  /** Short label per kabkot_id (shown when there is room). */
  labels: Record<string, string>;
  tooltip: (id: string) => string;
  selected: string | null;
  /** Ids to frame (e.g. the selected kabupaten or a region). */
  focus: string[];
  sites: MapSite[];
  showSites: boolean;
  onSelect: (id: string) => void;
  onSiteHover?: (s: MapSite | null) => void;
  onControl: (c: MapControl) => void;
  dark: boolean;
};

const MAP = "java-kab";
let registeredFor: GeoFC | null = null;

function bbox(features: Feature[]): [number, number, number, number] | null {
  let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
  const walk = (c: unknown) => {
    if (Array.isArray(c) && typeof c[0] === "number") {
      const [x, y] = c as number[];
      if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
    } else if (Array.isArray(c)) c.forEach(walk);
  };
  features.forEach((f) => walk(f.geometry.coordinates));
  return Number.isFinite(x0) ? [x0, y0, x1, y1] : null;
}

/** Choropleth of Java kabupaten/kota on ECharts' geo component, with site markers. */
export default function JavaMap({ geo, colors, labels, tooltip, selected, focus, sites, showSites, onSelect, onSiteHover, onControl, dark }: Props) {
  const el = useRef<HTMLDivElement>(null);
  const chart = useRef<ECharts | null>(null);
  const [ready, setReady] = useState(false);
  const cb = useRef({ onSelect, onSiteHover, tooltip });
  useEffect(() => { cb.current = { onSelect, onSiteHover, tooltip }; });

  useEffect(() => {
    let disposed = false;
    let ro: ResizeObserver | null = null;
    import("echarts").then((echarts) => {
      if (disposed || !el.current) return;
      if (registeredFor !== geo) {
        // ECharts matches regions by properties.name.
        const named = { ...geo, features: geo.features.map((f) => ({ ...f, properties: { ...f.properties, name: f.properties.kabkot_id } })) };
        echarts.registerMap(MAP, named as unknown as Parameters<typeof echarts.registerMap>[1]);
        registeredFor = geo;
      }
      const c = echarts.init(el.current, undefined, { renderer: "canvas" });
      chart.current = c;
      c.on("click", (p) => {
        if (p.componentType === "geo" && p.name) cb.current.onSelect(p.name);
      });
      c.on("mouseover", (p) => {
        if (p.seriesType === "scatter") cb.current.onSiteHover?.((p.data as { site: MapSite }).site);
      });
      c.on("mouseout", (p) => { if (p.seriesType === "scatter") cb.current.onSiteHover?.(null); });
      ro = new ResizeObserver(() => c.resize());
      ro.observe(el.current);
      setReady(true);
    });
    return () => { disposed = true; ro?.disconnect(); chart.current?.dispose(); chart.current = null; setReady(false); };
  }, [geo]);

  // Frame the focused area.
  useEffect(() => {
    const c = chart.current;
    if (!ready || !c) return;
    const feats = focus.length ? geo.features.filter((f) => focus.includes(f.properties.kabkot_id)) : geo.features;
    const all = bbox(geo.features);
    const b = bbox(feats.length ? feats : geo.features);
    if (!b || !all) return;
    const span = Math.max((b[2] - b[0]) / (all[2] - all[0]), (b[3] - b[1]) / (all[3] - all[1]));
    c.setOption({ geo: { map: MAP, center: [(b[0] + b[2]) / 2, (b[1] + b[3]) / 2], zoom: focus.length ? Math.min(8, Math.max(1, 0.75 / span)) : 1.1 } });
  }, [ready, focus, geo]);

  useEffect(() => {
    const c = chart.current;
    if (!ready || !c) return;
    const ink = dark ? "#E6F2F0" : "#0F1F1D";
    const muted = dark ? "#9FB3AF" : "#3D4C49";
    const empty = dark ? "#22302E" : "#E9EEED";
    const stroke = dark ? "#0F1716" : "#FFFFFF";
    c.setOption({
      animationDurationUpdate: 500,
      tooltip: {
        trigger: "item", backgroundColor: "#0F1F1D", borderWidth: 0, padding: [8, 12],
        textStyle: { color: "#fff", fontFamily: "Poppins", fontSize: 12 },
        extraCssText: "border-radius:10px;box-shadow:0 8px 20px rgba(0,0,0,.2);",
        formatter: (p: { componentType: string; name: string; data?: { site?: MapSite } }) =>
          p.componentType === "geo" ? cb.current.tooltip(p.name) : p.data?.site ? siteTip(p.data.site) : "",
      },
      geo: {
        map: MAP, roam: true, scaleLimit: { min: 0.8, max: 40 }, selectedMode: false,
        layoutCenter: ["50%", "52%"], layoutSize: "112%",
        itemStyle: { areaColor: empty, borderColor: stroke, borderWidth: 0.8 },
        emphasis: { itemStyle: { borderColor: ink, borderWidth: 1.5 }, label: { show: true, color: ink, fontWeight: 600 } },
        label: { show: false },
        labelLayout: { hideOverlap: true },
        tooltip: { show: true },
        regions: geo.features.map((f) => {
          const id = f.properties.kabkot_id;
          const isSel = id === selected;
          return {
            name: id,
            itemStyle: { areaColor: colors[id] ?? empty, borderColor: isSel ? ink : stroke, borderWidth: isSel ? 2.5 : 0.8 },
            label: { show: !!labels[id], formatter: labels[id] ?? "", color: muted, fontFamily: "Poppins", fontSize: 11, fontWeight: isSel ? 600 : 500 },
            emphasis: { itemStyle: { areaColor: colors[id] ?? empty } },
          };
        }),
      },
      series: [{
        type: "scatter", coordinateSystem: "geo", z: 5,
        symbolSize: 11,
        data: showSites ? sites.filter((s) => s.lat != null && s.lon != null).map((s) => ({
          value: [s.lon, s.lat], site: s,
          itemStyle: { color: "#fff", borderColor: s.status === "bad" ? "#E04848" : "#0E8579", borderWidth: 2.5 },
        })) : [],
        emphasis: { scale: 1.6 },
      }],
    }, { replaceMerge: ["series"] });
  }, [ready, colors, labels, selected, sites, showSites, dark, geo]);

  useEffect(() => {
    onControl({
      zoomBy: (f) => {
        const c = chart.current;
        if (!c) return;
        const opt = c.getOption() as { geo?: { zoom?: number }[] };
        const z = opt.geo?.[0]?.zoom ?? 1;
        c.setOption({ geo: { zoom: Math.max(0.8, Math.min(40, z * f)) } });
      },
      reset: () => chart.current?.setOption({ geo: { zoom: 1, center: undefined } }),
    });
  }, [onControl]);

  return <div ref={el} className="pm-canvas" role="img" aria-label="Peta kabupaten dan kota di Jawa" />;
}

function siteTip(s: MapSite): string {
  const parts = [
    s.availability != null ? `Availability ${s.availability.toLocaleString("id-ID", { maximumFractionDigits: 1 })}%` : "",
    s.payload_pct != null ? `payload ${s.payload_pct > 0 ? "+" : ""}${s.payload_pct.toLocaleString("id-ID", { maximumFractionDigits: 0 })}%` : "",
  ].filter(Boolean).join(" · ");
  return `<b>${s.site_id}${s.kecamatan ? ` · ${s.kecamatan}` : ""}</b><br/><span style="color:#C0EDE8">${parts}</span>`;
}
