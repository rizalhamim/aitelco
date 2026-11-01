"use client";
// Redesign v2 page 09: Statistik aplikasi (admin). Who uses Agent Java, which features, which
// version: KPI strip, daily active users, access requests waiting for approval, login heatmap,
// feature sessions and question topics, version adoption, downloads vs update installs, the
// access table (opens the user drawer) and login security.
import { useCallback, useEffect, useMemo, useState } from "react";
import AppShell, { TopBar } from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { authFetch } from "@/lib/auth";
import { downloadXlsx } from "@/lib/xlsx";
import UserDrawer from "./UserDrawer";
import "./statistik.css";
import "./stat2.css";

type Row = {
  id: number; username: string; full_name: string; email: string; department: string | null; role: string;
  is_active: boolean; platform: string; platforms: string[]; app_version: string | null; is_latest: boolean;
  device_model: string | null; last_login: string | null; last_seen: string | null; login_count: number;
  region: string; state: "aktif" | "tidak_aktif" | "versi_lama";
};
type V2 = {
  active: { dau: number; wau: number; mau: number };
  logins_today: { total: number; web: number; android: number };
  questions: { count: number; change: number | null };
  adoption: { version: string | null; devices_on_latest: number; devices: number; downloads_since_release: number };
  failed: { count: number; locked_accounts: number };
  daily_active: { date: string; dau: number; wau: number }[];
  features: { key: string; label: string; sessions: number }[];
  topics: { key: string; label: string; count: number; pct: number }[];
  pending: { id: number; full_name: string; email: string; department: string | null; region: string; requested_at: string }[];
  security: { tag: "terkunci" | "pantau" | "diblokir"; title: string; at: string; note: string }[];
  downloads_14d: { date: string; downloads: number; updates: number }[];
  accounts: { total: number; active_30d: number; outdated_devices: number };
};
type Stats = {
  v2: V2;
  latest_release: { version_name: string | null };
  kpis: { logins_web: number; logins_android: number };
  login_heatmap: number[][];
  version_adoption: { week_end: string; versions: Record<string, number> }[];
  outdated_users: { id: number }[];
  users: Row[];
};

const PERIODS = [{ d: 1, label: "Hari ini" }, { d: 7, label: "7 hari" }, { d: 30, label: "30 hari" }, { d: 90, label: "90 hari" }];
const TABS = [{ k: "semua", label: "Semua" }, { k: "aktif", label: "Aktif" }, { k: "tidak_aktif", label: "Tidak aktif" }, { k: "versi_lama", label: "Versi lama" }] as const;
type Tab = (typeof TABS)[number]["k"];
const PAGE = 6;
const T = "#0E8579", L = "#22B8C9", LI = "#8FD6CB", AM = "#D98E0B", GR = "#9AAAA6";
const HC = ["#ECF3F1", "#C0EDE8", "#8FDFD7", "#3FBFB1", "#0E8579"];
const ROW_COL = ["#0E8579", "#2C6CB0", "#5E8A12", "#B33A5B", "#0E6F7C"];
const PEND_COL = ["#2C6CB0", "#B7791F", "#6A4CB5"];
const TOPIC_BG: Record<string, string> = { performance: "#E6F7F5", site: "#F4FCE3", profile: "#E1ECFA" };
const DAYS = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"];
const WEEKDAY = ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"];
const NICE = [1, 2, 4, 5, 8, 10, 20, 25, 40, 50, 100, 200, 250, 400, 500, 1000, 2000, 2500, 5000, 10000];

