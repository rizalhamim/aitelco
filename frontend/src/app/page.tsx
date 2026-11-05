"use client";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import AppShell, { TopBar } from "./components/shell/AppShell";
import { type ChartSpec as SmartChartSpec } from "./components/charts/SmartChart";
import ChartPanel from "./components/ChartPanel";
import SiteMap from "./components/SiteMap";
import { Icon } from "./components/v2/Icon";
import { AnswerViz, KpiRow, detectLatLon, type Kpi } from "./components/v2/Answer";
import { downloadXlsx } from "@/lib/xlsx";
import "./chat.css";
import "./tanya.css";
import Markdown from "./components/Markdown";
import AgentFlow, { type FlowEvent } from "./components/AgentFlow";
import { isLoggedIn, getUser, getAccessToken, canViewSQL, canExport, authFetch } from "@/lib/auth";

function gmaps(lat: unknown, lon: unknown): string | null {
  const la = typeof lat === "number" ? lat : parseFloat(String(lat));
  const lo = typeof lon === "number" ? lon : parseFloat(String(lon));
  if (!Number.isFinite(la) || !Number.isFinite(lo)) return null;
  return `https://www.google.com/maps/search/?api=1&query=${la},${lo}`;
}

function fmtNum(v: unknown): string {
  if (v === null || v === undefined || v === "") return "–";
  if (typeof v === "number") {
    return Number.isInteger(v) ? v.toLocaleString("id-ID") : v.toLocaleString("id-ID", { maximumFractionDigits: 2 });
  }
  return String(v);
}

