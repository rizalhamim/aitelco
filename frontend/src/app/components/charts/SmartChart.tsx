"use client";
import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ECharts, EChartsOption } from "echarts";
import {
  BarChart3, Check, ChevronDown, Database, Maximize2, Minimize2, RadioTower, TrendingDown, TrendingUp,
  UserPlus, Users, Wallet,
} from "lucide-react";
import { getPrefs, PREFS_EVENT, type UiPrefs } from "@/lib/prefs";

export type ChartType =
  | "kpi" | "line" | "area" | "bar" | "hbar" | "stacked_bar"
  | "donut" | "scatter" | "combo" | "none";

/** Mirrors backend/app/chart_spec.py. */
export type ChartSpec = {
  type: ChartType;
  x: string | null;
  y: string[];
  y2: string[];
  series_by: string | null;
  label: string | null;
  formats: Record<string, "currency" | "percent" | "number">;
  sort: "desc" | null;
  top_n: number | null;
  map_key: string | null;
  alternatives: ChartType[];
  title: string;
};

type Row = Record<string, unknown>;

type Props = {
  spec: ChartSpec;
  rows: Row[];
  /** Called with the clicked category when the chart offers a drill-down. */
  onDrill?: (column: string, value: string) => void;
  height?: number;
  subtitle?: string;
  /** Render without the outer card border (when the caller already draws one). */
  bare?: boolean;
  className?: string;
  /** Extra row between the header and the plot (breadcrumbs, badges). */
  toolbar?: React.ReactNode;
};

const TYPE_LABEL: Record<ChartType, string> = {
  kpi: "KPI", line: "Garis", area: "Area", bar: "Batang", hbar: "Batang horizontal",
  stacked_bar: "Bertumpuk", donut: "Donat", scatter: "Sebaran", combo: "Kombinasi", none: "",
};

function cssVar(name: string, fallback: string): string {
  if (typeof window === "undefined") return fallback;
  const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return v || fallback;
}

/** Series colors in the order the mockups use them. */
export function chartPalette(): string[] {
  return [
    cssVar("--ds-teal600", "#0E8579"),
    cssVar("--ds-teal300", "#5BCEC3"),
    "#F8D49B",
    cssVar("--ds-blue600", "#2C6CB0"),
    cssVar("--ds-violet600", "#6A4CB5"),
    cssVar("--ds-amber700", "#B7791F"),
    cssVar("--ds-rose600", "#C23A5B"),
    cssVar("--ds-green600", "#1F7A3A"),
  ];
}

const ACRONYMS: Record<string, string> = {
  mom: "MoM", yoy: "YoY", wow: "WoW", qoq: "QoQ", pct: "%", arpu: "ARPU", fwa: "FWA", ftth: "FTTH",
  ga: "GA", rgb: "RGB", kpi: "KPI", id: "ID", pb: "PB", gb: "GB", tb: "TB", bts: "BTS", im3: "IM3", "5g": "5G", "4g": "4G",
};

/** "mom_pct" → "MoM (%)", "revenue_bulan_lalu" → "Revenue Bulan Lalu" (mirrors chart_spec._humanize). */
export function humanize(col: string): string {
  const words = col.replace(/_/g, " ").split(/\s+/).filter(Boolean);
  const out = words.map((w) => ACRONYMS[w.toLowerCase()] ?? (w === w.toLowerCase() ? w[0].toUpperCase() + w.slice(1) : w));
  return out.length ? out.join(" ").replace(/ %/g, " (%)") : col;
}

const idNum = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 2 });

/** Short Indonesian number: 1.234 rb, 12,3 jt, 4,5 M, 1,2 T. */
export function shortNum(n: number): string {
  const a = Math.abs(n);
  if (a >= 1e12) return idNum.format(+(n / 1e12).toFixed(2)) + " T";
  if (a >= 1e9) return idNum.format(+(n / 1e9).toFixed(2)) + " M";
  if (a >= 1e6) return idNum.format(+(n / 1e6).toFixed(1)) + " jt";
  if (a >= 1e4) return idNum.format(+(n / 1e3).toFixed(1)) + " rb";
  return idNum.format(n);
}

