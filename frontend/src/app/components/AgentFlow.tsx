"use client";
import { useEffect, useMemo, useRef, useState, useCallback } from "react";

export type FlowEvent = {
  kind:
    | "user"
    | "analyst"
    | "router"
    | "agent"
    | "general"
    | "sql_write"
    | "bq_exec"
    | "bq_done"
    | "synth"
    | "export"
    | "retry"
    | "reflect"
    | "scope"
    | "reroute"
    | "error"
    | "done";
  t: number;
  label: string;
  detail?: string;
  domain?: string;
  feedback?: string;
  meta?: Record<string, string | number | boolean | null>;
};

const COLOR: Record<string, string> = {
  user: "#FFFFFF", analyst: "#FF6B35", router: "#0E8579",
  agent: "#15A697", general: "#8A9996", sql_write: "#F5A623",
  bq_exec: "#33BCAD", bq_done: "#33BCAD", synth: "#0A6A5F",
  export: "#6C63FF", retry: "#F5A623", reflect: "#2FA84F",
  scope: "#0E8579", reroute: "#FF6B35",
  error: "#E13838", done: "#33BCAD",
};

const DOMAIN_COLOR: Record<string, string> = {
  site_performance: "#15A697", network: "#0E8579", competitive: "#0A6A5F",
  reporting: "#F5A623", forecast: "#33BCAD", customer_hvc: "#15A697",
  marketing: "#0E8579", sales_distribution: "#0A6A5F",
  fixed_broadband: "#33BCAD", geo: "#F5A623", kpi_summary: "#15A697",
};

const ICON: Record<string, string> = {
  user: "U", analyst: "A", router: "◆", agent: "▲", general: "✺",
  sql_write: "{}", bq_exec: "≡", bq_done: "✓", synth: "✦",
  export: "↓", retry: "↻", reflect: "?", scope: "◈", reroute: "⇄",
  error: "!", done: "✓",
};

const NICE_LABEL: Record<string, string> = {
  site_performance: "Site Perf", network: "Network", competitive: "Competitive",
  reporting: "Reporting", forecast: "Forecast", customer_hvc: "HVC",
  marketing: "Marketing", sales_distribution: "Sales & Dist",
  fixed_broadband: "Broadband", geo: "Geography", kpi_summary: "Exec KPI",
  reference: "Reference", misc: "Misc",
};

const ROLE: Record<string, string> = {
  user: "QUERY", analyst: "ANALYST", router: "ORCHESTRATOR",
  agent: "DOMAIN AGENT", general: "DIRECT REPLY", sql_write: "QUERY BUILDER",
  bq_exec: "DATA ENGINE", bq_done: "DATA RESULT", synth: "SYNTHESIZER",
  export: "EXPORT", retry: "SELF-HEAL", reflect: "QUALITY CHECK",
  scope: "DOMAIN CHECK", reroute: "RE-ROUTE",
  error: "ERROR", done: "DELIVERED",
};

const ROLE_DESC: Record<string, string> = {
  user: "Pertanyaan diterima",
  analyst: "Memvalidasi & memperkaya pertanyaan",
  router: "Menentukan domain & agent terbaik",
  agent: "Menangani domain spesifik",
  general: "Menjawab pertanyaan umum",
  sql_write: "Menyusun query data optimal",
  bq_exec: "Mengambil data dari database",
  bq_done: "Data berhasil diterima",
  synth: "Merangkai jawaban akhir",
  export: "Membuat file export",
  retry: "Memperbaiki & mencoba ulang",
  reflect: "Memeriksa relevansi & mencari jawaban terbaik",
  scope: "Memastikan domain memiliki datanya",
  reroute: "Mengalihkan ke domain yang lebih tepat",
  error: "Terjadi kesalahan",
  done: "Jawaban siap dikirim",
};

function edgeLabel(from: string, to: string, toLabel?: string): string {
  const MAP: Record<string, string> = {
    "user→router": "RECEIVE", "user→analyst": "ANALYZE",
    "router→analyst": "VALIDATE", "analyst→router": "ROUTE",
    "router→agent": `→ ${toLabel || "Agent"}`, "router→general": "REPLY",
    "agent→sql_write": "BUILD QUERY", "sql_write→bq_exec": "FETCH DATA",
    "bq_exec→bq_done": "RESULT", "bq_done→synth": "SUMMARIZE",
    "synth→done": "DELIVER", "synth→export": "EXPORT", "bq_done→done": "DELIVER",
  };
  const key = `${from}→${to}`;
  if (MAP[key]) return MAP[key];
  if (to === "synth") return "SUMMARIZE";
  if (to === "retry") return "RETRY";
  if (to === "error") return "FAIL";
  if (to === "done") return "DELIVER";
  return "→";
}