const nf = (n: number) => n.toLocaleString("id-ID");
const fmt = (v: number) => String(Math.round(v * 10) / 10);
const initials = (name: string) => {
  const p = name.trim().split(/\s+/).filter(Boolean);
  return ((p[0]?.[0] ?? "") + (p.length > 1 ? p[p.length - 1][0] : "")).toUpperCase() || "?";
};
/** Axis: the smallest nice step whose `steps` multiples cover the data, and the top of the scale. */
function axis(max: number, steps: number): { step: number; top: number } {
  const step = NICE.find((s) => s * steps >= Math.max(1, max) * 0.95) ?? NICE[NICE.length - 1];
  return { step, top: Math.max(step * steps, Math.ceil((max * 1.05) / 5) * 5) };
}
/** WIB wall clock of an ISO time (the page reads like the office, wherever the browser is). */
const wib = (iso: string) => new Date(new Date(iso).getTime() + 7 * 3600e3);
const wibDay = (t: number) => Math.floor((t + 7 * 3600e3) / 864e5);
function ago(iso: string | null, now: number): string {
  if (!iso || !now) return "-";
  const t = new Date(iso).getTime();
  const m = Math.floor((now - t) / 60e3);
  if (m < 1) return "baru saja";
  if (m < 60) return `${m} menit lalu`;
  const days = wibDay(now) - wibDay(t);
  if (days <= 0) return `${Math.floor(m / 60)} jam lalu`;
  return days === 1 ? "Kemarin" : `${days} hari lalu`;
}
function when(iso: string, now: number): string {
  const d = wib(iso);
  const hm = `${String(d.getUTCHours()).padStart(2, "0")}.${String(d.getUTCMinutes()).padStart(2, "0")}`;
  const days = wibDay(now) - wibDay(new Date(iso).getTime());
  if (days <= 0) return `Hari ini ${hm}`;
  if (days === 1) return `Kemarin ${hm}`;
  if (days < 7) return `${WEEKDAY[d.getUTCDay()]} ${hm}`;
  return `${d.getUTCDate()}/${d.getUTCMonth() + 1} ${hm}`;
}

