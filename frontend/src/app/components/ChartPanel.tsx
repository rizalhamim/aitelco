"use client";
import { useMemo, useState } from "react";

type Row = Record<string, unknown>;
type Props = { columns: string[]; rows: Row[] };

const IOH_RED = "#15A697";
const IOH_INK = "#0F1F1D";
const IOH_MUTE = "#5A6B68";
const IOH_RULE = "#E1E9E7";
const PALETTE = [
  "#15A697", "#F5A623", "#2A74D4", "#FF6B35", "#0A6A5F",
  "#9A6CFF", "#2FA84F", "#0EA5E9", "#E13838", "#84CC16",
  "#0E8579", "#C42B2B",
];

type ChartType = "bar" | "line" | "pie" | "matrix";

function shortNum(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1e12) return (n / 1e12).toFixed(1) + "T";
  if (abs >= 1e9) return (n / 1e9).toFixed(1) + "B";
  if (abs >= 1e6) return (n / 1e6).toFixed(1) + "M";
  if (abs >= 1e3) return (n / 1e3).toFixed(1) + "K";
  return Number.isInteger(n) ? String(n) : n.toFixed(2);
}

function isTimeLike(v: unknown): boolean {
  if (typeof v === "number") return (v >= 190001 && v <= 210012) || (v >= 19000101 && v <= 21001231); // YYYYMM or YYYYMMDD
  if (typeof v === "string") {
    return /^\d{4}-\d{2}/.test(v) || /^\d{6}$/.test(v) || /^\d{8}$/.test(v) || /^\d{4}-\d{2}-\d{2}/.test(v) || /^\d{4}\/\d{2}/.test(v);
  }
  return false;
}

// a column is a time axis if its NAME looks temporal or its VALUES are time-like
const TIME_NAME = /^(dt_id|date|period|month_id|mth_id|mth|month|week|week_id|wk|tanggal|day|ds|datum)$|_(dt|date|month|week)$/i;
function isTimeColumn(name: string, rows: Row[]): boolean {
  if (TIME_NAME.test(name)) {
    // confirm values are not obviously non-temporal
    return rows.some((r) => r[name] != null);
  }
  return rows.length > 0 && rows.every((r) => r[name] == null || isTimeLike(r[name]));
}

export default function ChartPanel({ columns, rows }: Props) {
  const shape = useMemo(() => {
    if (rows.length === 0) return null;
    // classify columns across a sample of rows (not just the first)
    const sample = rows.slice(0, 30);
    const catCols: string[] = [];
    const numCols: string[] = [];
    for (const c of columns) {
      const vals = sample.map((r) => r[c]).filter((v) => v !== null && v !== undefined);
      const allNum = vals.length > 0 && vals.every((v) => typeof v === "number");
      if (allNum) numCols.push(c);
      else catCols.push(c);
    }
    if (numCols.length === 0) return null;
    // a time column makes this a time-series (line) chart
    const timeCol = columns.find((c) => isTimeColumn(c, rows)) || null;
    const cat = timeCol || catCols[0] || null;
    if (!cat) return null;
    // cap only NON-time charts at 60 rows; time-series allowed up to 400 points
    if (!timeCol && rows.length > 60) return null;
    if (timeCol && rows.length > 400) return null;
    return { cat, numCols, catCols, timeCol };
  }, [columns, rows]);

  const available: ChartType[] = useMemo(() => {
    if (!shape) return [];
    const list: ChartType[] = [];
    // time-series -> Line first (default); also offer Bar
    if (shape.timeCol && shape.numCols.length >= 1) list.push("line");
    list.push("bar");
    if (shape.numCols.length === 1 && rows.length <= 12) list.push("pie");
    if (shape.numCols.length >= 1 && rows.length <= 40) list.push("matrix");
    return list;
  }, [shape, rows.length]);

  const [type, setType] = useState<ChartType | null>(null);
  const active: ChartType | null = type && available.includes(type) ? type : (available[0] || null);

  if (!shape || !active) return null;

  return (
    <div className="chart-card">
      <div className="chart-toolbar">
        <span className="chart-title">Visualisasi</span>
        <div className="chart-switch">
          {available.map((t) => (
            <button
              key={t}
              className={`chart-switch-btn ${active === t ? "active" : ""}`}
              onClick={() => setType(t)}
            >
              {t === "bar" ? "Bar" : t === "line" ? "Line" : t === "pie" ? "Pie" : "Matrix"}
            </button>
          ))}
        </div>
      </div>
      {active === "bar" && <BarChartSvg shape={shape} rows={rows} />}
      {active === "line" && <LineChartSvg shape={shape} rows={rows} />}
      {active === "pie" && <PieChartSvg shape={shape} rows={rows} />}
      {active === "matrix" && <MatrixSvg shape={shape} rows={rows} />}
    </div>
  );
}

