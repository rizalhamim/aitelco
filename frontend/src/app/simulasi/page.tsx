"use client";
/* v3 06 Simulasi Target (design/mockup-v3/features/06-simulasi-target.html): will this
   month's target be reached, how big is the gap, what daily run-rate is needed, and what moves
   the estimate. The server returns the estimate, band and lever formulas; levers are applied
   here so sliders answer instantly. The scenario lives in the URL (?s=rate:1.5,sites:20). */
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { Fan, getJson, Tap, V3State, V3Top, type FanData } from "../components/v3/V3";
import { authFetch } from "@/lib/auth";
import "../v3.css";

type Effect = { type: "pct_of"; base: number } | { type: "fixed"; amount: number } | { type: "per_unit"; amount: number };
type Lever = { key: string; kind: "slider" | "toggle" | "locked"; label: string; note: string; unit?: string; min?: number; max?: number; step?: number;
  value?: number; value_label?: string; effect?: Effect };
type Region = { region: string; label: string; color: string; mtd: number; estimate: number; target: number | null; gap: number | null; per_day: number; need_per_day: number | null };
export type Sim = {
  metric: string; metric_label: string; unit: string; region: string | null; scope_label: string; month_label: string; title: string;
  basis: { data_until: string; source_note: string; remaining_days: number; weekend_days: number; target_source: string | null };
  days_elapsed: number; days_in_month: number; mtd: number; per_day: number;
  estimate: { mid: number; lo: number; hi: number; pct: number | null };
  target: number | null; target_vs_prev_pct: number | null; prev_month_label: string; gap: number | null; need_per_day: number | null;
  path: null | { days: number; today: number; act: number[]; mid: number[]; lo: number[]; hi: number[]; target_per_day: number; month_short: string };
  regions: Region[]; levers: Lever[]; target_note: string | null; method: string;
};

const METRIC_SEG = [["revenue", "Revenue"], ["fwa_gross_add", "Gross add FWA"], ["subs", "RGU 90D"]] as const;
const MINUS = "−";
const num = (v: number, d = 0) => v.toLocaleString("id-ID", { minimumFractionDigits: d, maximumFractionDigits: d });
const sgn = (v: number) => (v > 0 ? "+" : v < 0 ? MINUS : "");
/** v3_common.rp: "Rp 1,87 T", "Rp 61,7 M", "Rp 25 jt". */
function rp(v: number, sign = false) {
  const pre = sign ? sgn(v) : v < 0 ? MINUS : "", a = Math.abs(v);
  for (const [div, u, d] of [[1e12, "T", 2], [1e9, "M", 1], [1e6, "jt", 0]] as const) if (a >= div * (d === 2 ? 0.995 : 0.95)) return `${pre}Rp ${num(a / div, d)} ${u}`;
  return `${pre}Rp ${num(a, 0)}`;
}
/** Always in Rp miliar; whole numbers from Rp 10 M ("−Rp 27 M", "+Rp 0,3 M"). */
const rpm = (v: number, sign = false) => `${sign ? sgn(v) : v < 0 ? MINUS : ""}Rp ${num(Math.abs(v) / 1e9, Math.abs(v) >= 1e10 && !sign ? 0 : 1)} M`;
const cnt = (v: number, sign = false) => (sign ? sgn(v) : v < 0 ? MINUS : "") + (Math.abs(v) >= 1e6 ? `${num(Math.abs(v) / 1e6, 2)} jt` : num(Math.abs(Math.round(v))));

function parseS(s: string | null): Record<string, number> {
  const out: Record<string, number> = {};
  (s || "").split(",").forEach((p) => { const [k, v] = p.split(":"); if (k && v !== undefined && !Number.isNaN(Number(v))) out[k] = Number(v); });
  return out;
}
const lever = (l: Lever, v: number) => !l.effect ? 0 : l.effect.type === "pct_of" ? l.effect.base * v / 100 : l.effect.type === "fixed" ? (v ? l.effect.amount : 0) : l.effect.amount * v;
function niceStep(raw: number) { const p = 10 ** Math.floor(Math.log10(raw || 1)); return [1, 2, 5, 10].map((k) => k * p).find((s) => s >= raw) ?? 10 * p; }
function niceMax(v: number) { const p = 10 ** Math.floor(Math.log10(v || 1)); return Math.ceil((v / p) * 2) / 2 * p; }
const lowerFirst = (s: string) => (s[1] && s[1] === s[1].toLowerCase() ? s[0].toLowerCase() + s.slice(1) : s);

