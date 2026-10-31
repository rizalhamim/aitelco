"use client";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import MapCanvas, { type MapPoint, type Choropleth, type SiteChannel, type SiteChannelGroup, type SiteHistory, type SiteMetric } from "../../components/MapCanvas";
import Markdown from "../../components/Markdown";
import { isLoggedIn, getAccessToken, getUser } from "@/lib/auth";

type ChatTurn = { role: "user" | "assistant"; content: string; status?: string; error?: string };

type FixSite = {
  latitude: number; longitude: number; site_id: string; site_name: string; distance_km: number;
  site_type?: string; category?: string; addressable?: string; branch?: string; micro_cluster?: string;
  kecamatan?: string; kabupaten?: string; profitability_status_m1?: string; traffic_category?: string;
  perf?: Record<string, number | null>; mom?: Record<string, number | null>; yoy?: Record<string, number | null>;
  metrics?: Record<string, SiteMetric>;
  channels?: SiteChannel[]; channel_groups?: SiteChannelGroup[]; history?: SiteHistory[];
};

function detectLatLon(columns: string[]): { latKey: string; lonKey: string } | null {
  const lat = columns.find((c) => /^lat(itude)?$/i.test(c) || /_lat(itude)?$/i.test(c) || /(addr_)?latitude/i.test(c));
  const lon = columns.find((c) => /^lon(g|gitude)?$/i.test(c) || /_lon(g|gitude)?$/i.test(c) || /(addr_)?longitude/i.test(c));
  if (lat && lon) return { latKey: lat, lonKey: lon };
  return null;
}

function fmtVal(v: unknown): string {
  if (v === null || v === undefined || v === "") return "—";
  if (typeof v === "number") {
    return Number.isInteger(v) ? v.toLocaleString("id-ID") : v.toLocaleString("id-ID", { maximumFractionDigits: 2 });
  }
  return String(v);
}

function detectChoropleth(columns: string[], rows: Record<string, unknown>[]): Choropleth | null {
  const kecKey = columns.find((c) => /^kec_id$/i.test(c));
  const kabKey = columns.find((c) => /^kabkot_id$/i.test(c));
  const idKey = kecKey || kabKey;
  if (!idKey || rows.length === 0) return null;
  const level: "kecamatan" | "kabupaten" = kecKey ? "kecamatan" : "kabupaten";
  const labelKey = columns.find((c) => /^(kecamatan|kabupaten|kabkota|kabkot)$/i.test(c)) || idKey;
  // columns that are NOT a region key/label/province/month and ARE numeric
  const isExcluded = (c: string) =>
    c === idKey ||
    c === labelKey ||
    /_id$|^provinsi$|^province$|^kabupaten$|^kabkota$|^kecamatan$|^region$|month|periode?$|^cur_month$|^prev_month$/i.test(c);
  const numericCandidates = columns.filter((c) => !isExcluded(c) && rows.some((r) => typeof r[c] === "number"));
  // Prefer a growth/change/pct metric for choropleth coloring; else first numeric.
  const metricKey =
    numericCandidates.find((c) => /growth|pertumbuhan|change|delta|_pp$|_pct$|_pct_|trend/i.test(c)) ||
    numericCandidates[0];
  if (!metricKey) return null;
  const values: Record<string, { value: number; label: string; extra: Record<string, unknown> }> = {};
  for (const r of rows) {
    const id = String(r[idKey] ?? "").toUpperCase();
    const v = typeof r[metricKey] === "number" ? (r[metricKey] as number) : parseFloat(String(r[metricKey]));
    if (!id || !Number.isFinite(v)) continue;
    values[id] = { value: v, label: String(r[labelKey] ?? id), extra: r };
  }
  if (Object.keys(values).length === 0) return null;
  return { dissolveBy: "id", level, idKey: level === "kecamatan" ? "kec_id" : "kabkot_id", metricKey, values };
}