export default function StatistikPage() {
  const [days, setDays] = useState(7);
  const [data, setData] = useState<Stats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(0);
  const [reqKey, setReqKey] = useState(0);
  const [selected, setSelected] = useState<number | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [q, setQ] = useState("");
  const [tab, setTab] = useState<Tab>("semua");
  const [page, setPage] = useState(0);
  const [busy, setBusy] = useState<number | null>(null);

  useEffect(() => {
    let live = true;
    authFetch(`/api/admin/app-stats?days=${days}`)
      .then(async (r) => {
        if (r.status === 403) throw new Error("Halaman ini khusus admin.");
        if (!r.ok) throw new Error(`Gagal memuat statistik (${r.status}).`);
        const j = (await r.json()) as Stats;
        if (!live) return;
        setData(j);
        setNow(Date.now());
        setError(null);
      })
      .catch((e: Error) => { if (live) setError(e.message); });
    return () => { live = false; };
  }, [days, reqKey]);

  const flash = (s: string) => { setNotice(s); setTimeout(() => setNotice(null), 4000); };
  const remind = useCallback(async (ids: number[]) => {
    if (!ids.length) return;
    const r = await authFetch("/api/admin/app-stats/remind", { method: "POST", body: JSON.stringify({ user_ids: ids }) });
    const j = r.ok ? await r.json() : null;
    flash(j ? `Pengingat update terkirim ke ${nf(j.sent)} pengguna.` : "Pengingat gagal dikirim.");
  }, []);
  const decide = async (id: number, ok: boolean) => {
    setBusy(id);
    const r = await authFetch(`/api/admin/app-stats/pending/${id}/${ok ? "approve" : "reject"}`, { method: "POST" }).catch(() => null);
    setBusy(null);
    flash(r?.ok ? (ok ? "Akses disetujui. Link pembuatan password dikirim ke email pengguna." : "Permintaan akses ditolak.") : "Gagal menyimpan keputusan.");
    setReqKey((k) => k + 1);
  };

  const rows = useMemo(() => {
    const s = q.trim().toLowerCase();
    return (data?.users ?? []).filter((u) => (tab === "semua" || u.state === tab)
      && (!s || `${u.full_name} ${u.email} ${u.username}`.toLowerCase().includes(s)));
  }, [data, q, tab]);
  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  const shown = rows.slice(page * PAGE, page * PAGE + PAGE);
  const outdatedIds = (data?.outdated_users ?? []).map((u) => u.id);

  const exportXlsx = () => {
    if (!data) return;
    const label = PERIODS.find((p) => p.d === days)?.label ?? `${days} hari`;
    downloadXlsx(`statistik-aplikasi-${days}-hari`,
      ["Nama", "Username", "Email", "Departemen", "Region", "Platform", "Versi", "Perangkat", "Terakhir aktif", "Jumlah login", "Status"],
      data.users.map((u) => ({
        Nama: u.full_name, Username: u.username, Email: u.email, Departemen: u.department ?? "", Region: u.region,
        Platform: u.platforms.map((p) => (p === "web" ? "Web" : "Android")).join(", "), Versi: u.app_version ?? "",
        Perangkat: u.device_model ?? "", "Terakhir aktif": u.last_seen ?? "", "Jumlah login": u.login_count,
        Status: u.state === "aktif" ? "Aktif" : u.state === "versi_lama" ? "Versi lama" : "Tidak aktif",
      })), "Akses pengguna", `Statistik aplikasi ${label}`);
  };

  const v = data?.v2;
  const plabel = days === 1 ? "hari ini" : `${days} hari`;
  return (
    <AppShell>
      <TopBar
        title="Statistik aplikasi"
        subtitle="Admin · siapa yang memakai Agent Java, fitur apa, dan versi berapa."
        actions={<>
          <div className="seg" style={{ margin: 0 }} role="group" aria-label="Periode">
            {PERIODS.map((p) => <button key={p.d} className={days === p.d ? "on" : ""} aria-pressed={days === p.d} onClick={() => { setDays(p.d); setPage(0); }}>{p.label}</button>)}
          </div>
          <button className="linkbtn" onClick={exportXlsx} disabled={!data}><Icon name="dl" />Ekspor XLSX</button>
        </>}
      />
      <div className="stx">
        {error && <div className="err"><Icon name="warn" /> {error} <button className="linkbtn" onClick={() => setReqKey((k) => k + 1)}>Coba lagi</button></div>}
        {notice && <div className="err" role="status" style={{ background: "#E6F4EA", color: "#1F7A3A" }}><Icon name="check" /> {notice}</div>}
        {v && data && <>
          <div className="k5 c12">
            <div className="k9"><small><i style={{ background: "#E6F7F5", color: "#0A6A5F" }}><Icon name="users" /></i>Pengguna aktif</small>
              <b>{nf(v.active.dau)} <span>· {nf(v.active.wau)} · {nf(v.active.mau)}</span></b>
              <em>DAU · WAU · MAU, DAU/MAU {v.active.mau ? Math.round((100 * v.active.dau) / v.active.mau) : 0}%</em></div>
            <div className="k9"><small><i style={{ background: "#E1ECFA", color: "#2C6CB0" }}><Icon name="lock" /></i>Login hari ini</small>
              <b>{nf(v.logins_today.total)}</b><em>Web {nf(v.logins_today.web)} · Android {nf(v.logins_today.android)}</em></div>
            <div className="k9"><small><i style={{ background: "#F4FCE3", color: "#5E8A12" }}><Icon name="spark" /></i>Pertanyaan ke agent</small>
              <b>{nf(v.questions.count)}</b>
              {v.questions.change == null
                ? <em>{days === 1 ? "hari ini" : `${days} hari terakhir`}</em>
                : <em className={v.questions.change >= 0 ? "up" : "dn"}>{v.questions.change >= 0 ? "▲" : "▼"} {Math.abs(Math.round(v.questions.change))}% vs {days === 1 ? "kemarin" : `${days} hari sebelumnya`}</em>}
            </div>
            <div className="k9"><small><i style={{ background: "#E3F7FA", color: "#0E6F7C" }}><Icon name="phone" /></i>Adopsi versi {v.adoption.version ?? "-"}</small>
              <b>{nf(v.adoption.devices_on_latest)} <span>/ {nf(v.adoption.devices)}</span></b>
              <div className="bar2"><i style={{ flex: v.adoption.devices_on_latest }} /><i style={{ flex: Math.max(0, v.adoption.devices - v.adoption.devices_on_latest), background: "transparent" }} /></div>
              <em>perangkat Android · {nf(v.adoption.downloads_since_release)} unduhan</em></div>
            <div className="k9"><small><i style={{ background: "#FDECEC", color: "#C42B2B" }}><Icon name="shield" /></i>Login gagal</small>
              <b>{nf(v.failed.count)}</b>
              <em className={v.failed.locked_accounts ? "dn" : ""}>{v.failed.locked_accounts ? `${v.failed.locked_accounts} akun terkunci sementara` : "tidak ada akun terkunci"}</em></div>
          </div>

          <section className="card c8">
            <div className="ch"><div><h3>Pengguna aktif harian</h3><p>30 hari terakhir, akun unik yang login di web atau Android</p></div><span className="grow" />
              <div className="lg9"><span><i style={{ background: T }} />DAU</span><span><i className="ln" style={{ background: L }} />WAU (7 hari bergulir)</span></div></div>
            <DauChart d={v.daily_active} />
          </section>

          <section className="card c4 pend">
            <div className="ch"><div><h3>Menunggu persetujuan</h3><p>Akun baru yang mendaftar</p></div><span className="grow" />
              <span className="ctag" style={{ background: "#FDF3E2", color: "#B7791F" }}>{v.pending.length}</span></div>
            {v.pending.length === 0 && <div className="none">Tidak ada permintaan akses baru.</div>}
            {v.pending.map((p, i) => (
              <div className="pr" key={p.id} title={`${p.email} · ${when(p.requested_at, now)}`}>
                <i style={{ background: PEND_COL[i % PEND_COL.length] }}>{initials(p.full_name)}</i>
                <b>{p.full_name}</b><small>{[p.department, p.region].filter(Boolean).join(" · ")}</small>
                <div className="ab">
                  <button disabled={busy === p.id} onClick={() => decide(p.id, false)}>Tolak</button>
                  <button className="p" disabled={busy === p.id} onClick={() => decide(p.id, true)}>Setujui</button>
                </div>
              </div>
            ))}
          </section>

          <section className="card c7">
            <div className="ch"><div><h3>Aktivitas login</h3><p>Jumlah login per hari dan jam (WIB), {plabel}</p></div><span className="grow" />
              <div className="lg9"><span>Sedikit</span><span>{HC.map((c) => <i key={c} style={{ background: c }} />)}</span><span>Banyak</span></div></div>
            <Heat h={data.login_heatmap} />
            <div className="lg9" style={{ color: "#5A6B68" }}>{heatNote(data.login_heatmap)}</div>
          </section>

          <section className="card c5">
            <div className="ch"><div><h3>Pemakaian fitur</h3><p>Sesi per halaman, {plabel}</p></div></div>
            <Bars items={v.features.map((f) => ({ label: f.label, n: f.sessions, color: T }))} />
            <div className="ch" style={{ marginTop: 4 }}><div><h3 style={{ fontSize: 13.5 }}>Topik pertanyaan ke agent</h3></div></div>
            <div className="tp">{v.topics.map((t) => (
              <div key={t.key} style={{ background: TOPIC_BG[t.key] }} title={`${nf(t.count)} pertanyaan`}><b>{t.pct}%</b><small>{t.label}</small></div>
            ))}</div>
          </section>

          <section className="card c6">
            <AdoptionCard d={data} />
          </section>

          <section className="card c6">
            <div className="ch"><div><h3>Unduhan vs instal update</h3><p>Harian, 14 hari terakhir</p></div><span className="grow" />
              <div className="lg9"><span><i style={{ background: AM }} />Unduhan baru</span><span><i style={{ background: T }} />Instal update</span></div></div>
            <DlBars d={v.downloads_14d} />
          </section>

          <section className="card c8">
            <div className="ch"><div><h3>Akses pengguna</h3><p>{nf(v.accounts.total)} akun · {nf(v.accounts.active_30d)} aktif 30 hari · {nf(v.accounts.outdated_devices)} perangkat masih versi lama</p></div></div>
            <div className="tb2">
              <label className="sbox"><Icon name="search" /><input value={q} onChange={(e) => { setQ(e.target.value); setPage(0); }} placeholder="Cari nama atau email" aria-label="Cari pengguna" /></label>
              <div className="seg" role="group" aria-label="Status">
                {TABS.map((t) => <button key={t.k} className={tab === t.k ? "on" : ""} aria-pressed={tab === t.k} onClick={() => { setTab(t.k); setPage(0); }}>{t.label}</button>)}
              </div>
              <span className="grow" />
              <button className="linkbtn" style={{ height: 34, fontSize: 12.5 }} disabled={!outdatedIds.length} onClick={() => remind(outdatedIds)}>
                <Icon name="bell" />Ingatkan update ({outdatedIds.length})</button>
            </div>
            <table className="ut">
              <thead><tr><th>Pengguna</th><th>Departemen</th><th>Platform</th><th>Versi</th><th>Terakhir aktif</th><th>Status</th></tr></thead>
              <tbody>
                {shown.map((u, i) => (
                  <tr key={u.id} onClick={() => setSelected(u.id)} tabIndex={0} onKeyDown={(e) => e.key === "Enter" && setSelected(u.id)}>
                    <td><div className="who2"><i style={{ background: u.state === "tidak_aktif" ? GR : ROW_COL[(page * PAGE + i) % ROW_COL.length] }}>{initials(u.full_name || u.username)}</i>
                      <div><b>{u.full_name || u.username}</b><small>{u.role === "admin" ? `Admin · ${u.region}` : u.region}</small></div></div></td>
                    <td>{u.department || "-"}</td>
                    <td>{u.platforms.map((p, k) => <span key={p}>{k > 0 && " "}<span className={`pl ${p === "web" ? "w" : "a"}`}>{p === "web" ? "Web" : "Android"}</span></span>)}</td>
                    <td>{u.app_version || "-"}</td>
                    <td>{ago(u.last_seen, now)}</td>
                    <td>{u.state === "aktif" ? <span className="pl g">Aktif</span> : u.state === "versi_lama" ? <span className="pl o">Versi lama</span> : <span className="pl m">Tidak aktif</span>}</td>
                  </tr>
                ))}
                {!shown.length && <tr><td colSpan={6} className="empty">Tidak ada pengguna yang cocok.</td></tr>}
              </tbody>
            </table>
            <div className="foot2">
              <small>{rows.length ? `Menampilkan ${page * PAGE + 1} sampai ${Math.min(rows.length, page * PAGE + PAGE)} dari ${nf(rows.length)}` : "Tidak ada data"}</small>
              <span className="grow" />
              <button className="linkbtn" style={{ height: 32, fontSize: 12.5 }} disabled={page === 0} onClick={() => setPage((p) => p - 1)}>Sebelumnya</button>
              <button className="linkbtn" style={{ height: 32, fontSize: 12.5 }} disabled={page >= pages - 1} onClick={() => setPage((p) => p + 1)}>Berikutnya</button>
            </div>
          </section>

          <div className="pcol c4">
            <section className="card">
              <div className="ch"><div><h3>Login per platform</h3><p>{days === 1 ? "Hari ini" : `${days} hari`}</p></div></div>
              <Bars total items={[{ label: "Web", n: data.kpis.logins_web, color: "#2C6CB0" }, { label: "Android", n: data.kpis.logins_android, color: "#5E8A12" }]} />
            </section>
            <section className="card">
              <div className="ch"><div><h3>Login gagal dan keamanan</h3><p>{days === 1 ? "Hari ini" : `${days} hari`}</p></div></div>
              <div className="sec2">
                {v.security.length === 0 && <div className="empty">Tidak ada login gagal pada periode ini.</div>}
                {v.security.map((e, i) => (
                  <div className="sr" key={i}><b>{e.title}</b><small>{when(e.at, now)} · {e.note}</small>
                    <span className={`pl ${e.tag === "terkunci" ? "r" : e.tag === "pantau" ? "o" : "m"}`}>{e.tag === "terkunci" ? "Terkunci" : e.tag === "pantau" ? "Pantau" : "Diblokir"}</span></div>
                ))}
              </div>
            </section>
          </div>
        </>}
      </div>
      {selected != null && (
        <UserDrawer id={selected} onClose={() => setSelected(null)} onRemind={remind} onChanged={() => setReqKey((k) => k + 1)} />
      )}
    </AppShell>
  );
}

