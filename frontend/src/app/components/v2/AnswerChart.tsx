"use client";
/* Line / bar chart of the Tanya Agent answer card, ported from the approved mockup
   (design/mockup-v2/02-tanya-agent): light grid, axis labels in Poppins 11 px, the first
   series as a solid line with a soft area, the second dashed, a dashed hover rule with
   ringed points and a dark tooltip. Legend chips toggle series; Garis / Batang switches
   the mark. Width follows the container. */
import { useEffect, useId, useRef, useState } from "react";

export type AnswerSeries = {
  name: string; values: (number | null)[]; color: string;
  /** Tooltip row label per point when it differs from the legend name (e.g. "16 Sep"). */
  tips?: string[];
};

type Props = {
  labels: string[];
  /** Tooltip heading per point (falls back to the axis label). */
  titles?: string[];
  series: AnswerSeries[];
  /** Value in the tooltip, e.g. "Rp 13,3 M". */
  format: (v: number) => string;
  /** Axis tick text, e.g. "12 M". */
  axisFormat: (v: number) => string;
  height?: number;
  /** left, right, top, bottom padding (mockup web: 44, 12, 10, 26). */
  pad?: [number, number, number, number];
  small?: boolean;
  initialHover?: number;
  initialMode?: "line" | "bar";
};

function niceStep(span: number, target: number): number {
  const raw = span / Math.max(1, target);
  const mag = Math.pow(10, Math.floor(Math.log10(raw)));
  const f = raw / mag;
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * mag;
}

export function niceTicks(min: number, max: number, target = 3): number[] {
  if (min === max) { min -= 1; max += 1; }
  const step = niceStep(max - min, target);
  const lo = Math.floor(min / step) * step, hi = Math.ceil(max / step) * step;
  const out: number[] = [];
  for (let v = lo; v <= hi + step / 2; v += step) out.push(+v.toFixed(10));
  return out;
}