function rowsToPoints(columns: string[], rows: Record<string, unknown>[]): MapPoint[] {
  const ll = detectLatLon(columns);
  if (!ll) return [];
  const labelKey = columns.find((c) => /site_n|site_name|outlet_n|outlet_name|name|nama|kec|kab/i.test(c)) || columns[0];
  const metricKeys = columns.filter(
    (c) => c !== ll.latKey && c !== ll.lonKey && c !== labelKey && !/^(lat|lon|longitude|latitude)$/i.test(c)
  );
  return rows
    .map((r) => {
      const lat = typeof r[ll.latKey] === "number" ? (r[ll.latKey] as number) : parseFloat(String(r[ll.latKey]));
      const lon = typeof r[ll.lonKey] === "number" ? (r[ll.lonKey] as number) : parseFloat(String(r[ll.lonKey]));
      return {
        lat,
        lon,
        title: fmtVal(r[labelKey]),
        metrics: metricKeys.slice(0, 6).map((k) => ({ key: k, value: fmtVal(r[k]) })),
      };
    })
    .filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon) && p.lat !== 0 && p.lon !== 0);
}

type MapSpec = {
  mode: "points" | "choropleth" | "none";
  level?: string;
  dissolve_by?: "id" | "name";
  geo_key?: string;
  group_key?: string;
  id_key?: string;
  lat_key?: string;
  lon_key?: string;
  label_key?: string;
  metric_key?: string | null;
  coloring?: "sign" | "range" | "favorable_sign";
  legend?: string | null;
  style?: MapStyle;
};

type PointRule = {
  rank_by?: string;
  order?: "asc" | "desc";
  top?: number;
  where?: string;
  op?: "<" | "<=" | ">" | ">=" | "==";
  value?: number;
  color?: string;
  default?: boolean;
};
type MapStyle = {
  point_rules?: PointRule[];
  label?: { column?: string; format?: "short" | "mn" | "bn" | "full" | "raw"; show?: boolean };
};

