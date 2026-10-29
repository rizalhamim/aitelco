"use client";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import {
  Activity, ArrowRight, BellRing, Calendar, Check, CircleHelp, Clock, Copy, FileSpreadsheet, FileText,
  Globe, Languages, Mail, Map as MapIcon, MapPin, Mic, MoreHorizontal, Paperclip, Pin, RefreshCw, Send, Share2,
  Square, ThumbsUp, TrendingUp, Upload, Code2, Workflow,
} from "lucide-react";
import AppShell from "./components/shell/AppShell";
import SmartChart, { type ChartSpec } from "./components/charts/SmartChart";
import ResultTable from "./components/ResultTable";
import SiteMap from "./components/SiteMap";
import { downloadXlsx } from "@/lib/xlsx";
import "./chat.css";

function detectLatLon(columns: string[]): { latKey: string; lonKey: string } | null {
  const lat = columns.find((c) => /^lat(itude)?$/i.test(c) || /_lat(itude)?$/i.test(c) || /(addr_)?latitude/i.test(c));
  const lon = columns.find((c) => /^lon(g|gitude)?$/i.test(c) || /_lon(g|gitude)?$/i.test(c) || /(addr_)?longitude/i.test(c));
  if (lat && lon) return { latKey: lat, lonKey: lon };
  return null;
}
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
  if (v === null || v === undefined || v === "") return "—";
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
                    ) : "—"}
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
    if (v === null || v === undefined) return "—";
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
  chart?: ChartSpec;
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
    chart?: ChartSpec;
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