export default function AnswerChart({ labels, titles, series, format, axisFormat, height = 220, pad = [44, 12, 10, 26], small, initialHover, initialMode = "line" }: Props) {
  const [mode, setMode] = useState<"line" | "bar">(initialMode);
  const box = useRef<HTMLDivElement>(null);
  const [W, setW] = useState(0);
  const [hover, setHover] = useState(initialHover ?? Math.floor((labels.length - 1) / 2));
  const [on, setOn] = useState<boolean[]>(() => series.map(() => true));

  useEffect(() => {
    const el = box.current;
    if (!el) return;
    const ro = new ResizeObserver(() => setW(Math.floor(el.clientWidth)));
    ro.observe(el);
    setW(Math.floor(el.clientWidth));
    return () => ro.disconnect();
  }, []);

  const n = labels.length;
  const H = height;
  const [pl, pr, pt, pb] = pad;
  const vals = series.flatMap((s, i) => (on[i] ? s.values.filter((v): v is number => v != null) : []));
  const ticks = niceTicks(vals.length ? Math.min(...vals) : 0, vals.length ? Math.max(...vals) : 1);
  const lo = ticks[0], hi = ticks[ticks.length - 1];
  const iw = Math.max(1, W - pl - pr), ih = H - pt - pb;
  const x = (i: number) => pl + (n > 1 ? (iw * i) / (n - 1) : iw / 2);
  const y = (v: number) => pt + ih * (1 - (v - lo) / (hi - lo || 1));
  const every = Math.max(1, Math.ceil(n / 5));
  const gid = `ac${useId().replace(/[^a-zA-Z0-9]/g, "")}`;
  const fs = small ? 10 : 11;

  const path = (vs: (number | null)[]) => {
    let d = "", pen = false;
    vs.forEach((v, i) => {
      if (v == null) { pen = false; return; }
      d += `${pen ? "L" : "M"}${x(i).toFixed(1)} ${y(v).toFixed(1)} `;
      pen = true;
    });
    return d.trim();
  };

  const both = on.filter(Boolean).length > 1;
  const bw = iw / Math.max(1, n) / (both ? 2.6 : 1.6);
  const tipRows = series.map((s, i) => ({ s, i, v: s.values[hover] })).filter((r) => on[r.i] && r.v != null);
  const tx = x(hover) + 14, flip = tx + 170 > W;

  return (
    <div className="answer-chart">
      <div className="legend">
        {series.map((s, i) => (
          <button key={s.name} type="button" className={`lg ${on[i] ? "" : "off"}`} aria-pressed={on[i]}
            onClick={() => setOn((o) => (o.filter(Boolean).length > 1 || !o[i] ? o.map((b, j) => (j === i ? !b : b)) : o))}>
            <i style={{ background: s.color }} />{s.name}
          </button>
        ))}
        <span className="seg" style={{ marginLeft: "auto" }} role="group" aria-label="Bentuk grafik">
          <button type="button" className={mode === "line" ? "on" : ""} aria-pressed={mode === "line"} onClick={() => setMode("line")}>Garis</button>
          <button type="button" className={mode === "bar" ? "on" : ""} aria-pressed={mode === "bar"} onClick={() => setMode("bar")}>Batang</button>
        </span>
      </div>
      <div className="chartbox" ref={box}
        onMouseMove={(e) => {
          const r = e.currentTarget.getBoundingClientRect();
          const i = Math.round(((e.clientX - r.left - pl) / iw) * (n - 1));
          setHover(Math.max(0, Math.min(n - 1, i)));
        }}>
        {W > 0 && (
          <svg className="chart" width={W} height={H} role="img" aria-label={series.map((s) => s.name).join(", ")}>
            <defs>
              <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0" stopColor={series[0]?.color} stopOpacity={0.22} />
                <stop offset="1" stopColor={series[0]?.color} stopOpacity={0} />
              </linearGradient>
            </defs>
            {ticks.map((v) => (
              <g key={v}>
                <line x1={pl} x2={W - pr} y1={y(v)} y2={y(v)} stroke="#ECF3F1" strokeWidth={1} />
                <text x={pl - 8} y={y(v) + 4} textAnchor="end" fontFamily="Poppins, sans-serif" fontSize={fs} fill="#5A6B68">{axisFormat(v)}</text>
              </g>
            ))}
            {labels.map((l, i) => (i % every === 0 ? (
              <text key={i} x={x(i)} y={H - 6} textAnchor="middle" fontFamily="Poppins, sans-serif" fontSize={fs} fill="#5A6B68">{l}</text>
            ) : null))}
            {mode === "line" ? (
              <>
                {on[0] && series[0] && (() => {
                  const d = path(series[0].values);
                  const first = series[0].values.findIndex((v) => v != null);
                  let last = first;
                  series[0].values.forEach((v, i) => { if (v != null) last = i; });
                  return d ? <path d={`${d} L${x(last)} ${y(lo)} L${x(first)} ${y(lo)} Z`} fill={`url(#${gid})`} /> : null;
                })()}
                {series.map((s, si) => ({ s, si })).reverse().map(({ s, si }) => on[si] ? (
                  <path key={s.name} d={path(s.values)} fill="none" stroke={s.color} strokeWidth={si ? 2 : 2.6}
                    strokeDasharray={si ? "5 4" : undefined} strokeLinejoin="round" strokeLinecap="round" />
                ) : null)}
              </>
            ) : (
              series.map((s, si) => on[si] ? s.values.map((v, i) => {
                if (v == null) return null;
                const off = both ? (si ? bw * 0.55 : -bw * 0.55) : 0;
                return <rect key={`${si}-${i}`} x={(x(i) + off - bw / 2).toFixed(1)} y={y(v).toFixed(1)} width={bw.toFixed(1)}
                  height={(y(lo) - y(v)).toFixed(1)} rx={2} fill={s.color} opacity={si ? 0.75 : 1} />;
              }) : null)
            )}
            {n > 0 && (
              <>
                <line x1={x(hover)} x2={x(hover)} y1={pt} y2={pt + ih} stroke="#0F1F1D" strokeWidth={1} strokeDasharray="3 3" opacity={0.5} />
                {series.map((s, si) => ({ s, si })).reverse().map(({ s, si }) => on[si] && s.values[hover] != null ? (
                  <circle key={s.name} cx={x(hover)} cy={y(s.values[hover]!)} r={5} fill="#fff" stroke={s.color} strokeWidth={2.5} />
                ) : null)}
              </>
            )}
          </svg>
        )}
        {W > 0 && tipRows.length > 0 && (
          <div className="tip" style={{ left: flip ? x(hover) - 14 - (small ? 150 : 165) : tx, top: small ? 4 : pt + 4 }}>
            <b>{titles?.[hover] ?? labels[hover]}</b>
            {tipRows.map((r) => (
              <div key={r.s.name}><i style={{ background: r.s.color }} />{r.s.tips?.[hover] ?? r.s.name}<span>{format(r.v!)}</span></div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
