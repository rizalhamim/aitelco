"use client";
import { useMemo, useState } from "react";
import type { ChartSpec, ChartSeries } from "../page";

type Row = Record<string, unknown>;
type Props = { columns: string[]; rows: Row[]; spec?: ChartSpec };

const IOH_RED = "#15A697";
const IOH_INK = "#0F1F1D";
const IOH_MUTE = "#5A6B68";
const IOH_RULE = "#E1E9E7";
const PALETTE = [
  "#15A697", "#F5A623", "#2A74D4", "#FF6B35", "#0A6A5F",
  "#9A6CFF", "#2FA84F", "#0EA5E9", "#E13838", "#84CC16",
  "#0E8579", "#C42B2B",
];

type ChartType = "bar" | "line" | "pie" | "matrix" | "funnel";

// ---- unit-aware number formatting -------------------------------------------------
// A number without its unit is not an answer: "2.4B" reads as a count, "Rp 2,4 M" reads
// as money. Indonesian locale throughout (comma decimal, dot thousands).
function fmtNumber(n: number, digits = 1): string {
  return n.toLocaleString("id-ID", { minimumFractionDigits: digits, maximumFractionDigits: digits });
}

function fmtRupiah(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1e12) return `Rp ${fmtNumber(n / 1e12)} T`;
  if (abs >= 1e9) return `Rp ${fmtNumber(n / 1e9)} M`;
  if (abs >= 1e6) return `Rp ${fmtNumber(n / 1e6)} Jt`;
  if (abs >= 1e3) return `Rp ${fmtNumber(n / 1e3)} Rb`;
  return `Rp ${fmtNumber(n, 0)}`;
}

function fmtCount(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1e9) return `${fmtNumber(n / 1e9)} M`;
  if (abs >= 1e6) return `${fmtNumber(n / 1e6)} Jt`;
  if (abs >= 1e3) return `${fmtNumber(n / 1e3)} Rb`;
  return Number.isInteger(n) ? n.toLocaleString("id-ID") : fmtNumber(n);
}

function fmtValue(n: number, unit: string): string {
  if (unit === "Rp") return fmtRupiah(n);
  if (unit === "%") return `${fmtNumber(n)}%`;
  return fmtCount(n);
}

// Axis ticks stay terse: the unit is already stated in the axis label.
function fmtTick(n: number, unit: string): string {
  if (unit === "%") return `${fmtNumber(n, 0)}%`;
  const abs = Math.abs(n);
  if (abs >= 1e12) return `${fmtNumber(n / 1e12, 1)}T`;
  if (abs >= 1e9) return `${fmtNumber(n / 1e9, 1)}M`;
  if (abs >= 1e6) return `${fmtNumber(n / 1e6, 1)}Jt`;
  if (abs >= 1e3) return `${fmtNumber(n / 1e3, 1)}Rb`;
  return fmtNumber(n, 0);
}

// ---- legacy fallback --------------------------------------------------------------
// Used only for results rendered before the backend started sending a spec (old chat
// history). New turns always carry one.
function isTimeLike(v: unknown): boolean {
  if (typeof v === "number") return (v >= 190001 && v <= 210012) || (v >= 19000101 && v <= 21001231);
  if (typeof v === "string") return /^\d{4}-\d{2}|^\d{6}$|^\d{8}$|^\d{4}\/\d{2}/.test(v);
  return false;
}
const TIME_NAME = /^(dt_id|date|period|month_id|mth_id|mth|month|week|week_id|wk|tanggal|day|ds|datum)$|_(dt|date|month|week)$/i;
const ID_NAME = /^(rank|ranking|no|nomor|urutan|rn)$|_id$|^id$/i;