export function formatValue(v: unknown, fmt?: string, short = true): string {
  if (typeof v !== "number" || !Number.isFinite(v)) return v == null ? "–" : String(v);
  if (fmt === "percent") {
    // Ratios stored as 0..1 read better as percentages.
    const pct = Math.abs(v) <= 1 && v !== 0 ? v * 100 : v;
    return idNum.format(+pct.toFixed(2)) + "%";
  }
  const body = short ? shortNum(v) : idNum.format(v);
  return fmt === "currency" ? "Rp " + body : body;
}

export function toNum(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string" && v.trim() !== "" && !Number.isNaN(Number(v))) return Number(v);
  return null;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
const DAYS = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"];

function timeLabel(v: unknown): string {
  const s = String(v ?? "");
  if (/^\d{6}$/.test(s)) return `${MONTHS[+s.slice(4, 6) - 1] ?? s.slice(4, 6)} ${s.slice(2, 4)}`;
  if (/^\d{8}$/.test(s)) return `${+s.slice(6, 8)} ${MONTHS[+s.slice(4, 6) - 1] ?? ""}`;
  const m = s.match(/^(\d{4})-(\d{2})(?:-(\d{2}))?/);
  if (m) return m[3] ? `${+m[3]} ${MONTHS[+m[2] - 1]}` : `${MONTHS[+m[2] - 1]} ${m[1].slice(2)}`;
  return s.length > 16 ? s.slice(0, 16) + "…" : s;
}

/** "2026-10-16" → "16 Okt 2026"; other values unchanged. */
export function dateLabel(v: unknown): string | null {
  const s = String(v ?? "");
  const m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T]|$)/) || s.match(/^(\d{4})(\d{2})(\d{2})$/);
  if (m) return `${+m[3]} ${MONTHS[+m[2] - 1]} ${m[1]}`;
  const ym = s.match(/^(\d{4})-?(\d{2})$/);
  if (ym && +ym[2] >= 1 && +ym[2] <= 12) return `${MONTHS[+ym[2] - 1]} ${ym[1]}`;
  return null;
}

function longTimeLabel(v: unknown): string {
  const s = String(v ?? "");
  const m = s.match(/^(\d{4})-?(\d{2})-?(\d{2})?/);
  if (m && m[3]) {
    const d = new Date(+m[1], +m[2] - 1, +m[3]);
    return `${DAYS[d.getDay()]}, ${+m[3]} ${MONTHS[+m[2] - 1]} ${m[1]}`;
  }
  if (m) return `${MONTHS[+m[2] - 1]} ${m[1]}`;
  return s;
}

function prepareRows(spec: ChartSpec, rows: Row[], showAll: boolean): Row[] {
  let out = rows;
  const measure = spec.y[0];
  if (spec.sort === "desc" && spec.x && measure && !spec.series_by) {
    out = [...rows].sort((a, b) => (toNum(b[measure]) ?? -Infinity) - (toNum(a[measure]) ?? -Infinity));
  }
  if (spec.top_n && !showAll && !spec.series_by) out = out.slice(0, spec.top_n);
  return out;
}

type LegendItem = { name: string; color: string; dashed?: boolean };
type Built = { option: EChartsOption; legend: LegendItem[] };