/** Horizontal bars: scaled to the largest item, or with `total` to the sum (a share). */
function Bars({ items, total }: { items: { label: string; n: number; color: string }[]; total?: boolean }) {
  const top = total ? items.reduce((a, b) => a + b.n, 0) : Math.max(0, ...items.map((i) => i.n));
  return (
    <div className="fu">{items.map((it) => (
      <div key={it.label}>{it.label}<span><i style={{ flex: it.n, background: it.color }} /><i style={{ flex: Math.max(0, top - it.n) }} /></span><b>{nf(it.n)}</b></div>
    ))}</div>
  );
}

function Tip({ tip }: { tip: { x: number; y: number; text: string } | null }) {
  return tip ? <div className="tip" style={{ left: `${tip.x}%`, top: `${tip.y}%` }}>{tip.text}</div> : null;
}

function grid(W: number, l: number, r: number, ax: { step: number; top: number }, Y: (v: number) => number) {
  const out = [];
  for (let g = 0; g <= ax.top + 1e-9; g += ax.step) {
    out.push(<g key={g}><line x1={l} x2={W - r} y1={fmt(Y(g))} y2={fmt(Y(g))} stroke="#ECF3F1" />
      <text x={l - 6} y={fmt(Y(g) + 3.5)} textAnchor="end" fontSize="10" fill="#5A6B68" fontFamily="Prompt">{g}</text></g>);
  }
  return out;
}

