"use client";
/* Parts of the Tanya Agent answer card (Redesign v2, mockup 02): headline KPI cards with
   sparklines, and the "Visual jawaban" card with Grafik / Tabel / Peta tabs. */
import { useState, type ReactNode } from "react";
import SmartChart, { formatValue, humanize, toNum, dateLabel, type ChartSpec } from "@/app/components/charts/SmartChart";
import SiteMap from "@/app/components/SiteMap";
import AnswerChart, { type AnswerSeries } from "./AnswerChart";
import { Icon } from "./Icon";

type Row = Record<string, unknown>;

export type Kpi = {
  column: string; label: string; value: number; format: string;
  prev: number | null; delta: number | null; delta_unit: "%" | "pp" | null; vs: string | null; spark: number[];
};

export type AnswerResult = {
  columns: string[];
  rows: Row[];
  row_count: number;
  chart?: ChartSpec;
  kpis?: Kpi[];
  /** Where the numbers came from, e.g. "Dump Performance 1 Nov 05.00". */
  source?: string;
  bytes_processed?: number;
};

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
const SERIES_COLORS = ["#0E8579", "#22B8C9", "#FF7A59", "#6A4CB5", "#B7791F", "#C23A5B"];
const nf = (d: number) => new Intl.NumberFormat("id-ID", { minimumFractionDigits: d, maximumFractionDigits: d });

/* ---------- KPI cards ---------- */

const KIND: { re: RegExp; icon: string; bg: string; fg: string; spark: string }[] = [
  { re: /revenue|rev|arpu|rp|idr|sales|penjualan/i, icon: "wallet", bg: "#FCEDD3", fg: "#B7791F", spark: "#0E8579" },
  { re: /payload|traffic|trafik|data|gb|tb|pb/i, icon: "db", bg: "#E3F7FA", fg: "#0E6F7C", spark: "#1597A8" },
  { re: /site|tower|bts|cell|availability/i, icon: "tower", bg: "#FBE2E8", fg: "#C23A5B", spark: "#C23A5B" },
  { re: /user|subs|pelanggan|customer|ga\b|gross/i, icon: "users", bg: "#ECE5FA", fg: "#6A4CB5", spark: "#6A4CB5" },
];
const UNIT_SUFFIX: Record<string, string> = { pb: "PB", tb: "TB", gb: "GB", mb: "MB" };
/** Metrics where a rise is bad (shown red when they go up). */
const LOWER_IS_BETTER = /bawah|below|under|gagal|fail|churn|drop|down|outage|keluhan|complaint|cost|biaya/i;

function sentence(col: string): string {
  const h = humanize(col);
  return h.split(" ").map((w, i) => (i === 0 || /[A-Z]{2,}|\d/.test(w) ? w : w.toLowerCase())).join(" ");
}

export function kpiParts(k: Kpi): { label: string; value: string } {
  const m = k.column.match(/_(pb|tb|gb|mb)$/i);
  const unit = m ? UNIT_SUFFIX[m[1].toLowerCase()] : /^(jumlah_)?sites?(_|$)/i.test(k.column) && Number.isInteger(k.value) ? "site" : "";
  const label = sentence(m ? k.column.slice(0, -m[0].length) : k.column);
  const body = k.format === "number" && !Number.isInteger(k.value) ? nf(1).format(k.value) : formatValue(k.value, k.format);
  return { label, value: unit ? `${body} ${unit}` : body };
}

function vsLabel(v: string | null): string {
  if (!v) return "";
  const s = String(v);
  const ym = s.match(/^(\d{4})-?(\d{2})$/);
  if (ym) return MONTHS[+ym[2] - 1] ?? s;
  return dateLabel(s)?.replace(/ \d{4}$/, "") ?? s;
}

function Spark({ values, color }: { values: number[]; color: string }) {
  const W = 84, H = 30;
  const mn = Math.min(...values), mx = Math.max(...values);
  const X = (i: number) => 2 + ((W - 6) * i) / (values.length - 1);
  const Y = (a: number) => 3 + (H - 6) * (1 - (a - mn) / (mx - mn || 1));
  return (
    <svg className="kspark" width={W} height={H} aria-hidden="true">
      <path d={values.map((a, i) => `${i ? "L" : "M"}${X(i).toFixed(1)} ${Y(a).toFixed(1)}`).join(" ")} fill="none" stroke={color}
        strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={X(values.length - 1)} cy={Y(values[values.length - 1])} r={3} fill={color} />
    </svg>
  );
}

