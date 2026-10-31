"use client";
import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { AlertCircle, AlertTriangle, CheckCheck, CircleCheck, Eye, MoreHorizontal, Pencil, Plus, Sparkles, Trash2 } from "lucide-react";
import AppShell from "../components/shell/AppShell";
import PageHero from "../components/ui/PageHero";
import Sparkline from "../components/ui/Sparkline";
import AlertDialog, { guessFromQuestion, METRIC_ICONS, type Metric, type Rule } from "./AlertDialog";
import { authFetch } from "@/lib/auth";
import { ago } from "@/lib/format";
import "./watchlist.css";

type Alert = {
  id: number; rule_id: number; severity: string; title: string; message: string; value: number | null;
  created_at: string; resolved: boolean; acknowledged: boolean; scope_label: string | null; metric_label: string | null;
};
type Tab = "watchlist" | "alert" | "riwayat";

const STATUS: Record<string, { label: string; tone: string }> = {
  kritis: { label: "Kritis", tone: "bad" }, peringatan: { label: "Peringatan", tone: "warn" },
  normal: { label: "Normal", tone: "ok" }, nonaktif: { label: "Nonaktif", tone: "off" },
  error: { label: "Tanpa data", tone: "off" }, baru: { label: "Menunggu", tone: "off" },
};
const SEV: Record<string, string> = { kritis: "Kritis", peringatan: "Peringatan", pulih: "Pulih" };

function clock(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const hm = d.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" });
  const days = Math.floor((new Date(now.toDateString()).getTime() - new Date(d.toDateString()).getTime()) / 86400000);
  if (days === 0) return hm;
  if (days === 1) return `Kemarin ${hm}`;
  return `${d.toLocaleDateString("id-ID", { day: "numeric", month: "short" })} ${hm}`;
}