function DauChart({ d }: { d: V2["daily_active"] }) {
  const [tip, setTip] = useState<{ x: number; y: number; text: string } | null>(null);
  const W = 700, H = 210, l = 30, t = 10, b = 22, r = 8, n = d.length;
  const ax = axis(Math.max(0, ...d.map((x) => Math.max(x.dau, x.wau))), 3);
  const X = (i: number) => l + ((W - l - r) * i) / Math.max(1, n - 1);
  const Y = (v: number) => t + (H - t - b) * (1 - v / ax.top);
  const line = (k: "dau" | "wau") => "M" + d.map((x, i) => `${fmt(X(i))} ${fmt(Y(x[k]))}`).join(" L");
  const last = d[n - 1];
  const labels: [number, string][] = [[0, `${n} hari lalu`], [8, "21"], [15, "14"], [22, "7"], [n - 1, "Hari ini"]];
  return (
    <div className="chw" onMouseLeave={() => setTip(null)}>
      <svg className="ch9" viewBox={`0 0 ${W} ${H}`} height={H} role="img" aria-label="Pengguna aktif harian"
        onMouseMove={(e) => {
          const box = e.currentTarget.getBoundingClientRect();
          const x = ((e.clientX - box.left) / box.width) * W;
          const i = Math.max(0, Math.min(n - 1, Math.round(((x - l) / (W - l - r)) * (n - 1))));
          const p = d[i];
          if (p) setTip({ x: (X(i) / W) * 100, y: (Y(p.wau) / H) * 100, text: `${p.date.split("-").reverse().slice(0, 2).join("/")} · DAU ${p.dau} · WAU ${p.wau}` });
        }}>
        {grid(W, l, r, ax, Y)}
        {n > 0 && <>
          <path d={`${line("dau")} L${fmt(X(n - 1))} ${fmt(Y(0))} L${fmt(X(0))} ${fmt(Y(0))} Z`} fill={T} opacity=".10" />
          <path d={line("wau")} fill="none" stroke={L} strokeWidth="2" strokeDasharray="5 4" />
          <path d={line("dau")} fill="none" stroke={T} strokeWidth="2.2" strokeLinejoin="round" />
          <circle cx={fmt(X(n - 1))} cy={fmt(Y(last.dau))} r="4" fill={T} stroke="#fff" strokeWidth="2" />
          <circle cx={fmt(X(n - 1))} cy={fmt(Y(last.wau))} r="3.5" fill={L} stroke="#fff" strokeWidth="2" />
        </>}
        {n === 30 && labels.map(([i, s]) => (
          <text key={i} x={fmt(X(i))} y={H - 5} textAnchor={i === n - 1 ? "end" : i === 0 ? "start" : "middle"} fontSize="10" fill="#5A6B68" fontFamily="Prompt">{s}</text>
        ))}
      </svg>
      <Tip tip={tip} />
    </div>
  );
}