type Shape = { cat: string; numCols: string[]; catCols: string[]; timeCol: string | null };
type Sub = { shape: Shape; rows: Record<string, unknown>[] };

// ---- Vertical Bar ----
function BarChartSvg({ shape, rows }: Sub) {
  const cat = shape.cat;
  const num = shape.numCols[0];
  const data = rows
    .map((r) => ({ label: String(r[cat] ?? ""), value: Number(r[num]) || 0 }))
    .slice(0, 24);
  const W = 880, H = 320, padL = 56, padR = 16, padT = 18, padB = 70;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const maxV = Math.max(...data.map((d) => d.value), 1);
  const minV = Math.min(...data.map((d) => d.value), 0);
  const niceMax = Math.ceil(maxV * 1.08);
  const base = minV < 0 ? minV * 1.08 : 0;
  const range = niceMax - base || 1;
  const barW = Math.min(56, innerW / data.length - 8);
  const step = innerW / data.length;
  const ticks = 4;
  const yTicks = Array.from({ length: ticks + 1 }, (_, i) => base + (range / ticks) * i);
  const zeroY = padT + innerH - ((0 - base) / range) * innerH;

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img">
      {yTicks.map((t, i) => {
        const y = padT + innerH - ((t - base) / range) * innerH;
        return (
          <g key={i}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke={IOH_RULE} strokeWidth={1} />
            <text x={padL - 8} y={y + 3} fontSize={11} fontWeight={500} fill={IOH_MUTE} textAnchor="end">{shortNum(t)}</text>
          </g>
        );
      })}
      {data.map((d, i) => {
        const vY = padT + innerH - ((d.value - base) / range) * innerH;
        const h = Math.abs(vY - zeroY);
        const y = Math.min(vY, zeroY);
        const x = padL + i * step + (step - barW) / 2;
        return (
          <g key={i}>
            <rect x={x} y={y} width={barW} height={Math.max(h, 1)} fill={d.value < 0 ? IOH_MUTE : IOH_RED} rx={2} />
            <text x={x + barW / 2} y={(d.value < 0 ? y + h + 12 : y - 6)} fontSize={10} fontWeight={700} fill={d.value < 0 ? IOH_MUTE : IOH_RED} textAnchor="middle">{shortNum(d.value)}</text>
            <text x={x + barW / 2} y={padT + innerH + 16} fontSize={11} fontWeight={500} fill={IOH_INK} textAnchor="end" transform={`rotate(-30 ${x + barW / 2} ${padT + innerH + 16})`}>{d.label.length > 14 ? d.label.slice(0, 13) + "…" : d.label}</text>
          </g>
        );
      })}
      <line x1={padL} x2={W - padR} y1={zeroY} y2={zeroY} stroke={IOH_INK} strokeWidth={1.5} />
    </svg>
  );
}