const DOMAIN_COLOR: Record<string, string> = {
  site_performance: "var(--ioh-red)",
  revenue: "var(--ioh-red)",
  acquisition: "var(--ioh-pink)",
  fwa: "var(--ioh-teal)",
  ftth: "var(--ioh-teal)",
  "5g": "var(--ioh-magenta)",
  network: "var(--ioh-pink)",
  network_benchmark: "var(--ioh-yellow)",
  competitive: "var(--ioh-magenta)",
  kpi_summary: "var(--ioh-red)",
  customer_hvc: "var(--ioh-red)",
  sales_distribution: "var(--ioh-magenta)",
  territory_reference: "var(--ioh-grey)",
  PROFILE: "var(--ioh-yellow)",
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
  { icon: "duo_revenue", title: "Revenue Jawa Barat", text: "Bagaimana performa revenue Jawa Barat bulan ini dibanding bulan lalu? Kabupaten mana yang paling turun?" },
  { icon: "duo_site", title: "Site availability", text: "Site availability Jawa Timur minggu ini, mana yang di bawah target?" },
  { icon: "duo_marketshare", title: "Market share", text: "Market share FWA Semarang dibanding kompetitor 3 bulan terakhir" },
  { icon: "duo_report", title: "Profil kota", text: "Tampilkan profile lengkap kota Surabaya" },
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

function followUps(m: Msg): { icon: typeof Activity; text: string }[] {
  const out: { icon: typeof Activity; text: string }[] = [];
  const spec = m.result?.chart;
  const rows = m.result?.rows ?? [];
  const label = spec?.map_key ?? spec?.x;
  if (label && rows.length && spec?.type !== "line" && spec?.type !== "area") {
    const top = String(rows[rows.length > 1 && spec?.sort !== "desc" ? 0 : 0][label] ?? "");
    if (top) out.push({ icon: CircleHelp, text: `Kenapa ${top} seperti ini?` });
  }
  out.push({ icon: Activity, text: "Bandingkan dengan bulan lalu" });
  out.push({ icon: TrendingUp, text: "Proyeksi bulan depan" });
  if (spec?.map_key) out.push({ icon: MapIcon, text: "Tampilkan di peta" });
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
  const [moreOpen, setMoreOpen] = useState(false);
  const [showFlow, setShowFlow] = useState(false);
  const [copied, setCopied] = useState<number | null>(null);
  const [liked, setLiked] = useState<Record<number, boolean>>({});
  const [pinned, setPinned] = useState<Record<number, boolean>>({});
  const [listening, setListening] = useState(false);
  const moreRef = useRef<HTMLDivElement>(null);
  const taRef = useRef<HTMLTextAreaElement>(null);
  const abortRef = useRef<AbortController | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string>("");
  const attachRef = useRef<HTMLDivElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Auth check — redirect to login if not authenticated
  useEffect(() => {
    if (!isLoggedIn()) {
      router.push("/login");
    } else {
      setAuthChecked(true);
    }
  }, [router]);

  function chooseLang(l: "id" | "en") {
    setLang(l);
    try { localStorage.setItem("telco_ai_lang", l); } catch { /* ignore */ }
  }

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
        // session not in DB yet (e.g. fresh unused id) — keep screen blank
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
      const bubbles = el.querySelectorAll<HTMLElement>(".chat-user");
      const last = bubbles[bubbles.length - 1];
      el.scrollTo({ top: last ? Math.max(0, last.offsetTop - 12) : 0, behavior: "smooth" });
    });
    return () => cancelAnimationFrame(id);
  }, [messages.length]);

  // close the "more" menu when clicking outside it
  useEffect(() => {
    if (!moreOpen) return;
    function onDocClick(e: MouseEvent) {
      if (!moreRef.current?.contains(e.target as Node)) setMoreOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, [moreOpen]);

  const [summarySending, setSummarySending] = useState(false);
  const [summaryMsg, setSummaryMsg] = useState("");
  const [summaryStatus, setSummaryStatus] = useState<"" | "success" | "error">("");

  // Summarize the ENTIRE on-screen chat (key points/findings/insights/numbers/
  // action items) via the Analyst LLM, then email it with a branded PDF.
  async function summarizeAndSendMail() {
    if (summarySending) return;
    // include full underlying data (query tables + profile sections) so the
    // emailed PDF can present the complete, informative history — not just text.
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

  // Refresh: clear the current screen to a fresh/blank state (new session)
  function refreshChat() {
    if (busy) return;
    newChat();
    setSummaryMsg("");
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

  // Upload Excel (.xlsx) placeholder — parses client-side later
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
            update({ status: `${stepLabel} — ${stepDesc}` });
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
              writing_sql: `${label || "Agent"} — menyiapkan query data…`,
              executing: "Mengambil data dari database…",
              answering: "Menyusun jawaban…",
              exporting: "Export Agent — membuat file…",
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
            update({ profilePlan: plan, status: `🏙️ Profile: ${plan.territory_name} — ${plan.sub_queries.length} domains` });
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
              chart: data.chart as ChartSpec | undefined,
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
                chart: data.chart as ChartSpec | undefined,
              },
            });
            markStage("router", "analyst", "sql");
            pushFlow({
              kind: "bq_done", t: Date.now(),
              label: `${rowCount.toLocaleString("id-ID")} data rows`,
              feedback: `${cols.length} kolom · ${rowCount.toLocaleString("id-ID")} baris data diterima`,
              meta: { "columns": cols.length, "rows": rowCount },
            });
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
                ? "Belum optimal — mencari jawaban lebih baik…"
                : "Data tidak tersedia — menyiapkan alternatif…";
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
                ? "Domain tidak punya datanya — mengalihkan…"
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
              feedback: `${String(data.from || "")} → ${to || "—"}`,
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
                elapsedMs: next[i].startedAt ? Date.now() - next[i].startedAt! : undefined,
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
      // is not a real failure — don't show a scary "Network error".
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
  const title = questions[0]?.content.replace(/^📍\s*/, "") || "Percakapan baru";
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
  const showOnMap = (col: string, value: string) =>
    router.push(`/map?focus=${encodeURIComponent(value)}&level=${encodeURIComponent(col)}`);

  return (
    <AppShell
      activeSession={activeSession}
      onNewChat={newChat}
      onOpenSession={(sid) => loadSession(sid)}
      historyVersion={historyVersion}
      busy={busy}
      mainClassName="chat-main"
    >
      {summaryMsg && (
        <div className={`chat-toast ${summaryStatus}`} role="status">
          {summaryStatus === "success" ? <Check size={16} /> : <Mail size={16} />} {summaryMsg}
        </div>
      )}

      <header className="ui-topbar">
        <div className="ui-topbar-title">
          <b title={title}>{title}</b>
          <span>{questions.length ? `Percakapan · ${questions.length} pertanyaan` : "Tanya Agent · siap menjawab"}</span>
        </div>
        <span className="ui-chip teal chat-hide-sm"><MapPin size={16} /> Region: Jawa</span>
        <span className="ui-chip chat-hide-sm"><Calendar size={20} strokeWidth={1.6} /> {period}</span>
        <button className="ui-iconbtn" onClick={summarizeAndSendMail} disabled={summarySending || busy || messages.length === 0}
          title="Kirim ringkasan percakapan ke email" aria-label="Bagikan ringkasan">
          <Share2 size={18} />
        </button>
        <div className="chat-more" ref={moreRef}>
          <button className="ui-iconbtn" onClick={() => setMoreOpen((v) => !v)} aria-label="Lainnya" aria-expanded={moreOpen}>
            <MoreHorizontal size={18} />
          </button>
          {moreOpen && (
            <div className="ui-popover chat-more-menu" role="menu">
              <button role="menuitem" disabled={busy} onClick={() => { setMoreOpen(false); refreshChat(); }}>
                <RefreshCw size={16} /> Mulai percakapan baru
              </button>
              <button role="menuitem" disabled={summarySending || busy || messages.length === 0}
                onClick={() => { setMoreOpen(false); summarizeAndSendMail(); }}>
                <Mail size={16} /> {summarySending ? "Meringkas…" : "Ringkas & kirim ke email"}
              </button>
              <div className="chat-menu-label"><Languages size={14} /> Bahasa jawaban</div>
              <div className="ui-seg chat-lang">
                <button aria-pressed={lang === "id"} onClick={() => chooseLang("id")}>Indonesia</button>
                <button aria-pressed={lang === "en"} onClick={() => chooseLang("en")}>English</button>
              </div>
            </div>
          )}
        </div>
      </header>

      <div className="chat-scroll" ref={scrollRef}>
        <div className="ui-glow" aria-hidden="true" />
        <div className="chat-col">
          <div className="chat-domains" role="list" aria-label="Topik">
            {DOMAIN_CHIPS.map((d) => (
              <button key={d.key} role="listitem" className="chat-domain" disabled={busy} onClick={() => send(d.q)} title={d.q}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={`/illustrations/${d.icon}.svg`} alt="" width={36} height={36} />
                <span>{d.label}</span>
              </button>
            ))}
          </div>

          {messages.length === 0 && (
            <section className="chat-welcome">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className="chat-welcome-orb" src="/illustrations/hero_ai_orb.svg" alt="" width={168} height={168} />
              <h1>Halo{firstName ? `, ${firstName}` : ""}. Mau tahu apa hari ini?</h1>
              <p>Tanyakan revenue, site, network, market share atau sales di Jawa. Agent menulis query, mengambil data dari BigQuery, lalu menyajikan angka, grafik dan tabelnya.</p>
              <div className="chat-starters">
                {STARTERS.map((s) => (
                  <button key={s.text} className="chat-starter" onClick={() => send(s.text)}>
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={`/illustrations/${s.icon}.svg`} alt="" width={40} height={40} />
                    <span><b>{s.title}</b>{s.text}</span>
                    <ArrowRight size={16} />
                  </button>
                ))}
              </div>
            </section>
          )}

          {messages.map((m, i) => m.role === "user" ? (
            <div key={i} className="chat-user">
              <div className="chat-bubble">
                <p>{m.content}</p>
                {m.time && <span>{m.time}</span>}
              </div>
            </div>
          ) : (
            <div key={i} className="chat-answer">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img className="chat-avatar" src="/illustrations/ai_orb_particles.svg" alt="Agent" width={40} height={40} />
              <article className="chat-card">
                <div className="chat-pipeline">
                  {STAGES.map((st, si) => {
                    const done = m.stages?.includes(st.key);
                    const live = busy && i === lastAssistant && !done && STAGES.slice(0, si).every((p) => m.stages?.includes(p.key) || p.key === "sql");
                    if (!done && !(busy && i === lastAssistant) && !m.stages?.length) return null;
                    return (
                      <span key={st.key} className="chat-stage-wrap">
                        {si > 0 && <span className="chat-stage-line" />}
                        <span className={`chat-stage ${done ? "done" : live ? "live" : "todo"}`}>
                          {done ? <Check size={14} strokeWidth={2.4} /> : <span className="chat-stage-dot" />}
                          {st.label}
                        </span>
                      </span>
                    );
                  })}
                  <span className="chat-pipeline-meta">
                    {m.status ? (
                      <><span className="chat-spinner" /> {m.status}</>
                    ) : m.elapsedMs ? (
                      <><Clock size={14} /> Selesai dalam {Math.max(0.1, m.elapsedMs / 1000).toLocaleString("id-ID", { maximumFractionDigits: 1 })} dtk</>
                    ) : null}
                  </span>
                </div>

                {m.content && <div className="chat-text"><Markdown text={m.content} /></div>}
                {!m.content && m.status && !m.result && (
                  <div className="chat-skeleton" aria-hidden="true">
                    <span className="ui-skel" style={{ width: "92%" }} />
                    <span className="ui-skel" style={{ width: "76%" }} />
                    <span className="ui-skel" style={{ width: "58%" }} />
                  </div>
                )}

                {m.result && m.result.rows.length > 0 && (() => {
                  const geo = detectLatLon(m.result.columns);
                  const spec = m.result.chart;
                  return (
                    <>
                      {spec && spec.type !== "none" && (
                        <SmartChart spec={spec} rows={m.result.rows} onDrill={drill} height={spec.type === "hbar" ? Math.min(420, 60 + Math.min(m.result.rows.length, spec.top_n ?? 15) * 30) : 220} />
                      )}
                      {geo && (
                        <div className="chat-map"><SiteMap columns={m.result.columns} rows={m.result.rows} latKey={geo.latKey} lonKey={geo.lonKey} /></div>
                      )}
                      <ResultTable columns={m.result.columns} rows={m.result.rows} spec={spec}
                        onShowMap={spec?.map_key ? showOnMap : undefined} />
                    </>
                  );
                })()}

                {m.profileResults && m.profileResults.length > 0 && (
                  <div className="chat-profile">
                    <div className="chat-profile-head">
                      <b>{m.profilePlan?.territory_name ? `Profil ${m.profilePlan.territory_name}` : "Profil wilayah"}</b>
                      <span>{m.profileResults.filter((r) => r.status === "ok").length} dari {m.profileResults.length} sumber data berhasil</span>
                    </div>
                    <div className="chat-profile-grid">
                      {m.profileResults.map((pr, pi) => (
                        <div key={pi} className={`chat-profile-card ${pr.status === "ok" ? "" : "err"}`}>
                          <div className="chat-profile-card-head">
                            <span className="dot" style={{ background: DOMAIN_COLOR[pr.domain] || "var(--ds-chart-grey)" }} />
                            <b>{pr.section_title}</b>
                            <span>{pr.status === "ok" ? `${pr.row_count} baris` : "gagal"}</span>
                          </div>
                          {pr.status === "ok" && pr.chart && pr.chart.type !== "none" && (
                            <SmartChart spec={pr.chart} rows={pr.rows} height={180} bare />
                          )}
                          {pr.status === "ok" && pr.rows.length > 0 && (!pr.chart || pr.chart.type === "none" || pr.chart.type === "kpi") && (
                            <ResultTable columns={pr.columns} rows={pr.rows} spec={pr.chart} initialRows={5} />
                          )}
                          {pr.status !== "ok" && pr.error && <p className="chat-profile-err">{pr.error.slice(0, 140)}</p>}
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {m.locationResult && (
                  <div className="chat-loc">
                    {m.locationResult.kecProfile && (
                      <div className="chat-loc-block">
                        <b>{lang === "en" ? "Kecamatan profile" : "Profil kecamatan"}{m.locationResult.kecamatan?.kecamatan ? ` · ${m.locationResult.kecamatan.kecamatan}` : ""}</b>
                        <KecProfileCard profile={m.locationResult.kecProfile} isEN={lang === "en"} />
                      </div>
                    )}
                    {(["sites", "outlets"] as const).map((k) => {
                      const block = m.locationResult![k];
                      if (!block || block.rows.length === 0) return null;
                      const geo = detectLatLon(block.columns);
                      return (
                        <div key={k} className="chat-loc-block">
                          <b>{k === "sites" ? (lang === "en" ? "10 nearest sites" : "10 site terdekat") : (lang === "en" ? "10 nearest outlets" : "10 outlet terdekat")}</b>
                          {geo && <div className="chat-map"><SiteMap columns={block.columns} rows={block.rows} latKey={geo.latKey} lonKey={geo.lonKey} /></div>}
                          <NearestTable columns={block.columns} rows={block.rows} />
                        </div>
                      );
                    })}
                  </div>
                )}

                {m.error && (
                  <div className="chat-error" role="alert">
                    <b>Agent gagal menjawab.</b> {m.error}
                  </div>
                )}

                {m.sql && canViewSQL() && sqlVisible[i] && (
                  <pre className="chat-sql"><code>{m.sql}</code></pre>
                )}
                {showFlow && i === lastAssistant && pipelineFlow.length > 0 && (
                  <div className="chat-flow"><AgentFlow events={pipelineFlow} live={busy} tokenUsage={tokenUsage} /></div>
                )}

                {!m.status && (m.content || m.result) && (
                  <div className="chat-actions">
                    {m.result && m.result.rows.length > 0 && canExport() && (
                      <button className="ui-btn" onClick={() => exportXlsx(i)}><FileSpreadsheet size={20} strokeWidth={1.6} /> Export XLSX</button>
                    )}
                    {m.exportReady && canExport() ? (
                      <button className="ui-btn" onClick={() => downloadFromUrl(m.exportReady!.url, `bizplan-report.${m.exportReady!.format}`)}>
                        <FileText size={20} strokeWidth={1.6} /> Unduh {m.exportReady.format.toUpperCase()}
                      </button>
                    ) : m.result && canExport() ? (
                      <button className="ui-btn" disabled={busy} onClick={() => send("Buatkan laporan PDF dari hasil sebelumnya")}>
                        <FileText size={20} strokeWidth={1.6} /> Laporan PDF
                      </button>
                    ) : null}
                    {m.result && m.result.chart && m.result.chart.type !== "none" && (
                      <button className="ui-btn" onClick={() => pinToDashboard(i)} disabled={pinned[i]}>
                        <Pin size={20} strokeWidth={1.6} /> {pinned[i] ? "Tersemat di dashboard" : "Pin ke dashboard"}
                      </button>
                    )}
                    {m.result && (
                      <button className="ui-btn tint" onClick={() => watchThis(i)}><BellRing size={20} strokeWidth={1.6} /> Pantau &amp; beri alert</button>
                    )}
                    <span className="chat-actions-spacer" />
                    {m.sql && canViewSQL() && (
                      <button className="ui-iconbtn ghost" onClick={() => setSqlVisible((v) => ({ ...v, [i]: !v[i] }))}
                        aria-pressed={!!sqlVisible[i]} title="Lihat SQL"><Code2 size={16} /></button>
                    )}
                    {i === lastAssistant && pipelineFlow.length > 0 && canViewSQL() && (
                      <button className="ui-iconbtn ghost" onClick={() => setShowFlow((v) => !v)} aria-pressed={showFlow} title="Lihat alur agent"><Workflow size={16} /></button>
                    )}
                    <button className={`ui-iconbtn ghost ${liked[i] ? "on" : ""}`} onClick={() => setLiked((v) => ({ ...v, [i]: !v[i] }))}
                      aria-pressed={!!liked[i]} title="Jawaban membantu"><ThumbsUp size={16} /></button>
                    <button className="ui-iconbtn ghost" onClick={() => copyAnswer(i)} title="Salin jawaban">
                      {copied === i ? <Check size={16} /> : <Copy size={16} />}
                    </button>
                  </div>
                )}
              </article>
            </div>
          ))}

          {!busy && lastAssistant >= 0 && lastAssistant === messages.length - 1 && !messages[lastAssistant].error && (
            <div className="chat-followups">
              {followUps(messages[lastAssistant]).map((f) => (
                <button key={f.text} className="ui-chip outline-teal" onClick={() => f.text === "Tampilkan di peta" && messages[lastAssistant].result?.chart?.map_key
                  ? router.push("/map") : send(f.text)}>
                  <f.icon size={18} strokeWidth={1.7} /> {f.text}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="chat-composer">
        <div className="chat-input">
          <textarea
            ref={taRef}
            placeholder="Tanya apa saja tentang bisnis Jawa: revenue, site, market share…"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={handleKey}
            disabled={busy}
            rows={1}
            aria-label="Pertanyaan"
          />
          <div className="chat-tools">
            <input ref={fileInputRef} type="file" accept=".xlsx,.xls" hidden onChange={onFileChosen} />
            <div className="chat-attach" ref={attachRef}>
              <button className="ui-iconbtn ghost chat-tool" onClick={() => setAttachOpen((v) => !v)} disabled={busy || locating}
                aria-label="Lampiran" aria-haspopup="menu" aria-expanded={attachOpen}>
                {locating ? <span className="chat-spinner" /> : <Paperclip size={18} />}
              </button>
              {attachOpen && (
                <div className="ui-popover chat-attach-menu" role="menu">
                  <button role="menuitem" onClick={shareLocation}><MapPin size={16} /> Bagikan lokasi saya<small>Profil kecamatan, site & outlet terdekat</small></button>
                  <button role="menuitem" onClick={onPickFile}><Upload size={16} /> Unggah Excel<small>File .xlsx untuk dianalisis</small></button>
                </div>
              )}
            </div>
            <span className="ui-chip teal"><MapPin size={16} /> Lokasi: Region Jawa</span>
            {lang === "en" && <span className="ui-chip chat-hide-sm"><Globe size={16} /> English</span>}
            <span className="chat-actions-spacer" />
            <button className={`ui-iconbtn ghost chat-tool ${listening ? "on" : ""}`} onClick={voiceInput} disabled={busy} aria-label="Bicara">
              <Mic size={18} />
            </button>
            {busy ? (
              <button className="chat-send stop" onClick={stop} aria-label="Hentikan"><Square size={16} fill="currentColor" /></button>
            ) : (
              <button className="chat-send" onClick={() => send()} disabled={!input.trim()} aria-label="Kirim"><Send size={18} /></button>
            )}
          </div>
        </div>
        <p className="chat-disclaimer">Agent bisa keliru. Verifikasi angka penting sebelum dibagikan.</p>
      </div>
    </AppShell>
  );
}