interface VNode {
  id: string; label: string; sublabel?: string;
  kind: FlowEvent["kind"]; color: string; icon: string;
  parentIdx?: number;
  feedback?: string;
  meta?: Record<string, string | number | boolean | null>;
  startedAt: number;
  duration?: number;
}

function buildNodes(events: FlowEvent[]): VNode[] {
  const seen = new Set<string>();
  const nodes: VNode[] = [];
  let analystIdx: number | undefined, routerIdx: number | undefined, agentIdx: number | undefined;

  for (let ei = 0; ei < events.length; ei++) {
    const ev = events[ei];
    const key = ev.kind === "agent" ? `agent:${ev.domain}` : ev.kind;
    if (seen.has(key) && ev.kind !== "retry") continue;
    seen.add(key);

    let label = ev.label;
    let color = COLOR[ev.kind] || "#8A9996";
    if (ev.kind === "agent" && ev.domain) {
      label = NICE_LABEL[ev.domain] || ev.domain;
      color = DOMAIN_COLOR[ev.domain] || "#15A697";
    }

    let parentIdx: number | undefined;
    if (nodes.length > 0) {
      if (ev.kind === "user") parentIdx = undefined;
      else if (ev.kind === "analyst") parentIdx = nodes.length - 1;
      else if (ev.kind === "router") parentIdx = analystIdx ?? nodes.length - 1;
      else if (ev.kind === "agent" || ev.kind === "general") parentIdx = routerIdx;
      else if (ev.kind === "export") parentIdx = nodes.length - 1;
      else parentIdx = agentIdx ?? routerIdx ?? nodes.length - 1;
    }

    if (nodes.length > 0) {
      const prev = nodes[nodes.length - 1];
      if (prev.duration === undefined) {
        prev.duration = (ev.t - prev.startedAt) / 1000;
      }
    }

    nodes.push({
      id: `${key}-${nodes.length}`, label, sublabel: ev.detail, kind: ev.kind,
      color, icon: ICON[ev.kind] || "●", parentIdx,
      feedback: ev.feedback, meta: ev.meta,
      startedAt: ev.t,
    });
    if (ev.kind === "analyst") analystIdx = nodes.length - 1;
    if (ev.kind === "router") routerIdx = nodes.length - 1;
    if (ev.kind === "agent" || ev.kind === "general") agentIdx = nodes.length - 1;
  }
  return nodes;
}

function LiveTimer({ startedAt }: { startedAt: number }) {
  const [now, setNow] = useState(startedAt);
  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 100);
    return () => window.clearInterval(id);
  }, []);
  const elapsed = ((now - startedAt) / 1000).toFixed(1);
  return <span className="pv-live-timer">{elapsed}s</span>;
}

function DurationBadge({ seconds }: { seconds: number }) {
  return <span className="pv-duration">{seconds.toFixed(1)}s</span>;
}

type Props = {
  events: FlowEvent[];
  live: boolean;
  tokenUsage?: { prompt: number; completion: number; total: number };
};