export function KpiRow({ kpis }: { kpis: Kpi[] }) {
  if (!kpis.length) return null;
  return (
    <div className="kpis" style={{ gridTemplateColumns: `repeat(${Math.min(3, kpis.length)}, 1fr)` }}>
      {kpis.slice(0, 3).map((k) => {
        const kind = KIND.find((c) => c.re.test(k.column)) ?? { icon: "pulse", bg: "#E6F7F5", fg: "#0A6A5F", spark: "#0E8579" };
        const { label, value } = kpiParts(k);
        let delta: ReactNode = null;
        if (k.delta != null && k.prev != null) {
          const diff = k.value - k.prev;
          const up = diff > 0;
          const good = LOWER_IS_BETTER.test(k.column) ? !up : up;
          const counts = k.format === "number" && Number.isInteger(k.value) && Number.isInteger(k.prev);
          const amount = counts ? nf(0).format(Math.abs(diff)) : `${nf(1).format(Math.abs(k.delta))}${k.delta_unit === "pp" ? " pp" : "%"}`;
          delta = (
            <span className={`d ${diff === 0 ? "" : good ? "up" : "dn"}`}>
              {diff === 0 ? "=" : up ? "▲" : "▼"} {amount} {k.vs && <span>vs {vsLabel(k.vs)}</span>}
            </span>
          );
        }
        return (
          <div className="kpi" key={k.column}>
            <span className="lb"><i style={{ background: kind.bg, color: kind.fg }}><Icon name={kind.icon} /></i>{label}</span>
            <span className="v">{value}</span>
            {delta}
            {k.spark.length > 1 && <Spark values={k.spark} color={kind.spark} />}
          </div>
        );
      })}
    </div>
  );
}

/* ---------- Visual card ---------- */

export function detectLatLon(columns: string[]): { latKey: string; lonKey: string } | null {
  const lat = columns.find((c) => /^lat(itude)?$/i.test(c) || /_lat(itude)?$/i.test(c) || /(addr_)?latitude/i.test(c));
  const lon = columns.find((c) => /^lon(g|gitude)?$/i.test(c) || /_lon(g|gitude)?$/i.test(c) || /(addr_)?longitude/i.test(c));
  return lat && lon ? { latKey: lat, lonKey: lon } : null;
}

type Plot = { labels: string[]; titles: string[]; series: AnswerSeries[]; fmt: string; mode: "line" | "bar"; per: string };
const DAYS = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"];
const ym = (v: unknown) => { const m = String(v ?? "").match(/^(\d{4})-?(\d{2})$/); return m && +m[2] >= 1 && +m[2] <= 12 ? { y: +m[1], m: +m[2] } : null; };
const dayNum = (v: unknown) => { const n = toNum(v); return n != null && Number.isInteger(n) && n >= 1 && n <= 31 ? n : null; };

