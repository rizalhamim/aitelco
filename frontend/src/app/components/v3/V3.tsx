"use client";
/* Shared pieces of the Agent Java v3 pages (design/mockup-v3). The chart drawings follow
   design/mockup-v3/_base/draw.js line by line so the pages match the mockup PNGs. */
import { Fragment, useId, type ReactNode } from "react";
import { TopBar } from "@/app/components/shell/AppShell";
import { Icon } from "@/app/components/v2/Icon";

/** Rich text from the API: [{t, s?}] where s "b" is the lime highlight and "e" the peach one. */
export type Seg = { t: string; s?: "b" | "e" };
export function Rich({ segs }: { segs?: Seg[] | null }) {
  if (!segs) return null;
  return <>{segs.map((x, i) => x.s === "b" ? <b key={i}>{x.t}</b> : x.s === "e" ? <em key={i}>{x.t}</em> : <Fragment key={i}>{x.t}</Fragment>)}</>;
}
export const plain = (segs?: Seg[] | null) => (segs || []).map((s) => s.t).join("");

/** Region chip of the v3 top bar: looks like the mockup chip, works as a native select. */
export const REGION_OPTIONS = [
  { key: "", label: "Semua region" },
  { key: "WEST JAVA", label: "West Java" },
  { key: "CENTRAL JAVA", label: "Central Java" },
  { key: "EAST JAVA", label: "East Java" },
];
export function RegionChip({ value, onChange }: { value: string; onChange?: (v: string) => void }) {
  const label = REGION_OPTIONS.find((o) => o.key === value)?.label ?? "Semua region";
  return (
    <label className="chip teal v3chip"><Icon name="pin" />{label}
      {onChange && <select value={value} onChange={(e) => onChange(e.target.value)} aria-label="Region">
        {REGION_OPTIONS.map((o) => <option key={o.key} value={o.key}>{o.label}</option>)}
      </select>}
    </label>
  );
}
export function MonthChip({ label }: { label: string }) {
  return <span className="chip"><Icon name="cal" />{label}</span>;
}
/** Top bar of every v3 page: title, subtitle, region and month chips, alert bell, avatar. */
export function V3Top({ title, subtitle, region = "", onRegion, month, extra }: {
  title: string; subtitle?: ReactNode; region?: string; onRegion?: (v: string) => void; month?: string; extra?: ReactNode;
}) {
  return <TopBar title={title} subtitle={subtitle} actions={<>{extra}<RegionChip value={region} onChange={onRegion} />{month && <MonthChip label={month} />}</>} />;
}

/** draw.js sparkline: min-max scaled line, optional area fill, dot on the last point. */
export function Spark({ values, color, width, height, area = true, className = "spark" }: {
  values: number[]; color: string; width: number; height: number; area?: boolean; className?: string;
}) {
  const gid = "spk" + useId().replace(/[^a-zA-Z0-9]/g, "");
  if (!values || values.length < 2) return <svg className={className} width={width} height={height} aria-hidden="true" />;
  const mn = Math.min(...values), mx = Math.max(...values);
  const X = (i: number) => 2 + ((width - 6) * i) / (values.length - 1);
  const Y = (a: number) => 3 + (height - 8) * (1 - (a - mn) / (mx - mn || 1));
  const d = values.map((a, i) => (i ? "L" : "M") + X(i).toFixed(1) + " " + Y(a).toFixed(1)).join(" ");
  const n = values.length - 1;
  return (
    <svg className={className} width={width} height={height} aria-hidden="true">
      {area && (<>
        <defs><linearGradient id={gid} x1={0} y1={0} x2={0} y2={1}><stop offset={0} stopColor={color} stopOpacity={0.2} /><stop offset={1} stopColor={color} stopOpacity={0} /></linearGradient></defs>
        <path d={`${d} L${X(n)} ${height} L${X(0)} ${height} Z`} fill={`url(#${gid})`} />
      </>)}
      <path d={d} fill="none" stroke={color} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={X(n)} cy={Y(values[n])} r={3} fill={color} />
    </svg>
  );
}

/** draw.js audio waveform: n bars, the first `played` share lit. */
export function Wave({ n = 48, played = 0.38 }: { n?: number; played?: number }) {
  return (
    <div className="wave" aria-hidden="true">
      {Array.from({ length: n }, (_, i) => (
        <i key={i} className={i < n * played ? "p" : ""} style={{ height: 8 + Math.round(26 * Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.45))) }} />
      ))}
    </div>
  );
}