function SimulasiView() {
  const router = useRouter();
  const sp = useSearchParams();
  const [metric, setMetric] = useState(sp.get("metric") || "revenue");
  const [region, setRegion] = useState(sp.get("region") || "");
  const [vals, setVals] = useState<Record<string, number>>(() => parseS(sp.get("s")));
  const [data, setData] = useState<Sim | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    authFetch(`/api/simulasi?${new URLSearchParams({ metric, region })}`).then((r) => getJson<Sim>(r))
      .then((d) => { setData(d); setError(null); }).catch((e) => setError(e.message));
  }, [metric, region]);
  // keep the scenario shareable without a navigation per slider step
  useEffect(() => {
    const q = new URLSearchParams();
    if (metric !== "revenue") q.set("metric", metric);
    if (region) q.set("region", region);
    const s = Object.entries(vals).filter(([, v]) => v).map(([k, v]) => `${k}:${v}`).join(",");
    if (s) q.set("s", s);
    window.history.replaceState(null, "", `/simulasi${q.size ? "?" + q : ""}`);
  }, [metric, region, vals]);

  const flash = (t: string) => { setNote(t); window.setTimeout(() => setNote(null), 2600); };
  const idr = data?.unit === "IDR";
  const big = (v: number) => (idr ? rp(v) : cnt(v));
  const eff = (v: number) => (idr ? rpm(v, true) : cnt(v, true));

  const sc = useMemo(() => {
    if (!data) return null;
    const live = data.levers.filter((l) => l.kind !== "locked").map((l) => {
      const v = vals[l.key] ?? l.value ?? 0;
      return { l, v, e: lever(l, v) };
    });
    const total = live.reduce((a, x) => a + x.e, 0);
    const est = data.estimate.mid + total;
    return { live, total, est, pct: data.target ? est / data.target * 100 : null,
      rate: data.basis.remaining_days ? (est - data.mtd) / data.basis.remaining_days : null };
  }, [data, vals]);

  const unit = idr ? { div: 1e9, name: "Rp miliar" } : data && Math.max(...data.regions.map((r) => Math.abs(r.estimate)), 0) >= 1e5 ? { div: 1e3, name: "Ribu" } : { div: 1, name: "Jumlah" };

  const fan: FanData | null = useMemo(() => {
    const p = data?.path;
    if (!data || !p || !sc) return null;
    const d = (xs: number[]) => xs.map((v) => v / unit.div);
    const act = d(p.act), mid = d(p.mid), lo = d(p.lo), hi = d(p.hi), n = Math.max(mid.length - 1, 1);
    const alt = sc.total ? mid.map((v, i) => v + (sc.total / unit.div) * i / n) : null;
    const all = [0, ...act, ...lo, ...hi, ...(alt || [])];
    let mn = Math.min(...all), mx = Math.max(...all);
    const step = niceStep((mx - mn) / 4 || 1);
    mn = Math.floor(mn / step) * step; mx = Math.ceil(mx / step) * step;
    if (mx === Math.max(...all)) mx += step;
    const ticks: number[] = [];
    for (let t = mn; t <= mx + 1e-9; t += step) ticks.push(Math.round(t * 1000) / 1000);
    const lab = (v: number) => sgn(Math.round(v)) + num(Math.abs(Math.round(v)));
    return { days: p.days, today: p.today, min: mn, max: mx, ticks, act, mid, lo, hi, alt, target: 0, targetLabel: "Jalur target",
      midLabel: `Estimasi ${lab(mid[mid.length - 1] ?? act[act.length - 1])}`, altLabel: alt ? `Skenario ${lab(alt[alt.length - 1])}` : "",
      dayLabel: (x: number) => `${x} ${p.month_short}` };
  }, [data, sc, unit.div]);

  function set(k: string, v: number) { setVals((o) => ({ ...o, [k]: v })); }

  async function save() {
    if (!data || !sc) return;
    const active = sc.live.filter((x) => x.v);
    const r = await authFetch("/api/ruang/pins", { method: "POST", body: JSON.stringify({
      kind: "kpi", origin: "simulasi", title: data.title,
      subtitle: active.length ? `Skenario: ${active.map((x) => valueLabel(x.l, x.v)).join(", ")}` : "Estimasi tanpa skenario",
      spec: { type: "simulasi", metric: data.metric, region: data.region || "", scenario: Object.fromEntries(active.map((x) => [x.l.key, x.v])) } }) });
    flash(r.ok ? "Skenario disimpan ke Ruang Saya" : "Skenario gagal disimpan");
  }
  async function task() {
    if (!data || !sc) return;
    const need = data.need_per_day;
    const lvl = data.region ? "region" : "circle";
    const body = {
      title: `Kejar target ${data.metric_label} ${data.scope_label} ${data.month_label}`.slice(0, 200), origin: "simulasi",
      region: data.region, impact: data.gap, origin_ref: { metric: data.metric, region: data.region, scenario: vals },
      kpi: need != null ? { metric: data.metric, mode: "per_day", op: ">=", threshold: need, level: lvl, name: data.region || "JAVA",
        text: `Selesai jika ${lowerFirst(data.metric_label)} ${data.scope_label} ≥ ${idr ? rp(need) : cnt(need)} per hari` } : null,
      items: sc.live.filter((x) => x.v).map((x) => (x.l.kind === "toggle" ? `${x.l.label} ke ${(x.l.value_label || "").toLowerCase()}` : `${x.l.label} ${valueLabel(x.l, x.v)}`)),
    };
    const r = await authFetch("/api/tindak/tasks", { method: "POST", body: JSON.stringify(body) });
    if (!r.ok) { flash("Tugas gagal dibuat"); return; }
    router.push(`/tindak?task=${(await r.json()).id}`);
  }

  const d = data;
  return (
    <AppShell>
      <V3Top title="Simulasi Target" subtitle="Estimasi akhir bulan, gap ke target, dan skenario" region={region} onRegion={(v) => { setRegion(v); setVals({}); }} month={d?.month_label} />
      <div className="v3 f-06-simulasi-target">
        <V3State error={error} loading={!d && !error} />
        {d && sc && (
          <div className="body">
            <div className="col">
              <div className="hd"><div><div className="eb">Simulasi target · estimasi</div><h1>{d.title}</h1></div>
                <div className="grow" /><div className="seg">{METRIC_SEG.map(([k, l]) => <button key={k} className={metric === k ? "on" : ""} onClick={() => { setMetric(k); setVals({}); }}>{l}</button>)}</div></div>
              <div className="basis">
                <span><Icon name="db" />Data sampai {d.basis.data_until}{d.basis.source_note ? ` (${d.basis.source_note})` : ""}</span>
                <span><Icon name="cal" />Sisa {d.basis.remaining_days} hari, termasuk {d.basis.weekend_days} hari akhir pekan</span>
                {d.basis.target_source ? <span><Icon name="file" />Target dari {d.basis.target_source}</span> : <span><Icon name="warn" />Target belum diisi</span>}
              </div>
              <div className="kr">
                <div className="kx"><small>Realisasi MTD</small><b>{big(d.mtd)}</b><span>{d.days_elapsed} hari · {big(d.per_day)} per hari</span></div>
                <div className="kx e"><small>Akhir bulan <span className="est">Estimasi</span></small><b>{big(d.estimate.mid)}</b>
                  <span>{d.estimate.pct != null ? `${num(d.estimate.pct, 1)}% · ` : ""}rentang {big(d.estimate.lo)} sd {big(d.estimate.hi)}</span></div>
                <div className="kx"><small>Target</small><b>{d.target != null ? big(d.target) : "–"}</b>
                  <span>{d.target == null ? "Belum diisi di targets.json" : d.target_vs_prev_pct != null ? `${d.target_vs_prev_pct >= 0 ? "naik" : "turun"} ${num(Math.abs(d.target_vs_prev_pct), 1)}% dari realisasi ${d.prev_month_label}` : "dari targets.json"}</span></div>
                <div className={`kx ${d.gap != null && d.gap < 0 ? "g" : ""}`}><small>Gap estimasi</small><b style={d.gap != null && d.gap >= 0 ? { color: "#1F7A3A" } : undefined}>{d.gap != null ? (idr ? rpm(d.gap, d.gap > 0) : cnt(d.gap, true)) : "–"}</b>
                  <span>{d.need_per_day != null ? `perlu ${big(d.need_per_day)} per hari, kini ${big(d.per_day)}` : "perlu target untuk menghitung"}</span></div>
              </div>
              {d.target_note && <div className="say">{d.target_note}</div>}
              {fan && d.path && (
                <section className="card" aria-label="Fan chart">
                  <div className="ch"><div><h3>Selisih terhadap jalur target</h3><p>{unit.name}, kumulatif. Nol = tepat di jalur {big(d.path.target_per_day)} per hari. Di bawah nol = tertinggal. Garis tebal realisasi, garis putus estimasi dengan rentang 80%, ungu skenario kamu.</p></div></div>
                  <Fan f={fan} width={686} height={300} pr={100} />
                  <div className="leg"><span><i style={{ borderColor: "#0E8579" }} />Realisasi</span><span><i className="ds" style={{ borderColor: "#0E8579" }} />Estimasi</span><span><i className="bd" />Rentang 80% (P10 sd P90)</span>
                    <span><i className="ds" style={{ borderColor: "#6A4CB5" }} />Skenario</span><span><i style={{ borderColor: "#C42B2B", borderTopWidth: 2 }} />Jalur target</span></div>
                </section>
              )}
              <RegionTable d={d} div={unit.div} unitName={unit.name} />
            </div>
            <aside className="sc" aria-label="Skenario">
              <h3>Coba skenario</h3>
              <p>Geser tuas untuk melihat dampaknya ke estimasi akhir bulan. Hanya tuas yang datanya ada di Performance dump.</p>
              {d.levers.map((l) => l.kind === "locked" ? (
                <div key={l.key} className="lv lock"><div className="t"><Icon name="lock" />{l.label}</div><small>{l.note}</small><div className="sl" /></div>
              ) : (
                <LeverRow key={l.key} l={l} v={vals[l.key] ?? l.value ?? 0} onChange={(v) => set(l.key, v)} effect={eff(lever(l, vals[l.key] ?? l.value ?? 0))} />
              ))}
              <div className="res"><small>Hasil skenario <span className="est" style={{ background: "rgba(255,255,255,.18)", color: "#fff" }}>Estimasi</span></small>
                <b>{big(sc.est)}{sc.pct != null ? ` · ${num(sc.pct, 1)}%` : ""}</b><span>{resultText(d, sc)}</span>
                <div className="r"><em>{eff(sc.total)}</em>{sc.rate != null && <em>perlu {big(sc.rate)}/hari</em>}</div></div>
              <div className="btns"><Tap onClick={save}><Icon name="layers" />Simpan skenario</Tap><Tap className="pri" onClick={task}><Icon name="check" />Jadikan tugas</Tap></div>
              <div className="method"><Icon name="info" />{d.method}</div>
            </aside>
            {note && <div className="v3toast" role="status">{note}</div>}
          </div>
        )}
      </div>
    </AppShell>
  );
}