const COLOR_WORD: Record<string, string> = {
  red: "#E13838", merah: "#E13838",
  yellow: "#F5A623", kuning: "#F5A623",
  green: "#2FA84F", hijau: "#2FA84F",
  teal: "#15A697", biru: "#2A74D4",
  pink: "#0E8579", magenta: "#0A6A5F",
};
function resolveColor(c?: string): string | undefined {
  if (!c) return undefined;
  if (/^#[0-9a-f]{3,8}$/i.test(c)) return c;
  return COLOR_WORD[c.toLowerCase()];
}

// Compact magnitude format: 1.5e9 -> "1.5 Bn", 4.5e7 -> "45 Mn".
function fmtMagnitude(v: number, fmt?: string): string {
  if (!Number.isFinite(v)) return "—";
  const abs = Math.abs(v);
  const f = (n: number) => (Number.isInteger(n) ? n.toLocaleString("id-ID") : n.toLocaleString("id-ID", { maximumFractionDigits: 2 }));
  if (fmt === "raw" || fmt === "full") return f(v);
  if (fmt === "mn") return `${f(v / 1e6)} Mn`;
  if (fmt === "bn") return `${f(v / 1e9)} Bn`;
  // short / auto
  if (abs >= 1e12) return `${f(v / 1e12)} Tn`;
  if (abs >= 1e9) return `${f(v / 1e9)} Bn`;
  if (abs >= 1e6) return `${f(v / 1e6)} Mn`;
  if (abs >= 1e3) return `${f(v / 1e3)} K`;
  return f(v);
}

// Apply AI styling rules to points: per-row colour + persistent value label.
function applyPointStyle(
  pts: MapPoint[],
  rows: Record<string, unknown>[],
  columns: string[],
  style?: MapStyle
): MapPoint[] {
  if (!style) return pts;
  const col = (name?: string) => (name ? columns.find((c) => c.toLowerCase() === name.toLowerCase()) : undefined);

  // Pre-compute rank sets for rank_by rules.
  const rules = style.point_rules || [];
  const rankSets: (Set<number> | null)[] = rules.map((rule) => {
    if (!rule.rank_by || !rule.top) return null;
    const rk = col(rule.rank_by);
    if (!rk) return null;
    const idx = rows.map((r, i) => ({ i, v: Number(r[rk]) })).filter((x) => Number.isFinite(x.v));
    idx.sort((a, b) => (rule.order === "desc" ? b.v - a.v : a.v - b.v));
    return new Set(idx.slice(0, rule.top).map((x) => x.i));
  });

  const labelCol = col(style.label?.column);
  return pts.map((p, i) => {
    const r = rows[i] || {};
    let color: string | undefined;
    for (let ri = 0; ri < rules.length; ri++) {
      const rule = rules[ri];
      let match = false;
      if (rule.default) match = true;
      else if (rankSets[ri]) match = rankSets[ri]!.has(i);
      else if (rule.where && rule.op != null && rule.value != null) {
        const wc = col(rule.where);
        const v = wc ? Number(r[wc]) : NaN;
        if (Number.isFinite(v)) {
          match =
            rule.op === "<" ? v < rule.value :
            rule.op === "<=" ? v <= rule.value :
            rule.op === ">" ? v > rule.value :
            rule.op === ">=" ? v >= rule.value :
            v === rule.value;
        }
      }
      if (match) {
        color = resolveColor(rule.color);
        break;
      }
    }
    const labelText =
      style.label?.show !== false && labelCol && typeof r[labelCol] === "number"
        ? fmtMagnitude(r[labelCol] as number, style.label?.format)
        : undefined;
    return { ...p, color: color ?? p.color, labelText: labelText ?? p.labelText };
  });
}

// Build a Choropleth from the backend-provided spec (authoritative).
// Supports two dissolve modes:
//  • "id"   — values keyed by kec_id / kabkot_id (direct geometry match)
//  • "name" — values keyed by a territory name (region/branch/circle/…); the map
//             dissolves kecamatan polygons via the territory-map.
function choroplethFromSpec(spec: MapSpec, columns: string[], rows: Record<string, unknown>[]): Choropleth | null {
  if (spec.mode !== "choropleth" || !spec.metric_key) return null;
  const metricKey = columns.find((c) => c.toLowerCase() === spec.metric_key!.toLowerCase());
  if (!metricKey) return null;

  const dissolveBy: "id" | "name" = spec.dissolve_by === "name" ? "name" : "id";
  const level = spec.level || (spec.geo_key === "kabkot_id" ? "kabupaten" : "kecamatan");

  // The column whose value is the join key (kec_id/kabkot_id for "id", the
  // territory-name column for "name").
  const keyColName = dissolveBy === "name" ? spec.group_key : spec.geo_key || spec.id_key;
  const keyKey = keyColName ? columns.find((c) => c.toLowerCase() === keyColName.toLowerCase()) : undefined;
  if (!keyKey) return null;
  const labelKey =
    (spec.label_key && columns.find((c) => c.toLowerCase() === spec.label_key!.toLowerCase())) || keyKey;

  const values: Record<string, { value: number; label: string; extra: Record<string, unknown> }> = {};
  for (const r of rows) {
    const key = String(r[keyKey] ?? "").toUpperCase();
    const v = typeof r[metricKey] === "number" ? (r[metricKey] as number) : parseFloat(String(r[metricKey]));
    if (!key || !Number.isFinite(v)) continue;
    values[key] = { value: v, label: String(r[labelKey] ?? key), extra: r };
  }
  if (Object.keys(values).length === 0) return null;
  return {
    dissolveBy,
    level,
    idKey: dissolveBy === "id" ? (spec.geo_key === "kabkot_id" ? "kabkot_id" : "kec_id") : undefined,
    metricKey,
    coloring: spec.coloring || "range",
    legend: spec.legend || metricKey,
    values,
  };
}

function pointsFromSpec(spec: MapSpec, columns: string[], rows: Record<string, unknown>[]): MapPoint[] {
  if (spec.mode !== "points" || !spec.lat_key || !spec.lon_key) return [];
  const latKey = columns.find((c) => c.toLowerCase() === spec.lat_key!.toLowerCase());
  const lonKey = columns.find((c) => c.toLowerCase() === spec.lon_key!.toLowerCase());
  if (!latKey || !lonKey) return [];
  const labelKey =
    (spec.label_key && columns.find((c) => c.toLowerCase() === spec.label_key!.toLowerCase())) || columns[0];
  const metricKeys = columns.filter(
    (c) => c !== latKey && c !== lonKey && c !== labelKey && !/^(lat|lon|longitude|latitude)$/i.test(c)
  );
  // keep the row index so styling rules can be applied positionally
  const built = rows.map((r) => {
    const lat = typeof r[latKey] === "number" ? (r[latKey] as number) : parseFloat(String(r[latKey]));
    const lon = typeof r[lonKey] === "number" ? (r[lonKey] as number) : parseFloat(String(r[lonKey]));
    return {
      lat,
      lon,
      title: fmtVal(r[labelKey]),
      metrics: metricKeys.slice(0, 6).map((k) => ({ key: k, value: fmtVal(r[k]) })),
      _row: r,
    };
  });
  const valid = built.filter((p) => Number.isFinite(p.lat) && Number.isFinite(p.lon) && p.lat !== 0 && p.lon !== 0);
  const validRows = valid.map((p) => p._row);
  const pts: MapPoint[] = valid.map(({ lat, lon, title, metrics }) => ({ lat, lon, title, metrics }));
  return applyPointStyle(pts, validRows, columns, spec.style);
}

const EXAMPLES = [
  "Tampilkan 20 site dengan revenue turun bulan ini",
  "10 site terdekat dengan revenue di bawah 40 Mn",
  "Outlet IM3 terdekat dari lokasi saya",
  "Tampilkan outlet di kecamatan Wonocolo",
];

export default function MapQueryPage() {
  const router = useRouter();
  const [authed, setAuthed] = useState(false);
  const [userLoc, setUserLoc] = useState<{ lat: number; lon: number; accuracy?: number; timestamp?: number } | null>(null);
  const [locating, setLocating] = useState(true);
  const [points, setPoints] = useState<MapPoint[]>([]);
  const [choropleth, setChoropleth] = useState<Choropleth | null>(null);
  const [chatOpen, setChatOpen] = useState(true);
  const [turns, setTurns] = useState<ChatTurn[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [resultCount, setResultCount] = useState<number | null>(null);
  const [fixMode, setFixMode] = useState(false);
  const [fixLoading, setFixLoading] = useState(false);
  const [fixError, setFixError] = useState("");
  const [fixMonth, setFixMonth] = useState<string | null>(null);
  const [fixAuto, setFixAuto] = useState(false);
  const [labelOn, setLabelOn] = useState(false);
  const [labelMetric, setLabelMetric] = useState<"revenue" | "site_id" | "site_name" | "vlr">("revenue");
  const fixSitesRef = useRef<FixSite[]>([]);
  const sessionIdRef = useRef<string>("");
  const scrollRef = useRef<HTMLDivElement>(null);
  const abortRef = useRef<AbortController | null>(null);
  const lastResultRef = useRef<{ columns: string[]; rows: Record<string, unknown>[] } | null>(null);
  const restoredRef = useRef(false);

  function fmtMn(v: number | null | undefined): string {
    if (v === null || v === undefined) return "—";
    if (Math.abs(v) >= 1e6) return `${(v / 1e6).toLocaleString("id-ID", { maximumFractionDigits: 1 })} Mn`;
    return v.toLocaleString("id-ID", { maximumFractionDigits: 0 });
  }

  function fixLabelText(s: FixSite, metric: typeof labelMetric): string | undefined {
    if (metric === "site_id") return String(s.site_id ?? "");
    if (metric === "site_name") return String(s.site_name ?? s.site_id ?? "");
    if (metric === "vlr") return fmtMn(s.perf?.vlr_daily);
    return fmtMn(s.perf?.rev_prepaid); // revenue (default)
  }

  function buildFixPoints(sites: FixSite[], on: boolean, metric: typeof labelMetric, monthId: string | null): MapPoint[] {
    return sites.filter((s) => s.latitude != null && s.longitude != null).map((s) => {
      const pf = s.perf || {};
      const attrs = [
        { key: "Site ID", value: String(s.site_id ?? "—") },
        { key: "Jarak", value: `${s.distance_km ?? "—"} km` },
        { key: "Type", value: String(s.site_type ?? "—") },
        { key: "Category", value: String(s.category ?? "—") },
        { key: "Area", value: String(s.branch ?? "N/A") },
        { key: "District", value: String(s.micro_cluster ?? "N/A") },
        { key: "Cakupan detail channel", value: "Kecamatan" },
        { key: "Kecamatan", value: `${s.kecamatan ?? "—"}, ${s.kabupaten ?? "—"}` },
      ];
      const metrics = [
        { key: "Rev Prepaid", value: fmtMn(pf.rev_prepaid) },
        { key: "RGU 90D", value: fmtMn(pf.rgu_90d) },
        { key: "VLR Daily", value: fmtMn(pf.vlr_daily) },
      ];
      return {
        lat: s.latitude, lon: s.longitude,
        title: s.site_name || s.site_id, metrics, fix: true,
        labelText: on ? fixLabelText(s, metric) : undefined,
        detail: {
          perf: s.perf || {}, mom: s.mom || {}, yoy: s.yoy || {}, metrics: s.metrics || {},
          channels: s.channels || [], channel_groups: s.channel_groups || [], history: s.history || [], attrs, month_id: monthId,
        },
      } as MapPoint;
    });
  }

  async function loadFixSites() {
    if (fixLoading) return;
    setFixLoading(true);
    setFixError("");
    const loc = await new Promise<{ lat: number; lon: number; accuracy: number; timestamp: number } | null>((resolve) => {
        if (!navigator.geolocation) return resolve(null);
        navigator.geolocation.getCurrentPosition(
          (p) => resolve({ lat: p.coords.latitude, lon: p.coords.longitude, accuracy: p.coords.accuracy, timestamp: p.timestamp }),
          () => resolve(null), { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 });
      });
    if (loc) setUserLoc(loc);
    if (!loc) { setFixError("Lokasi GPS belum tersedia. Periksa izin lokasi dan coba lagi."); setFixLoading(false); return; }
    try {
      const r = await fetch("/api/geo/nearest-sites", { method: "POST", headers: { "Content-Type": "application/json", ...(getAccessToken() ? { Authorization: `Bearer ${getAccessToken()}` } : {}) }, body: JSON.stringify(loc) });
      const d = await r.json();
      if (d.ok) {
        const sites = (d.sites as FixSite[]) || [];
        fixSitesRef.current = sites;
        setFixMonth(d.month_id ?? null);
        setPoints(buildFixPoints(sites, labelOn, labelMetric, d.month_id ?? null));
      } else setFixError(d.error || "Data site belum tersedia.");
    } catch (error) { setFixError(String(error)); }
    setFixLoading(false);
  }

  // Rebuild fix-mode labels when the label toggle/metric changes (no refetch).
  useEffect(() => {
    if (!fixMode || fixSitesRef.current.length === 0) return;
    setPoints(buildFixPoints(fixSitesRef.current, labelOn, labelMetric, fixMonth));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [labelOn, labelMetric, fixMode]);

  function setMode(fix: boolean) {
    setFixMode(fix);
    setPoints([]); setChoropleth(null); setResultCount(null);
    if (fix) { setChatOpen(false); loadFixSites(); } else { setFixAuto(false); }
  }

  // auto-refresh fix sites
  useEffect(() => {
    if (!fixMode || !fixAuto) return;
    const id = setInterval(() => loadFixSites(), 60000);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fixMode, fixAuto]);

  function refreshMap() {
    setTurns([]);
    setPoints([]);
    setChoropleth(null);
    setResultCount(null);
    setInput("");
    lastResultRef.current = null;
    try {
      const uname = (getUser()?.username as string) || "anon";
      window.sessionStorage.removeItem(`map_state::${uname}`);
    } catch { /* ignore */ }
    if (userLoc) {
      // recenter on user after clearing
      // (map recenters via the userLoc effect path)
    }
  }

  useEffect(() => {
    if (!isLoggedIn()) {
      router.replace("/login");
      return;
    }
    // Stable per-user map session id so map queries are persisted to history
    // (used later for AI-agent relearning), instead of a throwaway id each load.
    if (!sessionIdRef.current) {
      const uname = (getUser()?.username as string) || "anon";
      const key = `map_session::${uname}`;
      let sid = typeof window !== "undefined" ? window.localStorage.getItem(key) : null;
      if (!sid) {
        sid = "map_" + uname + "_" + Date.now().toString(36);
        if (typeof window !== "undefined") window.localStorage.setItem(key, sid);
      }
      sessionIdRef.current = sid;
    }
    const t = setTimeout(() => setAuthed(true), 0);
    if (typeof navigator !== "undefined" && navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          setUserLoc({ lat: pos.coords.latitude, lon: pos.coords.longitude, accuracy: pos.coords.accuracy, timestamp: pos.timestamp });
          setLocating(false);
        },
        () => setLocating(false),
        { enableHighAccuracy: true, timeout: 15000 }
      );
    } else {
      setTimeout(() => setLocating(false), 0);
    }
    // Restore the last map session (so leaving & returning keeps the visual).
    let rt: ReturnType<typeof setTimeout> | undefined;
    try {
      const uname = (getUser()?.username as string) || "anon";
      const raw = typeof window !== "undefined" ? window.sessionStorage.getItem(`map_state::${uname}`) : null;
      if (raw) {
        const s = JSON.parse(raw);
        rt = setTimeout(() => {
          if (Array.isArray(s.turns)) setTurns(s.turns);
          if (Array.isArray(s.points)) setPoints(s.points);
          if (s.choropleth) setChoropleth(s.choropleth);
          if (typeof s.resultCount === "number") setResultCount(s.resultCount);
          restoredRef.current = true;
        }, 0);
      }
    } catch { /* ignore */ }
    return () => {
      clearTimeout(t);
      if (rt) clearTimeout(rt);
    };
  }, [router]);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [turns]);

  // Persist the map session so it survives navigation (cleared only on Refresh).
  useEffect(() => {
    if (!authed) return;
    try {
      const uname = (getUser()?.username as string) || "anon";
      window.sessionStorage.setItem(
        `map_state::${uname}`,
        JSON.stringify({ turns, points, choropleth, resultCount })
      );
    } catch { /* ignore quota */ }
  }, [authed, turns, points, choropleth, resultCount]);

  // Apply the backend's authoritative map_spec against the stored result.
  function applySpec(spec: MapSpec) {
    const res = lastResultRef.current;
    if (!res) return;
    const { columns: cols, rows } = res;
    if (spec.mode === "choropleth") {
      const choro = choroplethFromSpec(spec, cols, rows);
      if (choro) {
        setPoints([]);
        setChoropleth(choro);
        setResultCount(Object.keys(choro.values).length);
        return;
      }
    }
    if (spec.mode === "points") {
      const pts = pointsFromSpec(spec, cols, rows);
      if (pts.length > 0) {
        setChoropleth(null);
        setPoints(pts);
        setResultCount(pts.length);
        return;
      }
    }
    // spec said none / nothing renderable → fall back to local heuristic
    applyResult(cols, rows);
  }

  // Local heuristic fallback (used when no/none map_spec arrives).
  function applyResult(cols: string[], rows: Record<string, unknown>[]) {
    if (rows.length === 0) return;
    const choro = detectChoropleth(cols, rows);
    if (choro) {
      setPoints([]);
      setChoropleth(choro);
      setResultCount(Object.keys(choro.values).length);
      return;
    }
    const pts = rowsToPoints(cols, rows);
    if (pts.length > 0) {
      setChoropleth(null);
      setPoints((prev) => {
        const merged = [...prev, ...pts];
        setResultCount(merged.length);
        return merged;
      });
    } else {
      setResultCount((c) => (c == null ? 0 : c));
    }
  }

  async function send(text?: string) {
    const msg = (text ?? input).trim();
    if (!msg || busy) return;
    setInput("");
    setResultCount(null);
    setPoints([]);
    setChoropleth(null);

    // Only inject the user's GPS coordinate when the question is proximity-based
    // ("terdekat", "dari lokasi saya", "sekitar saya", "dekat sini"). For every
    // other question we send the raw message untouched, exactly like the main
    // chat — so the same AI-agent pipeline (analyst → router → SQL) behaves
    // identically and is not nudged into treating everything as a map query.
    const proximityRe = /terdekat|nearest|lokasi saya|sekitar saya|sekitar sini|dekat sini|dekat saya|dari sini|di sekitar/i;
    const needsLoc = userLoc && proximityRe.test(msg) && !/-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+/.test(msg);
    const outgoing = needsLoc
      ? `${msg} (gunakan koordinat lokasi saya: ${userLoc!.lat.toFixed(6)}, ${userLoc!.lon.toFixed(6)})`
      : msg;

    // Build real conversation history (same shape as the main chat) so the
    // agent keeps context across follow-up map questions.
    const history = turns.slice(-12).map((t) => ({
      role: t.role,
      content: t.role === "user" ? t.content : (t.content || t.status || "").slice(0, 1500),
    }));

    setTurns((t) => [...t, { role: "user", content: msg }, { role: "assistant", content: "", status: "Memproses…" }]);
    setBusy(true);

    const update = (patch: Partial<ChatTurn>) =>
      setTurns((prev) => {
        const next = [...prev];
        next[next.length - 1] = { ...next[next.length - 1], ...patch };
        return next;
      });
    const append = (chunk: string) =>
      setTurns((prev) => {
        const next = [...prev];
        const i = next.length - 1;
        next[i] = { ...next[i], content: (next[i].content || "") + chunk, status: undefined };
        return next;
      });

    const ctrl = new AbortController();
    abortRef.current = ctrl;
    let gotDone = false, gotContent = false;
    try {
      const res = await fetch(`/api/chat/stream`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(getAccessToken() ? { Authorization: `Bearer ${getAccessToken()}` } : {}),
        },
        body: JSON.stringify({
          message: outgoing,
          session_id: sessionIdRef.current,
          language: "id",
          history,
          map_context: true,
        }),
        signal: ctrl.signal,
      });
      if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        let sep;
        while ((sep = buf.indexOf("\n\n")) !== -1) {
          const raw = buf.slice(0, sep);
          buf = buf.slice(sep + 2);
          let event = "message", dataStr = "";
          for (const ln of raw.split("\n")) {
            if (ln.startsWith("event:")) event = ln.slice(6).trim();
            else if (ln.startsWith("data:")) dataStr += ln.slice(5).trim();
          }
          if (!dataStr) continue;
          let data: Record<string, unknown> = {};
          try { data = JSON.parse(dataStr); } catch { continue; }

          if (event === "step_start") {
            update({ status: `${(data.label as string) || data.step} — ${(data.desc as string) || ""}` });
          } else if (event === "status") {
            update({ status: (data.label as string) || (data.stage as string) });
          } else if (event === "route") {
            const dom = data.domain as string;
            update({ status: dom && dom !== "none" ? `Domain: ${dom} — menyiapkan query…` : "Menyusun jawaban…" });
          } else if (event === "sql") {
            update({ status: "Mengambil data dari database…" });
          } else if (event === "retry") {
            update({ status: `Memperbaiki query (percobaan ${data.attempt ?? ""})…` });
          } else if (event === "result" || event === "profile_domain_result") {
            const cols = (data.columns as string[]) || [];
            const rows = (data.rows as Record<string, unknown>[]) || [];
            lastResultRef.current = { columns: cols, rows };
            // For multi-domain profile results (no map_spec per chunk), use the
            // local heuristic so points accumulate. For a single result the
            // authoritative map_spec event (next) will override.
            if (event === "profile_domain_result") applyResult(cols, rows);
          } else if (event === "map_spec") {
            applySpec(data as MapSpec);
          } else if (event === "token") {
            gotContent = true;
            append(String(data.t || ""));
          } else if (event === "error") {
            update({ error: String(data.error || "error"), status: undefined });
          } else if (event === "done") {
            gotDone = true;
            update({ status: undefined });
          }
        }
      }
    } catch (e: unknown) {
      const err = e instanceof Error ? e.message : String(e);
      if (!err.includes("aborted") && !gotDone && !gotContent) {
        update({ error: err, status: undefined });
      } else {
        update({ status: undefined });
      }
    } finally {
      setBusy(false);
      abortRef.current = null;
    }
  }

  function recenter() {
    if (typeof navigator === "undefined" || !navigator.geolocation) return;
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setUserLoc({ lat: pos.coords.latitude, lon: pos.coords.longitude, accuracy: pos.coords.accuracy, timestamp: pos.timestamp });
        setLocating(false);
      },
      () => setLocating(false),
      { enableHighAccuracy: true, timeout: 15000 }
    );
  }

  if (!authed) return null;

  return (
    <div className="mq-root">
      <MapCanvas points={points} userLoc={userLoc} choropleth={choropleth} />

      {/* Top bar: AI/Fix toggle blended into the header */}
      <div className="mq-topbar">
        <button className="mq-back" onClick={() => router.push("/map")} title="Kembali ke Peta & Site">←</button>
        <div className="mq-mode-seg">
          {([[false, "🤖", "AI"], [true, "📡", "Fix"]] as const).map(([k, ic, lbl]) => (
            <button key={String(k)} onClick={() => setMode(k)} title={k ? "Fix Mode" : "AI Mode"}
              className={`mq-mode-btn${fixMode === k ? " active" : ""}`}><span style={{ fontSize: 12 }}>{ic}</span>{lbl}</button>
          ))}
        </div>
        <div className="mq-loc">
          {locating ? "📍 …" : userLoc ? `GPS${userLoc.accuracy === undefined ? "" : ` ±${Math.round(userLoc.accuracy)} m`}` : "GPS N/A"}
        </div>
        <button className="mq-recenter" onClick={recenter} title="Perbarui lokasi saya">⟳</button>
        <button className="mq-recenter" onClick={refreshMap} title="Refresh map (hapus hasil)">🗑</button>
      </div>

      {/* Fix panel, compact: status + label toggle/picker + auto + refresh */}
      {fixMode && (
        <div style={{ position: "absolute", top: 64, left: 12, right: 12, zIndex: 1000, display: "flex", alignItems: "center", flexWrap: "wrap", gap: 6, background: "rgba(255,255,255,.96)", border: "1px solid #E1E9E7", borderRadius: 10, padding: "6px 10px", boxShadow: "0 2px 8px rgba(0,0,0,.1)" }}>
          <span style={{ flex: 1, minWidth: 120, fontSize: 12, fontWeight: 600, color: "#0F1F1D" }}>{fixLoading ? "Memuat…" : fixError || `${points.length} site${fixMonth ? ` · ${fixMonth}` : ""}`}</span>
          <button onClick={() => setLabelOn((v) => !v)} title="Tampilkan label di marker"
            style={{ border: `1px solid ${labelOn ? "#15A697" : "#E1E9E7"}`, background: labelOn ? "#15A697" : "#fff", color: labelOn ? "#fff" : "#5A6B68", borderRadius: 999, padding: "4px 10px", fontSize: 11, fontWeight: 700, cursor: "pointer" }}>🏷 Label</button>
          {labelOn && (
            <select value={labelMetric} onChange={(e) => setLabelMetric(e.target.value as typeof labelMetric)}
              style={{ border: "1px solid #E1E9E7", borderRadius: 8, padding: "4px 6px", fontSize: 11.5, color: "#0F1F1D", background: "#fff", fontFamily: "Prompt,sans-serif" }}>
              <option value="revenue">Revenue</option>
              <option value="site_id">Site ID</option>
              <option value="site_name">Site Name</option>
              <option value="vlr">VLR</option>
            </select>
          )}
          <button onClick={() => setFixAuto((v) => !v)} title="Auto refresh 60s" style={{ border: `1px solid ${fixAuto ? "#33BCAD" : "#E1E9E7"}`, background: fixAuto ? "#33BCAD" : "#fff", color: fixAuto ? "#fff" : "#5A6B68", borderRadius: 999, padding: "4px 9px", fontSize: 11, fontWeight: 600, cursor: "pointer" }}>⟲</button>
          <button onClick={loadFixSites} disabled={fixLoading} title="Refresh" style={{ border: "1px solid #E1E9E7", background: "#fff", borderRadius: 8, padding: "4px 9px", fontSize: 12, cursor: "pointer" }}>↻</button>
        </div>
      )}

      {resultCount !== null && !fixMode && (
        <div className="mq-badge">
          {resultCount > 0 ? `${resultCount} lokasi divisualkan` : "Tidak ada lokasi untuk divisualkan"}
        </div>
      )}

      {/* Floating chat toggle */}
      {!chatOpen && !fixMode && (
        <button className="mq-fab" onClick={() => setChatOpen(true)} title="Tanya AI">
          <span>💬</span>
        </button>
      )}

      {/* Floating chat panel */}
      {chatOpen && !fixMode && (
        <div className="mq-chat">
          <div className="mq-chat-head">
            <span className="mq-chat-title">Tanya peta</span>
            <button className="mq-chat-reset" onClick={refreshMap} title="Reset chat (mulai dari nol)">↺ Reset</button>
            <button className="mq-chat-hide" onClick={() => setChatOpen(false)} title="Sembunyikan">✕</button>
          </div>
          <div className="mq-chat-body" ref={scrollRef}>
            {turns.length === 0 ? (
              <div className="mq-examples">
                <div className="mq-examples-hint">Coba tanyakan:</div>
                {EXAMPLES.map((e) => (
                  <button key={e} className="mq-example" onClick={() => send(e)}>{e}</button>
                ))}
              </div>
            ) : (
              turns.map((t, i) => (
                <div key={i} className={`mq-turn ${t.role}`}>
                  {t.role === "user" ? (
                    <div className="mq-user-msg">{t.content}</div>
                  ) : (
                    <div className="mq-ai-msg">
                      {t.status && <div className="mq-status">{t.status}</div>}
                      {t.error && <div className="mq-error">{t.error}</div>}
                      {t.content && <Markdown text={t.content} />}
                    </div>
                  )}
                </div>
              ))
            )}
          </div>
          <div className="mq-composer">
            <textarea
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  send();
                }
              }}
              placeholder="Tampilkan 20 site revenue turun bulan ini…"
              rows={1}
            />
            <button className="mq-send" disabled={busy || !input.trim()} onClick={() => send()}>
              {busy ? "…" : "➤"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