/** Indonesian number with one decimal, as draw.js labels waterfall bars. */
export const id1 = (n: number) => n.toLocaleString("id-ID", { maximumFractionDigits: 1, minimumFractionDigits: 1 });

/** Plain loading / error panel in the v3 look. */
export function V3State({ error, loading }: { error?: string | null; loading?: boolean }) {
  if (error) return <div className="v3err"><Icon name="warn" />{error}</div>;
  if (loading) return <div className="v3load" aria-busy="true">Memuat data…</div>;
  return null;
}

/** Fetch helper: JSON or a readable error. */
export async function getJson<T>(r: Response): Promise<T> {
  if (!r.ok) {
    let msg = `Gagal memuat (${r.status})`;
    try { const j = await r.json(); if (j?.detail) msg = typeof j.detail === "string" ? j.detail : msg; } catch { /* not JSON */ }
    throw new Error(msg);
  }
  return r.json();
}

/** A span that acts as a button: the mockup CSS styles these controls by tag (`.chips span`,
    `.acts span`), so keeping the tag keeps the pixels while staying keyboard reachable. */
export function Tap({ onClick, className, children, label, pressed, style, title }: {
  onClick: () => void; className?: string; children?: ReactNode; label?: string; pressed?: boolean; style?: React.CSSProperties; title?: string;
}) {
  return (
    <span role="button" tabIndex={0} className={className} aria-label={label} aria-pressed={pressed} style={style} title={title}
      onClick={onClick} onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onClick(); } }}>{children}</span>
  );
}

/** draw.js waterfall (`bleed`: px the chart may run into the card padding, as the mockup does): start total, signed contributions, end total; the scale starts at
    `min` (marked with a zig-zag break on the total bars). bars: [{l, v, t?: "total"|"end", dim?}] */
export type WfBar = { l: string; v?: number; t?: "total" | "end"; dim?: number };
export function Waterfall({ bars, min: lo, max: hi, width, height, bleed = 0 }: { bars: WfBar[]; min: number; max: number; width: number; height: number; bleed?: number }) {
  const pl = 8, pr = 8, pt = 26, pb = 46, iw = width - pl - pr, ih = height - pt - pb;
  const Y = (v: number) => pt + ih * (1 - (v - lo) / (hi - lo)), bw = iw / bars.length;
  const T = { fontFamily: "var(--f-display)" } as const;
  let run = 0;
  const els: ReactNode[] = [];
  bars.forEach((r, i) => {
    const x = pl + bw * i + bw * 0.16, w = bw * 0.68;
    let a: number, b: number, c: string, lab: string;
    if (r.t === "total") { run = r.v ?? 0; a = lo; b = run; c = "#0F3A35"; lab = id1(run); }
    else if (r.t === "end") { a = lo; b = run; c = "#0E8579"; lab = id1(run); }
    else { const v = r.v ?? 0; a = run; b = run + v; run = b; c = v < 0 ? "#C42B2B" : "#2FA84F"; lab = (v > 0 ? "+" : "−") + id1(Math.abs(v)); }
    const y1 = Y(Math.max(a, b)), y2 = Y(Math.min(a, b));
    els.push(<rect key={`r${i}`} x={x} y={y1} width={w} height={Math.max(2, y2 - y1)} rx={4} fill={c} opacity={r.dim ? 0.45 : 1} />);
    if (r.t) els.push(<path key={`z${i}`} d={`M${x} ${Y(lo) - 10} l${w / 4} -5 l${w / 4} 5 l${w / 4} -5 l${w / 4} 5`} stroke="#fff" strokeWidth={2} fill="none" />);
    if (i < bars.length - 1 && bars[i + 1].t !== "end") els.push(<line key={`l${i}`} x1={x + w} x2={x + bw} y1={Y(run)} y2={Y(run)} stroke="#9FB1AD" strokeDasharray="3 3" />);
    els.push(<text key={`t${i}`} x={x + w / 2} y={y1 - 7} textAnchor="middle" fontSize={11.5} fontWeight={600} fill={r.t ? "#0F1F1D" : c} style={T}>{lab}</text>);
    r.l.split("|").forEach((p, k) => els.push(
      <text key={`b${i}-${k}`} x={x + w / 2} y={height - pb + 18 + k * 13} textAnchor="middle" fontSize={k ? 10 : 11} fill={k ? "#8A9A97" : "#3D4C49"} fontWeight={r.t ? 600 : 500} style={T}>{p}</text>));
  });
  return (
    <svg viewBox={`0 0 ${width} ${height}`} width={width} height={height} style={{ maxWidth: `calc(100% + ${bleed}px)`, height: "auto", flex: "none" }} role="img" aria-label="Waterfall kontribusi">
      {els}
      <line x1={pl} x2={width - pr} y1={Y(lo)} y2={Y(lo)} stroke="#B9C6C3" />
    </svg>
  );
}

