"use client";
/* 05 Peta Agent: map of one kabupaten (or region) with a map chat. Every answer adds layers
   (choropleth, site points, uploaded polygons) and the map recolours by Performance, Site
   productivity or Profile wilayah. Layout follows design/mockup-v2/05-peta-agent. */
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell, { TopBar } from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { authFetch } from "@/lib/auth";
import "../dashboard/dashboard.css";
import "./peta.css";

type Cat = "perf" | "prod" | "prof";
type Metric = { key: string; cat: Cat; name: string; short: string; kind: "div" | "seq"; unit: string; d: number; pre?: string; scale?: number; available?: boolean };
type Unit = { n: string; d: string; cx: number; cy: number; sites: number; crit: number; status: string; label: boolean; m: Record<string, number | null> };
type Site = { id: string; name: string | null; k: string; kab: string; x: number; y: number; lat: number; lon: number; crit: boolean; status: string; payload_mom: number | null; revenue_mom: number | null; availability: number | null };
type MapData = {
  scope: { level: string; kabupaten: string; name: string; province: string; region: string };
  frame: { w: number; h: number; lon0: number; lat1: number; cx: number; s: number; ox: number; oy: number };
  month_label: string; month_short: string; unit_level: string; units: Unit[]; sites: Site[]; sites_without_coord: number;
  neighbors: { n: string; d: string }[]; outline: string; metrics: Metric[];
  source: { kind: string; label?: string };
};
type Shape = { name: string; label: string; kind: string; desc: string; size_kb: number; count: string; area_km2: number; d: string; rings: number[][][]; points: number[][] };
type AnsLayer = { kind: "chor" | "sites" | "point"; metric?: string; threshold?: number; label: string; x?: number; y?: number; lat?: number; lon?: number };
type Stat = { label: string; short?: string; value: string; sub?: string | null; tone?: string };
type Answer = { time: string; text: string; layers: AnsLayer[]; stats: Stat[]; actions: string[]; site_ids?: string[]; focus?: number[] | null; select?: string | null; suggestions?: string[] };
type Msg = { role: "user"; text: string; file?: Shape } | ({ role: "agent" } & Answer);
type View = { x: number; y: number; z: number };
type Layers = { chor: boolean; crit: boolean; up: boolean; all: boolean; opacity: number };

const CATS: { key: Cat; label: string; icon: string }[] = [
  { key: "perf", label: "Performance", icon: "pulse" }, { key: "prod", label: "Site productivity", icon: "tower" }, { key: "prof", label: "Profile wilayah", icon: "users" },
];
const DIV = ["#C42B2B", "#E5634F", "#F4A08A", "#F9D6CB", "#D8EFEA", "#7FCFC3"];
const SEQ = ["#EAF6F3", "#C3E8E1", "#8FD6CB", "#4FB8AA", "#1A9483", "#0A6A5F"];
const DIV_TICKS = ["−15%", "−12%", "−8%", "−4%", "0", "+2%", "+5%"];
const divCol = (v: number) => (v <= -12 ? DIV[0] : v <= -8 ? DIV[1] : v <= -4 ? DIV[2] : v < 0 ? DIV[3] : v < 2 ? DIV[4] : DIV[5]);
const idn = (v: number, d: number) => v.toLocaleString("id-ID", { minimumFractionDigits: d, maximumFractionDigits: d });
const pct = (v: number) => (v > 0 ? "+" : v < 0 ? "−" : "") + idn(Math.abs(v), 1) + "%";
const disp = (m: Metric, v: number) => v / (m.scale || 1);
const fmtM = (m: Metric, v: number | null | undefined) => (v == null ? "-" : m.kind === "div" ? pct(v) : (m.pre || "") + idn(disp(m, v), m.d) + m.unit);
// Free part of the map (right of the layer panel, below the metric bar): answers focus there.
const FREE = { left: 372, top: 109, right: 0, bottom: 0 };
const MAX_Z = 8;

function bold(text: string) {
  return text.split(/(\*\*[^*]+\*\*)/).map((p, i) => (p.startsWith("**") ? <b key={i}>{p.slice(2, -2)}</b> : <span key={i}>{p}</span>));
}

function b64(file: File): Promise<string> {
  return new Promise((res, rej) => {
    const r = new FileReader();
    r.onload = () => res(String(r.result).split(",")[1] || "");
    r.onerror = () => rej(r.error);
    r.readAsDataURL(file);
  });
}

function download(blob: Blob, name: string) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 2000);
}

function nowLabel() {
  const d = new Date();
  return `${String(d.getHours()).padStart(2, "0")}.${String(d.getMinutes()).padStart(2, "0")}`;
}

export default function MapPage() {
  return <Suspense><PetaAgent /></Suspense>;
}