function fallbackSpec(columns: string[], rows: Row[]): ChartSpec | null {
  if (rows.length === 0) return null;
  const sample = rows.slice(0, 30);
  const catCols: string[] = [];
  const numCols: string[] = [];
  for (const c of columns) {
    const vals = sample.map((r) => r[c]).filter((v) => v !== null && v !== undefined);
    const allNum = vals.length > 0 && vals.every((v) => typeof v === "number");
    // Never plot an identifier: `rank` holding 1,2,3 is numeric but is not a quantity.
    if (allNum && !ID_NAME.test(c) && !TIME_NAME.test(c)) numCols.push(c);
    else catCols.push(c);
  }
  if (numCols.length === 0) return null;
  const timeCol = columns.find((c) => TIME_NAME.test(c) || rows.every((r) => r[c] == null || isTimeLike(r[c]))) || null;
  const varying = timeCol ? new Set(rows.map((r) => String(r[timeCol]))).size > 1 : false;
  const category = (varying ? timeCol : catCols.find((c) => !TIME_NAME.test(c))) || catCols[0] || null;
  if (!category) return null;
  if (!varying && rows.length > 60) return null;
  const series: ChartSeries[] = numCols.slice(0, 6).map((c) => ({
    column: c, role: "count", unit: "", label: c,
    axis_side: "left" as const, can_be_negative: false,
  }));
  return {
    mode: varying ? "line" : "bar",
    category,
    series,
    axes: [{ unit: "", side: "left", columns: series.map((s) => s.column), zero_line: false }],
    dual_axis: false,
  };
}

export default function ChartPanel({ columns, rows, spec }: Props) {
  const active = useMemo<ChartSpec | null>(() => {
    if (spec && spec.mode && spec.mode !== "none" && spec.series?.length) return spec;
    return fallbackSpec(columns, rows);
  }, [spec, columns, rows]);

  // When the result had more categories than fit as readable bars, the backend sends
  // the ranked subset it wants plotted. Plot exactly that, so the chart matches the
  // caption ("24 teratas dari 38 kabkota") instead of an arbitrary first slice.
  const plotRows = useMemo<Row[]>(
    () => (active?.rows?.length ? (active.rows as Row[]) : rows),
    [active, rows],
  );

  const available: ChartType[] = useMemo(() => {
    if (!active) return [];
    const list: ChartType[] = [];
    if (active.mode === "line") list.push("line");
    if (active.mode === "funnel") list.push("funnel");
    if (active.mode === "pie") list.push("pie");
    list.push("bar");
    if (active.mode === "line") list.push("bar");
    if ((active.series?.length ?? 0) >= 1 && rows.length <= 40) list.push("matrix");
    return Array.from(new Set(list));
  }, [active, rows.length]);

  const [picked, setPicked] = useState<ChartType | null>(null);
  const type: ChartType | null =
    picked && available.includes(picked) ? picked : (available[0] || null);

  if (!active || !type) return null;

  return (
    <div className="chart-card">
      <div className="chart-toolbar">
        <div>
          <span className="chart-title">{active.title || "Visualisasi"}</span>
          {active.caption && <div className="chart-caption">{active.caption}</div>}
        </div>
        <div className="chart-switch">
          {available.map((t) => (
            <button
              key={t}
              className={`chart-switch-btn ${type === t ? "active" : ""}`}
              onClick={() => setPicked(t)}
            >
              {t === "bar" ? "Bar" : t === "line" ? "Line" : t === "pie" ? "Pie" : t === "funnel" ? "Funnel" : "Matrix"}
            </button>
          ))}
        </div>
      </div>
      {type === "bar" && <BarChartSvg spec={active} rows={plotRows} />}
      {type === "line" && <LineChartSvg spec={active} rows={plotRows} />}
      {type === "pie" && <PieChartSvg spec={active} rows={plotRows} />}
      {type === "funnel" && <FunnelSvg spec={active} rows={plotRows} />}
      {type === "matrix" && <MatrixSvg spec={active} rows={plotRows} />}
    </div>
  );
}

type Sub = { spec: ChartSpec; rows: Row[] };

