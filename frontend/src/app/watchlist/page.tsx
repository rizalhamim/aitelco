"use client";
// Redesign v2 page 07: Watchlist dan Alert. Status strip, grouped watch table (Performance, Site
// productivity, Profile wilayah) with 7-period trend, alert history, active alerts and a watch
// written as a sentence that the agent parses into a rule.
import { Fragment, Suspense, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell, { TopBar } from "../components/shell/AppShell";
import { Pencil, Trash2 } from "lucide-react";
import { Icon } from "../components/v2/Icon";
import AlertDialog, { guessFromQuestion, type Metric, type Rule } from "./AlertDialog";
import { authFetch, getUser } from "@/lib/auth";
import { ago } from "@/lib/format";
import "../dashboard/dashboard.css";
import "./watch2.css";

type WRule = Rule & {
  title: string; micon: string; group: string; group_label: string; available: boolean; kabupaten: string | null;
  threshold_sub: string; notify_push: boolean; near: boolean; value_sub: string | null; trend_threshold: number | null;
};
type Alert = {
  id: number; rule_id: number; severity: string; title: string; message: string; created_at: string;
  resolved: boolean; acknowledged: boolean; resolved_at: string | null; acknowledged_at: string | null;
  metric: string | null; scope_label: string | null; rule_title: string | null; group: string | null; group_label: string | null;
  kabupaten: string | null; value_label: string | null;
};
type Stats = {
  alerts_30d: number; by_group: { key: string; label: string; count: number }[];
  handled_hours: number | null; handled_delta_hours: number | null; repeating: { rule_id: number; title: string }[];
};
type Parsed = {
  metric: string | null; scope_level: string; scope_value: string; condition: string | null; threshold: number | null; days: number;
  missing: string[]; metric_label?: string; group_label?: string; available?: boolean; scope_label?: string;
  condition_label?: string | null; name?: string; source_question: string;
};
type Filter = "k" | "w" | "near" | "n" | null;

const GROUPS = [{ key: "perf", label: "Performance" }, { key: "prod", label: "Site productivity" }, { key: "prof", label: "Profile wilayah" }];
const GCOL: Record<string, string> = { perf: "#0E8579", prod: "#22B8C9", prof: "#B7791F" };
// Icon tile colours: Performance per metric, the other groups one colour each.
const PERF_TONE: Record<string, [string, string]> = {
  payload: ["#E3F7FA", "#0E6F7C"], revenue: ["#FCEDD3", "#B7791F"], rev_data: ["#FCEDD3", "#B7791F"], fwa_revenue: ["#FCEDD3", "#B7791F"],
  availability: ["#ECE5FA", "#6A4CB5"], gross_add: ["#E1ECFA", "#2C6CB0"], fwa_rgu: ["#E1ECFA", "#2C6CB0"],
};
const tone = (r: WRule): [string, string] =>
  r.group === "prod" ? ["#F4FCE3", "#5E8A12"] : r.group === "prof" ? ["#FBE2DA", "#B5401F"] : PERF_TONE[r.metric] ?? ["#E6F7F5", "#0A6A5F"];
const ST: Record<string, [string, string]> = {
  kritis: ["k", "Kritis"], peringatan: ["w", "Peringatan"], normal: ["n", "Normal"], nonaktif: ["o", "Nonaktif"],
  error: ["o", "Tanpa data"], nodata: ["o", "Tanpa data"], baru: ["o", "Menunggu"],
};
// Watch metric -> Peta Agent layer. Metrics without a layer get no "Peta" action.
const MAP_METRIC: Record<string, string> = {
  payload: "payload_mom", revenue: "revenue_mom", availability: "availability", rev_site: "rev_site", rgu_site: "rgu_site",
  vlr_site: "vlr_site", market_share: "market_share", subs: "subs", gross_add: "gross_add", fwa_pen: "fwa_pen",
};
const EXAMPLE = "Kabari saya kalau revenue per site di Kab. Garut turun di bawah Rp 180 jt selama 2 bulan";
const idn = (v: number, d = 1) => v.toLocaleString("id-ID", { minimumFractionDigits: d, maximumFractionDigits: d });

function when(iso: string): string {
  const d = new Date(iso);
  return `${d.toLocaleDateString("id-ID", { day: "numeric", month: "short" })}, ${d.toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" })}`;
}
const day = (iso: string) => new Date(iso).toLocaleDateString("id-ID", { day: "numeric", month: "short" });

/** 7-period trend with the threshold as a dashed line (same drawing as the mockup). */
function Spark({ values, line, s }: { values: (number | null)[]; line: number | null; s: string }) {
  const W = 84, H = 30;
  const v = values.filter((x): x is number => x != null);
  if (v.length < 2) return <svg className="wsp" width={W} height={H} aria-hidden="true" />;
  const all = line == null ? v : [...v, line];
  const mn = Math.min(...all), mx = Math.max(...all);
  const X = (i: number) => 3 + ((W - 8) * i) / (v.length - 1);
  const Y = (a: number) => 4 + (H - 8) * (1 - (a - mn) / (mx - mn || 1));
  const c = s === "k" ? "#C42B2B" : s === "w" ? "#D98E0B" : s === "o" ? "#9AA9A6" : "#0E8579";
  return (
    <svg className="wsp" width={W} height={H} aria-hidden="true">
      {line != null && <line x1={0} x2={W} y1={Y(line)} y2={Y(line)} stroke="#C42B2B" strokeWidth={1} strokeDasharray="3 3" opacity={0.6} />}
      <path d={v.map((a, i) => `${i ? "L" : "M"}${X(i).toFixed(1)} ${Y(a).toFixed(1)}`).join(" ")} fill="none" stroke={c} strokeWidth={2} strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={X(v.length - 1)} cy={Y(v[v.length - 1])} r={3} fill={c} />
    </svg>
  );
}

function WatchlistInner() {
  const router = useRouter();
  const params = useSearchParams();
  const [rules, setRules] = useState<WRule[] | null>(null);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [metrics, setMetrics] = useState<Metric[]>([]);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<"w" | "h">(params.get("tab") === "riwayat" ? "h" : "w");
  const [group, setGroup] = useState("all");
  const [filter, setFilter] = useState<Filter>(null);
  const [menu, setMenu] = useState<number | null>(null);
  const [dialog, setDialog] = useState<{ edit?: WRule | null; prefill?: { metric?: string; scope?: { level: string; value: string }; condition?: string; question?: string } } | null>(() => {
    if (!params.get("new")) return null;
    const q = params.get("q") || "";
    return { prefill: q ? { ...guessFromQuestion(q), question: q } : undefined };
  });
  const [version, setVersion] = useState(0);
  const reload = () => setVersion((v) => v + 1);

  useEffect(() => {
    let alive = true;
    authFetch("/api/watchlist/rules").then(async (r) => {
      const d = await r.json();
      if (!r.ok) throw new Error(d.detail || `HTTP ${r.status}`);
      if (alive) setRules(d.rules);
    }).catch((e) => { if (alive) { setError(e instanceof Error ? e.message : "Gagal memuat"); setRules([]); } });
    authFetch("/api/watchlist/alerts?status=all&limit=200").then((r) => (r.ok ? r.json() : null))
      .then((d) => { if (alive && d?.alerts) setAlerts(d.alerts); }).catch(() => {});
    authFetch("/api/watchlist/stats").then((r) => (r.ok ? r.json() : null))
      .then((d) => { if (alive && d) setStats(d); }).catch(() => {});
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

  const list = useMemo(() => rules ?? [], [rules]);
  const active = list.filter((r) => r.active);
  const count = {
    k: active.filter((r) => r.status === "kritis").length,
    w: active.filter((r) => r.status === "peringatan").length,
    near: active.filter((r) => r.near).length,
    n: active.length,
  };
  const open = alerts.filter((a) => !a.resolved && !a.acknowledged && a.severity !== "pulih");
  const history = alerts.filter((a) => a.severity !== "pulih");

  const visible = (r: WRule) => (group === "all" || r.group === group) && (
    !filter ? true : filter === "n" ? r.active : filter === "near" ? r.near
      : r.active && r.status === (filter === "k" ? "kritis" : "peringatan"));

  async function patch(r: WRule, body: Partial<WRule>) {
    setRules((cur) => cur?.map((x) => (x.id === r.id ? { ...x, ...body } : x)) ?? cur);
    await authFetch(`/api/watchlist/rules/${r.id}`, {
      method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    }).catch(() => {});
  }
  async function remove(r: WRule) {
    if (!confirm(`Hapus pantauan "${r.title} ${r.scope_label}"? Riwayat alertnya ikut terhapus.`)) return;
    await authFetch(`/api/watchlist/rules/${r.id}`, { method: "DELETE" }).catch(() => {});
    reload();
  }
  async function handled(a: Alert) {
    setAlerts((cur) => cur.map((x) => (x.id === a.id ? { ...x, acknowledged: true, acknowledged_at: new Date().toISOString() } : x)));
    await authFetch(`/api/watchlist/alerts/${a.id}/ack`, { method: "POST" }).catch(() => {});
  }
  const ask = (a: Alert) => router.push(`/?q=${encodeURIComponent(`Kenapa ${a.title}? ${a.message}`.trim())}`);
  const mapHref = (a: Alert) => {
    const m = a.metric ? MAP_METRIC[a.metric] : undefined;
    return m && a.kabupaten ? `/map?kabupaten=${encodeURIComponent(a.kabupaten)}&metric=${m}` : null;
  };

  const name = (getUser()?.full_name || getUser()?.username || "").split(" ")[0] || "Anda";
  const histStatus = (a: Alert): [string, string, string] =>
    !a.resolved && !a.acknowledged ? [a.severity === "kritis" ? "k" : "w", "Aktif", "Belum"]
      : a.acknowledged ? ["n", a.resolved ? "Selesai" : "Ditangani", `${name}, ${day(a.acknowledged_at!)} ${new Date(a.acknowledged_at!).toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" })}`]
        : ["n", "Selesai otomatis", a.resolved_at ? `Kembali normal ${day(a.resolved_at)}` : "Kembali normal"];

  const delta = stats?.handled_delta_hours;
  const SS: { f: Exclude<Filter, null>; bg: string; fg: string; icon: string; label: string }[] = [
    { f: "k", bg: "#FDECEC", fg: "#C42B2B", icon: "warn", label: "Kritis" },
    { f: "w", bg: "#FDF3E2", fg: "#B7791F", icon: "info", label: "Peringatan" },
    { f: "near", bg: "#FFF7E0", fg: "#B7791F", icon: "eye", label: "Mendekati ambang" },
    { f: "n", bg: "#E6F4EA", fg: "#1F7A3A", icon: "check", label: "Total pantauan aktif" },
  ];

  return (
    <AppShell>
      <TopBar
        title="Watchlist dan Alert"
        subtitle="Pantau KPI, wilayah, dan site. Agent memberi tahu saat lewat ambang."
        actions={<button className="btn-p" onClick={() => setDialog({})}><Icon name="plus" />Pantauan baru</button>}
      />
      <div className="wlx">
        {error && <div className="werr"><Icon name="warn" /> Watchlist belum bisa dimuat: {error}</div>}
        <div className="sstrip full">
          {SS.map((s) => (
            <button key={s.f} className={`ss${filter === s.f ? " on" : ""}`} aria-pressed={filter === s.f}
              onClick={() => { setFilter((f) => (f === s.f ? null : s.f)); setTab("w"); }}>
              <span className="ic3" style={{ background: s.bg, color: s.fg }}><Icon name={s.icon} /></span>
              <b>{count[s.f]}</b><small>{s.label}</small>
            </button>
          ))}
        </div>

        <section className="card" style={{ paddingTop: 4 }} aria-label="Daftar pantauan">
          <div className="wtabs" role="tablist">
            <button role="tab" aria-selected={tab === "w"} className={tab === "w" ? "on" : ""} onClick={() => setTab("w")}>Watchlist <b>{list.length}</b></button>
            <button role="tab" aria-selected={tab === "h"} className={tab === "h" ? "on" : ""} onClick={() => setTab("h")}>Riwayat alert <b>{history.length}</b></button>
          </div>
          <div className="gbar">
            <small>Kelompok</small>
            <div className={`seg gseg${tab === "h" ? " hid" : ""}`}>
              {[{ key: "all", label: "Semua" }, ...GROUPS].map((g) => (
                <button key={g.key} className={group === g.key ? "on" : ""} onClick={() => setGroup(g.key)}>{g.label}</button>
              ))}
            </div>
            <span className="grow" />
            <small>{tab === "w" ? "Urut: kelompok, lalu terbaru" : "Terbaru di atas"}</small>
          </div>
          <div className="tscroll">
            {tab === "w" ? (
              <table className="wt">
                <thead><tr><th>Pantauan</th><th>Saat ini</th><th>Ambang</th><th>Tren 7 periode</th><th>Status</th><th>Notif</th></tr></thead>
                <tbody>
                  {rules && list.length === 0 && (
                    <tr className="empty"><td colSpan={6}>Belum ada pantauan. Tulis kalimat di kanan atau tekan Pantauan baru.</td></tr>
                  )}
                  {GROUPS.map((g) => {
                    const rows = list.filter((r) => r.group === g.key && visible(r));
                    if (!rows.length) return null;
                    return (
                      <Fragment key={g.key}>
                        <tr className="grp"><td colSpan={6}><div className="gl">{g.label}<span>{rows.length} pantauan</span></div></td></tr>
                        {rows.map((r) => {
                          const [sc, sl] = ST[r.active ? r.status : "nonaktif"] ?? ST.baru;
                          const [bg, fg] = tone(r);
                          return (
                            <tr key={r.id} className="rw" onClick={() => setDialog({ edit: r })}>
                              <td><div className="mn"><i style={{ background: bg, color: fg }}><Icon name={r.micon} /></i><b>{r.title}</b><small>{r.scope_label}</small></div></td>
                              <td className="val">{r.value_label || "-"}{r.value_sub && <small>{r.value_sub}</small>}</td>
                              <td className="thr">{r.threshold_label}<small>{r.threshold_sub}</small></td>
                              <td><Spark values={r.trend} line={r.trend_threshold} s={sc} /></td>
                              <td><span className={`st2 ${sc}`}><i />{sl}</span></td>
                              <td className="ntc" onClick={(e) => e.stopPropagation()}>
                                <div className="nt">
                                  {([["notify_inapp", "bell", "In-app"], ["notify_email", "mail", "Email"], ["notify_push", "phone", "Push Android"]] as const).map(([k, ic, lb]) => (
                                    <button key={k} className={r[k] ? "" : "off"} aria-pressed={!!r[k]} title={`${lb} ${r[k] ? "aktif" : "mati"}`}
                                      onClick={() => patch(r, { [k]: !r[k] })}><Icon name={ic} /></button>
                                  ))}
                                </div>
                                <button className="rmore" aria-label={`Aksi ${r.title}`} aria-expanded={menu === r.id}
                                  onClick={(e) => { e.stopPropagation(); setMenu(menu === r.id ? null : r.id); }}><Icon name="dots" /></button>
                                {menu === r.id && (
                                  <div className="rmenu" role="menu">
                                    <button role="menuitem" onClick={() => setDialog({ edit: r })}><Pencil size={15} />Ubah ambang</button>
                                    <button role="menuitem" onClick={() => patch(r, { active: !r.active, status: r.active ? "nonaktif" : "baru" })}>
                                      <Icon name={r.active ? "pause" : "play"} />{r.active ? "Jeda pemantauan" : "Lanjutkan pemantauan"}
                                    </button>
                                    <button role="menuitem" className="danger" onClick={() => remove(r)}><Trash2 size={15} />Hapus</button>
                                  </div>
                                )}
                              </td>
                            </tr>
                          );
                        })}
                      </Fragment>
                    );
                  })}
                </tbody>
              </table>
            ) : (
              <table className="wt">
                <thead><tr><th>Waktu</th><th>Pantauan</th><th>Nilai saat alert</th><th>Status</th><th>Ditangani</th></tr></thead>
                <tbody>
                  {history.length === 0 && <tr className="empty"><td colSpan={5}>Belum ada alert.</td></tr>}
                  {history.map((a) => {
                    const [sc, sl, by] = histStatus(a);
                    return (
                      <tr key={a.id}>
                        <td>{when(a.created_at)}</td>
                        <td><b>{a.rule_title || a.title}</b>{a.scope_label ? ` · ${a.scope_label}` : ""}</td>
                        <td>{a.value_label || "-"}</td>
                        <td><span className={`st2 ${sc}`}><i />{sl}</span></td>
                        <td>{by}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
          {stats && (
            <div className="wfoot">
              <div className="wf1">
                <b>{stats.alerts_30d} alert dalam 30 hari</b><small>Per kelompok, termasuk yang sudah ditangani</small>
                <div className="gstack">{stats.by_group.filter((g) => g.count > 0).map((g) => <i key={g.key} style={{ flex: g.count, background: GCOL[g.key] }} />)}</div>
                <div className="glg">{stats.by_group.map((g) => <span key={g.key}><i style={{ background: GCOL[g.key] }} />{g.label} <b>{g.count}</b></span>)}</div>
              </div>
              <div className="wf2">
                <small>Rata-rata ditangani</small>
                <b>{stats.handled_hours != null ? `${idn(stats.handled_hours)} jam` : "-"}</b>
                <em>{delta == null ? "Belum ada pembanding bulan lalu" : delta === 0 ? "Sama dengan bulan lalu" : `lebih ${delta < 0 ? "cepat" : "lambat"} ${idn(Math.abs(delta))} jam dari bulan lalu`}</em>
              </div>
              <div className="wf2">
                <small>Alert berulang</small>
                <b>{stats.repeating.length} pantauan</b>
                <em>{stats.repeating.length ? stats.repeating.map((x) => x.title).join(", ") : "Tidak ada yang berulang"}</em>
              </div>
            </div>
          )}
        </section>

        <div className="rcol">
          <section className="card" aria-label="Alert aktif">
            <div className="ch"><h3>Alert aktif</h3><div className="grow" />{open.length > 0 && <span className="badge">{open.length}</span>}</div>
            {open.length === 0 && <p className="alnone">Tidak ada alert aktif. Semua pantauan dalam ambang.</p>}
            {open.map((a) => {
              const k = a.severity === "kritis" ? "k" : "w";
              const href = mapHref(a);
              return (
                <div key={a.id} className={`al ${k}`}>
                  <span className="ai"><Icon name={k === "k" ? "warn" : "info"} /></span>
                  <b>{a.title}<small>{ago(a.created_at)}</small></b>
                  <p>{a.message}</p>
                  <div className="tg"><span className={`sev ${k}`}>{k === "k" ? "Kritis" : "Peringatan"}</span>{a.group_label}</div>
                  <div className="acts2">
                    <button className="p" onClick={() => ask(a)}><Icon name="spark" />Tanya agent</button>
                    {href && <Link href={href}><Icon name="map" />Peta</Link>}
                    <button onClick={() => handled(a)}><Icon name="check" />Ditangani</button>
                  </div>
                </div>
              );
            })}
          </section>
          <SentenceCard metrics={metrics} onSaved={reload} onManual={(p) => setDialog({ prefill: p })} />
        </div>
      </div>

      {dialog && (
        <AlertDialog
          metrics={metrics}
          edit={dialog.edit ?? null}
          prefill={dialog.prefill}
          onClose={() => { setDialog(null); if (params.get("new")) router.replace("/watchlist"); }}
          onSaved={() => { setDialog(null); reload(); }}
        />
      )}
    </AppShell>
  );
}

/** "Pantauan baru dari kalimat": the agent reads a sentence into metric, scope and condition. */
function SentenceCard({ metrics, onSaved, onManual }: {
  metrics: Metric[]; onSaved: () => void;
  onManual: (p: { metric?: string; scope?: { level: string; value: string }; condition?: string; question?: string }) => void;
}) {
  const [text, setText] = useState(EXAMPLE);
  const [parsed, setParsed] = useState<Parsed | null>(null);
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState("");
  const [ch, setCh] = useState({ notify_inapp: true, notify_email: true, notify_push: true });
  const seq = useRef(0);

  async function read(t: string) {
    if (t.trim().length < 3) { setParsed(null); return; }
    const n = ++seq.current;
    setBusy(true);
    try {
      const r = await authFetch("/api/watchlist/parse", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text: t }) });
      const d = r.ok ? await r.json() : null;
      if (n === seq.current) setParsed(d);
    } catch { if (n === seq.current) setParsed(null); }
    if (n === seq.current) setBusy(false);
  }
  useEffect(() => {
    const id = setTimeout(() => read(text), text === EXAMPLE ? 0 : 600);
    return () => clearTimeout(id);
  }, [text]);

  const fresh = parsed?.source_question === text;
  const ok = !!parsed && fresh && parsed.missing.length === 0 && !!parsed.metric;
  async function save() {
    if (!ok || !parsed) return;
    const r = await authFetch("/api/watchlist/rules", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name: parsed.name, metric: parsed.metric, scope_level: parsed.scope_level, scope_value: parsed.scope_value,
        condition: parsed.condition, threshold: parsed.threshold, days: parsed.days, ...ch, source_question: text,
      }),
    }).catch(() => null);
    if (r?.ok) { setSaved(`${parsed.name} tersimpan`); setText(""); setParsed(null); onSaved(); }
    else setSaved("Gagal menyimpan, coba Atur manual");
  }
  const miss = (k: string) => !!parsed && parsed.missing.includes(k);

  return (
    <section className="card nl" aria-label="Pantauan baru dari kalimat">
      <div className="ch"><div><h3>Pantauan baru dari kalimat</h3><p>Tulis seperti bicara, agent mengubahnya jadi aturan</p></div></div>
      <div className="in2">
        <textarea value={text} rows={3} aria-label="Kalimat pantauan" placeholder="Contoh: kabari saya kalau payload Kab. Garut turun lebih dari 5% selama 3 hari"
          onChange={(e) => { setText(e.target.value); setSaved(""); }}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); read(text); } }} />
        <div className="row">
          <small><Icon name="spark" />{busy ? "Agent membaca..." : saved || (fresh ? "Dibaca agent" : text.trim() ? "Tekan kirim agar dibaca agent" : "Tulis kalimat dulu")}</small>
          <span className="grow" />
          <button className="snd" aria-label="Baca kalimat" disabled={busy || text.trim().length < 3} onClick={() => read(text)}><Icon name="send" /></button>
        </div>
      </div>
      {parsed && (
        <div className="parse">
          <div><small>Metrik</small><b className={miss("metric") ? "miss" : ""}>{parsed.metric_label || "Belum terbaca"}</b></div>
          <div><small>Kelompok</small><b className={miss("metric") ? "miss" : ""}>{parsed.group_label || "Belum terbaca"}</b></div>
          <div><small>Wilayah</small><b>{parsed.scope_label || "Circle Java"}</b></div>
          <div><small>Kondisi</small><b className={miss("condition") || miss("threshold") ? "miss" : ""}>{parsed.condition_label || "Belum terbaca"}</b></div>
        </div>
      )}
      {parsed?.available === false && <p className="pnote">Data metrik ini belum ada di sumber, pantauan akan berstatus Tanpa data sampai tersedia.</p>}
      <div className="chans">
        {([["notify_inapp", "bell", "In-app"], ["notify_email", "mail", "Email"], ["notify_push", "phone", "Push Android"]] as const).map(([k, ic, lb]) => (
          <button key={k} className={ch[k] ? "" : "off"} aria-pressed={ch[k]} onClick={() => setCh((c) => ({ ...c, [k]: !c[k] }))}><Icon name={ic} />{lb}</button>
        ))}
      </div>
      <div className="save">
        <button className="a1" disabled={!ok} onClick={save}><Icon name="check" />Simpan pantauan</button>
        <button className="a2" onClick={() => onManual(parsed?.metric ? {
          metric: metrics.some((m) => m.key === parsed.metric) ? parsed.metric : undefined,
          scope: { level: parsed.scope_level, value: parsed.scope_value }, condition: parsed.condition || undefined, question: text,
        } : { question: text || undefined })}>Atur manual</button>
      </div>
    </section>
  );
}

export default function WatchlistPage() {
  return <Suspense fallback={null}><WatchlistInner /></Suspense>;
}