/** Line and vertical bar results draw with the mockup chart; other shapes keep SmartChart. */
function toPlot(spec: ChartSpec | undefined, rows: Row[]): Plot | null {
  if (!spec || !spec.x || !["line", "area", "bar"].includes(spec.type) || !spec.y.length) return null;
  const x = spec.x;
  const fmt = spec.formats?.[spec.y[0]] ?? "number";
  const mode = spec.type === "bar" ? "bar" : "line";
  if (spec.series_by) {
    const sb = spec.series_by;
    let groups: string[] = [];
    rows.forEach((r) => { const g = String(r[sb] ?? ""); if (!groups.includes(g)) groups.push(g); });
    if (groups.length > SERIES_COLORS.length) return null;
    let keys: string[] = [];
    rows.forEach((r) => { const l = String(r[x] ?? ""); if (!keys.includes(l)) keys.push(l); });
    if (keys.length > 62) return null;
    const value = (k: string, g: string) => toNum(rows.find((r) => String(r[x] ?? "") === k && String(r[sb] ?? "") === g)?.[spec.y[0]]);
    // Month against month by day of month ("Okt vs Sep per hari"): newest month first,
    // axis "1 Okt", tooltip "Jum, 16 Okt 2026" with rows "Okt" and "16 Sep".
    if (groups.every((g) => ym(g)) && keys.every((k) => dayNum(k) != null)) {
      groups = [...groups].sort((a, b) => (String(b) > String(a) ? 1 : -1));
      keys = [...keys].sort((a, b) => dayNum(a)! - dayNum(b)!);
      const g0 = ym(groups[0])!;
      return {
        labels: keys.map((k) => `${dayNum(k)} ${MONTHS[g0.m - 1]}`),
        titles: keys.map((k) => { const d = dayNum(k)!; return `${DAYS[new Date(g0.y, g0.m - 1, d).getDay()]}, ${d} ${MONTHS[g0.m - 1]} ${g0.y}`; }),
        series: groups.map((g, gi) => {
          const gm = ym(g)!;
          return {
            name: `${MONTHS[gm.m - 1]} ${gm.y}`, color: SERIES_COLORS[gi], values: keys.map((k) => value(k, g)),
            tips: keys.map((k) => (gi === 0 ? MONTHS[gm.m - 1] : `${dayNum(k)} ${MONTHS[gm.m - 1]}`)),
          };
        }),
        fmt, mode, per: " per hari",
      };
    }
    const series = groups.map((g, gi) => ({ name: dateLabel(g) ?? g, color: SERIES_COLORS[gi], values: keys.map((k) => value(k, g)) }));
    return { labels: keys.map((l) => dateLabel(l) ?? l), titles: keys.map((l) => dateLabel(l) ?? l), series, fmt, mode, per: "" };
  }
  if (rows.length > 62 || spec.y.length > SERIES_COLORS.length) return null;
  const labels = rows.map((r) => String(r[x] ?? ""));
  const series = spec.y.map((c, i) => ({ name: humanize(c), color: SERIES_COLORS[i], values: rows.map((r) => toNum(r[c])) }));
  const monthly = labels.every((l) => ym(l));
  return { labels: labels.map((l) => dateLabel(l) ?? l), titles: labels.map((l) => dateLabel(l) ?? l), series, fmt, mode, per: monthly ? " per bulan" : "" };
}

/** One decimal for big numbers in the tooltip: "Rp 12,2 M". */
function fmt1(v: number, fmt: string): string {
  const a = Math.abs(v);
  const one = (n: number, u: string) => `${nf(1).format(n)} ${u}`;
  const body = a >= 1e12 ? one(v / 1e12, "T") : a >= 1e9 ? one(v / 1e9, "M") : a >= 1e6 ? one(v / 1e6, "jt") : null;
  if (!body) return formatValue(v, fmt);
  return fmt === "currency" ? `Rp ${body}` : body;
}

function unitText(plot: Plot): string {
  const vals = plot.series.flatMap((s) => s.values.filter((v): v is number => v != null)).map(Math.abs);
  const mx = vals.length ? Math.max(...vals) : 0;
  const u = plot.fmt === "currency" ? (mx >= 1e12 ? "Rp triliun" : mx >= 1e9 ? "Rp miliar" : mx >= 1e6 ? "Rp juta" : "Rupiah")
    : plot.fmt === "percent" ? "Persen" : mx >= 1e9 ? "Miliar" : mx >= 1e6 ? "Juta" : "";
  return u ? `${u}${plot.per}` : plot.per.trim();
}

function cell(v: unknown, col: string, spec?: ChartSpec): { text: string; cls: string } {
  const n = toNum(v);
  if (n == null) return { text: v == null ? "–" : String(v), cls: "" };
  const fmt = spec?.formats?.[col];
  const isDelta = /(mom|yoy|wow|qoq|growth|delta|change|selisih|vs_)/i.test(col);
  const text = isDelta && fmt === "percent"
    ? `${n > 0 ? "+" : n < 0 ? "−" : ""}${formatValue(Math.abs(n), "percent").replace("%", "")}%`
    : formatValue(n, fmt);
  return { text, cls: `n${isDelta ? (n < 0 ? " dn" : n > 0 ? " up" : "") : ""}` };
}

function V2Table({ columns, rows, spec }: { columns: string[]; rows: Row[]; spec?: ChartSpec }) {
  const [all, setAll] = useState(false);
  const shown = all ? rows : rows.slice(0, 8);
  const numeric = (c: string) => rows.some((r) => toNum(r[c]) != null);
  return (
    <div className="tblwrap">
      <table className="tbl">
        <thead><tr>{columns.map((c) => <th key={c} className={numeric(c) ? "n" : ""}>{humanize(c)}</th>)}</tr></thead>
        <tbody>
          {shown.map((r, i) => (
            <tr key={i}>{columns.map((c) => { const x = cell(r[c], c, spec); return <td key={c} className={x.cls}>{x.text}</td>; })}</tr>
          ))}
        </tbody>
      </table>
      {rows.length > 8 && (
        <button type="button" className="linkbtn tblmore" onClick={() => setAll((v) => !v)}>
          {all ? "Ringkas" : `Tampilkan semua ${rows.length} baris`}
        </button>
      )}
    </div>
  );
}