function valueLabel(l: Lever, v: number) {
  if (l.kind === "toggle") return v ? l.value_label || "Aktif" : "Tidak";
  if (l.unit === "%") return `${v > 0 ? "+" : ""}${num(v, (l.step ?? 1) < 1 ? 1 : 0)}%`;
  return `${num(v)} ${l.unit || ""}`.trim();
}

function resultText(d: Sim, sc: { live: { l: Lever; v: number; e: number }[]; total: number; est: number }) {
  const on = sc.live.filter((x) => x.v);
  if (!on.length) return "Geser tuas untuk melihat dampaknya. Tanpa skenario, hasil sama dengan estimasi.";
  const parts: string[] = [];
  if (d.target != null) parts.push(sc.est >= d.target ? "Gap tertutup." : `Gap tersisa ${d.unit === "IDR" ? rpm(d.target - sc.est) : cnt(d.target - sc.est)}.`);
  const top = [...on].sort((a, b) => b.e - a.e);
  parts.push(`Tuas terbesar: ${lowerFirst(top[0].l.label)}.`);
  const weak = top.length > 1 ? top[top.length - 1] : null;
  if (weak && sc.total && weak.e / sc.total < 0.05) parts.push(`${weak.l.label.replace(/ on air$/, "")} hampir tidak berpengaruh bulan ini.`);
  return parts.join(" ");
}