/** draw.js forecast fan, signed against the target path: actual (thick), estimate (dashed) with the P10 to P90 band,
    optional scenario (purple dashed), the target line and a "Hari ini" marker. mid/lo/hi/alt start at day `today`. */
export type FanData = { days: number; today: number; min: number; max: number; ticks: number[]; act: number[]; mid: number[]; lo: number[]; hi: number[];
  alt?: number[] | null; target: number; targetLabel: string; midLabel: string; altLabel?: string; dayLabel: (d: number) => string };
export function Fan({ f, width, height, pr = 70 }: { f: FanData; width: number; height: number; pr?: number }) {
  const pl = 52, pt = 14, pb = 30, iw = width - pl - pr, ih = height - pt - pb, c = "#0E8579";
  const X = (d: number) => pl + iw * (d - 1) / (f.days - 1), Y = (v: number) => pt + ih * (1 - (v - f.min) / (f.max - f.min));
  const T = { fontFamily: "var(--f-display)" } as const;
  const line = (vs: number[], d0: number) => vs.map((v, i) => `${i ? "L" : "M"}${X(d0 + i)} ${Y(v)}`).join(" ");
  const s0 = f.today, n = f.mid.length - 1;
  const band = f.mid.length ? line(f.lo, s0) + " " + f.hi.map((v, i) => `L${X(s0 + i)} ${Y(v)}`).reverse().join(" ") + "Z" : "";
  const tick = (t: number) => (t > 0 ? "+" : "") + t.toLocaleString("id-ID").replace("-", "−");
  const days = [1, 8, 15, 22, f.days];
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} style={{ flex: "none" }} role="img" aria-label="Selisih terhadap jalur target">
      {f.ticks.map((t) => <g key={t}><line x1={pl} x2={width - pr} y1={Y(t)} y2={Y(t)} stroke={t ? "#ECF3F1" : "#B9C6C3"} />
        <text x={pl - 8} y={Y(t) + 4} textAnchor="end" fontSize={11} fill="#5A6B68" style={T}>{tick(t)}</text></g>)}
      {days.map((d) => <text key={d} x={X(d)} y={height - 8} textAnchor="middle" fontSize={11} fill="#5A6B68" style={T}>{f.dayLabel(d)}</text>)}
      {band && <path d={band} fill={c} opacity={0.14} />}
      {f.alt && <path d={line(f.alt, s0)} fill="none" stroke="#6A4CB5" strokeWidth={2.5} strokeDasharray="7 5" />}
      {f.mid.length > 0 && <path d={line(f.mid, s0)} fill="none" stroke={c} strokeWidth={2} strokeDasharray="5 5" />}
      <path d={line(f.act, 1)} fill="none" stroke={c} strokeWidth={3} strokeLinecap="round" />
      <circle cx={X(s0)} cy={Y(f.act[s0 - 1])} r={5} fill="#fff" stroke={c} strokeWidth={2.5} />
      <line x1={X(s0)} x2={X(s0)} y1={pt} y2={pt + ih} stroke="#0F1F1D" strokeDasharray="2 3" opacity={0.5} />
      <text x={X(s0) + 6} y={pt + 10} fontSize={10.5} fontWeight={600} fill="#0F1F1D" style={T}>Hari ini</text>
      <line x1={pl} x2={width - pr} y1={Y(f.target)} y2={Y(f.target)} stroke="#C42B2B" strokeWidth={1.5} />
      <text x={width - pr + 6} y={Y(f.target) + 4} fontSize={11} fontWeight={700} fill="#C42B2B" style={T}>{f.targetLabel}</text>
      {n >= 0 && <text x={width - pr + 6} y={Y(f.mid[n]) + 4} fontSize={11} fontWeight={700} fill={c} style={T}>{f.midLabel}</text>}
      {f.alt && <text x={width - pr + 6} y={Y(f.alt[f.alt.length - 1]) - 4} fontSize={11} fontWeight={700} fill="#6A4CB5" style={T}>{f.altLabel}</text>}
    </svg>
  );
}