function axisFor(spec: ChartSpec, side: "left" | "right") {
  return (spec.axes || []).find((a) => a.side === side) || null;
}

function seriesOn(spec: ChartSpec, side: "left" | "right"): ChartSeries[] {
  return (spec.series || []).filter((s) => (s.axis_side || "left") === side);
}

/** Independent scale per axis, so a percentage is never flattened by a rupiah scale. */
function scaleFor(series: ChartSeries[], rows: Row[]) {
  let max = -Infinity, min = Infinity;
  for (const s of series) {
    for (const r of rows) {
      const v = Number(r[s.column]);
      if (Number.isFinite(v)) { max = Math.max(max, v); min = Math.min(min, v); }
    }
  }
  if (!Number.isFinite(max)) { max = 1; min = 0; }
  if (min > 0) min = 0;
  const needsZero = series.some((s) => s.can_be_negative) || min < 0;
  const base = needsZero ? min * 1.08 : 0;
  const top = max <= 0 ? 1 : max * 1.08;
  return { base, top, range: (top - base) || 1 };
}

// ---- Vertical Bar (up to two axes) ----
function BarChartSvg({ spec, rows }: Sub) {
  const cat = spec.category as string;
  const left = seriesOn(spec, "left");
  const right = seriesOn(spec, "right");
  const data = rows.slice(0, 24);
  const W = 880, H = 340, padL = 66, padR = right.length ? 66 : 18, padT = 18, padB = 74;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const sL = scaleFor(left, data);
  const sR = right.length ? scaleFor(right, data) : null;
  const step = innerW / Math.max(data.length, 1);
  const groupW = Math.min(56, step - 10);
  const barW = Math.max(4, groupW / Math.max(left.length + right.length, 1));
  const ticks = 4;
  const zeroY = padT + innerH - ((0 - sL.base) / sL.range) * innerH;
  const leftUnit = axisFor(spec, "left")?.unit ?? "";
  const rightUnit = axisFor(spec, "right")?.unit ?? "";
  const all = [...left, ...right];

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={spec.title}>
      {Array.from({ length: ticks + 1 }, (_, i) => {
        const t = sL.base + (sL.range / ticks) * i;
        const y = padT + innerH - ((t - sL.base) / sL.range) * innerH;
        const tr = sR ? sR.base + (sR.range / ticks) * i : null;
        return (
          <g key={i}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke={IOH_RULE} strokeWidth={1} />
            <text x={padL - 8} y={y + 3} fontSize={11} fontWeight={500} fill={IOH_MUTE} textAnchor="end">{fmtTick(t, leftUnit)}</text>
            {tr !== null && <text x={W - padR + 8} y={y + 3} fontSize={11} fontWeight={500} fill={IOH_MUTE} textAnchor="start">{fmtTick(tr, rightUnit)}</text>}
          </g>
        );
      })}
      {data.map((r, i) => {
        const gx = padL + i * step + (step - groupW) / 2;
        const label = String(r[cat] ?? "");
        return (
          <g key={i}>
            {all.map((s, si) => {
              const isRight = (s.axis_side || "left") === "right";
              const sc = isRight && sR ? sR : sL;
              const v = Number(r[s.column]);
              if (!Number.isFinite(v)) return null;
              const vY = padT + innerH - ((v - sc.base) / sc.range) * innerH;
              const zY = padT + innerH - ((0 - sc.base) / sc.range) * innerH;
              const h = Math.max(Math.abs(vY - zY), 1);
              const x = gx + si * barW;
              const color = all.length === 1 ? (v < 0 ? IOH_MUTE : IOH_RED) : PALETTE[si % PALETTE.length];
              return (
                <g key={s.column}>
                  <rect x={x} y={Math.min(vY, zY)} width={Math.max(barW - 2, 2)} height={h} fill={color} rx={2}>
                    <title>{`${s.label}: ${fmtValue(v, s.unit)}`}</title>
                  </rect>
                  {all.length <= 2 && (
                    <text x={x + barW / 2} y={v < 0 ? Math.min(vY, zY) + h + 12 : Math.min(vY, zY) - 5}
                      fontSize={9} fontWeight={700} fill={color} textAnchor="middle">{fmtValue(v, s.unit)}</text>
                  )}
                </g>
              );
            })}
            <text x={gx + groupW / 2} y={padT + innerH + 16} fontSize={11} fontWeight={500} fill={IOH_INK}
              textAnchor="end" transform={`rotate(-30 ${gx + groupW / 2} ${padT + innerH + 16})`}>
              {label.length > 14 ? label.slice(0, 13) + "…" : label}
            </text>
          </g>
        );
      })}
      <line x1={padL} x2={W - padR} y1={zeroY} y2={zeroY} stroke={IOH_INK} strokeWidth={1.5} />
      <Legend series={all} y={H - 12} showUnits={all.length > 1} />
    </svg>
  );
}