function heatNote(h: number[][]): string {
  const total = h.flat().reduce((a, b) => a + b, 0);
  if (!total) return "Belum ada login pada periode ini.";
  const hours = Array.from({ length: 24 }, (_, k) => h.slice(0, 5).reduce((a, row) => a + (row[k] || 0), 0));
  const top = hours.map((v, k) => [v, k]).sort((a, b) => b[0] - a[0]);
  const peaks: number[] = [];
  for (const [v, k] of top) {
    if (!v || peaks.length === 2) break;
    if (peaks.every((p) => Math.abs(p - k) >= 3)) peaks.push(k);
  }
  const weekday = h.slice(0, 5).flat().reduce((a, b) => a + b, 0) / 5;
  const weekend = h.slice(5).flat().reduce((a, b) => a + b, 0) / 2;
  const hh = (k: number) => `${String(k).padStart(2, "0")}.00`;
  const pk = peaks.sort((a, b) => a - b).map(hh);
  return `Puncak Senin sampai Jumat pukul ${pk.join(" dan ")}.${weekend < weekday * 0.5 ? " Akhir pekan sepi." : " Akhir pekan tetap ramai."}`;
}

function Heat({ h }: { h: number[][] }) {
  const max = Math.max(0, ...h.flat());
  const lvl = (v: number) => (v <= 0 || !max ? 0 : Math.max(1, Math.round((4 * v) / max)));
  return (
    <div className="hm">
      {DAYS.map((dn, d) => [
        <span key={dn}>{dn}</span>,
        ...Array.from({ length: 24 }, (_, k) => <i key={`${dn}${k}`} title={`${dn} ${String(k).padStart(2, "0")}.00 · ${h[d]?.[k] ?? 0} login`} style={{ background: HC[lvl(h[d]?.[k] ?? 0)] }} />),
      ])}
      <span />
      {Array.from({ length: 24 }, (_, k) => <span key={`x${k}`} className="hx">{k % 6 === 0 ? k : ""}</span>)}
    </div>
  );
}