function tileShade(v: number): [string, string] {
  return v <= -5 ? ["#C42B2B", "#fff"] : v <= -2 ? ["#F7B4A7", "#6E2410"] : v < 0 ? ["#FDECEC", "#8A2020"] : v <= 2 ? ["#DDF1E4", "#1F5E30"] : ["#2E9E57", "#fff"];
}

/** Region tiles coloured by the first change column (or by the main metric's rank). */
function TileMap({ rows, spec, columns }: { rows: Row[]; spec: ChartSpec; columns: string[] }) {
  const key = spec.map_key!;
  const delta = columns.find((c) => /(mom|yoy|wow|growth|delta|change|vs_)/i.test(c) && rows.some((r) => toNum(r[c]) != null));
  const metric = delta ?? spec.y[0];
  const vals = rows.map((r) => toNum(r[metric]) ?? 0);
  const mx = Math.max(...vals.map(Math.abs), 1);
  return (
    <>
      <div className="tmap">
        {rows.slice(0, 24).map((r, i) => {
          const v = vals[i];
          const [bg, fg] = delta ? tileShade(v) : tileShade(((v / mx) * 10) - 5);
          return (
            <div key={i} style={{ background: bg, color: fg }}>{String(r[key] ?? "")}
              <span>{delta ? `${v > 0 ? "+" : v < 0 ? "−" : ""}${nf(1).format(Math.abs(v))}%` : formatValue(v, spec.formats?.[metric])}</span>
            </div>
          );
        })}
      </div>
      <p className="tmap-note">Peta ringkas per wilayah. Buka di Peta Agent untuk batas wilayah asli.</p>
    </>
  );
}

export function AnswerViz({ result, onDrill }: { result: AnswerResult; onDrill?: (col: string, value: string) => void }) {
  const spec = result.chart;
  const rows = result.rows;
  const plot = toPlot(spec, rows);
  const geo = detectLatLon(result.columns);
  const hasChart = !!plot || (!!spec && spec.type !== "none" && spec.type !== "kpi");
  const hasMap = !!geo || !!spec?.map_key;
  const [tab, setTab] = useState<"chart" | "table" | "map">(hasChart ? "chart" : "table");
  const title = spec?.title || "Hasil query";
  const sub = tab === "chart" && plot
    ? [unitText(plot), "arahkan kursor untuk detail"].filter(Boolean).join(" · ")
    : `${result.row_count.toLocaleString("id-ID")} baris`;
  return (
    <div className="viz">
      <div className="vhead">
        <div><h4>{title}</h4><p>{sub}</p></div>
        <div className="seg" role="tablist" aria-label="Bentuk jawaban">
          {hasChart && <button role="tab" aria-selected={tab === "chart"} className={tab === "chart" ? "on" : ""} onClick={() => setTab("chart")}><Icon name="line" />Grafik</button>}
          <button role="tab" aria-selected={tab === "table"} className={tab === "table" ? "on" : ""} onClick={() => setTab("table")}><Icon name="table" />Tabel</button>
          {hasMap && <button role="tab" aria-selected={tab === "map"} className={tab === "map" ? "on" : ""} onClick={() => setTab("map")}><Icon name="map" />Peta</button>}
        </div>
      </div>
      {tab === "chart" && plot && (
        <AnswerChart labels={plot.labels} titles={plot.titles} series={plot.series} initialMode={plot.mode}
          format={(v) => fmt1(v, plot.fmt)} axisFormat={(v) => formatValue(v, plot.fmt).replace(/^Rp /, "")} />
      )}
      {tab === "chart" && !plot && spec && <SmartChart spec={spec} rows={rows} onDrill={onDrill} bare height={spec.type === "hbar" ? Math.min(420, 60 + Math.min(rows.length, spec.top_n ?? 15) * 30) : 240} />}
      {tab === "table" && <V2Table columns={result.columns} rows={rows} spec={spec} />}
      {tab === "map" && (geo
        ? <div className="vmap"><SiteMap columns={result.columns} rows={rows} latKey={geo.latKey} lonKey={geo.lonKey} /></div>
        : spec?.map_key ? <TileMap rows={rows} spec={spec} columns={result.columns} /> : null)}
    </div>
  );
}