function WatchlistInner() {
  const router = useRouter();
  const params = useSearchParams();
  const [rules, setRules] = useState<Rule[] | null>(null);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [metrics, setMetrics] = useState<Metric[]>([]);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<Tab>(params.get("tab") === "alert" ? "alert" : params.get("tab") === "riwayat" ? "riwayat" : "watchlist");
  const [dialog, setDialog] = useState<{ edit?: Rule | null; question?: string } | null>(
    params.get("new") ? { question: params.get("q") || undefined } : null,
  );
  const [menu, setMenu] = useState<number | null>(null);
  const [version, setVersion] = useState(0);
  const [loadedAt, setLoadedAt] = useState(0);

  useEffect(() => {
    let alive = true;
    authFetch("/api/watchlist/rules").then(async (r) => {
      const d = await r.json();
      if (!r.ok) throw new Error(d.detail || `HTTP ${r.status}`);
      if (alive) setRules(d.rules);
    }).catch((e) => { if (alive) { setError(e instanceof Error ? e.message : "Gagal memuat"); setRules([]); } });
    authFetch("/api/watchlist/alerts?status=all&limit=100").then((r) => (r.ok ? r.json() : null))
      .then((d) => { if (alive && d?.alerts) { setAlerts(d.alerts); setLoadedAt(Date.now()); } }).catch(() => {});
    return () => { alive = false; };
  }, [version]);

  useEffect(() => {
    authFetch("/api/watchlist/meta").then((r) => (r.ok ? r.json() : null))
      .then((d) => d?.metrics && setMetrics(d.metrics)).catch(() => {});
  }, []);

  useEffect(() => {
    if (menu == null) return;
    const close = () => setMenu(null);
    document.addEventListener("click", close);
    return () => document.removeEventListener("click", close);
  }, [menu]);

  const reload = useCallback(() => setVersion((v) => v + 1), []);
  const open = alerts.filter((a) => !a.resolved && a.severity !== "pulih");
  const unread = open.filter((a) => !a.acknowledged);
  const timeline = useMemo(() => {
    const dayAgo = loadedAt - 86400000;
    const recent = alerts.filter((a) => new Date(a.created_at).getTime() >= dayAgo);
    return { items: (recent.length >= 3 ? recent : alerts).slice(0, 6), recent: recent.length >= 3 };
  }, [alerts, loadedAt]);

  function closeDialog() {
    setDialog(null);
    if (params.get("new")) router.replace("/watchlist");
  }

  async function patch(r: Rule, body: Partial<Rule>) {
    setRules((cur) => cur?.map((x) => (x.id === r.id ? { ...x, ...body } : x)) ?? cur);
    await authFetch(`/api/watchlist/rules/${r.id}`, {
      method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    }).catch(() => {});
  }
  async function remove(r: Rule) {
    if (!confirm(`Hapus pantauan "${r.metric_label} ${r.scope_label}"? Riwayat alertnya ikut terhapus.`)) return;
    await authFetch(`/api/watchlist/rules/${r.id}`, { method: "DELETE" }).catch(() => {});
    reload();
  }
  async function ack(a: Alert) {
    setAlerts((cur) => cur.map((x) => (x.id === a.id ? { ...x, acknowledged: true } : x)));
    await authFetch(`/api/watchlist/alerts/${a.id}/ack`, { method: "POST" }).catch(() => {});
  }
  const ask = (text: string) => router.push(`/?q=${encodeURIComponent(text)}`);

  const prefill = dialog && !dialog.edit && dialog.question ? { ...guessFromQuestion(dialog.question), question: dialog.question } : undefined;

  return (
    <AppShell>
      <div className="ui-page wl">
        <PageHero
          icon="/illustrations/duo_alert.svg"
          art="/illustrations/iso_tower.svg"
          eyebrow="Pemantauan"
          title="Watchlist & Alert"
          sub="KPI dan site yang Anda pantau, dengan ambang batas dan notifikasi."
          actions={
            <>
              <span className="ph-glass"><Eye size={18} /> {rules?.length ?? 0} dipantau · {open.length} alert</span>
              <button className="ph-cta" onClick={() => setDialog({})}><Plus size={18} /> Buat alert</button>
            </>
          }
        />

        <div className="ui-tabs" role="tablist">
          <button role="tab" aria-selected={tab === "watchlist"} onClick={() => setTab("watchlist")}>
            Watchlist <span className="ui-badge soft">{rules?.length ?? 0}</span>
          </button>
          <button role="tab" aria-selected={tab === "alert"} onClick={() => setTab("alert")}>
            Alert aktif {open.length > 0 && <span className="ui-badge">{open.length}</span>}
          </button>
          <button role="tab" aria-selected={tab === "riwayat"} onClick={() => setTab("riwayat")}>Riwayat</button>
        </div>

        {error && <div className="ui-card ui-card-pad wl-error"><AlertTriangle size={18} /> Watchlist belum bisa dimuat: {error}</div>}

        <div className="wl-body">
          <div className="wl-main">
            {tab === "watchlist" && (
              <div className="ui-card wl-table">
                {rules && rules.length === 0 ? (
                  <div className="ui-empty">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src="/illustrations/empty_state_alert.svg" alt="" />
                    <b>Belum ada yang dipantau</b>
                    <span>Pilih KPI dan wilayah, agent akan mengecek setiap hari dan memberi tahu saat ambang terlampaui.</span>
                    <button className="ui-btn lg primary" onClick={() => setDialog({})}><Plus size={18} /> Buat alert pertama</button>
                  </div>
                ) : (
                  <div className="ui-table-wrap">
                    <table className="ui-table">
                      <thead>
                        <tr><th>KPI / site</th><th>Saat ini</th><th>Ambang</th><th>Tren 7 hari</th><th>Status</th><th>Notif</th><th aria-label="Aksi" /></tr>
                      </thead>
                      <tbody>
                        {!rules && Array.from({ length: 4 }, (_, i) => (
                          <tr key={i}><td colSpan={7}><span className="ui-skel" style={{ display: "block", height: 22 }} /></td></tr>
                        ))}
                        {rules?.map((r) => {
                          const st = STATUS[r.status] ?? STATUS.baru;
                          const Icon = METRIC_ICONS[r.icon] ?? METRIC_ICONS.activity;
                          const notif = r.notify_inapp || r.notify_email;
                          return (
                            <tr key={r.id} className={r.status === "kritis" ? "hl" : ""}>
                              <td>
                                <span className="wl-kpi">
                                  <span className="wl-kpi-ico"><Icon size={16} /></span>
                                  <span><b>{r.metric_label}</b><small>{r.scope_label}</small></span>
                                </span>
                              </td>
                              <td className={`wl-val ${st.tone}`}>{r.value_label}</td>
                              <td className="wl-thr-cell" title={r.days > 1 ? `Selama ${r.days} hari berturut-turut` : undefined}>{r.threshold_label}</td>
                              <td className="wl-trend">
                                {r.trend.filter((v) => v != null).length > 1
                                  ? <Sparkline values={r.trend} height={28} color={st.tone === "bad" ? "var(--ds-danger-solid)" : st.tone === "warn" ? "var(--ds-warning)" : "var(--ds-teal600)"} />
                                  : <span className="wl-muted">Belum cukup data</span>}
                              </td>
                              <td><span className={`wl-status ${st.tone}`}>{st.label}</span></td>
                              <td>
                                <button className="ui-switch wl-switch" role="switch" aria-checked={notif}
                                  aria-label={`Notifikasi ${r.metric_label} ${r.scope_label}`}
                                  onClick={() => patch(r, notif ? { notify_inapp: false, notify_email: false } : { notify_inapp: true })} />
                              </td>
                              <td className="wl-rowact">
                                <button className="ui-iconbtn ghost sm" aria-label="Aksi" onClick={(e) => { e.stopPropagation(); setMenu(menu === r.id ? null : r.id); }}>
                                  <MoreHorizontal size={18} />
                                </button>
                                {menu === r.id && (
                                  <div className="ui-popover wl-menu" role="menu">
                                    <button role="menuitem" onClick={() => setDialog({ edit: r })}><Pencil size={16} /> Ubah ambang</button>
                                    <button role="menuitem" onClick={() => ask(`Kenapa ${r.metric_label.toLowerCase()} ${r.scope_label} ${r.value_label} bulan ini? Wilayah mana yang paling berpengaruh?`)}><Sparkles size={16} /> Tanya agent</button>
                                    <button role="menuitem" onClick={() => patch(r, { active: !r.active, status: r.active ? "nonaktif" : "baru" })}>
                                      <Eye size={16} /> {r.active ? "Jeda pemantauan" : "Lanjutkan pemantauan"}
                                    </button>
                                    <button role="menuitem" className="danger" onClick={() => remove(r)}><Trash2 size={16} /> Hapus</button>
                                  </div>
                                )}
                              </td>
                            </tr>
                          );
                        })}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {tab === "alert" && (
              <div className="wl-alerts">
                {open.length === 0 && (
                  <div className="ui-card ui-empty">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src="/illustrations/empty_state_alert.svg" alt="" />
                    <b>Tidak ada alert aktif</b>
                    <span>Semua KPI yang dipantau masih dalam batas normal.</span>
                  </div>
                )}
                {open.map((a) => (
                  <article key={a.id} className={`wl-alert ${a.severity} ${a.acknowledged ? "read" : ""}`}>
                    <span className="wl-alert-ico">{a.severity === "kritis" ? <AlertTriangle size={20} /> : <AlertCircle size={20} />}</span>
                    <div className="wl-alert-body">
                      <div className="wl-alert-top"><b>{a.title}</b><time>{ago(a.created_at)}</time></div>
                      <p>{a.message}</p>
                      <div className="wl-alert-meta">
                        <span className={`wl-status ${a.severity === "kritis" ? "bad" : "warn"}`}>{SEV[a.severity]}</span>
                        {[a.scope_label, a.metric_label].filter(Boolean).join(" · ")}
                      </div>
                      <div className="wl-alert-actions">
                        <button className="ui-btn tint" onClick={() => ask(`Jelaskan penyebab: ${a.title}. ${a.message}`)}><Sparkles size={16} /> Tanya agent</button>
                        {!a.acknowledged
                          ? <button className="ui-btn" onClick={() => ack(a)}><CheckCheck size={16} /> Tandai sudah dibaca</button>
                          : <span className="wl-muted"><CircleCheck size={14} /> Sudah dibaca</span>}
                      </div>
                    </div>
                  </article>
                ))}
              </div>
            )}

            {tab === "riwayat" && (
              <div className="ui-card wl-table">
                {alerts.length === 0 ? (
                  <div className="ui-empty"><span>Belum ada riwayat alert.</span></div>
                ) : (
                  <div className="ui-table-wrap">
                    <table className="ui-table">
                      <thead><tr><th>Waktu</th><th>Alert</th><th>Wilayah</th><th>Tingkat</th><th>Status</th></tr></thead>
                      <tbody>
                        {alerts.map((a) => (
                          <tr key={a.id}>
                            <td className="wl-muted">{clock(a.created_at)}</td>
                            <td className="wrap"><b className="wl-hist-title">{a.title}</b><small className="wl-hist-msg">{a.message}</small></td>
                            <td>{a.scope_label ?? "–"}</td>
                            <td><span className={`wl-status ${a.severity === "kritis" ? "bad" : a.severity === "pulih" ? "ok" : "warn"}`}>{SEV[a.severity] ?? a.severity}</span></td>
                            <td className="wl-muted">{a.severity === "pulih" ? "Pulih" : a.resolved ? "Selesai" : a.acknowledged ? "Dibaca" : "Baru"}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}
          </div>

          <aside className="ui-card wl-timeline">
            <div className="wl-tl-head">
              <h2 className="ui-card-title">Timeline alert</h2>
              <p className="ui-card-sub">{timeline.recent ? "24 jam terakhir" : "Terbaru"}{unread.length ? ` · ${unread.length} belum dibaca` : ""}</p>
            </div>
            {timeline.items.length === 0 && <p className="wl-muted wl-tl-empty">Belum ada alert. Agent mengecek setiap pantauan sekali sehari.</p>}
            <ol className="wl-tl">
              {timeline.items.map((a) => (
                <li key={a.id} className={a.severity}>
                  <span className="wl-tl-dot" />
                  <div>
                    <time>{clock(a.created_at)}</time>
                    <b>{a.title}</b>
                    <span>{a.message}</span>
                  </div>
                </li>
              ))}
            </ol>
            {alerts.length > timeline.items.length && (
              <button className="ui-link wl-tl-more" onClick={() => setTab("riwayat")}>Lihat semua riwayat</button>
            )}
          </aside>
        </div>

        <p className="wl-foot wl-muted">
          Agent mengecek setiap pantauan sekali sehari dari data MTD BigQuery. Perubahan dihitung terhadap bulan lalu.{" "}
          <Link href="/dashboard" className="ui-link">Buka Dashboard</Link>
        </p>
      </div>

      {dialog && metrics.length > 0 && (
        <AlertDialog metrics={metrics} edit={dialog.edit} prefill={prefill}
          onClose={closeDialog} onSaved={() => { closeDialog(); reload(); setTab("watchlist"); }} />
      )}
    </AppShell>
  );
}

export default function WatchlistPage() {
  return <Suspense fallback={<div className="ui-boot" />}><WatchlistInner /></Suspense>;
}
