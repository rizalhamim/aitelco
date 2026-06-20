"use client";
import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import DataTable from "./components/DataTable";
import ChartPanel from "./components/ChartPanel";
import SiteMap from "./components/SiteMap";

function detectLatLon(columns: string[]): { latKey: string; lonKey: string } | null {
  const lat = columns.find((c) => /^lat(itude)?$/i.test(c) || /_lat(itude)?$/i.test(c) || /(addr_)?latitude/i.test(c));
  const lon = columns.find((c) => /^lon(g|gitude)?$/i.test(c) || /_lon(g|gitude)?$/i.test(c) || /(addr_)?longitude/i.test(c));
  if (lat && lon) return { latKey: lat, lonKey: lon };
  return null;
}
import Markdown from "./components/Markdown";
import AgentFlow, { type FlowEvent } from "./components/AgentFlow";
import { isLoggedIn, getUser, getAccessToken, logout, isAdmin, canViewSQL, canExport, authFetch } from "@/lib/auth";

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

type Domain = { key: string; label: string; description: string; table_count: number; tables: string[] };

type Result = {
  columns: string[];
  rows: Record<string, unknown>[];
  row_count: number;
  sql?: string;
  bytes_processed?: number;
};

type Msg = {
  role: "user" | "assistant";
  content: string;
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

const EXAMPLES = [
  { label: "🏙️ Profile Kota", text: "Tampilkan profile lengkap kota Surabaya" },
  { label: "Site Performance", text: "Top 5 kecamatan dengan revenue data tertinggi 30 hari terakhir" },
  { label: "Network 5G", text: "Berapa total traffic 5G per region di bulan terakhir?" },
  { label: "Competitive", text: "Bandingkan market share IM3 vs Telkomsel per kabkota di bulan terakhir" },
  { label: "Forecast", text: "Tampilkan forecast revenue untuk top 5 micro-cluster bulan depan" },
];

export default function Home() {
  const router = useRouter();
  const [domains, setDomains] = useState<Domain[]>([]);
  const [messages, setMessages] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [pipelineFlow, setPipelineFlow] = useState<FlowEvent[]>([]);
  const [tokenUsage, setTokenUsage] = useState<{prompt: number; completion: number; total: number}>({prompt: 0, completion: 0, total: 0});
  const [sqlVisible, setSqlVisible] = useState<Record<number, boolean>>({});
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [authChecked, setAuthChecked] = useState(false);
  const [historyList, setHistoryList] = useState<{ session_id: string; title: string; message_count: number; updated_at: string | null }[]>([]);
  const [activeSession, setActiveSession] = useState<string>("");
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [accountMenuOpen, setAccountMenuOpen] = useState(false);
  const [darkMode, setDarkMode] = useState(false);
  const [attachOpen, setAttachOpen] = useState(false);
  const [locating, setLocating] = useState(false);
  const [lang, setLang] = useState<"id" | "en">("id");
  const abortRef = useRef<AbortController | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);
  const sessionIdRef = useRef<string>("");
  const accountMenuRef = useRef<HTMLDivElement>(null);
  const accountMenuRefDesktop = useRef<HTMLDivElement>(null);
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

  useEffect(() => {
    if (typeof window !== "undefined") {
      const isDark = localStorage.getItem("theme") === "dark" || 
                    (!localStorage.getItem("theme") && window.matchMedia("(prefers-color-scheme: dark)").matches);
      setDarkMode(isDark);
      if (isDark) {
        document.documentElement.classList.add("dark");
        document.documentElement.setAttribute("data-theme", "dark");
      } else {
        document.documentElement.classList.remove("dark");
        document.documentElement.setAttribute("data-theme", "light");
      }
    }
  }, []);

  const toggleDarkMode = useCallback(() => {
    setDarkMode((prev) => {
      const next = !prev;
      localStorage.setItem("theme", next ? "dark" : "light");
      if (next) {
        document.documentElement.classList.add("dark");
        document.documentElement.setAttribute("data-theme", "dark");
      } else {
        document.documentElement.classList.remove("dark");
        document.documentElement.setAttribute("data-theme", "light");
      }
      return next;
    });
  }, []);

  function chooseLang(l: "id" | "en") {
    setLang(l);
    try { localStorage.setItem("telco_ai_lang", l); } catch { /* ignore */ }
  }

  useEffect(() => {
    if (!authChecked) return;
    authFetch(`/api/domains`)
      .then((r) => r.json())
      .then((d) => setDomains(d.domains || []))
      .catch(() => setDomains([]));
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
    loadHistoryList();
    // Restore the last conversation from the DB so a page reload doesn't lose it.
    if (restoredSid) {
      loadSession(restoredSid, { silent: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [authChecked]);

  async function loadHistoryList() {
    try {
      const res = await authFetch("/api/history/sessions", {
        headers: { ...(getAccessToken() ? { Authorization: `Bearer ${getAccessToken()}` } : {}) },
      });
      if (!res.ok) return;
      const data = await res.json();
      // endpoint returns a bare array; tolerate {sessions:[...]} too
      const list = Array.isArray(data) ? data : (data.sessions || []);
      setHistoryList(list);
    } catch {
      /* ignore */
    }
  }

  async function loadSession(sid: string, opts?: { silent?: boolean }) {
    if (busy) return;
    const silent = opts?.silent === true;
    if (!silent) {
      setLoadingHistory(true);
      setSidebarOpen(false);
    }
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
    } finally {
      if (!silent) setLoadingHistory(false);
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
    setSidebarOpen(false);
  }

  // smooth-scroll to bottom on any chat change
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const id = requestAnimationFrame(() => {
      el.scrollTo({ top: el.scrollHeight, behavior: "smooth" });
    });
    return () => cancelAnimationFrame(id);
  }, [messages, pipelineFlow, busy]);

  // close the account menu when clicking outside it
  useEffect(() => {
    if (!accountMenuOpen) return;
    function onDocClick(e: MouseEvent) {
      const t = e.target as Node;
      const inMobile = accountMenuRef.current?.contains(t);
      const inDesktop = accountMenuRefDesktop.current?.contains(t);
      if (!inMobile && !inDesktop) setAccountMenuOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    return () => document.removeEventListener("mousedown", onDocClick);
  }, [accountMenuOpen]);

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

    const userMsg: Msg = { role: "user", content: msg };
    const assistantMsg: Msg = { role: "assistant", content: "", status: "Analyzing…" };
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
              },
            });
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
            update({ status: undefined });
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

  const subtitle = useMemo(
    () => `${domains.length || 13} AI agents · Multi-domain analytics`,
    [domains.length],
  );

  if (!authChecked) {
    return (
      <div style={{
        minHeight: "100vh",
        background: "#0a0a0f",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: "#888",
      }}>
        Loading...
      </div>
    );
  }

  return (
    <div className="app-shell">
      {/* Summary email toast notification */}
      {summaryMsg && (
        <div className={`summary-toast ${summaryStatus}`} role="status">
          <span className="summary-toast-ico">{summaryStatus === "success" ? "✓" : summaryStatus === "error" ? "!" : "…"}</span>
          <span>{summaryMsg}</span>
        </div>
      )}
      {/* Mobile top bar — only visible on <=920px */}
      <div className="mobile-topbar">
        <button className="hamburger" onClick={() => setSidebarOpen(true)} aria-label="Open menu">
          <span /><span /><span />
        </button>
        <div className="mobile-brand">
          <div className="logo-dot" />
          <span className="brand-name">Bizplan Java Agent</span>
        </div>
        <button className="mobile-newchat" onClick={newChat} aria-label="New chat" disabled={busy}>
          + Baru
        </button>
        {authChecked && getUser() && (
          <button className="map-fab-btn account-fab-mobile" onClick={() => router.push("/map")} title="Map Query" aria-label="Map Query">
            <span className="map-fab-ico">◎</span>
          </button>
        )}
                    {authChecked && getUser() && (
                      <div className="account-fab account-fab-mobile" ref={accountMenuRef}>
                        <button
                          className="account-fab-btn"
                          onClick={() => setAccountMenuOpen((v) => !v)}
                          aria-haspopup="menu"
                          aria-expanded={accountMenuOpen}
                          title="Menu"
                        >
                          <span className="account-avatar">
                            {(getUser()?.full_name || getUser()?.username || "?").charAt(0).toUpperCase()}
                          </span>
                          <span className="account-name-inline">{getUser()?.full_name || getUser()?.username}</span>
                          <span className="account-caret">▾</span>
                        </button>
                        {accountMenuOpen && (
                          <div className="account-menu" role="menu">
                            <div className="account-menu-header">
                              <span className="account-avatar lg">
                                {(getUser()?.full_name || getUser()?.username || "?").charAt(0).toUpperCase()}
                              </span>
                              <div>
                                <div className="account-menu-name">{getUser()?.full_name || getUser()?.username}</div>
                                <div className="account-menu-role">{isAdmin() ? "Administrator" : (getUser()?.role || "User")}</div>
                              </div>
                            </div>

                            {/* Response language toggle */}
                            <div className="account-menu-label">Response Language</div>
                            <div className="lang-toggle">
                              <button
                                className={`lang-opt ${lang === "id" ? "active" : ""}`}
                                onClick={() => chooseLang("id")}
                                aria-pressed={lang === "id"}
                              >🇮🇩 ID</button>
                              <button
                                className={`lang-opt ${lang === "en" ? "active" : ""}`}
                                onClick={() => chooseLang("en")}
                                aria-pressed={lang === "en"}
                              >🇬🇧 EN</button>
                            </div>
                            <div className="account-menu-divider" />

                            {/* Chat actions */}
                            <div className="account-menu-label">Chat</div>
                            <button className="account-menu-item" role="menuitem"
                              disabled={busy}
                              onClick={() => { setAccountMenuOpen(false); refreshChat(); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-ink)" }}>↻</span> Refresh (chat baru)
                            </button>
                            <button className="account-menu-item" role="menuitem"
                              disabled={summarySending || busy || messages.length === 0}
                              onClick={() => { setAccountMenuOpen(false); summarizeAndSendMail(); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-red)" }}>✉</span>
                              {summarySending ? " Meringkas…" : " Summary & Send Mail"}
                            </button>

                            <div className="account-menu-divider" />
                            {/* Account */}
                            <div className="account-menu-label">Account</div>
                            <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/map"); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-magenta)" }}>◎</span> Map Query
                            </button>
                            <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/reports"); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-teal)" }}>▦</span> Performance Outlook
                            </button>
                            <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/site"); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-teal)" }}>📡</span> Site Performance
                            </button>
                            <button className="account-menu-item" role="menuitem" onClick={() => { toggleDarkMode(); setAccountMenuOpen(false); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-yellow)" }}>{darkMode ? "☼" : "☾"}</span> {darkMode ? "Light Mode" : "Dark Mode"}
                            </button>
                            <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/profile"); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-teal)" }}>◐</span> Profile
                            </button>
                            {isAdmin() && (
                              <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/admin"); }}>
                                <span className="ami-ico" style={{ color: "var(--ioh-yellow)" }}>★</span> Admin
                              </button>
                            )}
                            <button className="account-menu-item logout" role="menuitem" onClick={() => { setAccountMenuOpen(false); logout(); }}>
                              <span className="ami-ico" style={{ color: "var(--ioh-red)" }}>⎋</span> Logout
                            </button>
                          </div>
                        )}
                      </div>
                    )}
      </div>

      {/* Sidebar overlay backdrop */}
      {sidebarOpen && <div className="sidebar-backdrop" onClick={() => setSidebarOpen(false)} />}

      {/* Sidebar */}
      <aside className={`sidebar ${sidebarOpen ? "open" : ""}`}>
        <div className="sidebar-top-row">
          <div className="sidebar-brand">
            <div className="logo-dot" />
            <div>
              <div className="brand-name">Bizplan Java Agent</div>
              <div className="brand-sub">AI Agent · Java</div>
            </div>
          </div>
          <button className="sidebar-close" onClick={() => setSidebarOpen(false)} aria-label="Close menu">✕</button>
        </div>

        {/* Pipeline takes over sidebar when active */}
        {(busy || pipelineFlow.length > 0) ? (
          <div className="sidebar-pipeline-wrap">
            <AgentFlow events={pipelineFlow} live={busy} tokenUsage={tokenUsage} />
          </div>
        ) : (
          <>
            <button className="new-chat-btn" onClick={newChat}>
              <span className="new-chat-plus">+</span> Chat Baru
            </button>

            <div className="history-section">
              <h4 style={{ marginBottom: 8, fontFamily: "var(--font-display)" }}>Riwayat Chat</h4>
              <div className="history-list">
                {loadingHistory && <div className="history-empty">Memuat…</div>}
                {!loadingHistory && historyList.length === 0 && (
                  <div className="history-empty">Belum ada riwayat</div>
                )}
                {!loadingHistory && historyList.map((h) => (
                  <button
                    key={h.session_id}
                    className={`history-item ${h.session_id === activeSession ? "active" : ""}`}
                    onClick={() => loadSession(h.session_id)}
                    title={h.title}
                  >
                    <span className="history-title">{h.title || "Untitled chat"}</span>
                    <span className="history-meta">{h.message_count} pesan</span>
                  </button>
                ))}
              </div>
            </div>
          </>
        )}

        <div style={{ marginTop: "auto", paddingTop: 12, borderTop: "1px solid var(--ioh-rule)" }}>
          <div className="confidential">Confidential · Internal Use Only</div>
        </div>
      </aside>

      {/* Main */}
      <main className="main">
        <header className="app-header">
          <div>
            <div className="title">Bizplan Java Agent</div>
            <div className="subtitle">{subtitle}</div>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            {authChecked && getUser() && (
              <button
                className="map-fab-btn account-fab-desktop"
                onClick={() => router.push("/map")}
                title="Map Query"
              >
                <span className="map-fab-ico">◎</span>
                <span className="map-fab-label">Map</span>
              </button>
            )}
            {authChecked && getUser() && (
              <div className="account-fab account-fab-desktop" ref={accountMenuRefDesktop}>
                <button
                  className="account-fab-btn"
                  onClick={() => setAccountMenuOpen((v) => !v)}
                  aria-haspopup="menu"
                  aria-expanded={accountMenuOpen}
                  title="Menu"
                >
                  <span className="account-avatar">
                    {(getUser()?.full_name || getUser()?.username || "?").charAt(0).toUpperCase()}
                  </span>
                  <span className="account-name-inline">{getUser()?.full_name || getUser()?.username}</span>
                  <span className="account-caret">▾</span>
                </button>
                {accountMenuOpen && (
                  <div className="account-menu" role="menu">
                    <div className="account-menu-header">
                      <span className="account-avatar lg">
                        {(getUser()?.full_name || getUser()?.username || "?").charAt(0).toUpperCase()}
                      </span>
                      <div>
                        <div className="account-menu-name">{getUser()?.full_name || getUser()?.username}</div>
                        <div className="account-menu-role">{isAdmin() ? "Administrator" : (getUser()?.role || "User")}</div>
                      </div>
                    </div>
                    <div className="account-menu-label">Response Language</div>
                    <div className="lang-toggle">
                      <button className={`lang-opt ${lang === "id" ? "active" : ""}`} onClick={() => chooseLang("id")} aria-pressed={lang === "id"}>🇮🇩 ID</button>
                      <button className={`lang-opt ${lang === "en" ? "active" : ""}`} onClick={() => chooseLang("en")} aria-pressed={lang === "en"}>🇬🇧 EN</button>
                    </div>
                    <div className="account-menu-divider" />
                    <div className="account-menu-label">Chat</div>
                    <button className="account-menu-item" role="menuitem" disabled={busy} onClick={() => { setAccountMenuOpen(false); refreshChat(); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-ink)" }}>↻</span> Refresh (chat baru)
                    </button>
                    <button className="account-menu-item" role="menuitem" disabled={summarySending || busy || messages.length === 0} onClick={() => { setAccountMenuOpen(false); summarizeAndSendMail(); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-red)" }}>✉</span>{summarySending ? " Meringkas…" : " Summary & Send Mail"}
                    </button>
                    <div className="account-menu-divider" />
                    <div className="account-menu-label">Account</div>
                    <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/map"); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-magenta)" }}>◎</span> Map Query
                    </button>
                    <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/reports"); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-teal)" }}>▦</span> Performance Outlook
                    </button>
                    <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/site"); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-teal)" }}>📡</span> Site Performance
                    </button>
                    <button className="account-menu-item" role="menuitem" onClick={() => { toggleDarkMode(); setAccountMenuOpen(false); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-yellow)" }}>{darkMode ? "☼" : "☾"}</span> {darkMode ? "Light Mode" : "Dark Mode"}
                    </button>
                    <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/profile"); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-teal)" }}>◐</span> Profile
                    </button>
                    {isAdmin() && (
                      <button className="account-menu-item" role="menuitem" onClick={() => { setAccountMenuOpen(false); router.push("/admin"); }}>
                        <span className="ami-ico" style={{ color: "var(--ioh-yellow)" }}>★</span> Admin
                      </button>
                    )}
                    <button className="account-menu-item logout" role="menuitem" onClick={() => { setAccountMenuOpen(false); logout(); }}>
                      <span className="ami-ico" style={{ color: "var(--ioh-red)" }}>⎋</span> Logout
                    </button>
                  </div>
                )}
              </div>
            )}
          </div>
        </header>

        <div className="messages" ref={scrollRef}>
          <div className="messages-inner">
            {messages.length === 0 && (
              <div className="welcome">
                <div className="welcome-hero">
                  <div className="eyebrow">Built for analysts.</div>
                  <h1>
                    Ask data, <span className="red">get answers.</span>
                  </h1>
                  <p className="lede">
                    Tanyakan apa pun tentang revenue site, market share kompetitor,
                    performa 5G, forecast, atau KPI eksekutif. AI Orchestrator akan
                    menganalisis pertanyaan Anda dan mengarahkan ke agent yang tepat
                    untuk memberikan jawaban akurat dalam hitungan detik.
                  </p>
                  <div className="welcome-stats">
                    <div>
                      <div className="stat-num">13</div>
                      <div className="stat-lbl">AI Agents</div>
                    </div>
                    <div>
                      <div className="stat-num">11</div>
                      <div className="stat-lbl">Domains</div>
                    </div>
                    <div>
                      <div className="stat-num">~15s</div>
                      <div className="stat-lbl">Avg Response</div>
                    </div>
                    <div>
                      <div className="stat-num">24/7</div>
                      <div className="stat-lbl">Available</div>
                    </div>
                  </div>
                </div>
                <div className="welcome-aside">
                  <div className="examples-eyebrow eyebrow">Try a question</div>
                  <div className="examples">
                    {EXAMPLES.map((ex) => (
                      <button key={ex.text} className="example" onClick={() => send(ex.text)}>
                        <span className="ex-label">{ex.label}</span>
                        <span className="ex-text">{ex.text}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {messages.map((m, i) => (
              <div key={i} className={`msg ${m.role === "user" ? "msg-user" : "msg-assistant"}`}>
                {m.role === "user" ? (
                  <div className="bubble">{m.content}</div>
                ) : (
                  <>
                    <div className="trace-strip">
                      <div className="trace-pills">
                        {m.domain && m.domain !== "none" && (
                          <span
                            className="pill"
                            style={{
                              background: DOMAIN_COLOR[m.domain] || "var(--ioh-grey)",
                              color: "var(--ioh-white)",
                            }}
                          >
                            {m.domain === "PROFILE"
                              ? `🏙️ Profile: ${m.profilePlan?.territory_name || ""}`
                              : (m.domainLabel || m.domain)}
                          </span>
                        )}
                        {m.domain === "none" && <span className="pill grey">General</span>}
                        {m.status && (
                          <span className="status-row">
                            <span className="status-dot" />
                            {m.status}
                          </span>
                        )}
                      </div>

                      {/* SQL toggle — admin/analyst only */}
                      {m.sql && canViewSQL() && (
                        <div className="sql-panel-wrap">
                          <button
                            className="sql-toggle"
                            onClick={() => setSqlVisible(prev => ({...prev, [i]: !prev[i]}))}
                          >
                            {sqlVisible[i] ? "▾ Hide SQL" : "▸ Show SQL"}
                          </button>
                          {sqlVisible[i] && (
                            <div className="sql-panel tnum">
                              <span className="sql-label">SQL Query</span>
                              {m.sql}
                            </div>
                          )}
                        </div>
                      )}

                      {m.result && m.result.rows.length > 0 && (() => {
                        const geo = detectLatLon(m.result.columns);
                        return (
                          <>
                            {geo && (
                              <SiteMap
                                columns={m.result.columns}
                                rows={m.result.rows}
                                latKey={geo.latKey}
                                lonKey={geo.lonKey}
                              />
                            )}
                            <ChartPanel columns={m.result.columns} rows={m.result.rows} />
                            <DataTable
                              columns={m.result.columns}
                              rows={m.result.rows}
                            />
                          </>
                        );
                      })()}

                      {/* Export download — admin/analyst/data_user only */}
                      {m.exportReady && canExport() && (
                        <div className="export-bar">
                          <button
                            className="export-btn"
                            onClick={() => downloadFromUrl(
                              m.exportReady!.url,
                              `ioh_report.${m.exportReady!.format}`
                            )}
                          >
                            {m.exportReady.format === "pdf" ? "📄" : "📊"}{" "}
                            Download {m.exportReady.format.toUpperCase()}
                          </button>
                        </div>
                      )}

                      {/* Profile domain results grid */}
                      {m.profileResults && m.profileResults.length > 0 && (
                        <div className="profile-grid">
                          <div className="profile-grid-header">
                            <span className="profile-grid-title">📊 Data Sources ({m.profileResults.filter(r => r.status === "ok").length}/{m.profileResults.length} success)</span>
                          </div>
                          <div className="profile-cards">
                            {m.profileResults.map((pr, pi) => (
                              <div key={pi} className={`profile-card ${pr.status === "ok" ? "ok" : "err"}`}>
                                <div className="profile-card-head">
                                  <span className="profile-card-dot" style={{ background: DOMAIN_COLOR[pr.domain] || "var(--ioh-grey)" }} />
                                  <span className="profile-card-title">{pr.section_title}</span>
                                  <span className={`profile-card-badge ${pr.status}`}>
                                    {pr.status === "ok" ? `${pr.row_count} rows` : "error"}
                                  </span>
                                </div>
                                {pr.status === "ok" && pr.rows.length > 0 && (
                                  <DataTable
                                    columns={pr.columns}
                                    rows={pr.rows.slice(0, 10)}
                                    bytes={0}
                                  />
                                )}
                                {pr.status !== "ok" && pr.error && (
                                  <div className="profile-card-error">{pr.error.slice(0, 120)}</div>
                                )}
                              </div>
                            ))}
                          </div>
                        </div>
                      )}

                      {m.error && (
                        <div className="callout danger">
                          <span className="label">Error</span>
                          {m.error}
                        </div>
                      )}
                    </div>
                    {m.content && <Markdown text={m.content} />}
                    {m.locationResult && (
                      <div className="loc-result">
                        {m.locationResult.kecProfile && (
                          <div className="loc-block">
                            <div className="loc-block-title">🏙️ {lang === "en" ? "Kecamatan Profile" : "Profil Kecamatan"}{m.locationResult.kecamatan?.kecamatan ? ` · ${m.locationResult.kecamatan.kecamatan}` : ""}</div>
                            <KecProfileCard profile={m.locationResult.kecProfile} isEN={lang === "en"} />
                          </div>
                        )}
                        {m.locationResult.sites && m.locationResult.sites.rows.length > 0 && (
                          <div className="loc-block">
                            <div className="loc-block-title">📡 {lang === "en" ? "10 Nearest Sites" : "10 Site Terdekat"}</div>
                            {(() => {
                              const geo = detectLatLon(m.locationResult!.sites!.columns);
                              return geo ? (
                                <SiteMap columns={m.locationResult!.sites!.columns} rows={m.locationResult!.sites!.rows} latKey={geo.latKey} lonKey={geo.lonKey} />
                              ) : null;
                            })()}
                            <NearestTable columns={m.locationResult.sites.columns} rows={m.locationResult.sites.rows} />
                          </div>
                        )}
                        {m.locationResult.outlets && m.locationResult.outlets.rows.length > 0 && (
                          <div className="loc-block">
                            <div className="loc-block-title">🏪 {lang === "en" ? "10 Nearest Outlets" : "10 Outlet Terdekat"}</div>
                            {(() => {
                              const geo = detectLatLon(m.locationResult!.outlets!.columns);
                              return geo ? (
                                <SiteMap columns={m.locationResult!.outlets!.columns} rows={m.locationResult!.outlets!.rows} latKey={geo.latKey} lonKey={geo.lonKey} />
                              ) : null;
                            })()}
                            <NearestTable columns={m.locationResult.outlets.columns} rows={m.locationResult.outlets.rows} />
                          </div>
                        )}
                      </div>
                    )}
                  </>
                )}
              </div>
            ))}
          </div>
        </div>

        <div className="composer">
          <div className="composer-inner">
            <textarea
              placeholder="Tanya tentang revenue, network, market share, forecast, KPI…  (Enter untuk kirim, Shift+Enter untuk baris baru)"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              onKeyDown={handleKey}
              disabled={busy}
              rows={1}
              autoFocus
            />
            <input ref={fileInputRef} type="file" accept=".xlsx,.xls" style={{ display: "none" }} onChange={onFileChosen} />
            <div className="attach-wrap" ref={attachRef}>
              <button
                className="attach-btn"
                onClick={() => setAttachOpen((v) => !v)}
                disabled={busy || locating}
                title="Lampiran"
                aria-haspopup="menu"
                aria-expanded={attachOpen}
              >
                {locating ? "…" : "+"}
              </button>
              {attachOpen && (
                <div className="attach-menu" role="menu">
                  <button className="attach-item" role="menuitem" onClick={shareLocation}>
                    <span className="attach-ico" style={{ color: "var(--ioh-red)" }}>📍</span>
                    <span><b>Share Location</b><br /><span className="attach-sub">Profil kecamatan + site & outlet terdekat</span></span>
                  </button>
                  <button className="attach-item" role="menuitem" onClick={onPickFile}>
                    <span className="attach-ico" style={{ color: "var(--ioh-teal)" }}>📊</span>
                    <span><b>Upload Excel</b><br /><span className="attach-sub">File .xlsx untuk dianalisa</span></span>
                  </button>
                </div>
              )}
            </div>
            {busy ? (
              <button className="send stop" onClick={stop} title="Batalkan request">
                Stop
              </button>
            ) : (
              <button
                className="send"
                onClick={() => send()}
                title={!input.trim() ? "Ketik pertanyaan dulu" : "Kirim (Enter)"}
              >
                Send
              </button>
            )}
          </div>
          <div className="hint">Enter to send · Shift+Enter untuk baris baru</div>
        </div>
      </main>
    </div>
  );
}