// ---- Line Chart (time series, multi-series) ----
function LineChartSvg({ shape, rows }: Sub) {
  const cat = shape.timeCol || shape.cat;
  const series = shape.numCols.slice(0, 6);
  const sorted = [...rows].sort((a, b) => String(a[cat]).localeCompare(String(b[cat])));
  const labels = sorted.map((r) => String(r[cat] ?? ""));
  const W = 880, H = 340, padL = 56, padR = 110, padT = 18, padB = 64;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  let maxV = -Infinity, minV = Infinity;
  for (const r of sorted) for (const s of series) {
    const v = Number(r[s]); if (Number.isFinite(v)) { maxV = Math.max(maxV, v); minV = Math.min(minV, v); }
  }
  if (!Number.isFinite(maxV)) { maxV = 1; minV = 0; }
  if (minV > 0) minV = 0;
  const niceMax = maxV * 1.08, range = (niceMax - minV) || 1;
  const stepX = sorted.length > 1 ? innerW / (sorted.length - 1) : innerW;
  const ticks = 4;
  const yTicks = Array.from({ length: ticks + 1 }, (_, i) => minV + (range / ticks) * i);

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img">
      {yTicks.map((t, i) => {
        const y = padT + innerH - ((t - minV) / range) * innerH;
        return (
          <g key={i}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke={IOH_RULE} strokeWidth={1} />
            <text x={padL - 8} y={y + 3} fontSize={11} fill={IOH_MUTE} textAnchor="end">{shortNum(t)}</text>
          </g>
        );
      })}
      {labels.map((lb, i) => {
        if (sorted.length > 12 && i % Math.ceil(sorted.length / 12) !== 0 && i !== sorted.length - 1) return null;
        const x = padL + i * stepX;
        return <text key={i} x={x} y={padT + innerH + 18} fontSize={10} fill={IOH_INK} textAnchor="middle">{lb.length > 8 ? lb.slice(-6) : lb}</text>;
      })}
      {series.map((s, si) => {
        const color = PALETTE[si % PALETTE.length];
        const pts = sorted.map((r, i) => {
          const v = Number(r[s]); if (!Number.isFinite(v)) return null;
          const x = padL + i * stepX;
          const y = padT + innerH - ((v - minV) / range) * innerH;
          return `${x},${y}`;
        }).filter(Boolean).join(" ");
        return (
          <g key={s}>
            <polyline points={pts} fill="none" stroke={color} strokeWidth={2.2} strokeLinejoin="round" strokeLinecap="round" />
            {sorted.map((r, i) => {
              const v = Number(r[s]); if (!Number.isFinite(v)) return null;
              const x = padL + i * stepX;
              const y = padT + innerH - ((v - minV) / range) * innerH;
              return <circle key={i} cx={x} cy={y} r={2.5} fill={color} />;
            })}
            <g transform={`translate(${W - padR + 10}, ${padT + si * 18})`}>
              <line x1={0} y1={5} x2={14} y2={5} stroke={color} strokeWidth={2.5} />
              <text x={18} y={8} fontSize={10} fontWeight={600} fill={IOH_INK}>{s.length > 12 ? s.slice(0, 11) + "…" : s}</text>
            </g>
          </g>
        );
      })}
      <line x1={padL} x2={W - padR} y1={padT + innerH} y2={padT + innerH} stroke={IOH_INK} strokeWidth={1.5} />
    </svg>
  );
}

