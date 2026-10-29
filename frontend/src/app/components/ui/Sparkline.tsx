"use client";
import { useId, useMemo, useState } from "react";

type Props = {
  values: (number | null)[];
  labels?: string[];
  color?: string;
  height?: number;
  format?: (v: number) => string;
  /** Draws a dashed horizontal reference line (e.g. a target). */
  reference?: number | null;
  /** Text drawn left of the reference line, e.g. "-5%". */
  referenceLabel?: string;
};

/** Smooth area sparkline with a hover readout. Pure SVG, scales to its container width. */
export default function Sparkline({ values, labels, color = "var(--ds-teal600)", height = 44, format, reference, referenceLabel }: Props) {
  const id = useId().replace(/:/g, "");
  const [hover, setHover] = useState<number | null>(null);
  const W = 228;
  const pts = useMemo(() => {
    const vals = values.map((v) => (v == null || !Number.isFinite(v) ? null : v));
    const nums = vals.filter((v): v is number => v != null).concat(reference != null ? [reference] : []);
    if (nums.length < 2) return [];
    const min = Math.min(...nums), max = Math.max(...nums);
    const span = max - min || 1;
    const step = W / Math.max(1, vals.length - 1);
    return vals.map((v, i) => (v == null ? null : { x: i * step, y: 4 + (height - 8) * (1 - (v - min) / span), v }));
  }, [values, height, reference]);

  const line = useMemo(() => {
    const p = pts.filter(Boolean) as { x: number; y: number }[];
    if (p.length < 2) return "";
    let d = `M${p[0].x},${p[0].y}`;
    for (let i = 1; i < p.length; i++) {
      const a = p[i - 1], b = p[i];
      const cx = (a.x + b.x) / 2;
      d += ` C${cx},${a.y} ${cx},${b.y} ${b.x},${b.y}`;
    }
    return d;
  }, [pts]);

  if (!line) return <div style={{ height }} />;
  const p = pts.filter(Boolean) as { x: number; y: number; v: number }[];
  const area = `${line} L${p[p.length - 1].x},${height} L${p[0].x},${height} Z`;
  const refY = (() => {
    if (reference == null) return null;
    const nums = values.filter((v): v is number => v != null).concat([reference]);
    const min = Math.min(...nums), max = Math.max(...nums);
    return 4 + (height - 8) * (1 - (reference - min) / (max - min || 1));
  })();
  const h = hover != null ? pts[hover] : null;

  return (
    <div className="spark" style={{ height }}
      onMouseLeave={() => setHover(null)}
      onMouseMove={(e) => {
        const r = e.currentTarget.getBoundingClientRect();
        const i = Math.round(((e.clientX - r.left) / r.width) * (values.length - 1));
        setHover(Math.max(0, Math.min(values.length - 1, i)));
      }}>
      <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" width="100%" height={height} aria-hidden="true">
        <defs>
          <linearGradient id={`g${id}`} x1="0" x2="0" y1="0" y2="1">
            <stop offset="0" stopColor={color} stopOpacity="0.22" />
            <stop offset="1" stopColor={color} stopOpacity="0" />
          </linearGradient>
        </defs>
        <path d={area} fill={`url(#g${id})`} />
        {refY != null && <line x1="0" x2={W} y1={refY} y2={refY} stroke="var(--ds-warning)" strokeWidth="1.2" strokeDasharray="4 3" vectorEffect="non-scaling-stroke" />}
        <path d={line} fill="none" stroke={color} strokeWidth="2" vectorEffect="non-scaling-stroke" strokeLinecap="round" />
      </svg>
      {refY != null && referenceLabel && <span className="spark-ref" style={{ top: refY }}>{referenceLabel}</span>}
      {h && (
        <>
          <span className="spark-dot" style={{ left: `${(h.x / W) * 100}%`, top: h.y, borderColor: color }} />
          <span className="spark-tip" style={{ left: `${(h.x / W) * 100}%` }}>
            {labels?.[hover!] ? `${labels[hover!]} · ` : ""}{format ? format(h.v) : h.v}
          </span>
        </>
      )}
    </div>
  );
}
