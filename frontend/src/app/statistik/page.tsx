"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  AlertCircle, BellRing, ChevronDown, ChevronLeft, ChevronRight, Download, Filter, Lock, Monitor, Radio, Search, TrendingUp,
} from "lucide-react";
import type { EChartsOption } from "echarts";
import AppShell from "../components/shell/AppShell";
import PageHero from "../components/ui/PageHero";
import Sparkline from "../components/ui/Sparkline";
import EChart, { TOOLTIP, tipRow, type ChartTheme } from "../components/charts/EChart";
import UserDrawer from "./UserDrawer";
import { authFetch } from "@/lib/auth";
import { Avatar, DAYS, MONTHS, dateLabel, relAgo, stamp, versionKey } from "./util";
import "./statistik.css";

type UserRow = {
  id: number; username: string; full_name: string; email: string; department: string | null; role: string; is_active: boolean;
  platform: "android" | "web"; app_version: string | null; is_latest: boolean; device_model: string | null; os_version: string | null;
  last_login: string | null; login_count: number;
  last_activity: { at: string; action: string; domain: string | null; label: string } | null;
  status: "aktif" | "tidak_aktif";
};
type Stats = {
  generated_at: string; period_days: number;
  latest_release: { version_name: string | null; version_code: number | null; mandatory: boolean; released_at: string | null };
  kpis: {
    downloads_total: number; downloads_period: number; devices_installed: number; android_users: number; pct_on_latest: number | null;
    dau: number; wau: number; mau: number; logins_android: number; logins_web: number; failed_logins: number;
  };
  versions: { version: string; users: number }[];
  version_adoption: { week_end: string; versions: Record<string, number> }[];
  downloads_timeline: { date: string; downloads: number; updates: number }[];
  login_heatmap: number[][];
  release_markers: { version: string; date: string; mandatory: boolean }[];
  failed_summary: { total: number; attempts: number; reasons: { key: string; label: string; count: number }[] };
  failed_logins_recent: { user_id: number; username: string | null; email: string | null; reason: string; at: string; ip: string | null; client: string }[];
  outdated_users: { id: number; full_name: string; department: string | null; app_version: string; device_model: string | null; last_login: string | null }[];
  users: UserRow[];
};

const PERIODS = [7, 30, 90];
const PAGE = 8;
const nf = (v: number) => v.toLocaleString("id-ID");
const pctTxt = (v: number, d = 0) => `${v.toLocaleString("id-ID", { maximumFractionDigits: d })}%`;

type Group = { label: string; color: keyof ChartTheme; has: (v: string) => boolean };
/** Latest version on its own, the next two minor lines, then everything older — as in the mockup legend. */
function versionGroups(all: string[], latest: string | null): Group[] {
  const minor = (v: string) => v.split(".").slice(0, 2).join(".");
  const others = [...new Set(all.filter((v) => v !== latest && v !== "unknown").map(minor))]
    .sort((a, b) => versionKey(b) - versionKey(a));
  const groups: Group[] = [];
  if (latest) groups.push({ label: `v${latest}`, color: "teal600", has: (v) => v === latest });
  const colors: (keyof ChartTheme)[] = ["teal300", "amber"];
  others.slice(0, 2).forEach((m, i) => groups.push({ label: `v${m}.x`, color: colors[i], has: (v) => v !== latest && minor(v) === m }));
  const rest = others.slice(2);
  if (rest.length || all.includes("unknown")) {
    const top = rest[0];
    const named = [...groups];
    groups.push({ label: top ? `≤ v${top}` : "lainnya", color: "grey", has: (v) => !named.some((g) => g.has(v)) });
  }
  return groups;
}