function buildOption(spec: ChartSpec, type: ChartType, rows: Row[], prefs: UiPrefs, compact: boolean): Built {
  const colors = chartPalette();
  const ink = cssVar("--ds-ink", "#0F1F1D");
  const mute = cssVar("--ds-text-mute", "#5A6B68");
  const rule = cssVar("--ds-rule", "#E1E9E7");
  const surface = cssVar("--ds-surface", "#FFFFFF");
  const muted = cssVar("--ds-surface-muted", "#ECF3F1");
  const teal50 = cssVar("--ds-teal50", "#E6F7F5");
  const grey = cssVar("--ds-chart-grey", "#B9C6C3");
  const fmtOf = (c: string) => spec.formats[c];
  const legend: LegendItem[] = [];

  const tooltipBase = {
    show: prefs.tooltip,
    backgroundColor: "rgba(15,31,29,0.94)",
    borderWidth: 0,
    padding: [10, 12],
    textStyle: { color: "#fff", fontSize: 12, fontFamily: "Poppins, system-ui, sans-serif" },
    extraCssText: "border-radius:12px;box-shadow:0 16px 40px -4px rgba(15,31,29,.10),0 2px 6px rgba(15,31,29,.05);",
  };
  const row = (color: string, label: string, value: string) =>
    `<div style="display:flex;align-items:center;gap:6px;margin-top:6px;min-width:140px">` +
    `<span style="width:8px;height:8px;border-radius:99px;background:${color}"></span>` +
    `<span style="color:#C9D6D3;flex:1">${label}</span><b style="font-weight:600;margin-left:12px">${value}</b></div>`;

  const base: EChartsOption = {
    color: colors,
    animation: prefs.animation,
    animationDuration: 500,
    animationDurationUpdate: 400,
    animationEasing: "cubicOut",
    textStyle: { fontFamily: "Poppins, system-ui, sans-serif", color: ink },
    grid: { left: 4, right: 12, top: 12, bottom: 4, containLabel: true },
    legend: { show: false },
  };

  const axisCommon = {
    axisLine: { show: false },
    axisTick: { show: false },
    axisLabel: { color: mute, fontSize: 12 },
    splitLine: { lineStyle: { color: rule } },
  };

  if (type === "donut") {
    const m = spec.y[0];
    const data = rows.map((r, i) => ({ name: String(r[spec.x ?? ""] ?? ""), value: toNum(r[m]) ?? 0, itemStyle: { color: colors[i % colors.length] } }));
    data.forEach((d, i) => legend.push({ name: d.name, color: colors[i % colors.length] }));
    const total = data.reduce((s, d) => s + d.value, 0);
    return {
      legend,
      option: {
        ...base,
        tooltip: {
          ...tooltipBase, trigger: "item",
          formatter: (p: unknown) => {
            const q = p as { name: string; value: number; percent: number; color: string };
            return `<b style="font-weight:600">${q.name}</b>` + row(q.color, humanize(m), formatValue(q.value, fmtOf(m))) + row(q.color, "Porsi", `${idNum.format(q.percent)}%`);
          },
        },
        title: {
          text: formatValue(total, fmtOf(m)), subtext: "Total",
          left: "center", top: "38%",
          textStyle: { fontSize: 20, fontWeight: 700, color: ink }, subtextStyle: { fontSize: 12, color: mute },
        },
        series: [{
          type: "pie", radius: ["58%", "82%"], center: ["50%", "50%"], avoidLabelOverlap: true,
          itemStyle: { borderRadius: 6, borderColor: surface, borderWidth: 3 },
          label: { show: false },
          emphasis: { scale: true, scaleSize: 6 },
          data,
        }],
      },
    };
  }

  if (type === "scatter") {
    const [mx, my] = spec.y;
    legend.push({ name: spec.label ? humanize(spec.label) : "Titik", color: colors[0] });
    return {
      legend,
      option: {
        ...base,
        tooltip: {
          ...tooltipBase, trigger: "item",
          formatter: (p: unknown) => {
            const d = (p as { data: [number, number, string] }).data;
            return `<b style="font-weight:600">${d[2] ?? ""}</b>` + row(colors[0], humanize(mx), formatValue(d[0], fmtOf(mx), false)) + row(colors[0], humanize(my), formatValue(d[1], fmtOf(my), false));
          },
        },
        grid: { ...base.grid, bottom: 28, left: 12 },
        xAxis: { ...axisCommon, type: "value", name: humanize(mx), nameLocation: "middle", nameGap: 30, nameTextStyle: { color: mute }, axisLabel: { ...axisCommon.axisLabel, formatter: (v: number) => formatValue(v, fmtOf(mx)) } },
        yAxis: { ...axisCommon, type: "value", name: humanize(my), nameTextStyle: { color: mute }, axisLabel: { ...axisCommon.axisLabel, formatter: (v: number) => formatValue(v, fmtOf(my)) } },
        series: [{
          type: "scatter", symbolSize: 12,
          itemStyle: { color: colors[0], opacity: 0.75, borderColor: surface, borderWidth: 1 },
          emphasis: { focus: "self", scale: 1.6 },
          data: rows.map((r) => [toNum(r[mx]) ?? 0, toNum(r[my]) ?? 0, String(r[spec.label ?? ""] ?? "")]),
        }],
      },
    };
  }

  const x = spec.x ?? "";
  const horizontal = type === "hbar";
  const isLine = type === "line" || type === "area";
  const rawCats: unknown[] = spec.series_by
    ? Array.from(new Set(rows.map((r) => r[x])))
    : rows.map((r) => r[x]);
  const categories = rawCats.map((c) => String(c ?? ""));
  let series: NonNullable<EChartsOption["series"]>;
  const seriesFmt: string[] = [];

  const areaFill = (c: string) => ({
    type: "linear" as const, x: 0, y: 0, x2: 0, y2: 1,
    colorStops: [{ offset: 0, color: c + "33" }, { offset: 1, color: c + "00" }],
  });

  const mkSeries = (name: string, data: (number | null)[], i: number, opts: { kind: "line" | "bar"; yAxisIndex?: number; stack?: boolean; fmt?: string; dashed?: boolean; area?: boolean }) => {
    const c = opts.dashed ? grey : colors[i % colors.length];
    legend.push({ name, color: c, dashed: opts.dashed });
    seriesFmt.push(opts.fmt ?? "number");
    if (opts.kind === "line") {
      return {
        name, type: "line" as const, data, yAxisIndex: opts.yAxisIndex ?? 0, color: c,
        smooth: 0.35, showSymbol: rows.length <= 12 && !compact, symbol: "circle", symbolSize: 8,
        lineStyle: { width: opts.dashed ? 2 : 2.5, type: opts.dashed ? ("dashed" as const) : ("solid" as const), color: c },
        itemStyle: { color: c, borderColor: surface, borderWidth: 2 },
        areaStyle: opts.area ? { color: areaFill(c) } : undefined,
        stack: opts.stack ? "total" : undefined,
        emphasis: { scale: 1.5, itemStyle: { color: surface, borderColor: c, borderWidth: 3 } },
        z: opts.dashed ? 1 : 2,
      };
    }
    return {
      name, type: "bar" as const, data, yAxisIndex: opts.yAxisIndex ?? 0, color: c,
      stack: opts.stack ? "total" : undefined,
      barMaxWidth: horizontal ? 16 : 18, barGap: "35%", barCategoryGap: "38%",
      itemStyle: { color: c, borderRadius: opts.stack ? 0 : horizontal ? [0, 6, 6, 0] : [6, 6, 0, 0] },
      emphasis: { focus: "series" as const },
    };
  };

  if (spec.series_by) {
    // Long format → one series per split value.
    const m = spec.y[0];
    const groups = Array.from(new Set(rows.map((r) => String(r[spec.series_by!] ?? ""))));
    const cell = new Map<string, number>();
    rows.forEach((r) => cell.set(`${r[x]}|${r[spec.series_by!]}`, toNum(r[m]) ?? 0));
    series = groups.map((g, i) => mkSeries(g, rawCats.map((c) => cell.get(`${c}|${g}`) ?? 0), i, {
      kind: isLine ? "line" : "bar", stack: type === "stacked_bar", fmt: fmtOf(m), area: type === "area",
    }));
  } else if (type === "combo") {
    series = [
      ...spec.y.map((c, i) => mkSeries(humanize(c), rows.map((r) => toNum(r[c])), i, { kind: "bar", fmt: fmtOf(c) })),
      ...spec.y2.map((c, i) => mkSeries(humanize(c), rows.map((r) => toNum(r[c])), i + 3, { kind: "line", yAxisIndex: 1, fmt: fmtOf(c) })),
    ];
  } else {
    const targets = prefs.targetLine ? Object.keys(rows[0] ?? {}).filter((c) => /target|tgt/i.test(c) && !spec.y.includes(c)) : [];
    series = [
      ...spec.y.map((c, i) => {
        // A "previous period" measure reads as the dashed comparison line.
        const dashed = isLine && i > 0 && /prev|lalu|sebelum|_ly$|last/i.test(c);
        return mkSeries(humanize(c), rows.map((r) => toNum(r[c])), i, {
          kind: isLine ? "line" : "bar", fmt: fmtOf(c), dashed, area: isLine && (type === "area" || i === 0) && !dashed,
        });
      }),
      ...targets.map((c) => {
        const amber = cssVar("--ds-warning", "#F5A623");
        legend.push({ name: humanize(c), color: amber, dashed: true });
        seriesFmt.push(fmtOf(spec.y[0]) ?? "number");
        return {
          name: humanize(c), type: "line" as const, data: rows.map((r) => toNum(r[c])), color: amber,
          showSymbol: false, lineStyle: { type: "dashed" as const, width: 1.5, color: amber }, z: 3,
        };
      }),
    ];
  }

  const catAxis = {
    ...axisCommon,
    type: "category" as const,
    data: categories.map(timeLabel),
    boundaryGap: !isLine,
    axisLabel: { ...axisCommon.axisLabel, hideOverlap: true, width: horizontal ? 130 : 90, overflow: "truncate" as const, margin: 12 },
    splitLine: { show: false },
    inverse: horizontal,
  };
  const valFmt = (c: string) => (v: number) => formatValue(v, fmtOf(c));
  const valAxis = [
    // Lines read better zoomed to their range; bars must start at zero.
    { ...axisCommon, type: "value" as const, splitNumber: 3, scale: isLine && !spec.series_by, axisLabel: { ...axisCommon.axisLabel, formatter: valFmt(spec.y[0]) } },
    ...(type === "combo" && spec.y2.length
      ? [{ ...axisCommon, type: "value" as const, splitNumber: 3, splitLine: { show: false }, axisLabel: { ...axisCommon.axisLabel, formatter: valFmt(spec.y2[0]) } }]
      : []),
  ];

  const zoomable = !horizontal && categories.length > 14 && !compact;
  const visible = Math.min(categories.length, isLine ? 31 : 14);
  const start = zoomable ? Math.max(0, 100 - (visible / categories.length) * 100) : 0;
  const teal500 = cssVar("--ds-teal500", "#15A697");

  return {
    legend,
    option: {
      ...base,
      tooltip: {
        ...tooltipBase,
        trigger: "axis",
        axisPointer: isLine
          ? { type: "line", lineStyle: { color: mute, type: "dashed", width: 1.5 } }
          : { type: "shadow", shadowStyle: { color: teal50, opacity: 0.9 } },
        formatter: (ps: unknown) => {
          const arr = ps as { dataIndex: number; seriesIndex: number; seriesName: string; value: number | null; color: string }[];
          if (!arr.length) return "";
          const head = isLine ? longTimeLabel(rawCats[arr[0].dataIndex]) : String(categories[arr[0].dataIndex] ?? "");
          return `<b style="font-weight:600">${head}</b>` + arr
            .map((p) => row(legend[p.seriesIndex]?.color ?? p.color, p.seriesName, formatValue(p.value, seriesFmt[p.seriesIndex])))
            .join("");
        },
      },
      grid: { ...base.grid, bottom: zoomable ? 52 : 4 },
      xAxis: horizontal ? valAxis[0] : catAxis,
      yAxis: horizontal ? catAxis : valAxis,
      dataZoom: zoomable
        ? [
            { type: "inside", start, end: 100 },
            {
              type: "slider", start, end: 100, height: 34, bottom: 0, left: 8, right: 8,
              backgroundColor: muted, borderColor: "transparent", borderRadius: 8,
              fillerColor: teal500 + "1A",
              dataBackground: { lineStyle: { color: colors[1], width: 1.2 }, areaStyle: { color: "transparent" } },
              selectedDataBackground: { lineStyle: { color: colors[0], width: 1.2 }, areaStyle: { color: "transparent" } },
              handleIcon: "path://M4,0 a4,4 0 0 1 4,4 v12 a4,4 0 0 1 -4,4 a4,4 0 0 1 -4,-4 v-12 a4,4 0 0 1 4,-4 z",
              handleSize: "60%",
              handleStyle: { color: surface, borderColor: teal500, borderWidth: 1.5 },
              moveHandleSize: 0,
              brushSelect: false,
              showDetail: false,
            },
          ]
        : undefined,
      series,
    },
  };
}