function LeverRow({ l, v, onChange, effect }: { l: Lever; v: number; onChange: (v: number) => void; effect: string }) {
  const ref = useRef<HTMLDivElement>(null);
  const lo = l.min ?? 0, hi = l.kind === "toggle" ? 1 : l.max ?? 1, step = l.kind === "toggle" ? 1 : l.step ?? 1;
  const pct = ((v - lo) / (hi - lo || 1)) * 100;
  const fromX = useCallback((x: number) => {
    const r = ref.current?.getBoundingClientRect();
    if (!r) return;
    const raw = lo + Math.min(1, Math.max(0, (x - r.left) / r.width)) * (hi - lo);
    onChange(Math.round(Math.round(raw / step) * step * 100) / 100);
  }, [lo, hi, step, onChange]);
  const key = (e: React.KeyboardEvent) => {
    const dir = e.key === "ArrowRight" || e.key === "ArrowUp" ? 1 : e.key === "ArrowLeft" || e.key === "ArrowDown" ? -1 : 0;
    if (dir) { e.preventDefault(); onChange(Math.min(hi, Math.max(lo, Math.round((v + dir * step) * 100) / 100))); }
    else if (l.kind === "toggle" && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); onChange(v ? 0 : 1); }
  };
  return (
    <div className="lv"><div className="t">{l.label}<span className="grow" /><b>{valueLabel(l, v)}</b></div><small>{l.note}</small>
      <div ref={ref} className="sl" role="slider" tabIndex={0} aria-label={l.label} aria-valuemin={lo} aria-valuemax={hi} aria-valuenow={v} aria-valuetext={valueLabel(l, v)}
        style={{ cursor: "pointer", touchAction: "none" }} onKeyDown={key}
        onPointerDown={(e) => { if (l.kind === "toggle") { onChange(v ? 0 : 1); return; } (e.target as Element).setPointerCapture?.(e.pointerId); fromX(e.clientX); }}
        onPointerMove={(e) => { if (l.kind !== "toggle" && e.buttons) fromX(e.clientX); }}>
        <i style={{ width: `${pct}%` }} /><em style={{ left: `${pct}%` }} />
        {l.kind === "slider" && <><span className="tk" style={{ left: 0 }}>{l.unit === "%" ? `${num(lo)}%` : num(lo)}</span><span className="tk" style={{ left: "100%" }}>{l.unit === "%" ? `+${num(hi)}%` : num(hi)}</span></>}
      </div>
      <div className="eff" style={{ marginTop: l.kind === "slider" ? 10 : 4 }}>Dampak<b>{effect}</b></div></div>
  );
}