export default function StatistikPage() {
  const [days, setDays] = useState(30);
  const [data, setData] = useState<Stats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(0);
  const [reqKey, setReqKey] = useState(0);
  const [selected, setSelected] = useState<number | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    authFetch(`/api/admin/app-stats?days=${days}`)
      .then(async (r) => {
        if (!live) return;
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

  const remind = useCallback(async (ids: number[]) => {
    if (!ids.length) return;
    const r = await authFetch("/api/admin/app-stats/remind", { method: "POST", body: JSON.stringify({ user_ids: ids }) });
    const j = r.ok ? await r.json() : null;
    setNotice(j ? `Pengingat update terkirim ke ${nf(j.sent)} pengguna.` : "Pengingat gagal dikirim.");
    setTimeout(() => setNotice(null), 4000);
  }, []);

  const exportCsv = useCallback((rows: UserRow[]) => {
    const cols: [string, (u: UserRow) => unknown][] = [
      ["nama", (u) => u.full_name], ["email", (u) => u.email], ["departemen", (u) => u.department], ["platform", (u) => u.platform],
      ["versi", (u) => u.app_version], ["perangkat", (u) => u.device_model], ["login_terakhir", (u) => u.last_login],
      ["jumlah_login", (u) => u.login_count], ["aktivitas", (u) => u.last_activity?.label], ["status", (u) => u.status],
    ];
    const esc = (v: unknown) => {
      const s = v == null ? "" : String(v);
      return /[",\n;]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const csv = [cols.map((c) => c[0]).join(","), ...rows.map((u) => cols.map((c) => esc(c[1](u))).join(","))].join("\n");
    const url = URL.createObjectURL(new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" }));
    const a = document.createElement("a");
    a.href = url;
    a.download = `akses-pengguna-${days}-hari.csv`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }, [days]);

  return (
    <AppShell>
      <div className="ui-page st">
        <PageHero
          icon="/illustrations/duo_download.svg"
          art="/illustrations/iso_tower.svg"
          eyebrow="Admin · akses aplikasi"
          title="Statistik penggunaan aplikasi"
          sub="Unduhan APK, adopsi versi dan aktivitas login pengguna Android dan web."
          actions={
            <>
              <div className="ui-seg st-seg" role="group" aria-label="Periode">
                {PERIODS.map((d) => (
                  <button key={d} aria-pressed={days === d} onClick={() => setDays(d)}>{d} hari</button>
                ))}
              </div>
              <button className="ph-cta" onClick={() => data && exportCsv(data.users)} disabled={!data}>
                <Download size={20} /> Export CSV
              </button>
            </>
          }
        />

        {notice && <div className="st-notice" role="status"><BellRing size={18} /> {notice}</div>}
        {error && (
          <div className="ui-card ui-card-pad st-error">
            <AlertCircle size={18} /> {error}
            <button className="ui-btn" onClick={() => setReqKey((k) => k + 1)}>Coba lagi</button>
          </div>
        )}

        {!data && !error && <Skeleton />}
        {data && (
          <>
            <KpiRow d={data} />
            <div className="st-row st-row-a">
              <Adoption d={data} />
              <Outdated d={data} now={now} onRemind={remind} />
            </div>
            <Downloads d={data} />
            <div className="st-row st-row-b">
              <Heatmap d={data} />
              <Failed d={data} now={now} />
            </div>
            <UsersTable d={data} now={now} selected={selected} onSelect={setSelected} onExport={exportCsv} />
          </>
        )}
      </div>
      {selected != null && (
        <UserDrawer id={selected} onClose={() => setSelected(null)} onRemind={remind}
          onChanged={() => setReqKey((k) => k + 1)} />
      )}
    </AppShell>
  );
}

function Skeleton() {
  return (
    <>
      <div className="st-kpis">{[0, 1, 2, 3].map((i) => <div key={i} className="ui-skel" style={{ height: 156, borderRadius: 20 }} />)}</div>
      <div className="st-row st-row-a">
        <div className="ui-skel" style={{ height: 359, borderRadius: 20 }} />
        <div className="ui-skel" style={{ height: 331, borderRadius: 20 }} />
      </div>
    </>
  );
}

/* ── KPI row ── */

function KpiRow({ d }: { d: Stats }) {
  const k = d.kpis;
  const installedPct = k.downloads_total ? Math.round((100 * k.devices_installed) / k.downloads_total) : 0;
  const onLatest = d.versions.find((v) => v.version === d.latest_release.version_name)?.users ?? 0;
  const outdated = Math.max(0, k.android_users - onLatest);
  const latestPct = k.pct_on_latest ?? 0;
  const logins = k.logins_android + k.logins_web;
  const androidPct = logins ? Math.round((100 * k.logins_android) / logins) : 0;
  const spark = useMemo(() => d.downloads_timeline.reduce<number[]>(
    (acc, t) => [...acc, (acc[acc.length - 1] ?? 0) + t.downloads + t.updates], []), [d.downloads_timeline]);
  const periodLabel = d.period_days === 30 ? "bulan ini" : `${d.period_days} hari`;
  const ringC = 2 * Math.PI * 34;
  return (
    <section className="st-kpis" aria-label="Ringkasan">
      <article className="st-kpi st-kpi-dark">
        <span className="st-kpi-label">Unduhan APK · terpasang</span>
        <div className="st-kpi-big">
          <b>{nf(k.downloads_total)}</b>
          <span>{nf(k.devices_installed)} terpasang ({installedPct}%)</span>
        </div>
        <span className="st-pill-glass"><TrendingUp size={12} /> {nf(k.downloads_period)} unduhan {periodLabel}</span>
        <div className="st-kpi-spark">
          <Sparkline values={spark} color="#5BCEC3" height={36}
            labels={d.downloads_timeline.map((t) => dateLabel(t.date))} format={(v) => `${nf(v)} kumulatif`} />
        </div>
      </article>

      <article className="st-kpi">
        <span className="st-kpi-label">Versi terbaru {d.latest_release.version_name ? `v${d.latest_release.version_name}` : "–"}</span>
        <div className="st-donut-row">
          <svg width="84" height="84" viewBox="0 0 84 84" role="img" aria-label={`${latestPct}% di versi terbaru`}>
            <circle cx="42" cy="42" r="34" fill="none" stroke="var(--ds-warning)" strokeWidth="9" />
            <circle cx="42" cy="42" r="34" fill="none" stroke="var(--ds-teal600)" strokeWidth="9"
              strokeDasharray={`${(ringC * latestPct) / 100} ${ringC}`} transform="rotate(-90 42 42)" />
            <text x="42" y="42" textAnchor="middle" className="st-donut-v">{Math.round(latestPct)}%</text>
            <text x="42" y="55" textAnchor="middle" className="st-donut-s">terbaru</text>
          </svg>
          <ul className="st-legend-list">
            <li><i style={{ background: "var(--ds-teal600)" }} /> Terbaru <b>{nf(onLatest)}</b></li>
            <li><i style={{ background: "var(--ds-warning)" }} /> Usang <b>{nf(outdated)}</b></li>
          </ul>
        </div>
      </article>

      <article className="st-kpi">
        <span className="st-kpi-label">Pengguna aktif (DAU · WAU · MAU)</span>
        <div className="st-dwm">
          <div><b>{nf(k.dau)}</b><span>Hari ini</span></div>
          <div><b>{nf(k.wau)}</b><span>7 hari</span></div>
          <div><b>{nf(k.mau)}</b><span>30 hari</span></div>
        </div>
        <span className="st-kpi-foot">DAU/MAU {k.mau ? pctTxt((100 * k.dau) / k.mau) : "–"}</span>
      </article>

      <article className="st-kpi">
        <span className="st-kpi-label">Login per platform</span>
        <b className="st-kpi-h">{logins ? `${androidPct}% Android` : "Belum ada login"}</b>
        <div className="st-split" aria-hidden="true">
          <span style={{ flex: k.logins_android || (logins ? 0 : 1) }} />
          <span style={{ flex: k.logins_web || (logins ? 0 : 1) }} />
        </div>
        <div className="st-split-lg"><span>Android {nf(k.logins_android)}</span><span>Web {nf(k.logins_web)}</span></div>
      </article>
    </section>
  );
}

/* ── Version adoption ── */

function Adoption({ d }: { d: Stats }) {
  const latest = d.latest_release.version_name;
  const all = useMemo(() => [...new Set(d.version_adoption.flatMap((w) => Object.keys(w.versions)))], [d.version_adoption]);
  const groups = useMemo(() => versionGroups(all, latest), [all, latest]);
  const mandatory = [...d.release_markers].reverse().find((m) => m.mandatory);
  const empty = !d.version_adoption.some((w) => Object.keys(w.versions).length);

  const build = useCallback((t: ChartTheme): EChartsOption => {
    const labels = d.version_adoption.map((w) => dateLabel(w.week_end));
    const shares = d.version_adoption.map((w) => {
      const total = Object.values(w.versions).reduce((a, b) => a + b, 0) || 1;
      return groups.map((g) => (100 * Object.entries(w.versions).filter(([v]) => g.has(v)).reduce((a, [, n]) => a + n, 0)) / total);
    });
    let markIdx = -1;
    if (mandatory) {
      const md = mandatory.date;
      markIdx = d.version_adoption.findIndex((w) => w.week_end >= md);
    }
    const order = [...groups.keys()].reverse(); // oldest at the bottom
    return {
      grid: { left: 4, right: 8, top: markIdx >= 0 ? 34 : 8, bottom: 4, containLabel: true },
      tooltip: {
        ...TOOLTIP, trigger: "axis",
        formatter: (ps: unknown) => {
          const arr = ps as { dataIndex: number; seriesName: string; color: string; value: number }[];
          return `<b>Minggu s.d. ${labels[arr[0].dataIndex]}</b>` +
            [...arr].reverse().map((p) => tipRow(p.color, p.seriesName, pctTxt(p.value, 1))).join("");
        },
      },
      xAxis: {
        type: "category", data: labels, boundaryGap: false,
        axisLine: { show: false }, axisTick: { show: false },
        axisLabel: { color: t.mute, fontSize: 11, interval: Math.max(0, Math.ceil(labels.length / 5) - 1) },
      },
      yAxis: {
        type: "value", max: 100, interval: 50, axisLabel: { color: t.mute, fontSize: 11, formatter: "{value}%" },
        splitLine: { lineStyle: { color: t.rule } },
      },
      series: order.map((gi, n) => ({
        name: groups[gi].label, type: "line", stack: "v", smooth: 0.35, symbol: "none",
        lineStyle: { width: 0 }, areaStyle: { color: t[groups[gi].color] as string, opacity: 1 },
        color: t[groups[gi].color] as string,
        emphasis: { focus: "series" },
        data: shares.map((s) => +s[gi].toFixed(2)),
        ...(n === order.length - 1 && markIdx >= 0 && mandatory ? {
          markLine: {
            symbol: "none", silent: true, animation: false,
            lineStyle: { color: t.ink, type: "dashed", width: 1.2 },
            label: {
              formatter: `Wajib update v${mandatory.version} · ${dateLabel(mandatory.date)}`, position: "end",
              color: "#fff", backgroundColor: "#0F1F1D", borderRadius: 8, padding: [5, 8], fontSize: 11, fontWeight: 600,
            },
            data: [{ xAxis: markIdx }],
          },
        } : {}),
      })),
    };
  }, [d.version_adoption, groups, mandatory]);

  return (
    <article className="ui-card st-card st-adopt">
      <header className="st-head">
        <div>
          <h2 className="ui-card-title">Adopsi versi aplikasi</h2>
          <p className="ui-card-sub">% pengguna per versi, {d.version_adoption.length} minggu</p>
        </div>
        <div className="st-chips">
          {groups.map((g) => (
            <span key={g.label} className="st-lchip"><i className={`c-${g.color}`} /> {g.label}</span>
          ))}
        </div>
      </header>
      {empty
        ? <p className="st-empty">Belum ada perangkat Android yang mengirim versi aplikasinya.</p>
        : <EChart build={build} height={260} label="Grafik area bertumpuk adopsi versi aplikasi per minggu" />}
    </article>
  );
}

function Outdated({ d, now, onRemind }: { d: Stats; now: number; onRemind: (ids: number[]) => Promise<void> }) {
  const mandatory = d.latest_release.mandatory ? d.latest_release.version_name
    : [...d.release_markers].reverse().find((m) => m.mandatory)?.version ?? null;
  const below = mandatory ? d.outdated_users.filter((u) => versionKey(u.app_version) < versionKey(mandatory)).length : 0;
  const [busy, setBusy] = useState(false);
  return (
    <article className="ui-card st-card st-outdated">
      <header className="st-head">
        <div>
          <h2 className="ui-card-title">Masih di versi lama</h2>
          <p className="ui-card-sub">{nf(d.outdated_users.length)} pengguna{mandatory ? ` · ${nf(below)} di bawah versi wajib` : ""}</p>
        </div>
      </header>
      {d.outdated_users.length === 0
        ? <p className="st-empty">Semua pengguna Android sudah memakai versi terbaru.</p>
        : (
          <ul className="st-people">
            {d.outdated_users.slice(0, 4).map((u) => {
              const crit = mandatory != null && versionKey(u.app_version) < versionKey(mandatory);
              return (
                <li key={u.id}>
                  <Avatar name={u.full_name} />
                  <div className="st-person">
                    <b>{u.full_name}</b>
                    <span>{[u.department, relAgo(u.last_login, now)].filter(Boolean).join(" · ")}</span>
                  </div>
                  <span className={`st-ver ${crit ? "crit" : "old"}`}>v{u.app_version}</span>
                </li>
              );
            })}
          </ul>
        )}
      <button className="ui-btn lg primary st-full" disabled={!d.outdated_users.length || busy}
        onClick={async () => { setBusy(true); await onRemind(d.outdated_users.map((u) => u.id)); setBusy(false); }}>
        <BellRing size={20} /> Kirim pengingat update
      </button>
    </article>
  );
}

/* ── Downloads vs updates ── */

function Downloads({ d }: { d: Stats }) {
  const build = useCallback((t: ChartTheme): EChartsOption => {
    const tl = d.downloads_timeline;
    const labels = tl.map((x) => x.date);
    const markers = d.release_markers.filter((m) => labels.includes(m.date));
    const last = labels.length - 1;
    return {
      grid: { left: 4, right: 8, top: 30, bottom: 4, containLabel: true },
      tooltip: {
        ...TOOLTIP, trigger: "axis", axisPointer: { type: "line", lineStyle: { color: t.rule } },
        formatter: (ps: unknown) => {
          const arr = ps as { dataIndex: number; seriesName: string; color: string; value: number }[];
          const dt = new Date(`${labels[arr[0].dataIndex]}T00:00:00`);
          return `<b>${DAYS[(dt.getDay() + 6) % 7]}, ${dt.getDate()} ${MONTHS[dt.getMonth()]}</b>` +
            arr.map((p) => tipRow(p.color, p.seriesName, nf(p.value))).join("");
        },
      },
      xAxis: {
        type: "category", data: labels, axisLine: { show: false }, axisTick: { show: false },
        axisLabel: {
          color: t.mute, fontSize: 11, interval: 0,
          formatter: (v: string, i: number) => {
            if (i !== 0 && i !== last && i % 10 !== 0) return "";
            if (i === last && last % 10 < 4 && last % 10 !== 0) return "";
            const dt = new Date(`${v}T00:00:00`);
            return i === 0 ? `${dt.getDate()} ${MONTHS[dt.getMonth()]}` : String(dt.getDate());
          },
        },
      },
      yAxis: { type: "value", minInterval: 1, splitNumber: 2, axisLabel: { color: t.mute, fontSize: 11 }, splitLine: { lineStyle: { color: t.rule } } },
      series: [
        {
          name: "Unduhan baru", type: "bar", barWidth: "88%", color: t.teal300,
          itemStyle: { borderRadius: [3, 3, 0, 0], opacity: 0.9 },
          emphasis: { itemStyle: { color: t.teal600, opacity: 1 } },
          data: tl.map((x) => x.downloads),
          markLine: markers.length ? {
            symbol: "none", silent: true, animation: false,
            lineStyle: { color: t.ink, type: "dashed", width: 1 },
            label: {
              position: "end", formatter: (p: { name?: string }) => `v${p.name}`,
              color: "#fff", backgroundColor: "#074D45", borderRadius: 6, padding: [3, 6], fontSize: 10, fontWeight: 600,
            },
            data: markers.map((m) => ({ name: m.version, xAxis: m.date })),
          } : undefined,
        },
        {
          name: "Instal update", type: "line", smooth: 0.4, symbol: "circle", symbolSize: 8, showSymbol: false,
          color: t.teal600, lineStyle: { width: 2, color: t.teal600 },
          itemStyle: { color: t.surface, borderColor: t.teal600, borderWidth: 2 },
          data: tl.map((x) => x.updates),
        },
      ],
    };
  }, [d.downloads_timeline, d.release_markers]);

  return (
    <article className="ui-card st-card">
      <header className="st-head">
        <div>
          <h2 className="ui-card-title">Unduhan vs instal update</h2>
          <p className="ui-card-sub">Harian, {d.period_days} hari · penanda = rilis</p>
        </div>
        <div className="st-chips">
          <span className="st-lchip"><i className="c-teal300" /> Unduhan baru</span>
          <span className="st-lchip"><i className="c-teal600" /> Instal update</span>
        </div>
      </header>
      <EChart build={build} height={250} label="Grafik unduhan APK baru dan instal update harian" />
    </article>
  );
}

/* ── Login heatmap ── */

function Heatmap({ d }: { d: Stats }) {
  const h = d.login_heatmap;
  const max = Math.max(0, ...h.flat());
  let peak: [number, number] | null = null;
  h.forEach((row, di) => row.forEach((v, hr) => { if (v > 0 && (!peak || v > h[peak[0]][peak[1]])) peak = [di, hr]; }));
  const level = (v: number) => (v <= 0 || !max ? 0 : Math.min(5, Math.ceil((5 * v) / max)));
  const hh = (n: number) => String(n).padStart(2, "0");
  const p = peak as [number, number] | null;
  return (
    <article className="ui-card st-card st-heat">
      <header className="st-head">
        <div>
          <h2 className="ui-card-title">Aktivitas login</h2>
          <p className="ui-card-sub">Hari × jam, {d.period_days} hari terakhir</p>
        </div>
        {d.kpis.failed_logins > 0 && <span className="st-badge-danger"><Lock size={13} /> {nf(d.kpis.failed_logins)} login gagal</span>}
      </header>
      <div className="st-heat-grid" role="table" aria-label="Jumlah login per hari dan jam (WIB)">
        {DAYS.map((day, di) => (
          <div key={day} className="st-heat-row" role="row">
            <span className="st-heat-day" role="rowheader">{day}</span>
            {h[di].map((v, hr) => (
              <span key={hr} role="cell" className={`st-cell l${level(v)}`}
                title={`${day} ${hh(hr)}.00–${hh((hr + 1) % 24)}.00 · ${nf(v)} login`} />
            ))}
          </div>
        ))}
        <div className="st-heat-row st-heat-hours" aria-hidden="true">
          <span className="st-heat-day" />
          {Array.from({ length: 24 }, (_, i) => <span key={i}>{i % 3 === 0 ? hh(i) : ""}</span>)}
        </div>
      </div>
      <div className="st-heat-scale">
        Sepi {[1, 2, 3, 4, 5].map((l) => <span key={l} className={`st-cell l${l}`} />)} Ramai
        {p && <> · puncak {DAYS[p[0]]} {hh(p[1])}.00–{hh((p[1] + 1) % 24)}.00</>}
      </div>
    </article>
  );
}

/* ── Failed logins ── */

function Failed({ d, now }: { d: Stats; now: number }) {
  const f = d.failed_summary;
  const max = Math.max(1, ...f.reasons.map((r) => r.count));
  return (
    <article className="ui-card st-card st-failed">
      <header className="st-head">
        <div>
          <h2 className="ui-card-title">Login gagal &amp; keamanan</h2>
          <p className="ui-card-sub">Dari login_audit · {d.period_days} hari</p>
        </div>
      </header>
      <div className="st-failed-big">
        <b>{nf(f.total)}</b>
        <span>login gagal · {f.attempts ? pctTxt((100 * f.total) / f.attempts, 1) : "0%"} dari {nf(f.attempts)} percobaan</span>
      </div>
      <ul className="st-reasons">
        {f.reasons.map((r) => (
          <li key={r.key}>
            <span>{r.label}</span>
            <i><s style={{ width: `${(100 * r.count) / max}%` }} /></i>
            <b>{nf(r.count)}</b>
          </li>
        ))}
      </ul>
      <span className="st-eyebrow">Terbaru</span>
      {d.failed_logins_recent.length === 0
        ? <p className="st-empty">Tidak ada login gagal pada periode ini.</p>
        : (
          <ul className="st-fail-list">
            {d.failed_logins_recent.slice(0, 3).map((x, i) => (
              <li key={i}>
                <span className="st-lock"><Lock size={16} /></span>
                <div>
                  <b>{x.email || x.username || "tidak dikenal"}</b>
                  <span>{[x.ip, x.client].filter(Boolean).join(" · ")}</span>
                </div>
                <time dateTime={x.at}>{stamp(x.at, now, true)}</time>
              </li>
            ))}
          </ul>
        )}
    </article>
  );
}

/* ── Users table ── */

type FilterKey = "department" | "version" | "platform" | "status";
const SORTS = [
  { key: "last_login", label: "login terakhir" },
  { key: "login_count", label: "jumlah login" },
  { key: "name", label: "nama" },
] as const;

function UsersTable({ d, now, selected, onSelect, onExport }: {
  d: Stats; now: number; selected: number | null; onSelect: (id: number) => void; onExport: (rows: UserRow[]) => void;
}) {
  const [q, setQ] = useState("");
  const [filters, setFilters] = useState<Record<FilterKey, string>>({ department: "", version: "", platform: "", status: "" });
  const [open, setOpen] = useState<FilterKey | "sort" | null>(null);
  const [sort, setSort] = useState<(typeof SORTS)[number]["key"]>("last_login");
  const [page, setPage] = useState(0);

  useEffect(() => {
    if (!open) return;
    const close = () => setOpen(null);
    document.addEventListener("click", close);
    return () => document.removeEventListener("click", close);
  }, [open]);

  const options: Record<FilterKey, { value: string; label: string }[]> = useMemo(() => ({
    department: [...new Set(d.users.map((u) => u.department).filter((x): x is string => !!x))].sort().map((x) => ({ value: x, label: x })),
    version: [{ value: "latest", label: "Versi terbaru" }, { value: "old", label: "Versi lama" },
      ...[...new Set(d.users.map((u) => u.app_version).filter((x): x is string => !!x))]
        .sort((a, b) => versionKey(b) - versionKey(a)).map((v) => ({ value: v, label: `v${v}` }))],
    platform: [{ value: "android", label: "Android" }, { value: "web", label: "Web" }],
    status: [{ value: "aktif", label: "Aktif" }, { value: "tidak_aktif", label: "Tidak aktif" }],
  }), [d.users]);

  const rows = useMemo(() => {
    const term = q.trim().toLowerCase();
    const out = d.users.filter((u) =>
      (!term || `${u.full_name} ${u.email} ${u.username}`.toLowerCase().includes(term)) &&
      (!filters.department || u.department === filters.department) &&
      (!filters.platform || u.platform === filters.platform) &&
      (!filters.status || u.status === filters.status) &&
      (!filters.version || (filters.version === "latest" ? u.is_latest : filters.version === "old" ? !!u.app_version && !u.is_latest : u.app_version === filters.version)));
    if (sort === "login_count") out.sort((a, b) => b.login_count - a.login_count);
    else if (sort === "name") out.sort((a, b) => a.full_name.localeCompare(b.full_name, "id"));
    else out.sort((a, b) => (b.last_login ?? "").localeCompare(a.last_login ?? ""));
    return out;
  }, [d.users, q, filters, sort]);

  const pages = Math.max(1, Math.ceil(rows.length / PAGE));
  const cur = Math.min(page, pages - 1);
  const shown = rows.slice(cur * PAGE, cur * PAGE + PAGE);
  const latest = d.latest_release.version_name;
  const mandatory = d.latest_release.mandatory ? latest : [...d.release_markers].reverse().find((m) => m.mandatory)?.version ?? null;
  const LABEL: Record<FilterKey, string> = { department: "Departemen", version: "Versi", platform: "Platform", status: "Status" };
  const setFilter = (k: FilterKey, v: string) => { setFilters((f) => ({ ...f, [k]: v })); setPage(0); setOpen(null); };

  return (
    <article className="ui-card st-card st-users">
      <header className="st-users-bar">
        <div>
          <h2 className="ui-card-title">Akses pengguna</h2>
          <p className="ui-card-sub">{nf(d.users.length)} pengguna · diurutkan berdasarkan {SORTS.find((s) => s.key === sort)!.label}</p>
        </div>
        <label className="st-search">
          <Search size={18} aria-hidden="true" />
          <input value={q} onChange={(e) => { setQ(e.target.value); setPage(0); }} placeholder="Cari nama atau email…" aria-label="Cari nama atau email" />
        </label>
        <button className="ui-btn st-csv" onClick={() => onExport(rows)}><Download size={18} /> Export CSV</button>
      </header>

      <div className="st-filters">
        {(Object.keys(LABEL) as FilterKey[]).map((k) => {
          const val = filters[k];
          const active = !!val;
          return (
            <div key={k} className="st-filter">
              <button className={`ui-chip ${active ? "teal" : ""}`} aria-expanded={open === k}
                onClick={(e) => { e.stopPropagation(); setOpen(open === k ? null : k); }}>
                {active ? <Filter size={16} /> : <ChevronDown size={16} />}
                {LABEL[k]}: {active ? options[k].find((o) => o.value === val)?.label ?? val : "semua"}
              </button>
              {open === k && (
                <div className="ui-popover st-pop" role="menu" onClick={(e) => e.stopPropagation()}>
                  <button role="menuitemradio" aria-checked={!val} onClick={() => setFilter(k, "")}>Semua</button>
                  {options[k].map((o) => (
                    <button key={o.value} role="menuitemradio" aria-checked={val === o.value} onClick={() => setFilter(k, o.value)}>{o.label}</button>
                  ))}
                </div>
              )}
            </div>
          );
        })}
        <div className="st-filter">
          <button className="ui-link st-sort" aria-expanded={open === "sort"} onClick={(e) => { e.stopPropagation(); setOpen(open === "sort" ? null : "sort"); }}>
            Urutkan: {SORTS.find((s) => s.key === sort)!.label}
          </button>
          {open === "sort" && (
            <div className="ui-popover st-pop" role="menu" onClick={(e) => e.stopPropagation()}>
              {SORTS.map((s) => (
                <button key={s.key} role="menuitemradio" aria-checked={sort === s.key} onClick={() => { setSort(s.key); setOpen(null); }}>{s.label}</button>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="ui-table-wrap">
        <table className="ui-table st-table">
          <thead>
            <tr>
              <th>Pengguna</th><th>Departemen</th><th>Platform</th><th>Versi</th><th className="st-hide-md">Perangkat</th>
              <th aria-sort={sort === "last_login" ? "descending" : undefined}>Login terakhir{sort === "last_login" ? " ↓" : ""}</th>
              <th aria-sort={sort === "login_count" ? "descending" : undefined}>Login{sort === "login_count" ? " ↓" : ""}</th>
              <th className="st-hide-md">Aktivitas</th><th>Status</th>
            </tr>
          </thead>
          <tbody>
            {shown.map((u) => {
              const stale = !u.last_login || now - new Date(u.last_login).getTime() > 14 * 864e5;
              const crit = !!u.app_version && mandatory != null && versionKey(u.app_version) < versionKey(mandatory);
              return (
                <tr key={u.id} className={selected === u.id ? "hl" : ""} tabIndex={0}
                  onClick={() => onSelect(u.id)} onKeyDown={(e) => { if (e.key === "Enter") onSelect(u.id); }}>
                  <td>
                    <div className="st-user">
                      <Avatar name={u.full_name || u.username} />
                      <div><b>{u.full_name || u.username}</b><span>{u.email}</span></div>
                    </div>
                  </td>
                  <td>{u.department || "–"}</td>
                  <td><span className="st-plat">{u.platform === "android" ? <Radio size={16} /> : <Monitor size={16} />}{u.platform === "android" ? "Android" : "Web"}</span></td>
                  <td>{u.app_version ? <span className={`st-ver ${u.is_latest ? "ok" : crit ? "crit" : "old"}`}>v{u.app_version}</span> : <span className="st-mute">—</span>}</td>
                  <td className="wrap st-dev st-hide-md">{u.device_model ? (u.platform === "web" ? u.device_model.replace(" ", " · ") : u.device_model) : "–"}</td>
                  <td>
                    <div className="st-when">
                      <b className={stale ? "stale" : ""}>{u.last_login ? relAgo(u.last_login, now) : "Belum pernah"}</b>
                      {u.last_login && <span>{stamp(u.last_login, now, false)}</span>}
                    </div>
                  </td>
                  <td className="st-num">{nf(u.login_count)}</td>
                  <td className="wrap st-act st-hide-md">{u.last_activity?.label ?? "–"}</td>
                  <td><span className={`st-status ${u.status}`}>{u.status === "aktif" ? "Aktif" : "Tidak aktif"}</span></td>
                </tr>
              );
            })}
            {!shown.length && <tr><td colSpan={9} className="st-empty-row">Tidak ada pengguna yang cocok.</td></tr>}
          </tbody>
        </table>
      </div>

      <footer className="st-pager">
        <span>{rows.length ? `${cur * PAGE + 1}–${Math.min(rows.length, cur * PAGE + PAGE)} dari ${nf(rows.length)}` : "0 pengguna"}</span>
        <nav aria-label="Halaman">
          <button aria-label="Sebelumnya" disabled={cur === 0} onClick={() => setPage(cur - 1)}><ChevronLeft size={16} /></button>
          {pageList(cur, pages).map((p, i) => p < 0
            ? <span key={`e${i}`}>…</span>
            : <button key={p} aria-current={p === cur ? "page" : undefined} onClick={() => setPage(p)}>{p + 1}</button>)}
          <button aria-label="Berikutnya" disabled={cur >= pages - 1} onClick={() => setPage(cur + 1)}><ChevronRight size={16} /></button>
        </nav>
      </footer>
    </article>
  );
}

/** 0-based pages to show: first three (or a window around the current), an ellipsis (-1) and the last. */
function pageList(cur: number, n: number): number[] {
  if (n <= 5) return Array.from({ length: n }, (_, i) => i);
  if (cur < 3) return [0, 1, 2, -1, n - 1];
  if (cur > n - 4) return [0, -1, n - 3, n - 2, n - 1];
  return [0, -1, cur, -1, n - 1];
}