function PetaAgent() {
  const params = useSearchParams();
  const router = useRouter();
  const [kab, setKab] = useState(params.get("kabupaten") || "");
  const region = params.get("region") || "";
  const focusSite = params.get("level") === "site" ? params.get("focus") || "" : "";
  const [data, setData] = useState<MapData | null>(null);
  const [err, setErr] = useState("");
  const [cat, setCat] = useState<Cat>("perf");
  const [metricKey, setMetricKey] = useState("payload_mom");
  const [layers, setLayers] = useState<Layers>({ chor: true, crit: true, up: true, all: true, opacity: 0.85 });
  const [critRule, setCritRule] = useState<{ metric: string; t: number } | null>(null);
  const [shape, setShape] = useState<Shape | null>(null);
  const [points, setPoints] = useState<AnsLayer[]>([]);
  const [selUnit, setSelUnit] = useState<string | null>(null);
  const [selSite, setSelSite] = useState<string | null>(null);
  const [view, setView] = useState<View | null>(null);
  const [size, setSize] = useState({ w: 748, h: 824 });
  const [hover, setHover] = useState<{ n: string; x: number; y: number } | null>(null);
  const [lyrMin, setLyrMin] = useState(false);
  const [base, setBase] = useState<"light" | "sat" | "road">("light");
  const [msgs, setMsgs] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [pending, setPending] = useState<Shape | null>(null);
  const [upErr, setUpErr] = useState("");
  const [pick, setPick] = useState(false);
  const [menu, setMenu] = useState<number | null>(null);
  const [list, setList] = useState<{ title: string; ids: string[] } | null>(null);
  const [hist, setHist] = useState(false);
  const [scopeOpen, setScopeOpen] = useState(false);
  const [drop, setDrop] = useState(false);
  const wrapRef = useRef<HTMLDivElement>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const msgsRef = useRef<HTMLDivElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const taRef = useRef<HTMLTextAreaElement>(null);
  const drag = useRef<{ x: number; y: number; v: View; moved: boolean } | null>(null);

  // ── data ──
  useEffect(() => {
    const q = new URLSearchParams();
    if (kab) q.set("kabupaten", kab);
    if (region) q.set("region", region);
    if (focusSite && !kab) q.set("site", focusSite);
    let alive = true;
    authFetch(`/api/map/agent?${q}`).then(async (r) => {
      const d = await r.json();
      if (!alive) return;
      if (!r.ok) { setErr(d?.detail || "Peta belum bisa dimuat"); return; }
      setErr("");
      setData(d);
    }).catch(() => alive && setErr("Peta belum bisa dimuat"));
    return () => { alive = false; };
  }, [kab, region, focusSite]);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setSize({ w: el.clientWidth, h: el.clientHeight }));
    ro.observe(el);
    setSize({ w: el.clientWidth, h: el.clientHeight });
    return () => ro.disconnect();
  }, []);

  const metric = useMemo(() => data?.metrics.find((m) => m.key === metricKey) ?? data?.metrics[0], [data, metricKey]);
  const unitWord = data?.unit_level === "kabupaten" ? "kabupaten" : "kecamatan";
  const unitPrefix = data?.unit_level === "kabupaten" ? "" : "Kec. ";

  // ── view ──
  const fit = useCallback((b: number[], free = FREE): View => {
    const fw = Math.max(size.w - free.left - free.right, 80), fh = Math.max(size.h - free.top - free.bottom, 80);
    const z = Math.min(fw / Math.max(b[2] - b[0], 1), fh / Math.max(b[3] - b[1], 1), MAX_Z);
    const cx = (b[0] + b[2]) / 2, cy = (b[1] + b[3]) / 2;
    return { z, x: cx - (free.left + fw / 2) / z, y: cy - (free.top + fh / 2) / z };
  }, [size]);
  const home = useCallback(() => (data ? fit([0, 0, data.frame.w, data.frame.h], { left: 0, top: 0, right: 0, bottom: 0 }) : null), [data, fit]);

  useEffect(() => {
    if (!data || view) return;
    const site = focusSite && data.sites.find((s) => s.id.toUpperCase() === focusSite.toUpperCase());
    if (site) {
      setSelSite(site.id);
      setView(fit([site.x - 60, site.y - 50, site.x + 60, site.y + 50]));
    } else setView(home());
    const worst = [...data.units].filter((u) => u.m.payload_mom != null).sort((a, b) => (a.m.payload_mom as number) - (b.m.payload_mom as number))[0];
    if (worst && !site) setSelUnit(worst.n);
  }, [data, view, focusSite, fit, home]);

  const z = view?.z ?? 1, u = 1 / z;
  const vb = view ? `${view.x} ${view.y} ${size.w / z} ${size.h / z}` : `0 0 ${size.w} ${size.h}`;
  const toScreen = (x: number, y: number) => (view ? [(x - view.x) * z, (y - view.y) * z] : [x, y]);

  function zoomAt(f: number, sx = size.w / 2, sy = size.h / 2) {
    if (!view) return;
    const nz = Math.min(Math.max(view.z * f, 0.4), MAX_Z * 2);
    const fx = view.x + sx / view.z, fy = view.y + sy / view.z;
    setView({ z: nz, x: fx - sx / nz, y: fy - sy / nz });
  }

  useEffect(() => {
    const el = svgRef.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      e.preventDefault();
      const r = el.getBoundingClientRect();
      zoomAt(Math.exp(-e.deltaY * 0.0015), e.clientX - r.left, e.clientY - r.top);
    };
    el.addEventListener("wheel", onWheel, { passive: false });
    return () => el.removeEventListener("wheel", onWheel);
  });

  function toFrame(e: { clientX: number; clientY: number }) {
    const r = svgRef.current!.getBoundingClientRect();
    return [view!.x + (e.clientX - r.left) / z, view!.y + (e.clientY - r.top) / z];
  }

  // ── colours ──
  const colour = useMemo(() => {
    const out: Record<string, string> = {};
    if (!data || !metric) return { fill: out, ticks: DIV_TICKS, ramp: DIV, ok: true };
    const vals = data.units.map((x) => x.m[metric.key]).filter((v): v is number => v != null).sort((a, b) => a - b);
    if (metric.kind === "div") {
      data.units.forEach((x) => { const v = x.m[metric.key]; out[x.n] = v == null ? "#E6ECEA" : divCol(v); });
      return { fill: out, ticks: DIV_TICKS, ramp: DIV, ok: vals.length > 0 };
    }
    const brk = [1, 2, 3, 4, 5].map((i) => vals[Math.floor((vals.length * i) / 6)]);
    data.units.forEach((x) => { const v = x.m[metric.key]; out[x.n] = v == null ? "#E6ECEA" : SEQ[brk.filter((b) => v >= b).length]; });
    const ticks = vals.length ? [vals[0], ...brk, vals[vals.length - 1]].map((v) => idn(disp(metric, v), metric.d)) : [];
    return { fill: out, ticks, ramp: SEQ, ok: vals.length > 0 };
  }, [data, metric]);

  const critSites = useMemo(() => {
    if (!data) return [];
    const r = critRule ?? { metric: "payload_mom", t: -10 };
    return data.sites.filter((s) => { const v = s[r.metric as "payload_mom"]; return v != null && v <= r.t; });
  }, [data, critRule]);
  const worstSite = useMemo(() => [...critSites].sort((a, b) => (a.payload_mom ?? 0) - (b.payload_mom ?? 0))[0]?.id, [critSites]);
  const critIds = useMemo(() => new Set(critSites.map((s) => s.id)), [critSites]);
  const layerCount = (layers.chor ? 1 : 0) + (layers.crit ? 1 : 0) + (shape && layers.up ? 1 : 0) + (layers.all ? 1 : 0) + points.length;

  // ── chat ──
  const scopeKey = data ? `${data.scope.level}:${data.scope.kabupaten || data.scope.region}` : "";
  useEffect(() => {
    msgsRef.current?.scrollTo({ top: msgsRef.current.scrollHeight });
  }, [msgs, busy]);

  useEffect(() => {
    if (!scopeKey || !msgs.length) return;
    try {
      const all = JSON.parse(localStorage.getItem("map_chats") || "[]") as { key: string; at: number; title: string; msgs: Msg[] }[];
      const title = (msgs.find((m) => m.role === "user") as { text: string } | undefined)?.text || "Percakapan peta";
      const id = `${scopeKey}|${(msgs[0] as { text?: string }).text}`;
      const rest = all.filter((c) => `${c.key}|${(c.msgs[0] as { text?: string }).text}` !== id);
      localStorage.setItem("map_chats", JSON.stringify([{ key: scopeKey, at: Date.now(), title, msgs }, ...rest].slice(0, 12)));
    } catch { /* storage unavailable */ }
  }, [msgs, scopeKey]);

  function applyAnswer(a: Answer) {
    for (const l of a.layers || []) {
      if (l.kind === "chor" && l.metric) {
        const m = data?.metrics.find((x) => x.key === l.metric);
        if (m) { setCat(m.cat); setMetricKey(m.key); }
        setLayers((s) => ({ ...s, chor: true }));
      } else if (l.kind === "sites") {
        setCritRule({ metric: l.metric || "payload_mom", t: l.threshold ?? -10 });
        setLayers((s) => ({ ...s, crit: true }));
      } else if (l.kind === "point") setPoints((p) => [...p, l]);
    }
    if (a.select) { setSelUnit(a.select); setSelSite(null); }
    if (a.focus) setView(fit(a.focus));
  }

  async function send(text?: string) {
    const q = (text ?? input).trim();
    if (!q || busy || !data) return;
    const file = pending;
    setMsgs((m) => [...m, { role: "user", text: q, file: file || undefined }]);
    setInput("");
    setPending(null);
    setBusy(true);
    try {
      const r = await authFetch("/api/map/agent/ask", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ q, region: data.scope.region, kabupaten: data.scope.kabupaten, shapes: shape ? [{ rings: shape.rings, name: shape.name }] : [] }),
      });
      const a = await r.json();
      if (!r.ok) throw new Error(a?.detail || "gagal");
      setMsgs((m) => [...m, { role: "agent", ...a }]);
      applyAnswer(a);
    } catch (e) {
      setMsgs((m) => [...m, { role: "agent", time: nowLabel(), text: `Maaf, jawaban belum bisa dibuat (${(e as Error).message}). Coba lagi sebentar.`, layers: [], stats: [], actions: [] }]);
    } finally {
      setBusy(false);
    }
  }

  async function attach(f: File) {
    setUpErr("");
    if (f.size > 20 * 1024 * 1024) { setUpErr("File lebih dari 20 MB"); return; }
    try {
      const r = await authFetch("/api/map/agent/upload", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: f.name, data: await b64(f), region: data?.scope.region || "", kabupaten: data?.scope.kabupaten || "" }),
      });
      const s = await r.json();
      if (!r.ok) throw new Error(s?.detail || "File tidak terbaca");
      setShape(s);
      setPending(s);
      setLayers((l) => ({ ...l, up: true }));
      taRef.current?.focus();
    } catch (e) {
      setUpErr((e as Error).message);
    }
  }

  function newChat() {
    setMsgs([]); setPoints([]); setShape(null); setPending(null); setCritRule(null);
    setLayers({ chor: true, crit: true, up: true, all: true, opacity: 0.85 });
    setCat("perf"); setMetricKey("payload_mom"); setView(home());
  }

  // ── exports ──
  const siteById = useMemo(() => new Map((data?.sites || []).map((s) => [s.id, s])), [data]);
  function features(ids: string[]) {
    const f: object[] = ids.map((id) => siteById.get(id)).filter(Boolean).map((s) => ({
      type: "Feature", geometry: { type: "Point", coordinates: [s!.lon, s!.lat] },
      properties: { site_id: s!.id, kecamatan: s!.k, kabupaten: s!.kab, status: s!.status, payload_mom: s!.payload_mom, revenue_mom: s!.revenue_mom, availability: s!.availability },
    }));
    if (shape) f.push({ type: "Feature", geometry: { type: "Polygon", coordinates: shape.rings }, properties: { nama: shape.label, area_km2: shape.area_km2 } });
    return f;
  }
  async function exportAs(fmt: "geojson" | "shp" | "csv", ids: string[]) {
    setMenu(null);
    const name = `peta_agent_${(data?.scope.kabupaten || data?.scope.region || "java").toLowerCase().replace(/\W+/g, "_")}`;
    const r = await authFetch("/api/map/agent/export", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ format: fmt, name, features: fmt === "csv" ? features(ids).slice(0, ids.length) : features(ids) }),
    });
    if (!r.ok) return;
    download(await r.blob(), fmt === "shp" ? `${name}_shp.zip` : `${name}.${fmt}`);
  }
  async function exportPng() {
    const svg = svgRef.current;
    if (!svg) return;
    const clone = svg.cloneNode(true) as SVGSVGElement;
    clone.setAttribute("width", String(size.w));
    clone.setAttribute("height", String(size.h));
    clone.querySelectorAll("image").forEach((n) => n.remove());
    const url = URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(clone)], { type: "image/svg+xml" }));
    const img = new Image();
    img.onload = () => {
      const c = document.createElement("canvas");
      c.width = size.w * 2; c.height = size.h * 2;
      const g = c.getContext("2d")!;
      g.scale(2, 2);
      g.fillStyle = "#D6EAF0"; g.fillRect(0, 0, size.w, size.h);
      g.drawImage(img, 0, 0, size.w, size.h);
      URL.revokeObjectURL(url);
      c.toBlob((b) => b && download(b, `peta_agent_${(data?.scope.kabupaten || "java").toLowerCase()}.png`));
    };
    img.src = url;
  }

  // ── map events ──
  function onDown(e: React.PointerEvent) {
    if (!view) return;
    drag.current = { x: e.clientX, y: e.clientY, v: view, moved: false };
    (e.target as Element).setPointerCapture?.(e.pointerId);
  }
  function onMove(e: React.PointerEvent) {
    const d = drag.current;
    if (d) {
      const dx = e.clientX - d.x, dy = e.clientY - d.y;
      if (Math.abs(dx) + Math.abs(dy) > 3) d.moved = true;
      if (d.moved) { setView({ ...d.v, x: d.v.x - dx / d.v.z, y: d.v.y - dy / d.v.z }); setHover(null); return; }
    }
    const t = (e.target as Element).closest?.("[data-u]") as SVGElement | null;
    if (!t || !wrapRef.current) { setHover(null); return; }
    const r = wrapRef.current.getBoundingClientRect();
    setHover({ n: t.dataset.u!, x: e.clientX - r.left + 14, y: e.clientY - r.top + 14 });
  }
  function onUp(e: React.PointerEvent) {
    const d = drag.current;
    drag.current = null;
    if (d?.moved || !view || !data) return;
    if (pick) {
      const [x, y] = toFrame(e);
      const f = data.frame;
      const lon = f.lon0 + (x - f.ox) / (f.cx * f.s), lat = f.lat1 - (y - f.oy) / f.s;
      setInput((v) => `${v ? v + " " : "Site terdekat dari "}${lat.toFixed(5)}, ${lon.toFixed(5)}`);
      setPick(false);
      taRef.current?.focus();
      return;
    }
    const el = e.target as SVGElement;
    const sid = el.dataset?.s;
    if (sid) { setSelSite(sid); return; }
    const un = (el.closest?.("[data-u]") as SVGElement | null)?.dataset.u;
    if (un) { setSelUnit(un); setSelSite(null); }
  }

  // ── derived UI ──
  const unit = data?.units.find((x) => x.n === selUnit) || null;
  const site = selSite ? siteById.get(selSite) : null;
  const hu = hover && data?.units.find((x) => x.n === hover.n);
  const catMetrics = (data?.metrics || []).filter((m) => m.cat === cat);
  const lastAgent = [...msgs].reverse().find((m) => m.role === "agent") as (Answer & { role: "agent" }) | undefined;
  const sugg = lastAgent?.suggestions?.length ? lastAgent.suggestions : ["Payload MoM per kecamatan, tandai site turun > 10%", "Site productivity per kecamatan", "Profile wilayah"];
  const scaleBar = useMemo(() => {
    if (!data) return { km: 5, px: 72 };
    const kmPerPx = 110.57 / (data.frame.s * z);
    const km = [0.5, 1, 2, 5, 10, 20, 50, 100].find((k) => k / kmPerPx >= 50) ?? 100;
    return { km, px: Math.round(km / kmPerPx) };
  }, [data, z]);

  const tiles = useMemo(() => {
    if (base === "light" || !data || !view) return [];
    const f = data.frame;
    const lon0 = f.lon0 + (view.x - f.ox) / (f.cx * f.s), lon1 = f.lon0 + (view.x + size.w / z - f.ox) / (f.cx * f.s);
    const lat0 = f.lat1 - (view.y - f.oy) / f.s, lat1 = f.lat1 - (view.y + size.h / z - f.oy) / f.s;
    const tz = Math.max(5, Math.min(17, Math.round(Math.log2((360 * f.cx * f.s * z) / 256 / Math.cos((lat0 * Math.PI) / 180)) + 0.3)));
    const n = 2 ** tz;
    const tx = (lon: number) => ((lon + 180) / 360) * n;
    const ty = (lat: number) => ((1 - Math.log(Math.tan((lat * Math.PI) / 180) + 1 / Math.cos((lat * Math.PI) / 180)) / Math.PI) / 2) * n;
    const lonOf = (x: number) => (x / n) * 360 - 180;
    const latOf = (y: number) => (Math.atan(Math.sinh(Math.PI * (1 - (2 * y) / n))) * 180) / Math.PI;
    const P = (lon: number, lat: number) => [f.ox + (lon - f.lon0) * f.cx * f.s, f.oy + (f.lat1 - lat) * f.s];
    const out: { href: string; x: number; y: number; w: number; h: number }[] = [];
    for (let i = Math.floor(tx(lon0)); i <= Math.floor(tx(lon1)); i++) {
      for (let j = Math.floor(ty(lat0)); j <= Math.floor(ty(lat1)); j++) {
        const [x0, y0] = P(lonOf(i), latOf(j)), [x1, y1] = P(lonOf(i + 1), latOf(j + 1));
        const href = base === "road" ? `https://tile.openstreetmap.org/${tz}/${i}/${j}.png`
          : `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${tz}/${j}/${i}`;
        out.push({ href, x: x0, y: y0, w: x1 - x0, h: y1 - y0 });
      }
    }
    return out.length > 120 ? [] : out;
  }, [base, data, view, size, z]);

  const labels = data && view ? data.units.filter((k) => k.label && k.cx > view.x + 20 * u && k.cx < view.x + size.w / z - 20 * u && k.cy > view.y + 10 * u && k.cy < view.y + size.h / z - 10 * u) : [];
  const shownMsgs = msgs;

  return (
    <AppShell mainClassName="pmain">
      <TopBar title="Peta Agent" subtitle="Tanya dengan bahasa biasa, jawabannya tampil di peta"
        actions={<>
          <div style={{ position: "relative" }}>
            <button className="chip teal btn" onClick={() => setScopeOpen((v) => !v)} aria-label="Pilih wilayah"><Icon name="pin" />{data ? `${data.scope.name}${data.scope.province ? `, ${data.scope.province}` : ""}` : "Memuat…"}</button>
            {scopeOpen && <ScopePicker current={data?.scope.kabupaten || ""} onPick={(k) => { setScopeOpen(false); setView(null); setSelUnit(null); setSelSite(null); setShape(null); setPoints([]); setKab(k); router.replace(`/map?kabupaten=${encodeURIComponent(k)}`); }} />}
          </div>
          <span className="chip"><Icon name="cal" />{data?.month_label ?? "Bulan ini"}</span>
        </>} />
      <div className="pmap">
        <div className="mapwrap" ref={wrapRef} data-name="Peta"
          onDragOver={(e) => { e.preventDefault(); }} onDrop={(e) => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) attach(f); }}>
          <svg ref={svgRef} className={`map${drag.current?.moved ? " drag" : ""}${pick ? " pick" : ""}`} viewBox={vb}
            onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerLeave={() => setHover(null)} role="img" aria-label={`Peta ${data?.scope.name ?? ""}`}>
            {view && <rect x={view.x - 50} y={view.y - 50} width={size.w / z + 100} height={size.h / z + 100} fill="#D6EAF0" />}
            {tiles.map((t) => <image key={t.href} href={t.href} x={t.x} y={t.y} width={t.w} height={t.h} preserveAspectRatio="none" />)}
            <g>{data?.neighbors.map((n) => <path key={n.n} d={n.d} fill={base === "light" ? "#E6ECEA" : "none"} stroke="#FFFFFF" strokeWidth={1.2 * u} fillRule="evenodd" />)}</g>
            {layers.chor && data && (
              <g fillOpacity={layers.opacity}>
                {data.units.map((x) => <path key={x.n} data-u={x.n} d={x.d} fill={colour.fill[x.n]} stroke="#FFFFFF" strokeWidth={u} fillRule="evenodd" />)}
                {hu && <path data-u={hu.n} d={hu.d} fill={colour.fill[hu.n]} stroke="#FFFFFF" strokeWidth={2.5 * u} fillRule="evenodd" />}
              </g>
            )}
            {!layers.chor && data && <g>{data.units.map((x) => <path key={x.n} data-u={x.n} d={x.d} fill="transparent" stroke="#FFFFFF" strokeWidth={u} />)}</g>}
            {data?.outline && <path d={data.outline} fill="none" stroke="#0A6A5F" strokeWidth={2 * u} strokeLinejoin="round" pointerEvents="none" />}
            {shape && layers.up && shape.d && (
              <g pointerEvents="none">
                <path d={shape.d} fill="#FFFFFF" fillOpacity={0.16} stroke="#FFFFFF" strokeWidth={5 * u} strokeLinejoin="round" />
                <path d={shape.d} fill="none" stroke="#0F1F1D" strokeWidth={2.2 * u} strokeDasharray={`${7 * u} ${4 * u}`} strokeLinejoin="round" />
              </g>
            )}
            {shape && layers.up && shape.points.map(([x, y], i) => <circle key={i} cx={x} cy={y} r={3.2 * u} fill="#0F1F1D" stroke="#fff" strokeWidth={u} pointerEvents="none" />)}
            {layers.all && <g>{data?.sites.filter((s) => !(layers.crit && critIds.has(s.id))).map((s) => <circle key={s.id} data-s={s.id} cx={s.x} cy={s.y} r={2.2 * u} fill="#3D4C49" fillOpacity={0.75} stroke="#FFFFFF" strokeWidth={0.8 * u} />)}</g>}
            <g pointerEvents="none">
              {labels.map((k) => (
                <text key={k.n} x={k.cx} y={k.cy} textAnchor="middle" style={{ fontFamily: "var(--f-display)" }} fontSize={10.5 * u} fontWeight={600} fill="#0F1F1D" stroke="#FFFFFF" strokeWidth={3 * u} paintOrder="stroke" strokeLinejoin="round">{k.n}</text>
              ))}
            </g>
            {points.map((p, i) => <g key={i} pointerEvents="none"><circle cx={p.x} cy={p.y} r={9 * u} fill="#0E8579" fillOpacity={0.2} /><circle cx={p.x} cy={p.y} r={4.5 * u} fill="#0E8579" stroke="#fff" strokeWidth={1.8 * u} /></g>)}
            {layers.crit && (
              <g>
                {critSites.map((s) => {
                  const big = s.id === worstSite || s.id === selSite;
                  return (
                    <g key={s.id}>
                      {big && <circle cx={s.x} cy={s.y} r={10 * u} fill="#C42B2B" fillOpacity={0.18} pointerEvents="none" />}
                      <circle data-s={s.id} cx={s.x} cy={s.y} r={(big ? 6 : 4.6) * u} fill="#C42B2B" stroke="#FFFFFF" strokeWidth={1.8 * u} style={{ cursor: "pointer" }} />
                    </g>
                  );
                })}
              </g>
            )}
            {site && !critIds.has(site.id) && <circle cx={site.x} cy={site.y} r={6 * u} fill="#0E8579" stroke="#fff" strokeWidth={1.8 * u} pointerEvents="none" />}
          </svg>
          {hover && hu && metric && (
            <div className="mtip" style={{ display: "block", left: hover.x, top: hover.y }}>
              <b>{unitPrefix}{hu.n}</b>{metric.name} {fmtM(metric, hu.m[metric.key])} · {hu.sites} site
            </div>
          )}

          <div className="mcard mbar" data-name="Metrik peta">
            <div className="mb1"><span className="lb">Warnai peta dengan</span>
              <div className="seg cseg">
                {CATS.map((c) => (
                  <button key={c.key} className={cat === c.key ? "on" : ""} onClick={() => { setCat(c.key); const first = data?.metrics.find((m) => m.cat === c.key); if (first) setMetricKey(first.key); }}>
                    <Icon name={c.icon} />{c.label}
                  </button>
                ))}
              </div>
            </div>
            <div className="mb2">
              {catMetrics.map((m) => (
                <button key={m.key} className={`mchip${m.key === metricKey ? " on" : ""}${m.available === false ? " na" : ""}`} onClick={() => setMetricKey(m.key)}
                  title={m.available === false ? "Data belum ada di dump Performance" : undefined}>{m.name}</button>
              ))}
              {cat === "prod" && <span className="mchip sub" title="Tipe site belum ada di dump Performance; semua tipe dihitung">Tipe site: Semua<Icon name="chev" style={{ width: 12, height: 12 }} /></span>}
            </div>
          </div>

          <div className={`mcard lyr${lyrMin ? " min" : ""}`} data-name="Panel layer">
            <div className="hd"><Icon name="layers" />Layer<small>{layerCount} aktif</small><span className="grow" />
              <button onClick={() => setLyrMin((v) => !v)} aria-label={lyrMin ? "Buka panel layer" : "Tutup panel layer"}><Icon name="chev" className="chev" style={{ color: "#5A6B68", width: 16 }} /></button>
            </div>
            <div className={`lr${layers.chor ? "" : " off"}`} onClick={() => setLayers((s) => ({ ...s, chor: !s.chor }))}>
              <span className="lsw" style={{ background: metric?.kind === "seq" ? `linear-gradient(90deg,${SEQ[0]},${SEQ[3]},${SEQ[5]})` : "linear-gradient(90deg,#C42B2B,#F4A08A,#D8EFEA,#7FCFC3)" }} />
              <div><b className="cn">{metric?.name ?? "Payload MoM"} per {unitWord}</b><small>Choropleth · {data?.units.length ?? 0} {unitWord}</small></div>
              <span className="eye"><i /></span>
            </div>
            <div className="op">Opasitas<div className="rail"><i style={{ width: `${layers.opacity * 100}%` }} />
              <input type="range" min={20} max={100} value={Math.round(layers.opacity * 100)} aria-label="Opasitas choropleth" onChange={(e) => setLayers((s) => ({ ...s, opacity: +e.target.value / 100 }))} /></div>{Math.round(layers.opacity * 100)}%</div>
            <div className={`lr${layers.crit ? "" : " off"}`} onClick={() => setLayers((s) => ({ ...s, crit: !s.crit }))}>
              <span className="lsw" style={{ background: "#C42B2B", borderRadius: "50%", border: "3px solid #fff", boxShadow: "0 0 0 1px #E1E9E7" }} />
              <div><b>Site {(critRule?.metric ?? "payload_mom") === "revenue_mom" ? "revenue" : "payload"} turun &gt; {idn(Math.abs(critRule?.t ?? -10), 0)}%</b><small>Titik koordinat · {critSites.length} site</small></div>
              <span className="eye"><i /></span>
            </div>
            {shape && (
              <div className={`lr${layers.up ? "" : " off"}`} onClick={() => setLayers((s) => ({ ...s, up: !s.up }))}>
                <span className="lsw" style={{ background: "rgba(255,255,255,.6)", border: "2px dashed #0F1F1D" }} />
                <div><b>{shape.label}</b><small>{shape.d ? `Poligon ${shape.kind} · ${idn(shape.area_km2, 1)} km²` : `Titik ${shape.kind} · ${shape.count}`}</small></div>
                <span className="eye"><i /></span>
              </div>
            )}
            <div className={`lr${layers.all ? "" : " off"}`} onClick={() => setLayers((s) => ({ ...s, all: !s.all }))}>
              <span className="lsw" style={{ background: "#3D4C49", borderRadius: "50%", transform: "scale(.55)" }} />
              <div><b>Semua site</b><small>Titik koordinat · {data?.sites.length ?? 0} site{data?.sites_without_coord ? ` (+${data.sites_without_coord} tanpa koordinat)` : ""}</small></div>
              <span className="eye"><i /></span>
            </div>
            <div className="bm">Peta dasar<div className="seg">
              <button className={base === "light" ? "on" : ""} onClick={() => setBase("light")}>Terang</button>
              <button className={base === "sat" ? "on" : ""} onClick={() => setBase("sat")}>Satelit</button>
              <button className={base === "road" ? "on" : ""} onClick={() => setBase("road")}>Jalan</button>
            </div></div>
          </div>

          <div className="mcard zm">
            <button onClick={() => zoomAt(1.4)} aria-label="Perbesar"><Icon name="plus" /></button>
            <button onClick={() => zoomAt(1 / 1.4)} aria-label="Perkecil"><Icon name="minus" /></button>
            <hr />
            <button onClick={() => { const h = home(); if (h) setView(h); }} aria-label="Kembali ke seluruh wilayah"><Icon name="locate" /></button>
            <button onClick={() => { const el = wrapRef.current?.parentElement; if (!document.fullscreenElement) el?.requestFullscreen?.(); else document.exitFullscreen?.(); }} aria-label="Layar penuh"><Icon name="max" /></button>
          </div>

          <div className="mcard lgd" data-name="Legenda">
            <b className="lt">{metric?.name ?? "Payload MoM"} per {unitWord}</b>
            {colour.ok ? (
              <>
                <div className="ramp lr6">{colour.ramp.map((c) => <i key={c} style={{ background: c }} />)}</div>
                <div className="tk ltk">{colour.ticks.map((t, i) => <span key={i}>{t}</span>)}</div>
              </>
            ) : <div className="na">Data {metric?.name} belum ada di dump Performance, jadi peta diwarnai abu-abu.</div>}
            <div className="sy">
              <span><i style={{ background: "#C42B2B", boxShadow: "0 0 0 2px #fff,0 0 0 3px #E1E9E7" }} />Site kritis</span>
              <span><i style={{ background: "#3D4C49", transform: "scale(.6)" }} />Site</span>
              <span><i style={{ background: "#fff", border: "1.5px dashed #0F1F1D", borderRadius: 3 }} />Area upload</span>
            </div>
          </div>
          <div className="mcard scl"><span>{idn(scaleBar.km, scaleBar.km < 1 ? 1 : 0)} km</span><i style={{ width: scaleBar.px }} /></div>

          {unit && !site && metric && data && (
            <div className="mcard kcard" data-name="Kartu kecamatan">
              <div className="h"><div><b>{unitPrefix}{unit.n}</b><small>{data.scope.level === "kabupaten" ? `${data.scope.name} · ` : ""}{unit.sites} site · {data.month_label}</small></div><span className="grow" />
                <span className={`sev ${unit.status === "kritis" ? "k" : unit.status === "waspada" ? "w" : "n"}`}>{unit.status === "kritis" ? "Kritis" : unit.status === "waspada" ? "Waspada" : "Normal"}</span></div>
              {CATS.map((c) => (
                <div className="ks" key={c.key}><span>{c.label}</span>
                  <div className="k3">{data.metrics.filter((m) => m.cat === c.key).slice(0, 3).map((m) => {
                    const v = unit.m[m.key];
                    return <div key={m.key}><small>{m.short}</small><b style={{ color: m.kind === "div" && v != null ? (v < 0 ? "#C42B2B" : "#1F7A3A") : "#0F1F1D" }}>{fmtM(m, v)}</b></div>;
                  })}</div>
                </div>
              ))}
              <div className="ac">
                <button className="a1" onClick={() => send(`Profile ${unitPrefix}${unit.n}`)}><Icon name="spark" />Tanya</button>
                <button className="a2" onClick={() => router.push(`/performance?${data.scope.level === "kabupaten" ? `kabupaten=${encodeURIComponent(data.scope.kabupaten)}&kecamatan=${encodeURIComponent(unit.n.toUpperCase())}` : `kabupaten=${encodeURIComponent(unit.n.replace(/^(Kab\. |Kota )/, (p) => (p === "Kota " ? "KOTA " : "")).toUpperCase())}`}`)}><Icon name="file" />Profil lengkap</button>
              </div>
            </div>
          )}
          {site && view && (() => {
            const [px, py] = toScreen(site.x, site.y);
            return (
              <div className="mcard pop" data-name="Popup site" style={{ left: px - 125, top: py - 16, transform: "translateY(-100%)" }}>
                <div className="h"><div><b>{site.id}</b><small>Kec. {site.k}{site.name ? ` · ${site.name}` : ""}</small></div><span className="grow" />
                  <span className={`sev ${site.status === "kritis" ? "k" : site.status === "waspada" ? "w" : "n"}`}>{site.status === "kritis" ? "Kritis" : site.status === "waspada" ? "Waspada" : "Normal"}</span>
                  <button aria-label="Tutup" onClick={() => setSelSite(null)} style={{ color: "#5A6B68", marginLeft: 2 }}>×</button></div>
                <div className="m2"><div><small>Payload MoM</small><b>{site.payload_mom == null ? "-" : pct(site.payload_mom)}</b></div><div><small>Revenue MoM</small><b>{site.revenue_mom == null ? "-" : pct(site.revenue_mom)}</b></div></div>
                <small style={{ font: "400 11px/1.3 var(--f-body)", color: "#5A6B68" }}>{site.lat.toFixed(5)}, {site.lon.toFixed(5)}</small>
                <div className="ac">
                  <button className="a1" onClick={() => router.push(`/?q=${encodeURIComponent(`Kenapa site ${site.id} di Kec. ${site.k} ${site.payload_mom != null && site.payload_mom < 0 ? "turun" : "berubah"} di ${data?.month_label}? Bandingkan payload, revenue dan availability dengan bulan lalu.`)}`)}><Icon name="spark" />Tanya</button>
                  <button className="a2" onClick={() => router.push(`/performance?kabupaten=${encodeURIComponent(data?.scope.kabupaten || "")}&kecamatan=${encodeURIComponent(site.k.toUpperCase())}`)}><Icon name="pulse" />Performance</button>
                </div>
              </div>
            );
          })()}
          {err && <div className="mcard" style={{ left: "50%", top: "50%", transform: "translate(-50%,-50%)", padding: 16, font: "500 13px/1.4 var(--f-display)" }}>{err}</div>}
        </div>

        <aside className={`mchat${drop ? " drop" : ""}`} data-name="Chat peta"
          onDragOver={(e) => { e.preventDefault(); setDrop(true); }} onDragLeave={() => setDrop(false)}
          onDrop={(e) => { e.preventDefault(); setDrop(false); const f = e.dataTransfer.files[0]; if (f) attach(f); }}>
          <div className="ch"><div><b>Percakapan peta</b><small>Setiap jawaban menambah layer di peta</small></div><span className="grow" />
            <button className="btn-ic" style={{ width: 34, height: 34, borderRadius: 10 }} onClick={() => setHist((v) => !v)} aria-label="Riwayat percakapan peta"><Icon name="hist" className="ic" style={{ width: 17, height: 17 }} /></button>
            <button className="btn-ic" style={{ width: 34, height: 34, borderRadius: 10 }} onClick={newChat} aria-label="Percakapan baru"><Icon name="plus" className="ic" style={{ width: 17, height: 17 }} /></button>
          </div>
          {hist && <HistoryList onPick={(m) => { setHist(false); setMsgs(m); [...m].filter((x) => x.role === "agent").forEach((a) => applyAnswer(a as Answer)); }} />}
          <div className="mmsgs" ref={msgsRef}>
            {!shownMsgs.length && (
              <div className="mempty"><b>Tanya apa saja tentang peta {data?.scope.name ?? ""}</b>
                Contoh: warnai per kecamatan, tandai site yang turun, cek koordinat, atau upload SHP lalu tanya isi areanya.</div>
            )}
            {shownMsgs.map((m, i) => m.role === "user" ? (
              <div className="mu" key={i}>
                {m.file && <div className="file"><i>{m.file.kind === "GeoJSON" ? "GEO" : m.file.kind}</i><div><b>{m.file.name}</b><small>{m.file.desc} · {m.file.count} · {m.file.size_kb} KB</small></div></div>}
                {m.text}
              </div>
            ) : (
              <div className="ma" key={i}>
                <div className="who"><i><Icon name="spark" /></i>Agent Java<small>{m.time}</small></div>
                <p>{bold(m.text)}</p>
                {m.layers.length > 0 && (
                  <div className="lchips">{m.layers.map((l, j) => (
                    <div className="lchip" key={j}>
                      <span className="lsw" style={{ background: l.kind === "chor" ? "linear-gradient(90deg,#C42B2B,#F4A08A,#7FCFC3)" : l.kind === "sites" ? "#C42B2B" : "#0E8579", borderRadius: l.kind === "chor" ? 4 : "50%" }} />{l.label}
                      <small onClick={() => {
                        if (!data) return;
                        if (l.kind === "chor") setView(fit([0, 0, data.frame.w, data.frame.h]));
                        else if (l.kind === "point" && l.x != null && l.y != null) setView(fit([l.x - 50, l.y - 44, l.x + 50, l.y + 44]));
                        else { const pts = critSites; if (pts.length) setView(fit([Math.min(...pts.map((s) => s.x)) - 20, Math.min(...pts.map((s) => s.y)) - 20, Math.max(...pts.map((s) => s.x)) + 20, Math.max(...pts.map((s) => s.y)) + 20])); }
                      }}><Icon name="zoomto" />Zoom</small>
                    </div>
                  ))}</div>
                )}
                {m.stats.length > 0 && (
                  <div className="mstat">{m.stats.map((s, j) => <div key={j}><small>{s.label}</small><b>{s.value}</b>{s.sub && <em className={s.tone || ""}>{s.sub}</em>}</div>)}</div>
                )}
                {m.actions.length > 0 && (
                  <div className="macts">
                    {m.actions.includes("sites") && <button onClick={() => setList({ title: `Daftar ${m.site_ids?.length ?? 0} site`, ids: m.site_ids || [] })}><Icon name="table" />Daftar {m.site_ids?.length ?? 0} site</button>}
                    {m.actions.includes("geojson") && (
                      <span className="dd">
                        <button onClick={() => setMenu(menu === i ? null : i)} aria-haspopup="menu"><Icon name="dl" />GeoJSON</button>
                        {menu === i && (
                          <div className="menu" role="menu">
                            <button onClick={() => exportAs("geojson", m.site_ids || [])}>GeoJSON (.geojson)</button>
                            <button onClick={() => exportAs("shp", m.site_ids || [])}>Shapefile (.zip)</button>
                            <button onClick={() => exportAs("csv", m.site_ids || [])}>CSV koordinat (.csv)</button>
                          </div>
                        )}
                      </span>
                    )}
                    {m.actions.includes("png") && <button onClick={exportPng}><Icon name="dl" />PNG peta</button>}
                  </div>
                )}
              </div>
            ))}
            {busy && <div className="typing">Agent Java sedang menyusun layer…</div>}
          </div>
          <div className="msugg">{sugg.map((s) => <button key={s} onClick={() => send(s)}><Icon name="spark" />{s}</button>)}</div>
          <div className="mcomp">
            <div className="box">
              {pending && <div className="att"><i>{pending.kind === "GeoJSON" ? "GEO" : pending.kind}</i><span>{pending.name} · {pending.count}</span><span className="grow" /><button onClick={() => setPending(null)} aria-label="Lepas file">×</button></div>}
              <textarea ref={taRef} value={input} rows={1} placeholder="Tanya tentang peta, atau tarik file ke sini…" aria-label="Pertanyaan peta"
                onChange={(e) => { setInput(e.target.value); e.target.style.height = "18.9px"; e.target.style.height = `${Math.min(e.target.scrollHeight, 120)}px`; }}
                onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }} />
              <div className="row">
                <button className="ib" onClick={() => fileRef.current?.click()} aria-label="Upload SHP, GeoJSON, KML atau CSV"><Icon name="clip" /></button>
                <button className={`ib${pick ? " on" : ""}`} onClick={() => setPick((v) => !v)} aria-label="Ambil koordinat dari peta" title="Klik peta untuk mengambil koordinat"><Icon name="pin" /></button>
                <Mic onText={(t) => setInput((v) => (v ? `${v} ${t}` : t))} />
                <span className="grow" />
                <button className="snd" onClick={() => send()} disabled={busy || !input.trim()} aria-label="Kirim"><Icon name="send" /></button>
              </div>
              {upErr && <div className="err">{upErr}</div>}
            </div>
            <div className="ft">Upload: SHP (.zip), GeoJSON, KML, CSV lat/long · maks 20 MB</div>
            <input ref={fileRef} type="file" hidden accept=".zip,.shp,.geojson,.json,.kml,.csv" aria-label="File peta" onChange={(e) => { const f = e.target.files?.[0]; if (f) attach(f); e.target.value = ""; }} />
          </div>
        </aside>

        {list && data && (
          <div className="sitelist" onClick={() => setList(null)}>
            <div onClick={(e) => e.stopPropagation()}>
              <header><b>{list.title}</b><span className="grow" />
                <button onClick={() => navigator.clipboard?.writeText(list.ids.map((id) => siteById.get(id)).filter(Boolean).map((s) => `${s!.id}\t${s!.lat}\t${s!.lon}`).join("\n"))}><Icon name="copy" />Salin koordinat</button>
                <button onClick={() => exportAs("csv", list.ids)}><Icon name="dl" />CSV</button>
                <button onClick={() => setList(null)} aria-label="Tutup">×</button>
              </header>
              <div className="tw"><table>
                <thead><tr><th>Site</th><th>Kecamatan</th><th>Latitude</th><th>Longitude</th><th>Payload MoM</th><th>Revenue MoM</th><th>Status</th></tr></thead>
                <tbody>{list.ids.map((id) => siteById.get(id)).filter(Boolean).map((s) => (
                  <tr key={s!.id} onClick={() => { setList(null); setSelSite(s!.id); setView(fit([s!.x - 60, s!.y - 50, s!.x + 60, s!.y + 50])); }}>
                    <td>{s!.id}</td><td>{s!.k}</td><td>{s!.lat.toFixed(5)}</td><td>{s!.lon.toFixed(5)}</td>
                    <td style={{ color: (s!.payload_mom ?? 0) < 0 ? "#C42B2B" : "#1F7A3A" }}>{s!.payload_mom == null ? "-" : pct(s!.payload_mom)}</td>
                    <td style={{ color: (s!.revenue_mom ?? 0) < 0 ? "#C42B2B" : "#1F7A3A" }}>{s!.revenue_mom == null ? "-" : pct(s!.revenue_mom)}</td>
                    <td>{s!.status}</td>
                  </tr>
                ))}</tbody>
              </table></div>
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function ScopePicker({ current, onPick }: { current: string; onPick: (k: string) => void }) {
  const [groups, setGroups] = useState<{ province: string; items: { kabupaten: string; name: string }[] }[]>([]);
  const [q, setQ] = useState("");
  useEffect(() => { authFetch("/api/map/agent/scopes").then((r) => (r.ok ? r.json() : [])).then(setGroups).catch(() => {}); }, []);
  const ql = q.toLowerCase();
  return (
    <div className="pmap" style={{ position: "absolute", top: 40, right: 0, flex: "none", zIndex: 30 }}>
      <div className="scopes">
        <input autoFocus placeholder="Cari kabupaten atau kota…" value={q} onChange={(e) => setQ(e.target.value)} aria-label="Cari wilayah" />
        {groups.map((g) => {
          const items = g.items.filter((x) => !ql || x.name.toLowerCase().includes(ql));
          if (!items.length) return null;
          return <div key={g.province}><h4>{g.province}</h4>{items.map((x) => <button key={x.kabupaten} className={x.kabupaten === current ? "on" : ""} onClick={() => onPick(x.kabupaten)}>{x.name}</button>)}</div>;
        })}
        {!groups.length && <div style={{ padding: 8, font: "400 12px/1.4 var(--f-body)", color: "#5A6B68" }}>Memuat daftar wilayah…</div>}
      </div>
    </div>
  );
}

function HistoryList({ onPick }: { onPick: (m: Msg[]) => void }) {
  const [items] = useState<{ key: string; at: number; title: string; msgs: Msg[] }[]>(() => {
    try { return JSON.parse(localStorage.getItem("map_chats") || "[]"); } catch { return []; }
  });
  return (
    <div className="mhist">
      {items.length ? items.map((c, i) => (
        <button key={i} onClick={() => onPick(c.msgs)}><b>{c.title}</b><small>{c.key.split(":")[1]} · {new Date(c.at).toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" })}</small></button>
      )) : <div className="none">Belum ada percakapan peta yang tersimpan di browser ini.</div>}
    </div>
  );
}

type SpeechCtor = new () => { lang: string; interimResults: boolean; onresult: (e: { results: { 0: { transcript: string } }[] }) => void; onend: () => void; start: () => void; stop: () => void };

function Mic({ onText }: { onText: (t: string) => void }) {
  const [on, setOn] = useState(false);
  const rec = useRef<InstanceType<SpeechCtor> | null>(null);
  function toggle() {
    const w = window as unknown as { SpeechRecognition?: SpeechCtor; webkitSpeechRecognition?: SpeechCtor };
    const C = w.SpeechRecognition || w.webkitSpeechRecognition;
    if (!C) { alert("Input suara belum didukung browser ini."); return; }
    if (on) { rec.current?.stop(); return; }
    const r = new C();
    r.lang = "id-ID";
    r.interimResults = false;
    r.onresult = (e) => onText(e.results[0][0].transcript);
    r.onend = () => setOn(false);
    rec.current = r;
    setOn(true);
    r.start();
  }
  return <button className={`ib${on ? " on" : ""}`} onClick={toggle} aria-label="Input suara"><Icon name="mic" /></button>;
}