function Legend({ series, y, showUnits }: { series: ChartSeries[]; y: number; showUnits: boolean }) {
  if (series.length < 2) return null;
  return (
    <g>
      {series.map((s, i) => (
        <g key={s.column} transform={`translate(${66 + i * 190}, ${y})`}>
          <rect width={10} height={10} rx={2} y={-8} fill={PALETTE[i % PALETTE.length]} />
          <text x={15} y={1} fontSize={10} fontWeight={600} fill={IOH_INK}>
            {s.label.length > 20 ? s.label.slice(0, 19) + "…" : s.label}
            {showUnits && s.unit ? ` (${s.unit})` : ""}
          </text>
        </g>
      ))}
    </g>
  );
}

// ---- Line (time series) ----
function LineChartSvg({ spec, rows }: Sub) {
  const cat = spec.category as string;
  const left = seriesOn(spec, "left");
  const right = seriesOn(spec, "right");
  const sorted = [...rows].sort((a, b) => String(a[cat]).localeCompare(String(b[cat])));
  const W = 880, H = 350, padL = 66, padR = right.length ? 66 : 110, padT = 18, padB = 70;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const sL = scaleFor(left, sorted);
  const sR = right.length ? scaleFor(right, sorted) : null;
  const stepX = sorted.length > 1 ? innerW / (sorted.length - 1) : innerW;
  const ticks = 4;
  const leftUnit = axisFor(spec, "left")?.unit ?? "";
  const rightUnit = axisFor(spec, "right")?.unit ?? "";
  const all = [...left, ...right];

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={spec.title}>
      {Array.from({ length: ticks + 1 }, (_, i) => {
        const t = sL.base + (sL.range / ticks) * i;
        const y = padT + innerH - ((t - sL.base) / sL.range) * innerH;
        const tr = sR ? sR.base + (sR.range / ticks) * i : null;
        return (
          <g key={i}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke={IOH_RULE} strokeWidth={1} />
            <text x={padL - 8} y={y + 3} fontSize={11} fill={IOH_MUTE} textAnchor="end">{fmtTick(t, leftUnit)}</text>
            {tr !== null && <text x={W - padR + 8} y={y + 3} fontSize={11} fill={IOH_MUTE} textAnchor="start">{fmtTick(tr, rightUnit)}</text>}
          </g>
        );
      })}
      {sorted.map((r, i) => {
        if (sorted.length > 12 && i % Math.ceil(sorted.length / 12) !== 0 && i !== sorted.length - 1) return null;
        const lb = String(r[cat] ?? "");
        return <text key={i} x={padL + i * stepX} y={padT + innerH + 18} fontSize={10} fill={IOH_INK} textAnchor="middle">{lb.length > 8 ? lb.slice(-6) : lb}</text>;
      })}
      {all.map((s, si) => {
        const isRight = (s.axis_side || "left") === "right";
        const sc = isRight && sR ? sR : sL;
        const color = PALETTE[si % PALETTE.length];
        const pts = sorted.map((r, i) => {
          const v = Number(r[s.column]);
          if (!Number.isFinite(v)) return null;
          return `${padL + i * stepX},${padT + innerH - ((v - sc.base) / sc.range) * innerH}`;
        }).filter(Boolean).join(" ");
        return (
          <g key={s.column}>
            <polyline points={pts} fill="none" stroke={color} strokeWidth={2.2} strokeLinejoin="round" strokeLinecap="round" />
            {sorted.map((r, i) => {
              const v = Number(r[s.column]);
              if (!Number.isFinite(v)) return null;
              const y = padT + innerH - ((v - sc.base) / sc.range) * innerH;
              return (
                <circle key={i} cx={padL + i * stepX} cy={y} r={2.5} fill={color}>
                  <title>{`${String(sorted[i][cat] ?? "")} · ${s.label}: ${fmtValue(v, s.unit)}`}</title>
                </circle>
              );
            })}
          </g>
        );
      })}
      <line x1={padL} x2={W - padR} y1={padT + innerH} y2={padT + innerH} stroke={IOH_INK} strokeWidth={1.5} />
      <Legend series={all} y={H - 10} showUnits={all.length > 1} />
    </svg>
  );
}