export default function AgentFlow({ events, live, tokenUsage }: Props) {
  const nodes = useMemo(() => buildNodes(events), [events]);
  const scrollRef = useRef<HTMLDivElement>(null);
  const prevCountRef = useRef(0);

  const scrollToBottom = useCallback(() => {
    const el = scrollRef.current;
    if (el) requestAnimationFrame(() => { el.scrollTop = el.scrollHeight; });
  }, []);

  useEffect(() => {
    if (nodes.length > prevCountRef.current) {
      scrollToBottom();
    }
    prevCountRef.current = nodes.length;
  }, [nodes.length, scrollToBottom]);

  const isDone = nodes.some(n => n.kind === "done");
  const isError = nodes.some(n => n.kind === "error");
  const t0 = nodes.length > 0 ? nodes[0].startedAt : 0;
  const tEnd = nodes.length > 0 ? nodes[nodes.length - 1].startedAt : 0;
  const totalElapsed = t0 > 0 ? ((tEnd - t0) / 1000).toFixed(1) : "0.0";

  if (nodes.length === 0) {
    return (
      <div className="pv-panel">
        <div className="pv-header">
          <span className="pv-title">Agent Pipeline</span>
          <span className="pv-badge idle">IDLE</span>
        </div>
        <div className="pv-idle">
          <div className="pv-idle-orb" />
          <div className="pv-idle-text">
            Pipeline akan aktif saat Anda mengirim pertanyaan
          </div>
          <div className="pv-idle-steps">
            {["Orchestrator", "Analyst", "Domain Agent", "Query Builder", "Data Engine", "Answer"].map((s, i) => (
              <div key={s} className="pv-idle-step">
                <div className="pv-idle-dot" />
                <span>{s}</span>
                {i < 5 && <div className="pv-idle-line" />}
              </div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  const lastNode = nodes[nodes.length - 1];
  const statusText = isError
    ? "Error"
    : isDone
      ? `Selesai · ${totalElapsed}s total`
      : lastNode
        ? ROLE_DESC[lastNode.kind] || lastNode.label
        : "Starting…";

  return (
    <div className={`pv-panel ${live ? "pv-live" : ""} ${isDone ? "pv-done" : ""}`}>
      <div className="pv-header">
        <span className="pv-title">Agent Pipeline</span>
        <span className={`pv-badge ${isError ? "err" : isDone ? "ok" : "run"}`}>
          {!isDone && !isError && live && <span className="pv-ping" />}
          {isError ? "ERROR" : isDone ? `${totalElapsed}s` : "LIVE"}
        </span>
      </div>
      <div className="pv-status-line">{statusText}</div>
      {tokenUsage && tokenUsage.total > 0 && (
        <div className="pv-token-bar">
          <span className="pv-token-label">TOKENS</span>
          <span className="pv-token-val">{tokenUsage.total.toLocaleString()}</span>
          <span className="pv-token-detail">in {tokenUsage.prompt.toLocaleString()} · out {tokenUsage.completion.toLocaleString()}</span>
        </div>
      )}
      <div className="pv-scroll" ref={scrollRef}>
        {nodes.map((n, i) => {
          const parent = n.parentIdx !== undefined ? nodes[n.parentIdx] : null;
          const isLast = i === nodes.length - 1;
          const isActive = live && isLast && !isDone && !isError;
          const isCompleted = !isActive;
          const elbl = parent ? edgeLabel(parent.kind, n.kind, n.label) : null;
          const hasFeedback = !!(n.feedback);
          const metaEntries = n.meta ? Object.entries(n.meta).filter(([, v]) => v !== null && v !== "" && v !== undefined) : [];

          return (
            <div key={n.id} className="pv-step pv-step-appear">
              {elbl && (
                <div className="pv-connector">
                  <div className={`pv-conn-line ${isActive ? "pv-conn-active" : ""}`} style={{ borderColor: isCompleted ? `${n.color}50` : n.color }}>
                    {isActive && <div className="pv-conn-particle" style={{ background: n.color }} />}
                  </div>
                  <span className="pv-conn-label" style={{ color: isActive ? n.color : undefined }}>{elbl}</span>
                </div>
              )}
              <div className={`pv-node ${isActive ? "pv-node-active" : ""} ${isCompleted && n.kind !== "user" ? "pv-node-done" : ""}`}>
                <div className="pv-node-icon-wrap">
                  {isActive && (
                    <div className="pv-node-pulse" style={{ borderColor: n.color, boxShadow: `0 0 12px ${n.color}40` }}>
                      <div className="pv-node-spinner" style={{ borderTopColor: n.color, borderRightColor: `${n.color}60` }} />
                    </div>
                  )}
                  <div
                    className="pv-node-icon"
                    style={{
                      borderColor: n.color,
                      boxShadow: isActive ? `0 0 20px ${n.color}50` : `0 0 4px ${n.color}15`,
                    }}
                  >
                    <span style={{ color: n.color }}>{n.icon}</span>
                  </div>
                  {isCompleted && n.kind !== "user" && n.kind !== "error" && n.kind !== "retry" && (
                    <div className="pv-node-checkmark" style={{ background: n.color }}>
                      <span>✓</span>
                    </div>
                  )}
                </div>
                <div className="pv-node-info">
                  <div className="pv-node-role" style={{ color: isActive ? n.color : undefined }}>{ROLE[n.kind] || ""}</div>
                  <div className="pv-node-label">{n.label}</div>
                  {isActive && <div className="pv-node-desc">{ROLE_DESC[n.kind] || ""}</div>}
                </div>
                <div className="pv-node-timer">
                  {isActive && <LiveTimer startedAt={n.startedAt} />}
                  {isCompleted && n.duration !== undefined && n.duration >= 0.1 && (
                    <DurationBadge seconds={n.duration} />
                  )}
                </div>
              </div>

              {(hasFeedback || metaEntries.length > 0) && (
                <div className="pv-feedback" style={{ borderLeftColor: `${n.color}40` }}>
                  {n.feedback && <div className="pv-feedback-msg">{n.feedback}</div>}
                  {metaEntries.length > 0 && (
                    <div className="pv-feedback-meta">
                      {metaEntries.map(([k, v]) => (
                        <span key={k} className="pv-meta-tag">
                          <span className="pv-meta-key">{k}</span>
                          <span className="pv-meta-val">{String(v)}</span>
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