// Nearest sites/outlets table with a Google Maps link column
function NearestTable({ columns, rows }: { columns: string[]; rows: Record<string, unknown>[] }) {
  const latK = columns.find((c) => /^lat(itude)?$/i.test(c)) || "latitude";
  const lonK = columns.find((c) => /^lon(g|gitude)?$/i.test(c)) || "longitude";
  // show all columns except raw lat/lon (kept for the map link)
  const showCols = columns.filter((c) => c !== latK && c !== lonK);
  return (
    <div className="data-table-wrap tnum">
      <div className="data-table-scroll">
        <table className="data-table">
          <thead>
            <tr>
              <th className="num">#</th>
              {showCols.map((c) => <th key={c}>{c}</th>)}
              <th>Maps</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r, i) => {
              const url = gmaps(r[latK], r[lonK]);
              return (
                <tr key={i}>
                  <td className="num">{i + 1}</td>
                  {showCols.map((c) => <td key={c}>{fmtNum(r[c])}</td>)}
                  <td>
                    {url ? (
                      <a href={url} target="_blank" rel="noopener noreferrer" className="gmaps-link">🧭 Maps</a>
                    ) : "–"}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// Kecamatan KPI profile card grid
function KecProfileCard({ profile, isEN }: { profile: Record<string, unknown>; isEN: boolean }) {
  const items: { label: string; key: string }[] = isEN
    ? [
        { label: "Total Site", key: "total_site" },
        { label: "Addressable Site", key: "addressable_site" },
        { label: "Total Outlet", key: "total_outlet" },
        { label: "Revenue Prepaid", key: "revenue_prepaid" },
        { label: "RGU 90d", key: "rgu_90d" },
        { label: "Gross Add", key: "gross_add" },
        { label: "Net Add 90d", key: "net_add_90d" },
        { label: "Pack Subs", key: "pack_subs" },
        { label: "HVC Subs", key: "subs_hvc" },
      ]
    : [
        { label: "Jumlah Site", key: "total_site" },
        { label: "Addressable Site", key: "addressable_site" },
        { label: "Jumlah Outlet", key: "total_outlet" },
        { label: "Revenue Prepaid", key: "revenue_prepaid" },
        { label: "RGU 90 Hari", key: "rgu_90d" },
        { label: "Gross Add", key: "gross_add" },
        { label: "Net Add 90 Hari", key: "net_add_90d" },
        { label: "Pack Subscriber", key: "pack_subs" },
        { label: "Subscriber HVC", key: "subs_hvc" },
      ];
  function fmt(key: string, v: unknown): string {
    if (v === null || v === undefined) return "–";
    const n = typeof v === "number" ? v : parseFloat(String(v));
    if (!Number.isFinite(n)) return String(v);
    if (key === "revenue_prepaid") {
      if (Math.abs(n) >= 1e9) return "Rp " + (n / 1e9).toFixed(2) + " M";
      if (Math.abs(n) >= 1e6) return "Rp " + (n / 1e6).toFixed(1) + " Jt";
      return "Rp " + n.toLocaleString("id-ID");
    }
    return Math.round(n).toLocaleString("id-ID");
  }
  return (
    <div className="kec-profile">
      <div className="kec-profile-grid">
        {items.map((it) => (
          <div key={it.key} className="kec-stat">
            <div className="kec-stat-num">{fmt(it.key, profile[it.key])}</div>
            <div className="kec-stat-lbl">{it.label}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

type Result = {
  columns: string[];
  rows: Record<string, unknown>[];
  row_count: number;
  sql?: string;
  bytes_processed?: number;
  chart?: SmartChartSpec;
  kpis?: Kpi[];
  source?: string;
};

// Server chart spec (sse "chart_spec", read by components/ChartPanel). The redesign
// SmartChart spec arrives as result.chart and is imported above as SmartChartSpec.
// Decided by the backend (see backend/app/chart_spec.py) so web and mobile draw the
// same thing. A column's TYPE says nothing about its meaning, and the client-side
// guess used to plot whichever numeric column came first.
export type ChartSeries = {
  column: string;
  role: string;
  unit: string;
  label: string;
  axis_side: "left" | "right";
  can_be_negative: boolean;
};
export type ChartAxis = {
  unit: string;
  side: "left" | "right";
  columns: string[];
  zero_line: boolean;
};
export type ChartSpec = {
  mode: "bar" | "line" | "pie" | "matrix" | "funnel" | "none";
  category?: string;
  series?: ChartSeries[];
  axes?: ChartAxis[];
  dual_axis?: boolean;
  title?: string;
  caption?: string;
  truncated?: boolean;
  /** Present when the result had more categories than fit as bars: the ranked subset
   *  the chart should plot, already sorted. The caption says it is a subset. */
  rows?: Record<string, unknown>[];
  ranked_subset?: boolean;
};

type Stage = "router" | "analyst" | "sql" | "validasi" | "ringkasan";

type Msg = {
  role: "user" | "assistant";
  content: string;
  /** "HH.MM" when the message was sent. */
  time?: string;
  startedAt?: number;
  elapsedMs?: number;
  stages?: Stage[];
  domain?: string;
  domainLabel?: string;
  sql?: string;
  sqlExplanation?: string;
  result?: Result;
  chartSpec?: ChartSpec;
  status?: string;
  error?: string;
  exportReady?: { format: string; url: string };
  profilePlan?: {
    territory_type: string;
    territory_name: string;
    sub_queries: { domain: string; section_title: string; question: string }[];
  };
  profileResults?: {
    domain: string;
    section_title: string;
    status: string;
    row_count: number;
    error?: string | null;
    columns: string[];
    rows: Record<string, unknown>[];
    sql?: string | null;
    explanation?: string;
    chart?: SmartChartSpec;
  }[];
  locationResult?: {
    lat: number;
    lon: number;
    kecamatan?: { kec_id?: string; kecamatan?: string; kabkota?: string; provinsi?: string } | null;
    kecProfile?: Record<string, unknown> | null;
    sites?: { columns: string[]; rows: Record<string, unknown>[] };
    outlets?: { columns: string[]; rows: Record<string, unknown>[] };
  };
};


const DOMAIN_CHIPS = [
  { key: "revenue", label: "Revenue", icon: "duo_revenue", q: "Bagaimana performa revenue Jawa bulan ini dibanding bulan lalu per region?" },
  { key: "site", label: "Site", icon: "duo_site", q: "Site dengan availability di bawah target minggu ini per kabupaten" },
  { key: "network", label: "Network", icon: "duo_network", q: "Berapa total payload data per region di bulan terakhir?" },
  { key: "fwa", label: "FWA", icon: "duo_fwa", q: "Gross add FWA per kota bulan ini dibanding target" },
  { key: "ftth", label: "FTTH", icon: "duo_ftth", q: "Performa FTTH per kabupaten bulan terakhir" },
  { key: "competitive", label: "Market share", icon: "duo_marketshare", q: "Bandingkan market share IM3 vs Telkomsel per kabkota di bulan terakhir" },
  { key: "sales", label: "Sales", icon: "duo_sales", q: "Top 10 outlet dengan penjualan tertinggi bulan ini" },
];

const STARTERS = [
  { icon: "wallet", bg: "#FCEDD3", fg: "#B7791F", title: "Revenue West Java", text: "Bagaimana performa revenue West Java bulan ini dibanding bulan lalu? Kabupaten mana yang paling turun?" },
  { icon: "tower", bg: "#FBE2E8", fg: "#C23A5B", title: "Site availability", text: "Site availability East Java minggu ini, mana yang di bawah target?" },
  { icon: "pulse", bg: "#F4FCE3", fg: "#5E8A12", title: "Site productivity", text: "Site dengan produktivitas terendah di Central Java bulan ini" },
  { icon: "map", bg: "#E3F7FA", fg: "#0E6F7C", title: "Profil wilayah", text: "Tampilkan profile lengkap kota Surabaya" },
];

const STAGES: { key: Stage; label: string }[] = [
  { key: "router", label: "Router" },
  { key: "analyst", label: "Analyst" },
  { key: "sql", label: "SQL · BigQuery" },
  { key: "validasi", label: "Validasi" },
  { key: "ringkasan", label: "Ringkasan" },
];

const MONTHS_ID = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

function hhmm(d = new Date()): string {
  return `${String(d.getHours()).padStart(2, "0")}.${String(d.getMinutes()).padStart(2, "0")}`;
}

function followUps(m: Msg): string[] {
  const out: string[] = [];
  const spec = m.result?.chart;
  const rows = m.result?.rows ?? [];
  const label = spec?.map_key ?? spec?.x;
  if (label && rows.length && spec?.type !== "line" && spec?.type !== "area") {
    const top = String(rows[0][label] ?? "");
    if (top) out.push(`Kenapa ${top} seperti ini?`);
  }
  out.push("Bandingkan dengan bulan lalu");
  out.push("Proyeksi bulan depan");
  if (spec?.map_key) out.push("Tampilkan di peta");
  return out;
}


export default function Home() {
  const router = useRouter();
  const [messages, setMessages] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [pipelineFlow, setPipelineFlow] = useState<FlowEvent[]>([]);
  const [tokenUsage, setTokenUsage] = useState<{prompt: number; completion: number; total: number}>({prompt: 0, completion: 0, total: 0});
  const [sqlVisible, setSqlVisible] = useState<Record<number, boolean>>({});
  const [authChecked, setAuthChecked] = useState(false);
  const [activeSession, setActiveSession] = useState<string>("");
  const [attachOpen, setAttachOpen] = useState(false);
  const [locating, setLocating] = useState(false);
  const [lang, setLang] = useState<"id" | "en">("id");
  const [historyVersion, setHistoryVersion] = useState(0);
  const [copied, setCopied] = useState<number | null>(null);
  const [exportOpen, setExportOpen] = useState<number | null>(null);
  const [pinned, setPinned] = useState<Record<number, boolean>>({});
  const [listening, setListening] = useState(false);
  const taRef = useRef<HTMLTextAreaElement>(null);
  const abortRef = useRef<AbortController | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string>("");
  const attachRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Top bar title: the session's short title from history (falls back to the question).
  const [sessionTitle, setSessionTitle] = useState("");
  useEffect(() => {
    if (!activeSession) return;
    let alive = true;
    authFetch("/api/history/sessions").then((r) => (r.ok ? r.json() : []))
      .then((d) => {
        const list: { session_id: string; title?: string }[] = Array.isArray(d) ? d : d?.sessions || [];
        if (alive) setSessionTitle(list.find((x) => x.session_id === activeSession)?.title ?? "");
      }).catch(() => {});
    return () => { alive = false; };
  }, [activeSession, historyVersion]);

  // Answer language is chosen on the Profil page (Tampilan) and stored per browser.
  useEffect(() => {
    try {
      const l = localStorage.getItem("telco_ai_lang");
      if (l === "en" || l === "id") setLang(l);
    } catch { /* storage blocked */ }
  }, []);

  // Auth check: redirect to login if not authenticated
  useEffect(() => {
    if (!isLoggedIn()) {
      router.push("/login");
    } else {
      setAuthChecked(true);
    }
  }, [router]);

  useEffect(() => {
    if (!authChecked) return;
    // Per-user session id (scoped so different users on the same browser don't share)
    const uname = getUser()?.username || "anon";
    const key = `telco_ai_session_id::${uname}`;
    let restoredSid: string | null = null;
    try {
      let sid = localStorage.getItem(key);
      if (!sid) {
        sid =
          (typeof crypto !== "undefined" && "randomUUID" in crypto)
            ? crypto.randomUUID()
            : `s_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
        localStorage.setItem(key, sid);
      } else {
        restoredSid = sid;
      }
      sessionIdRef.current = sid;
      setActiveSession(sid);
    } catch {
      sessionIdRef.current = `s_${Date.now()}`;
    }
    // Links from other pages: /?new=1, /?s=<session>, /?q=<question>.
    const params = new URLSearchParams(window.location.search);
    const wantSession = params.get("s");
    const ask = params.get("q");
    if (params.toString()) window.history.replaceState(null, "", "/");
    if (params.get("new") || ask) {
      newChat();
      if (ask) setTimeout(() => send(ask), 0);
    } else if (wantSession) {
      loadSession(wantSession);
    } else if (restoredSid) {
      // Restore the last conversation from the DB so a page reload doesn't lose it.
      loadSession(restoredSid, { silent: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authChecked]);

  function loadHistoryList() {
    setHistoryVersion((v) => v + 1);
  }

  async function loadSession(sid: string, opts?: { silent?: boolean }) {
    if (busy) return;
    const silent = opts?.silent === true;
    try {
      const res = await authFetch(`/api/history/sessions/${sid}`, {
        headers: { ...(getAccessToken() ? { Authorization: `Bearer ${getAccessToken()}` } : {}) },
      });
      if (!res.ok) {
        // session not in DB yet (e.g. fresh unused id): keep screen blank
        return;
      }
      const data = await res.json();
      const loaded: Msg[] = (data.messages || []).map((m: { role: string; content: string; domain?: string; sql_query?: string }) => ({
        role: m.role === "user" ? "user" : "assistant",
        content: m.content || "",
        domain: m.domain || undefined,
        sql: m.sql_query || undefined,
      }));
      // On silent restore, only replace if there is actually content to show.
      if (silent && loaded.length === 0) return;
      setMessages(loaded);
      setPipelineFlow([]);
      sessionIdRef.current = sid;
      setActiveSession(sid);
      const uname = getUser()?.username || "anon";
      localStorage.setItem(`telco_ai_session_id::${uname}`, sid);
    } catch {
      /* ignore */
    }
  }

  function newChat() {
    if (busy) return;
    const sid =
      (typeof crypto !== "undefined" && "randomUUID" in crypto)
        ? crypto.randomUUID()
        : `s_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    sessionIdRef.current = sid;
    setActiveSession(sid);
    const uname = getUser()?.username || "anon";
    try { localStorage.setItem(`telco_ai_session_id::${uname}`, sid); } catch { /* ignore */ }
    setMessages([]);
    setPipelineFlow([]);
    setInput("");
    taRef.current?.focus();
  }

  // When a new question is asked (or a session loads), bring the latest
  // question to the top of the view so its answer streams in below it.
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const id = requestAnimationFrame(() => {
      // the window scrolls (sidebar and top bar are sticky); keep the question below the 76 px bar
      const bubbles = el.querySelectorAll<HTMLElement>(".ubub");
      const last = bubbles[bubbles.length - 1];
      const top = last ? last.getBoundingClientRect().top + window.scrollY - 76 - 22 : 0;
      window.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
    });
    return () => cancelAnimationFrame(id);
  }, [messages.length]);

  const [summarySending, setSummarySending] = useState(false);
  const [summaryMsg, setSummaryMsg] = useState("");
  const [summaryStatus, setSummaryStatus] = useState<"" | "success" | "error">("");

  // Summarize the ENTIRE on-screen chat (key points/findings/insights/numbers/
  // action items) via the Analyst LLM, then email it with a branded PDF.
  async function summarizeAndSendMail() {
    if (summarySending) return;
    // include full underlying data (query tables + profile sections) so the
    // emailed PDF can present the complete, informative history: not just text.
    const turns = messages
      .filter((m) => (m.content || "").trim() || m.result || (m.profileResults?.length))
      .map((m) => ({
        role: m.role,
        content: m.content || "",
        domain: m.domain || null,
        row_count: m.result?.row_count ?? null,
        result: m.result
          ? {
              columns: m.result.columns || [],
              rows: (m.result.rows || []).slice(0, 50),
              row_count: m.result.row_count ?? null,
            }
          : null,
        profile_sections: (m.profileResults && m.profileResults.length)
          ? m.profileResults
              .filter((p) => p.status === "ok")
              .map((p) => ({
                section_title: p.section_title,
                columns: p.columns || [],
                rows: (p.rows || []).slice(0, 30),
                row_count: p.row_count ?? null,
              }))
          : null,
      }));
    if (turns.length === 0) {
      setSummaryMsg("Belum ada chat untuk diringkas.");
      setTimeout(() => setSummaryMsg(""), 4000);
      return;
    }
    setSummarySending(true);
    setSummaryMsg("");
    setSummaryStatus("");
    try {
      const res = await authFetch("/api/auth/me/summarize-chat", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          ...(getAccessToken() ? { Authorization: `Bearer ${getAccessToken()}` } : {}),
        },
        body: JSON.stringify({ messages: turns, language: lang }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "Gagal mengirim summary");
      setSummaryMsg(data.message || "Email summary berhasil terkirim.");
      setSummaryStatus("success");
    } catch (e: unknown) {
      setSummaryMsg(e instanceof Error ? e.message : "Gagal mengirim summary");
      setSummaryStatus("error");
    } finally {
      setSummarySending(false);
      setTimeout(() => { setSummaryMsg(""); setSummaryStatus(""); }, 9000);
    }
  }

  // close attachment popup on outside click
  useEffect(() => {
    if (!attachOpen) return;
    function onDoc(e: MouseEvent) {
      if (attachRef.current && !attachRef.current.contains(e.target as Node)) setAttachOpen(false);
    }
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, [attachOpen]);

  // Share Location: ask the browser for GPS, resolve kecamatan + nearest sites/outlets
  function shareLocation() {
    setAttachOpen(false);
    if (busy || locating) return;
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      alert("Browser tidak mendukung Geolocation.");
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos.coords.latitude;
        const lon = pos.coords.longitude;
        const isEN = lang === "en";
        const userMsg: Msg = { role: "user", content: (isEN ? "📍 Share my location" : "📍 Share lokasi saya") + ` (${lat.toFixed(5)}, ${lon.toFixed(5)})` };
        const aMsg: Msg = { role: "assistant", content: "", status: isEN ? "Finding kecamatan & nearest locations…" : "Mencari kecamatan & lokasi terdekat…" };
        setMessages((m) => [...m, userMsg, aMsg]);
        try {
          const res = await authFetch("/api/geo/locate", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              ...(getAccessToken() ? { Authorization: `Bearer ${getAccessToken()}` } : {}),
            },
            body: JSON.stringify({ lat, lon }),
          });
          const data = await res.json();
          if (!res.ok || !data.ok) throw new Error(data.error || "Gagal mendapatkan data lokasi");
          const kec = data.kecamatan;
          const summary = kec
            ? (isEN
              ? `### 📍 Location Detected
**Kecamatan:** ${kec.kecamatan || "-"} · **City/Regency:** ${kec.kabkota || "-"} · **Province:** ${kec.provinsi || "-"}

_kec_id: \`${kec.kec_id || "-"}\`_

Here are the **10 nearest sites** and **10 nearest outlets** from your location.`
              : `### 📍 Lokasi Terdeteksi
**Kecamatan:** ${kec.kecamatan || "-"} · **Kab/Kota:** ${kec.kabkota || "-"} · **Provinsi:** ${kec.provinsi || "-"}

_kec_id: \`${kec.kec_id || "-"}\`_

Berikut **10 site terdekat** dan **10 outlet terdekat** dari lokasi Anda.`)
            : (isEN
              ? `### 📍 Location Detected
Coordinate (${lat.toFixed(5)}, ${lon.toFixed(5)}) is not mapped to a kecamatan, but here are the nearest sites & outlets.`
              : `### 📍 Lokasi Terdeteksi
Koordinat (${lat.toFixed(5)}, ${lon.toFixed(5)}) tidak terpetakan ke kecamatan, namun berikut site & outlet terdekat.`);
          setMessages((prev) => {
            const next = [...prev];
            const i = next.length - 1;
            next[i] = {
              ...next[i],
              status: undefined,
              content: summary,
              locationResult: { lat, lon, kecamatan: kec, kecProfile: data.kec_profile, sites: data.sites, outlets: data.outlets },
            };
            return next;
          });
        } catch (e: unknown) {
          setMessages((prev) => {
            const next = [...prev];
            const i = next.length - 1;
            next[i] = { ...next[i], status: undefined, error: e instanceof Error ? e.message : "Gagal" };
            return next;
          });
        } finally {
          setLocating(false);
        }
      },
      (err) => {
        setLocating(false);
        alert("Tidak bisa mengakses lokasi: " + err.message);
      },
      { enableHighAccuracy: true, timeout: 15000 },
    );
  }

  // Upload Excel (.xlsx) placeholder: parses client-side later
  function onPickFile() {
    setAttachOpen(false);
    fileInputRef.current?.click();
  }
  function onFileChosen(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    if (f) {
      setInput((prev) => (prev ? prev + " " : "") + `[file: ${f.name}]`);
    }
    e.target.value = "";
  }

  // Download helper for export_ready events
  async function downloadFromUrl(url: string, filename: string) {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const blob = await res.blob();
      const blobUrl = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = blobUrl;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(blobUrl);
    } catch (e) {
      console.error("Download failed:", e);
    }
  }

  async function send(text?: string) {
    const msg = (text ?? input).trim();
    if (!msg || busy) return;

    setInput("");
    setBusy(true);
    setPipelineFlow([{ kind: "user", t: Date.now(), label: "User query", feedback: msg.length > 50 ? msg.slice(0, 48) + "…" : msg }]);
    setTokenUsage({prompt: 0, completion: 0, total: 0});

    const userMsg: Msg = { role: "user", content: msg, time: hhmm() };
    const assistantMsg: Msg = { role: "assistant", content: "", status: "Menganalisis pertanyaan…", startedAt: Date.now(), stages: [] };
    setMessages((m) => [...m, userMsg, assistantMsg]);

    const idx = (prev: Msg[]) => prev.length - 1;
    const update = (patch: Partial<Msg>) =>
      setMessages((prev) => {
        const next = [...prev];
        const i = idx(next);
        next[i] = { ...next[i], ...patch };
        return next;
      });
    const appendContent = (chunk: string) =>
      setMessages((prev) => {
        const next = [...prev];
        const i = idx(next);
        next[i] = { ...next[i], content: (next[i].content || "") + chunk, status: undefined };
        return next;
      });
    const markStage = (...st: Stage[]) =>
      setMessages((prev) => {
        const next = [...prev];
        const i = idx(next);
        const have = new Set(next[i].stages || []);
        st.forEach((x) => have.add(x));
        next[i] = { ...next[i], stages: STAGES.map((x) => x.key).filter((k) => have.has(k)) };
        return next;
      });
    const pushFlow = (ev: FlowEvent) => {
      setPipelineFlow((f) => [...f, ev]);
    };
    const trackUsage = (data: Record<string, unknown>) => {
      const u = data._usage as {prompt_tokens?: number; completion_tokens?: number; total_tokens?: number} | undefined;
      if (u && u.total_tokens) {
        setTokenUsage({prompt: u.prompt_tokens || 0, completion: u.completion_tokens || 0, total: u.total_tokens || 0});
      }
    };

    const ctrl = new AbortController();
    abortRef.current = ctrl;
    let gotDone = false;
    let gotContent = false;
    try {
      const res = await fetch(`/api/chat/stream`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/event-stream",
          "Cache-Control": "no-cache",
          ...(getAccessToken() ? { "Authorization": `Bearer ${getAccessToken()}` } : {}),
        },
        body: JSON.stringify({
          message: msg,
          session_id: sessionIdRef.current,
          language: lang,
          history: messages.slice(-12).map((m) => ({
            role: m.role,
            content:
              m.role === "user"
                ? m.content
                : (m.content || m.status || "").slice(0, 1500),
          })),
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
          const lines = raw.split("\n");
          let event = "message"; let dataStr = "";
          for (const ln of lines) {
            if (ln.startsWith("event:")) event = ln.slice(6).trim();
            else if (ln.startsWith("data:")) dataStr += ln.slice(5).trim();
          }
          if (!dataStr) continue;
          let data: Record<string, unknown> = {};
          try { data = JSON.parse(dataStr); } catch { continue; }

          if (event === "step_start") {
            const step = data.step as string;
            const stepLabel = (data.label as string) || step;
            const stepDesc = (data.desc as string) || "";
            // Backend labels are short plain-language phases; the description adds the
            // specific (e.g. "Menyusun query untuk Revenue"), so show it when present.
            update({ status: stepDesc || stepLabel });
            const kindMap: Record<string, FlowEvent["kind"]> = {
              analyst: "analyst", router: "router", sql_write: "sql_write",
              bq_exec: "bq_exec", synth: "synth", export: "export",
              reflect: "reflect", refine: "sql_write",
              scope: "scope", reroute: "reroute",
            };
            const kind = kindMap[step];
            if (kind) {
              pushFlow({ kind, t: Date.now(), label: stepLabel, feedback: stepDesc });
            }
          } else if (event === "analyst") {
            trackUsage(data);
            markStage("analyst");
            const vq = (data.validated_query as string) || "";
            const hints = (data.hints as string) || "";
            const isData = data.is_data_query as boolean;
            const lang = (data.language as string) || "id";
            update({ status: "Analyst selesai" });
            setPipelineFlow(prev => {
              const idx = prev.findIndex(e => e.kind === "analyst");
              if (idx >= 0) {
                const updated = [...prev];
                updated[idx] = { ...updated[idx], t: Date.now(),
                  feedback: vq ? `"${vq.slice(0, 80)}${vq.length > 80 ? "…" : ""}"` : updated[idx].feedback,
                  meta: {
                    ...(isData !== undefined ? { "data_query": isData } : {}),
                    ...(lang ? { "lang": lang } : {}),
                    ...(hints ? { "hints": hints.slice(0, 60) } : {}),
                  },
                };
                return updated;
              }
              return prev;
            });
          } else if (event === "route") {
            trackUsage(data);
            markStage("router");
            const dom = data.domain as string;
            const reason = (data.reason as string) || "";
            const rephrased = (data.rephrased as string) || "";
            update({ domain: dom, status: "Orchestrator selesai routing" });
            setPipelineFlow(prev => {
              const idx = prev.findIndex(e => e.kind === "router");
              if (idx >= 0) {
                const updated = [...prev];
                updated[idx] = { ...updated[idx], t: Date.now(),
                  feedback: reason ? reason.slice(0, 80) : (rephrased ? `→ ${rephrased.slice(0, 60)}` : undefined),
                  meta: dom && dom !== "none" ? { "domain": dom } : undefined,
                };
                return updated;
              }
              return prev;
            });
            if (dom === "PROFILE") {
              pushFlow({ kind: "agent", t: Date.now(), label: "Profile Mode", domain: "PROFILE", feedback: "Multi-domain parallel profile deck" });
            } else if (dom && dom !== "none") {
              pushFlow({ kind: "agent", t: Date.now(), label: dom, domain: dom });
            } else {
              pushFlow({ kind: "general", t: Date.now(), label: "General reply", feedback: "Bukan pertanyaan data, menjawab langsung" });
            }
          } else if (event === "status") {
            const stage = data.stage as string;
            const label = (data.label as string) || "";
            const map: Record<string, string> = {
              analyzing: "Analyst sedang menganalisis…",
              writing_sql: `${label || "Agent"}: menyiapkan query data…`,
              executing: "Mengambil data dari database…",
              answering: "Menyusun jawaban…",
              exporting: "Export Agent: membuat file…",
              general: "Menyusun jawaban…",
              planning_profile: "Merencanakan profile multi-domain…",
              parallel_queries: `Mengambil data dari ${(data.count as number) || ""} sumber…`,
              compiling_profile: "Menyusun profile deck…",
            };
            const patch: Partial<Msg> = { status: map[stage] || stage };
            if (label) patch.domainLabel = label;
            update(patch);
          } else if (event === "profile_plan") {
            const plan = {
              territory_type: data.territory_type as string,
              territory_name: data.territory_name as string,
              sub_queries: data.sub_queries as { domain: string; section_title: string; question: string }[],
            };
            update({ profilePlan: plan, status: `🏙️ Profile: ${plan.territory_name}: ${plan.sub_queries.length} domains` });
            for (const sq of plan.sub_queries) {
              pushFlow({ kind: "agent", t: Date.now(), label: sq.section_title, domain: sq.domain });
            }
          } else if (event === "profile_domain_result") {
            const dr = {
              domain: data.domain as string,
              section_title: data.section_title as string,
              status: data.status as string,
              row_count: (data.row_count as number) || 0,
              error: data.error as string | null,
              columns: (data.columns as string[]) || [],
              rows: (data.rows as Record<string, unknown>[]) || [],
              sql: data.sql as string | null,
              explanation: (data.explanation as string) || "",
              chart: data.chart as SmartChartSpec | undefined,
            };
            setMessages((prev) => {
              const next = [...prev];
              const i = next.length - 1;
              const existing = next[i].profileResults || [];
              next[i] = { ...next[i], profileResults: [...existing, dr] };
              return next;
            });
            const icon = dr.status === "ok" ? "✅" : "❌";
            pushFlow({ kind: "bq_done", t: Date.now(), label: `${icon} ${dr.section_title}`, detail: dr.status === "ok" ? `${dr.row_count} rows` : (dr.error || "error").slice(0, 60) });
          } else if (event === "sql") {
            trackUsage(data);
            markStage("router", "analyst");
            const explanation = (data.explanation as string) || "";
            update({ sql: data.sql as string, sqlExplanation: explanation });
            setPipelineFlow(prev => {
              const idx = prev.findIndex(e => e.kind === "sql_write");
              if (idx >= 0) {
                const updated = [...prev];
                updated[idx] = { ...updated[idx], feedback: explanation ? explanation.slice(0, 100) : updated[idx].feedback };
                return updated;
              }
              return prev;
            });
          } else if (event === "result") {
            const rowCount = data.row_count as number;
            const bytes = data.bytes_processed as number;
            const cols = (data.columns as string[]) || [];
            update({
              result: {
                columns: cols,
                rows: data.rows as Record<string, unknown>[],
                row_count: rowCount,
                sql: data.sql as string,
                bytes_processed: bytes,
                chart: data.chart as SmartChartSpec | undefined,
                kpis: (data.kpis as Kpi[] | undefined) ?? [],
                source: data.source as string | undefined,
              },
            });
            markStage("router", "analyst", "sql");
            pushFlow({
              kind: "bq_done", t: Date.now(),
              label: `${rowCount.toLocaleString("id-ID")} data rows`,
              feedback: `${cols.length} kolom · ${rowCount.toLocaleString("id-ID")} baris data diterima`,
              meta: { "columns": cols.length, "rows": rowCount },
            });
          } else if (event === "chart_spec") {
            const spec = data as unknown as ChartSpec;
            if (spec && spec.mode && spec.mode !== "none") update({ chartSpec: spec });
          } else if (event === "export_ready") {
            update({
              exportReady: {
                format: data.format as string,
                url: data.download_url as string,
              },
            });
          } else if (event === "token") {
            if (!gotContent) markStage("router", "analyst", "validasi");
            gotContent = true;
            appendContent(String(data.t || ""));
          } else if (event === "retry") {
            update({ status: `Mencoba ulang query (percobaan ${data.attempt})…` });
            pushFlow({ kind: "retry", t: Date.now(), label: "Retry", detail: "Memperbaiki query…" });
          } else if (event === "reflect") {
            const verdict = String(data.verdict || "");
            const reason = String(data.reason || "");
            const msg = verdict === "ok"
              ? "Jawaban relevan ✓"
              : verdict === "refine"
                ? "Belum optimal: mencari jawaban lebih baik…"
                : "Data tidak tersedia: menyiapkan alternatif…";
            update({ status: msg });
            if (verdict === "ok") markStage("validasi");
            pushFlow({
              kind: "reflect", t: Date.now(), label: "Quality Check",
              detail: reason.slice(0, 90),
              feedback: msg,
            });
          } else if (event === "scope") {
            const verdict = String(data.verdict || "");
            const reason = String(data.reason || "");
            const msg = verdict === "answerable"
              ? "Domain sesuai ✓"
              : verdict === "reroute"
                ? "Domain tidak punya datanya: mengalihkan…"
                : "Perlu konfirmasi pertanyaan…";
            update({ status: msg });
            pushFlow({
              kind: "scope", t: Date.now(), label: "Domain Check",
              domain: String(data.domain || ""),
              detail: reason.slice(0, 90), feedback: msg,
            });
          } else if (event === "reroute") {
            const to = String(data.to || "");
            const reason = String(data.reason || "");
            update({ status: to ? `Mengalihkan ke domain ${to}…` : "Mencari domain lain…" });
            pushFlow({
              kind: "reroute", t: Date.now(), label: "Re-route",
              domain: to, detail: reason.slice(0, 90),
              feedback: `${String(data.from || "")} → ${to || "–"}`,
            });
          } else if (event === "clarify") {
            update({ status: "Menunggu konfirmasi…" });
          } else if (event === "error") {
            update({ error: String(data.error || "error"), status: undefined });
            pushFlow({ kind: "error", t: Date.now(), label: "Error", detail: String(data.error || "").slice(0, 80) });
          } else if (event === "done") {
            gotDone = true;
            trackUsage(data);
            setMessages((prev) => {
              const next = [...prev];
              const i = idx(next);
              const done = new Set(next[i].stages || []);
              const isData = !!next[i].result || !!next[i].profileResults?.length;
              STAGES.forEach((x) => { if (isData || (x.key !== "sql")) done.add(x.key); });
              next[i] = {
                ...next[i], status: undefined, stages: STAGES.map((x) => x.key).filter((k) => done.has(k)),
                elapsedMs: typeof data.elapsed_ms === "number" ? data.elapsed_ms as number
                  : next[i].startedAt ? Date.now() - next[i].startedAt! : undefined,
              };
              return next;
            });
            const dom = (data.domain as string) || "";
            pushFlow({ kind: "done", t: Date.now(), label: "Answer ready", feedback: dom && dom !== "none" ? `Domain: ${dom}` : "Jawaban telah dikirim" });
          }
        }
      }
    } catch (e: unknown) {
      const err = e instanceof Error ? e.message : String(e);
      // If the answer already streamed in (or completed), a late connection drop
      // is not a real failure: don't show a scary "Network error".
      if (!err.includes("aborted") && !gotDone && !gotContent) {
        update({ error: err, status: undefined });
        pushFlow({ kind: "error", t: Date.now(), label: "Network error", detail: err });
      } else {
        update({ status: undefined });
      }
    } finally {
      setBusy(false);
      abortRef.current = null;
      // refresh sidebar history list so the new/updated chat appears
      loadHistoryList();
    }
  }

  function handleKey(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      send();
    }
  }

  function stop() {
    abortRef.current?.abort();
    setBusy(false);
  }
  const questions = messages.filter((m) => m.role === "user");
  const title = sessionTitle || questions[0]?.content.replace(/^📍\s*/, "") || "Percakapan baru";
  const now = new Date();
  const period = `${MONTHS_ID[now.getMonth()]} ${now.getFullYear()}`;
  const firstName = (getUser()?.full_name || getUser()?.username || "").split(" ")[0];
  const lastAssistant = messages.map((m) => m.role).lastIndexOf("assistant");

  function copyAnswer(i: number) {
    const m = messages[i];
    navigator.clipboard?.writeText(m.content || "").then(() => {
      setCopied(i);
      setTimeout(() => setCopied(null), 1600);
    }).catch(() => {});
  }

  function exportXlsx(i: number) {
    const r = messages[i].result;
    if (!r) return;
    const q = messages[i - 1]?.content || "hasil";
    const slug = q.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 40) || "hasil";
    downloadXlsx(`bizplan-${slug}`, r.columns, r.rows, "Hasil");
  }

  function pinToDashboard(i: number) {
    const m = messages[i];
    if (!m.result) return;
    try {
      const key = `dash_pins::${getUser()?.username || "anon"}`;
      const pins = JSON.parse(localStorage.getItem(key) || "[]");
      pins.unshift({
        id: `${Date.now()}`,
        question: messages[i - 1]?.content || "",
        title: m.result.chart?.title || messages[i - 1]?.content || "Hasil",
        chart: m.result.chart,
        columns: m.result.columns,
        rows: m.result.rows.slice(0, 200),
        pinned_at: new Date().toISOString(),
      });
      localStorage.setItem(key, JSON.stringify(pins.slice(0, 12)));
      setPinned((p) => ({ ...p, [i]: true }));
    } catch { /* storage full or unavailable */ }
  }

  function watchThis(i: number) {
    const q = messages[i - 1]?.content || "";
    router.push(`/watchlist?new=1&q=${encodeURIComponent(q)}`);
  }

  function voiceInput() {
    type SR = { lang: string; interimResults: boolean; onresult: (e: { results: ArrayLike<ArrayLike<{ transcript: string }>> }) => void; onend: () => void; start: () => void; stop: () => void };
    const w = window as unknown as { SpeechRecognition?: new () => SR; webkitSpeechRecognition?: new () => SR };
    const Ctor = w.SpeechRecognition || w.webkitSpeechRecognition;
    if (!Ctor) {
      alert("Browser ini belum mendukung input suara.");
      return;
    }
    const rec = new Ctor();
    rec.lang = lang === "en" ? "en-US" : "id-ID";
    rec.interimResults = true;
    rec.onresult = (e) => {
      const text = Array.from(e.results).map((r) => r[0].transcript).join("");
      setInput(text);
    };
    rec.onend = () => setListening(false);
    setListening(true);
    rec.start();
  }

  // grow the composer with its content
  useEffect(() => {
    const ta = taRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    ta.style.height = `${Math.min(ta.scrollHeight, 200)}px`;
  }, [input]);

  const drill = busy ? undefined : (col: string, value: string) =>
    send(`Detailkan ${value} (${col.replace(/_/g, " ")}) dari hasil sebelumnya`);

  const fmtBytes = (b: number) => b >= 1e9 ? `${(b / 1e9).toLocaleString("id-ID", { maximumFractionDigits: 1 })} GB` : `${Math.max(1, Math.round(b / 1e6)).toLocaleString("id-ID")} MB`;
  const sourceOf = (m: Msg) => m.result?.source
    ?? (m.result && typeof m.result.bytes_processed === "number" ? `BigQuery · ${fmtBytes(m.result.bytes_processed)}` : m.domainLabel);
  const hasMap = (m: Msg) => !!m.result && (!!detectLatLon(m.result.columns) || !!m.result.chart?.map_key);

  return (
    <AppShell
      activeSession={activeSession}
      onNewChat={newChat}
      onOpenSession={(sid) => loadSession(sid)}
      historyVersion={historyVersion}
      busy={busy}
    >
      {summaryMsg && (
        <div className={`toast ${summaryStatus}`} role="status">
          <Icon name={summaryStatus === "success" ? "check" : "mail"} size={16} /> {summaryMsg}
        </div>
      )}

      <TopBar
        title={title}
        subtitle={questions.length ? `${questions.length} pertanyaan${lang === "en" ? " · English" : ""}` : "Siap menjawab"}
        actions={<>
          <span className="chip teal"><Icon name="pin" />Circle Java</span>
          <span className="chip"><Icon name="cal" />{period}</span>
          <button className="btn-ic" onClick={summarizeAndSendMail} disabled={summarySending || busy || messages.length === 0}
            title="Ringkas percakapan dan kirim ke email" aria-label="Bagikan ringkasan ke email">
            <Icon name="share" className="ic" />
          </button>
        </>}
      />

      <div className="tanya-body">
        <div className="tanya">
          <div className="conv" ref={scrollRef}>
            {messages.length === 0 && (
              <section className="welcome">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <span className="tile"><img src="/brand/icon_circle_java.png" alt="" /></span>
                <h1>Halo{firstName ? `, ${firstName}` : ""}. Mau tahu apa hari ini?</h1>
                <p>Tanyakan revenue, site, payload, market share atau profil wilayah di Circle Java. Agent menulis query, mengambil data, lalu menyajikan angka, grafik, tabel dan peta.</p>
                <div className="starters">
                  {STARTERS.map((s) => (
                    <button key={s.text} className="starter" onClick={() => send(s.text)}>
                      <i style={{ background: s.bg, color: s.fg }}><Icon name={s.icon} /></i>
                      <span><b>{s.title}</b>{s.text}</span>
                    </button>
                  ))}
                </div>
                <div className="domains" role="list" aria-label="Topik">
                  {DOMAIN_CHIPS.map((d) => (
                    <button key={d.key} role="listitem" className="sg" disabled={busy} onClick={() => send(d.q)} title={d.q}>
                      <Icon name="spark" />{d.label}
                    </button>
                  ))}
                </div>
              </section>
            )}

            {messages.map((m, i) => m.role === "user" ? (
              <div key={i} className="ubub">{m.content}{m.time && <small>{m.time}</small>}</div>
            ) : (
              <div key={i} className="ans">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <span className="tile"><img src="/brand/icon_circle_java.png" alt="" /></span>
                <article className="acard" aria-label="Jawaban Agent">
                  <div className="ahead">
                    <b>Agent Java</b>
                    {m.stages?.includes("validasi") && !m.error && <span className="pill ok"><Icon name="check" />Tervalidasi</span>}
                    {m.status ? (
                      <span className="pill live"><span className="spin" />{m.status}</span>
                    ) : m.stages?.length ? (
                      <button type="button" className="pill grey" aria-expanded={!!sqlVisible[i]}
                        onClick={() => setSqlVisible((v) => ({ ...v, [i]: !v[i] }))} title="Lihat langkah agent">
                        {m.stages.length} langkah{m.elapsedMs ? ` · ${Math.max(0.1, m.elapsedMs / 1000).toLocaleString("id-ID", { maximumFractionDigits: 1 })} dtk` : ""}
                        <Icon name="chev" />
                      </button>
                    ) : null}
                    {sourceOf(m) && <span className="r"><span className="pill src"><Icon name="db" />{sourceOf(m)}</span></span>}
                  </div>

                  {sqlVisible[i] && (
                    <div className="vsub">
                      {i === lastAssistant && pipelineFlow.length > 0 && <AgentFlow events={pipelineFlow} live={busy} tokenUsage={tokenUsage} />}
                      {m.sql && canViewSQL() && <pre className="sqlbox"><code>{m.sql}</code></pre>}
                    </div>
                  )}

                  {m.content && <div className="atext"><Markdown text={m.content} /></div>}
                  {!m.content && m.status && !m.result && (
                    <div className="askel" aria-hidden="true"><span style={{ width: "92%" }} /><span style={{ width: "76%" }} /><span style={{ width: "58%" }} /></div>
                  )}

                  {m.result && m.result.rows.length > 0 && (
                    <>
                      <KpiRow kpis={m.result.kpis ?? []} />
                      {m.chartSpec && (!m.result.chart || m.result.chart.type === "none") ? (
                        <div className="viz"><ChartPanel columns={m.result.columns} rows={m.result.rows} spec={m.chartSpec} /></div>
                      ) : null}
                      <AnswerViz result={m.result} onDrill={drill} />
                    </>
                  )}

                  {m.profileResults && m.profileResults.length > 0 && (
                    <div className="viz">
                      <div className="vhead"><div>
                        <h4>{m.profilePlan?.territory_name ? `Profil ${m.profilePlan.territory_name}` : "Profil wilayah"}</h4>
                        <p>{m.profileResults.filter((r) => r.status === "ok").length} dari {m.profileResults.length} sumber data berhasil</p>
                      </div></div>
                      <div className="vsub">
                        {m.profileResults.map((pr, pi) => pr.status === "ok" && pr.rows.length > 0 ? (
                          <AnswerViz key={pi} result={{ columns: pr.columns, rows: pr.rows, row_count: pr.row_count, chart: pr.chart ? { ...pr.chart, title: pr.chart.title || pr.section_title } : undefined }} />
                        ) : (
                          <div key={pi} className="aerr"><b>{pr.section_title}</b>: {pr.error ? pr.error.slice(0, 140) : "tidak ada data"}</div>
                        ))}
                      </div>
                    </div>
                  )}

                  {m.locationResult && (
                    <div className="vsub">
                      {m.locationResult.kecProfile && (
                        <div className="viz">
                          <div className="vhead"><div><h4>{lang === "en" ? "Kecamatan profile" : "Profil kecamatan"}{m.locationResult.kecamatan?.kecamatan ? ` · ${m.locationResult.kecamatan.kecamatan}` : ""}</h4></div></div>
                          <KecProfileCard profile={m.locationResult.kecProfile} isEN={lang === "en"} />
                        </div>
                      )}
                      {(["sites", "outlets"] as const).map((k) => {
                        const block = m.locationResult![k];
                        if (!block || block.rows.length === 0) return null;
                        const geo = detectLatLon(block.columns);
                        return (
                          <div key={k} className="viz">
                            <div className="vhead"><div><h4>{k === "sites" ? (lang === "en" ? "10 nearest sites" : "10 site terdekat") : (lang === "en" ? "10 nearest outlets" : "10 outlet terdekat")}</h4></div></div>
                            {geo && <div className="vmap"><SiteMap columns={block.columns} rows={block.rows} latKey={geo.latKey} lonKey={geo.lonKey} /></div>}
                            <NearestTable columns={block.columns} rows={block.rows} />
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {m.error && <div className="aerr" role="alert"><b>Agent gagal menjawab.</b> {m.error}</div>}

                  {!m.status && (m.content || m.result) && (
                    <div className="vfoot">
                      <button type="button" className="pill ai" onClick={() => taRef.current?.focus()}><Icon name="spark" />Lanjutkan</button>
                      <div className="act">
                        <button type="button" onClick={() => copyAnswer(i)}><Icon name={copied === i ? "check" : "copy"} />{copied === i ? "Tersalin" : "Salin"}</button>
                        {(m.result?.rows.length || m.exportReady) && canExport() ? (
                          <button type="button" onClick={() => setExportOpen((v) => (v === i ? null : i))} aria-expanded={exportOpen === i}><Icon name="dl" />Ekspor</button>
                        ) : null}
                        {m.result && <button type="button" onClick={() => watchThis(i)}><Icon name="bellplus" />Pantau</button>}
                        {hasMap(m) && (
                          <button type="button" className="pri" onClick={() => router.push(`/map?q=${encodeURIComponent(messages[i - 1]?.content || "")}`)}>
                            <Icon name="map" />Buka di Peta Agent
                          </button>
                        )}
                        {exportOpen === i && (
                          <div className="menu" role="menu">
                            {m.result && m.result.rows.length > 0 && <button role="menuitem" onClick={() => { setExportOpen(null); exportXlsx(i); }}><Icon name="table" />Unduh Excel (XLSX)</button>}
                            {m.exportReady ? (
                              <button role="menuitem" onClick={() => { setExportOpen(null); downloadFromUrl(m.exportReady!.url, `agent-java.${m.exportReady!.format}`); }}>
                                <Icon name="file" />Unduh {m.exportReady.format.toUpperCase()}
                              </button>
                            ) : m.result ? (
                              <button role="menuitem" disabled={busy} onClick={() => { setExportOpen(null); send("Buatkan laporan PDF dari hasil sebelumnya"); }}><Icon name="file" />Buat laporan PDF</button>
                            ) : null}
                            {m.result?.chart && m.result.chart.type !== "none" && (
                              <button role="menuitem" disabled={pinned[i]} onClick={() => { setExportOpen(null); pinToDashboard(i); }}>
                                <Icon name="grid" />{pinned[i] ? "Tersemat di Dashboard" : "Sematkan ke Dashboard"}
                              </button>
                            )}
                          </div>
                        )}
                      </div>
                    </div>
                  )}
                </article>
              </div>
            ))}

            {!busy && lastAssistant >= 0 && lastAssistant === messages.length - 1 && !messages[lastAssistant].error && (
              <div className="sugg">
                {followUps(messages[lastAssistant]).map((f) => (
                  <button key={f} className="sg" onClick={() => f === "Tampilkan di peta"
                    ? router.push(`/map?q=${encodeURIComponent(messages[lastAssistant - 1]?.content || "")}`) : send(f)}>
                    <Icon name="spark" />{f}
                  </button>
                ))}
              </div>
            )}
          </div>

          <div className="dock">
            <div className="fade" />
            <div className="composer">
              <textarea
                ref={taRef}
                placeholder="Tanya apa saja tentang bisnis Circle Java: revenue, site, market share, peta…"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKey}
                disabled={busy}
                rows={1}
                aria-label="Pertanyaan"
              />
              <div className="row" ref={attachRef}>
                <input ref={fileInputRef} type="file" accept=".xlsx,.xls" hidden onChange={onFileChosen} />
                <button className="btn-ic" onClick={() => setAttachOpen((v) => !v)} disabled={busy || locating}
                  aria-label="Lampiran" aria-haspopup="menu" aria-expanded={attachOpen}>
                  {locating ? <span className="pill live"><span className="spin" /></span> : <Icon name="clip" className="ic" />}
                </button>
                {attachOpen && (
                  <div className="menu" role="menu">
                    <button role="menuitem" onClick={shareLocation}><Icon name="locate" /><span>Bagikan lokasi saya<small>Profil kecamatan, site dan outlet terdekat</small></span></button>
                    <button role="menuitem" onClick={onPickFile}><Icon name="up" /><span>Unggah Excel<small>File .xlsx untuk dianalisis</small></span></button>
                  </div>
                )}
                <span className="chip teal"><Icon name="pin" />Circle Java</span>
                <span className="chip"><Icon name="cal" />{period}</span>
                {lang === "en" && <span className="chip"><Icon name="globe" />English</span>}
                <span className="grow" />
                <button className={`btn-ic bare ${listening ? "on" : ""}`} onClick={voiceInput} disabled={busy} aria-label="Bicara"><Icon name="mic" className="ic" /></button>
                {busy ? (
                  <button className="send stop" onClick={stop} aria-label="Hentikan"><Icon name="minus" /></button>
                ) : (
                  <button className="send" onClick={() => send()} disabled={!input.trim()} aria-label="Kirim"><Icon name="send" /></button>
                )}
              </div>
            </div>
            <p className="disclaim">Agent bisa keliru. Cek angka penting sebelum dibagikan.</p>
          </div>
        </div>
      </div>
    </AppShell>
  );
}