// ---- Funnel (conversion stages) ----
function FunnelSvg({ spec, rows }: Sub) {
  const stages = (spec.series || []).map((s) => {
    const total = rows.reduce((acc, r) => acc + (Number(r[s.column]) || 0), 0);
    return { label: s.label, unit: s.unit, value: total };
  });
  const top = stages[0]?.value || 1;
  const W = 880, barH = 44, gap = 12, padL = 190, padR = 120;
  const H = stages.length * (barH + gap) + 20;
  const innerW = W - padL - padR;

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={spec.title}>
      {stages.map((st, i) => {
        const w = Math.max((st.value / top) * innerW, 2);
        const y = 10 + i * (barH + gap);
        const convFromTop = top ? (st.value / top) * 100 : 0;
        const prev = i > 0 ? stages[i - 1].value : null;
        const convFromPrev = prev ? (st.value / prev) * 100 : null;
        return (
          <g key={st.label}>
            <text x={padL - 12} y={y + barH / 2 + 4} fontSize={12} fontWeight={600} fill={IOH_INK} textAnchor="end">{st.label}</text>
            <rect x={padL} y={y} width={w} height={barH} rx={4} fill={PALETTE[i % PALETTE.length]} />
            <text x={padL + 10} y={y + barH / 2 + 4} fontSize={12} fontWeight={700} fill="#fff">{fmtValue(st.value, st.unit)}</text>
            <text x={W - padR + 10} y={y + barH / 2 + 4} fontSize={11} fontWeight={600} fill={IOH_MUTE}>
              {convFromPrev !== null ? `${fmtNumber(convFromPrev)}% dari atas` : `${fmtNumber(convFromTop, 0)}%`}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

// ---- Pie / Donut ----
function PieChartSvg({ spec, rows }: Sub) {
  const cat = spec.category as string;
  const s0 = (spec.series || [])[0];
  const data = rows
    .map((r) => ({ label: String(r[cat] ?? ""), value: Math.max(Number(r[s0.column]) || 0, 0) }))
    .filter((d) => d.value > 0)
    .sort((a, b) => b.value - a.value)
    .slice(0, 12);
  const total = data.reduce((s, d) => s + d.value, 0) || 1;
  const W = 880, H = 320, cx = 170, cy = 160, r = 120, rin = r * 0.55;

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
    return {
      path: `M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1} L ${ix1} ${iy1} A ${rin} ${rin} 0 ${large} 0 ${ix0} ${iy0} Z`,
      color: PALETTE[i % PALETTE.length], pct: frac * 100, label: d.label, value: d.value,
    };
  });

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={spec.title}>
      {segs.map((s, i) => (
        <path key={i} d={s.path} fill={s.color} stroke="#fff" strokeWidth={2}>
          <title>{`${s.label}: ${fmtValue(s.value, s0.unit)} (${fmtNumber(s.pct)}%)`}</title>
        </path>
      ))}
      <text x={cx} y={cy - 4} textAnchor="middle" fontSize={17} fontWeight={800} fill={IOH_INK}>{fmtValue(total, s0.unit)}</text>
      <text x={cx} y={cy + 14} textAnchor="middle" fontSize={10} fontWeight={600} fill={IOH_MUTE}>TOTAL</text>
      {segs.map((s, i) => (
        <g key={i} transform={`translate(${cx + r + 40}, ${36 + i * 21})`}>
          <rect width={12} height={12} rx={2} fill={s.color} />
          <text x={18} y={10} fontSize={11} fontWeight={600} fill={IOH_INK}>{s.label.length > 22 ? s.label.slice(0, 21) + "…" : s.label}</text>
          <text x={300} y={10} fontSize={11} fontWeight={700} fill={IOH_MUTE} textAnchor="end">{fmtNumber(s.pct)}% · {fmtValue(s.value, s0.unit)}</text>
        </g>
      ))}
    </svg>
  );
}

// ---- Matrix (heatmap grid) ----
function MatrixSvg({ spec, rows }: Sub) {
  const cat = spec.category as string;
  const metrics = (spec.series || []).slice(0, 8);
  const data = rows.slice(0, 20);
  const cellW = 104, cellH = 30, labelW = 150, headH = 46;
  const W = labelW + metrics.length * cellW + 16;
  const H = headH + data.length * cellH + 12;

  const ranges = metrics.map((m) => {
    const vals = data.map((r) => Number(r[m.column])).filter((v) => Number.isFinite(v));
    return { min: Math.min(...vals, 0), max: Math.max(...vals, 1) };
  });

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} role="img" aria-label={spec.title} style={{ maxWidth: W }}>
      {metrics.map((m, i) => (
        <text key={m.column} x={labelW + i * cellW + cellW / 2} y={headH - 24} fontSize={10} fontWeight={700} fill={IOH_INK}
          textAnchor="middle" transform={`rotate(-12 ${labelW + i * cellW + cellW / 2} ${headH - 24})`}>
          {m.label.length > 13 ? m.label.slice(0, 12) + "…" : m.label}{m.unit ? ` (${m.unit})` : ""}
        </text>
      ))}
      {data.map((r, ri) => {
        const y = headH + ri * cellH;
        const lbl = String(r[cat] ?? "");
        return (
          <g key={ri}>
            <text x={8} y={y + cellH / 2 + 4} fontSize={11} fontWeight={600} fill={IOH_INK}>{lbl.length > 20 ? lbl.slice(0, 19) + "…" : lbl}</text>
            {metrics.map((m, mi) => {
              const v = Number(r[m.column]);
              const x = labelW + mi * cellW;
              const ok = Number.isFinite(v);
              const { min, max } = ranges[mi];
              const t = max === min ? 0.5 : (v - min) / (max - min);
              return (
                <g key={mi}>
                  <rect x={x + 1} y={y + 1} width={cellW - 2} height={cellH - 2} rx={3} stroke="#fff" strokeWidth={1}
                    fill={ok ? `rgba(21, 166, 151,${(0.12 + t * 0.78).toFixed(3)})` : "#F5F9F8"} />
                  <text x={x + cellW / 2} y={y + cellH / 2 + 4} fontSize={10} fontWeight={600} textAnchor="middle"
                    fill={ok && t > 0.6 ? "#fff" : IOH_INK}>{ok ? fmtValue(v, m.unit) : "N/A"}</text>
                </g>
              );
            })}
          </g>
        );
      })}
    </svg>
  );
}