function verGroup(v: string, latest: string | null): 0 | 1 | 2 {
  const [a, b] = (latest || "").split(".").map((x) => parseInt(x, 10));
  const [c, e] = v.split(".").map((x) => parseInt(x, 10));
  if (!Number.isFinite(a) || !Number.isFinite(c)) return 2;
  if (c === a && e === b) return 0;
  if (c === a && e === b - 1) return 1;
  return 2;
}

function AdoptionCard({ d }: { d: Stats }) {
  const latest = d.latest_release.version_name;
  const [a, b] = (latest || "0.0").split(".");
  const W = 470, H = 190, l = 30, t = 10, bt = 22, r = 8;
  const weeks = d.version_adoption.map((w) => {
    const g = [0, 0, 0];
    for (const [ver, n] of Object.entries(w.versions)) g[verGroup(ver, latest)] += n;
    return g;
  });
  const n = weeks.length;
  const ax = axis(Math.max(0, ...weeks.map((g) => g[0] + g[1] + g[2])), 2);
  const X = (i: number) => l + ((W - l - r) * i) / Math.max(1, n - 1);
  const Y = (v: number) => t + (H - t - bt) * (1 - v / ax.top);
  const layers: [number, string][] = [[2, GR], [1, LI], [0, T]];
  const lo = weeks.map(() => 0);
  const paths = layers.map(([k, c]) => {
    const hi = weeks.map((g, i) => lo[i] + g[k]);
    const p = "M" + hi.map((v, i) => `${fmt(X(i))} ${fmt(Y(v))}`).join(" L") + " L" + [...lo.keys()].reverse().map((i) => `${fmt(X(i))} ${fmt(Y(lo[i]))}`).join(" L") + " Z";
    hi.forEach((v, i) => { lo[i] = v; });
    return <path key={k} d={p} fill={c} opacity=".9" />;
  });
  const labs = weeks.map((_, i) => (i === n - 1 ? "Minggu ini" : i === 0 ? `${n - 1} mg lalu` : String(n - 1 - i)));
  return (<>
    <div className="ch"><div><h3>Adopsi versi aplikasi</h3><p>Perangkat Android per versi, per minggu</p></div><span className="grow" />
      <div className="lg9"><span><i style={{ background: T }} />{a}.{b}</span><span><i style={{ background: LI }} />{a}.{Number(b) - 1}.x</span><span><i style={{ background: GR }} />Lebih lama</span></div></div>
    <svg className="ch9" viewBox={`0 0 ${W} ${H}`} height={H} role="img" aria-label="Adopsi versi per minggu">
      <title>{weeks.map((g, i) => `${labs[i]}: ${a}.${b} ${g[0]}, ${a}.${Number(b) - 1}.x ${g[1]}, lebih lama ${g[2]}`).join("; ")}</title>
      {grid(W, l, r, ax, Y)}
      {n > 1 && paths}
      {labs.map((s, i) => (
        <text key={i} x={fmt(X(i))} y={H - 5} textAnchor={i === 0 ? "start" : i === n - 1 ? "end" : "middle"} fontSize="10" fill="#5A6B68" fontFamily="Prompt">{s}</text>
      ))}
    </svg>
  </>);
}