// ---- Pie / Donut ----
function PieChartSvg({ shape, rows }: Sub) {
  const cat = shape.cat;
  const num = shape.numCols[0];
  const data = rows
    .map((r) => ({ label: String(r[cat] ?? ""), value: Math.max(Number(r[num]) || 0, 0) }))
    .filter((d) => d.value > 0)
    .sort((a, b) => b.value - a.value)
    .slice(0, 12);
  const total = data.reduce((s, d) => s + d.value, 0) || 1;
  const W = 880, H = 320, cx = 170, cy = 160, r = 120, rin = r * 0.55;

  // precompute cumulative start angle per slice (no mutation during render)
  const starts: number[] = [];
  data.reduce((acc, d) => { starts.push(acc); return acc + (d.value / total) * Math.PI * 2; }, -Math.PI / 2);

  const segs = data.map((d, i) => {
    const frac = d.value / total;
    const a0 = starts[i], a1 = a0 + frac * Math.PI * 2;
    const x0 = cx + r * Math.cos(a0), y0 = cy + r * Math.sin(a0);
    const x1 = cx + r * Math.cos(a1), y1 = cy + r * Math.sin(a1);
    const ix1 = cx + rin * Math.cos(a1), iy1 = cy + rin * Math.sin(a1);
    const ix0 = cx + rin * Math.cos(a0), iy0 = cy + rin * Math.sin(a0);
    const large = (a1 - a0) > Math.PI ? 1 : 0;
    const path = `M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1} L ${ix1} ${iy1} A ${rin} ${rin} 0 ${large} 0 ${ix0} ${iy0} Z`;
    return { path, color: PALETTE[i % PALETTE.length], pct: (frac * 100), label: d.label, value: d.value };
  });

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img">
      {segs.map((s, i) => <path key={i} d={s.path} fill={s.color} stroke="#fff" strokeWidth={2} />)}
      <text x={cx} y={cy - 4} textAnchor="middle" fontSize={20} fontWeight={800} fill={IOH_INK}>{shortNum(total)}</text>
      <text x={cx} y={cy + 14} textAnchor="middle" fontSize={10} fontWeight={600} fill={IOH_MUTE}>TOTAL</text>
      {segs.map((s, i) => (
        <g key={i} transform={`translate(${cx + r + 40}, ${36 + i * 21})`}>
          <rect width={12} height={12} rx={2} fill={s.color} />
          <text x={18} y={10} fontSize={11} fontWeight={600} fill={IOH_INK}>{s.label.length > 22 ? s.label.slice(0, 21) + "…" : s.label}</text>
          <text x={300} y={10} fontSize={11} fontWeight={700} fill={IOH_MUTE} textAnchor="end">{s.pct.toFixed(1)}% · {shortNum(s.value)}</text>
        </g>
      ))}
    </svg>
  );
}

// ---- Box Matrix (heatmap-style grid: rows = category, cols = numeric metrics) ----
function MatrixSvg({ shape, rows }: Sub) {
  const cat = shape.cat;
  const metrics = shape.numCols.slice(0, 8);
  const data = rows.slice(0, 20);
  const cellW = 92, cellH = 30, labelW = 150, headH = 46;
  const W = labelW + metrics.length * cellW + 16;
  const H = headH + data.length * cellH + 12;

  // per-metric min/max for normalization
  const ranges = metrics.map((m) => {
    const vals = data.map((r) => Number(r[m])).filter((v) => Number.isFinite(v));
    return { min: Math.min(...vals, 0), max: Math.max(...vals, 1) };
  });

  function shade(v: number, mi: number): string {
    const { min, max } = ranges[mi];
    const t = max === min ? 0.5 : (v - min) / (max - min);
    const alpha = 0.12 + t * 0.78;
    return `rgba(21, 166, 151,${alpha.toFixed(3)})`;
  }

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img" style={{ maxWidth: W }}>
      {metrics.map((m, i) => (
        <text key={m} x={labelW + i * cellW + cellW / 2} y={headH - 24} fontSize={10} fontWeight={700} fill={IOH_INK} textAnchor="middle" transform={`rotate(-12 ${labelW + i * cellW + cellW / 2} ${headH - 24})`}>{m.length > 13 ? m.slice(0, 12) + "…" : m}</text>
      ))}
      {data.map((r, ri) => {
        const y = headH + ri * cellH;
        const lbl = String(r[cat] ?? "");
        return (
          <g key={ri}>
            <text x={8} y={y + cellH / 2 + 4} fontSize={11} fontWeight={600} fill={IOH_INK}>{lbl.length > 20 ? lbl.slice(0, 19) + "…" : lbl}</text>
            {metrics.map((m, mi) => {
              const v = Number(r[m]);
              const x = labelW + mi * cellW;
              const ok = Number.isFinite(v);
              return (
                <g key={mi}>
                  <rect x={x + 1} y={y + 1} width={cellW - 2} height={cellH - 2} fill={ok ? shade(v, mi) : "#F5F9F8"} stroke="#fff" strokeWidth={1} rx={3} />
                  <text x={x + cellW / 2} y={y + cellH / 2 + 4} fontSize={10} fontWeight={600} fill={ok && (v - ranges[mi].min) / ((ranges[mi].max - ranges[mi].min) || 1) > 0.6 ? "#fff" : IOH_INK} textAnchor="middle">{ok ? shortNum(v) : "—"}</text>
                </g>
              );
            })}
          </g>
        );
      })}
    </svg>
  );
}