function RegionTable({ d, div, unitName }: { d: Sim; div: number; unitName: string }) {
  if (!d.regions.length) return null;
  const n1 = (v: number) => num(v / div, 1), n0 = (v: number) => num(Math.round(v / div));
  const scale = niceMax(Math.max(...d.regions.flatMap((r) => [r.per_day, r.need_per_day ?? 0])) / div);
  const gapCell = (g: number | null) => g == null ? <td>–</td> : <td className={g >= 0 ? "up" : "dn"}>{sgn(Math.round(g / div)) + num(Math.abs(Math.round(g / div)))}</td>;
  return (
    <section className="card" aria-label="Per region" style={{ paddingBottom: 8 }}>
      <div className="ch"><div><h3>Gap dan run-rate per region</h3><p>{unitName}. Run-rate perlu = (target dikurangi realisasi) dibagi {d.basis.remaining_days} hari tersisa.</p></div></div>
      <table className="rt2"><thead><tr><th>Region</th><th>Realisasi MTD</th><th>Estimasi</th><th>Target</th><th>Gap</th><th>Per hari: kini vs perlu</th></tr></thead><tbody>
        {d.regions.map((r) => {
          const ok = (r.gap ?? 0) >= 0 || (r.need_per_day != null && r.per_day >= r.need_per_day);
          return (
            <tr key={r.region}><td><span className="rn"><i style={{ background: r.color }} />{r.label}</span></td><td>{n1(r.mtd)}</td><td><em>{n0(r.estimate)}</em></td>
              <td>{r.target != null ? n0(r.target) : "–"}</td>{gapCell(r.gap)}
              <td><span className="rr"><span className="bar"><i style={{ width: `${Math.round((r.per_day / div / scale) * 100)}%`, background: ok ? "#2FA84F" : "#C42B2B" }} />
                {r.need_per_day != null && <em style={{ left: `${Math.round((r.need_per_day / div / scale) * 1000) / 10}%` }} />}</span>
                {n1(r.per_day)} vs {r.need_per_day != null ? n1(r.need_per_day) : "–"}</span></td></tr>
          );
        })}
        {!d.region && d.regions.length > 1 && (
          <tr><td><b>Circle Java</b></td><td><b>{n1(d.mtd)}</b></td><td><em>{n0(d.estimate.mid)}</em></td><td><b>{d.target != null ? n0(d.target) : "–"}</b></td>{gapCell(d.gap)}
            <td><b>{n1(d.per_day)} vs {d.need_per_day != null ? n1(d.need_per_day) : "–"}</b></td></tr>
        )}
      </tbody></table>
    </section>
  );
}

export default function SimulasiPage() {
  return <Suspense fallback={<div className="ui-boot" />}><SimulasiView /></Suspense>;
}