function DlBars({ d }: { d: V2["downloads_14d"] }) {
  const W = 470, H = 190, l = 30, t = 10, b = 22, r = 8, n = d.length;
  const ax = axis(Math.max(0, ...d.map((x) => Math.max(x.downloads, x.updates))), 2);
  const bw = (W - l - r) / Math.max(1, n);
  const Y = (v: number) => t + (H - t - b) * (1 - v / ax.top);
  return (
    <svg className="ch9" viewBox={`0 0 ${W} ${H}`} height={H} role="img" aria-label="Unduhan baru dan instal update per hari">
      {grid(W, l, r, ax, Y)}
      {d.map((x, i) => {
        const x0 = l + i * bw + bw * 0.18, w = bw * 0.3;
        return (
          <g key={x.date}>
            <title>{`${x.date.split("-").reverse().slice(0, 2).join("/")}: ${x.downloads} unduhan baru, ${x.updates} instal update`}</title>
            <rect x={fmt(x0)} y={fmt(Y(x.downloads))} width={fmt(w)} height={fmt(Y(0) - Y(x.downloads))} rx="2" fill={AM} />
            <rect x={fmt(x0 + w + 1.5)} y={fmt(Y(x.updates))} width={fmt(w)} height={fmt(Y(0) - Y(x.updates))} rx="2" fill={T} />
          </g>
        );
      })}
      {([[0, "14 hari lalu"], [7, "7"], [n - 1, "Hari ini"]] as [number, string][]).map(([i, s]) => (
        <text key={i} x={fmt(l + i * bw + bw / 2)} y={H - 5} textAnchor={i === 0 ? "start" : i === n - 1 ? "end" : "middle"} fontSize="10" fill="#5A6B68" fontFamily="Prompt">{s}</text>
      ))}
    </svg>
  );
}