function kpiIcon(col: string) {
  if (/rev|rp|arpu|sales|amount|nilai/i.test(col)) return { Icon: Wallet, tone: "amber" };
  if (/payload|traffic|data|gb|tb|pb/i.test(col)) return { Icon: Database, tone: "violet" };
  if (/gross|add|ga\b|acq|new/i.test(col)) return { Icon: UserPlus, tone: "green" };
  if (/sub|user|pelanggan|customer|rgb/i.test(col)) return { Icon: Users, tone: "blue" };
  if (/site|avail|bts|tower|cell/i.test(col)) return { Icon: RadioTower, tone: "teal" };
  return { Icon: BarChart3, tone: "teal" };
}

const DELTA_COL = /(_|^)(mom|yoy|wow|qoq|growth|delta|change|pct_change|chg|gap)(_|$)/i;

export function KpiTiles({ spec, rows }: { spec: ChartSpec; rows: Row[] }) {
  const r = rows[0] ?? {};
  const deltas = spec.y.filter((c) => DELTA_COL.test(c));
  const values = spec.y.filter((c) => !DELTA_COL.test(c));
  // Pair each delta with the value column it most likely describes.
  const deltaFor = (c: string) => deltas.find((d) => d.toLowerCase().startsWith(c.toLowerCase().split("_")[0])) ??
    (values.length === 1 ? deltas[0] : undefined);
  return (
    <div className="sc-kpis">
      {(values.length ? values : spec.y).map((c) => {
        const { Icon, tone } = kpiIcon(c);
        const d = deltaFor(c);
        const dv = d ? toNum(r[d]) : null;
        return (
          <div key={c} className="ui-kpi">
            <div className="ui-kpi-top">
              <span className="ui-tile" data-tone={tone}><Icon size={18} /></span>
              {dv != null && (
                <span className={`ui-delta ${dv > 0 ? "up" : dv < 0 ? "down" : "flat"}`}>
                  {dv >= 0 ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
                  {formatValue(Math.abs(dv), spec.formats[d!] ?? "percent")}
                </span>
              )}
            </div>
            <span className="ui-kpi-label">{humanize(c)}</span>
            <span className="ui-kpi-value">{formatValue(r[c], spec.formats[c])}</span>
          </div>
        );
      })}
    </div>
  );
}

export function usePrefs(): UiPrefs {
  const [prefs, setPrefs] = useState<UiPrefs>(() => getPrefs());
  useEffect(() => {
    const read = () => setPrefs(getPrefs());
    read();
    window.addEventListener(PREFS_EVENT, read);
    return () => window.removeEventListener(PREFS_EVENT, read);
  }, []);
  return prefs;
}

/** Changes whenever light/dark or accent changes, so canvas colors follow the theme. */
export function useThemeKey(): string {
  const [key, setKey] = useState("");
  useEffect(() => {
    const el = document.documentElement;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const read = () => setKey(`${el.className}|${el.dataset.theme}|${el.dataset.accent}|${mq.matches}`);
    read();
    mq.addEventListener("change", read);
    const obs = new MutationObserver(read);
    obs.observe(el, { attributes: true, attributeFilter: ["data-theme", "class", "data-accent"] });
    return () => { mq.removeEventListener("change", read); obs.disconnect(); };
  }, []);
  return key;
}

export default function SmartChart({ spec, rows, onDrill, height = 240, subtitle, bare, className, toolbar }: Props) {
  const el = useRef<HTMLDivElement>(null);
  const chart = useRef<ECharts | null>(null);
  const [type, setType] = useState<ChartType>(spec.type);
  const [showAll, setShowAll] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [menu, setMenu] = useState(false);
  const [hiddenSeries, setHiddenSeries] = useState<Record<string, boolean>>({});
  const [legend, setLegend] = useState<LegendItem[]>([]);
  const prefs = usePrefs();
  const themeKey = useThemeKey();
  const data = useMemo(() => prepareRows(spec, rows, showAll), [spec, rows, showAll]);
  const hidden = spec.top_n && !showAll && !spec.series_by ? Math.max(0, rows.length - spec.top_n) : 0;
  const drillRef = useRef(onDrill);
  useEffect(() => { drillRef.current = onDrill; }, [onDrill]);

  const [specType, setSpecType] = useState(spec.type);
  if (specType !== spec.type) {
    setSpecType(spec.type);
    setType(spec.type);
  }

  useEffect(() => {
    if (!expanded) return;
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") setExpanded(false); };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [expanded]);

  useEffect(() => {
    if (type === "kpi" || type === "none" || !el.current) return;
    let disposed = false;
    let ro: ResizeObserver | null = null;
    import("echarts").then((echarts) => {
      if (disposed || !el.current) return;
      chart.current?.dispose();
      const c = echarts.init(el.current, undefined, { renderer: "canvas" });
      chart.current = c;
      const built = buildOption(spec, type, data, prefs, !expanded && height < 200);
      c.setOption(built.option, true);
      setLegend(built.legend);
      setHiddenSeries({});
      c.on("click", (p) => {
        const q = p as { name?: string; dataIndex?: number };
        const drill = drillRef.current;
        if (!drill || !spec.x || q.name == null) return;
        const raw = spec.series_by || q.dataIndex == null ? q.name : String(data[q.dataIndex]?.[spec.x] ?? q.name);
        drill(spec.map_key ?? spec.x, raw);
      });
      ro = new ResizeObserver(() => c.resize());
      ro.observe(el.current);
    });
    return () => { disposed = true; ro?.disconnect(); chart.current?.dispose(); chart.current = null; };
  }, [spec, type, data, prefs, themeKey, expanded, height]);

  const toggleSeries = useCallback((name: string) => {
    chart.current?.dispatchAction({ type: "legendToggleSelect", name });
    setHiddenSeries((h) => ({ ...h, [name]: !h[name] }));
  }, []);

  if (spec.type === "none") return null;
  const options = [spec.type, ...spec.alternatives.filter((a) => a !== spec.type)];
  const isSeriesLegend = type !== "donut";
  const sub = subtitle ?? (type === "kpi" ? "" : onDrill && spec.map_key
    ? `Klik ${type === "line" || type === "area" ? "titik" : "batang"} untuk detail ${humanize(spec.map_key).toLowerCase()}`
    : "Arahkan kursor untuk detail");

  const head = (
    <figcaption className="sc-head">
      <div className="sc-titles">
        <span className="sc-title">{spec.title}</span>
        {sub && <span className="sc-sub">{sub}</span>}
      </div>
      <div className="sc-actions">
        {type !== "kpi" && legend.length > 1 && legend.length <= 8 && (
          <div className="sc-legend" role="group" aria-label="Seri">
            {legend.map((l) => (
              <button key={l.name} type="button" className="sc-pill" aria-pressed={!hiddenSeries[l.name]}
                onClick={() => isSeriesLegend && toggleSeries(l.name)}>
                <span className={`sc-dot ${l.dashed ? "dashed" : ""}`} style={{ background: l.color }} />
                {l.name}
              </button>
            ))}
          </div>
        )}
        {options.length > 1 && (
          <div className="sc-type">
            <button type="button" className="sc-pill" onClick={() => setMenu((v) => !v)} aria-expanded={menu} aria-haspopup="menu">
              {TYPE_LABEL[type]} <ChevronDown size={14} />
            </button>
            {menu && (
              <div className="ui-popover sc-type-menu" role="menu" onMouseLeave={() => setMenu(false)}>
                {options.map((t) => (
                  <button key={t} role="menuitemradio" aria-checked={t === type} onClick={() => { setType(t); setMenu(false); }}>
                    <span className="sc-check">{t === type && <Check size={14} />}</span>{TYPE_LABEL[t]}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
        {type !== "kpi" && (
          <button type="button" className="ui-iconbtn sm" onClick={() => setExpanded((v) => !v)}
            aria-label={expanded ? "Perkecil grafik" : "Perbesar grafik"}>
            {expanded ? <Minimize2 size={16} /> : <Maximize2 size={16} />}
          </button>
        )}
      </div>
    </figcaption>
  );

  if (type === "kpi") {
    return (
      <figure className="sc-kpi-wrap">
        {options.length > 1 && head}
        <KpiTiles spec={spec} rows={rows} />
      </figure>
    );
  }

  return (
    <>
      {expanded && <div className="sc-scrim" onClick={() => setExpanded(false)} />}
      <figure className={`sc-card ${bare ? "bare" : ""} ${expanded ? "expanded" : ""} ${className ?? ""}`}>
        {head}
        {toolbar}
        <div ref={el} className="sc-canvas" style={{ height: expanded ? "min(70vh, 640px)" : height }} role="img" aria-label={spec.title} />
        {(hidden > 0 || (showAll && spec.top_n)) && (
          <button type="button" className="sc-more" onClick={() => setShowAll((v) => !v)}>
            {showAll ? `Tampilkan ${spec.top_n} teratas` : `Tampilkan semua (${rows.length})`}
          </button>
        )}
      </figure>
    </>
  );
}
