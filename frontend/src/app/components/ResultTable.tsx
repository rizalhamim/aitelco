"use client";
import { useMemo, useState } from "react";
import { ArrowDown, ArrowRight, ArrowUp, TrendingDown, TrendingUp } from "lucide-react";
import { dateLabel, formatValue, humanize, toNum, type ChartSpec } from "./charts/SmartChart";

type Row = Record<string, unknown>;

type Props = {
  columns: string[];
  rows: Row[];
  spec?: ChartSpec;
  /** Shows a "Lihat di peta" link on each row of a territory result. */
  onShowMap?: (column: string, value: string) => void;
  initialRows?: number;
};

const GROWTH = /(_|^)(mom|yoy|wow|qoq|growth|delta|change|chg|gap|selisih)(_|$)/i;
const PCT = /(pct|percent|persen|rate|ratio|share|growth|mom|yoy|ach|availability|util|churn)/i;
const CUR = /(revenue|rev|arpu|rp|idr|amount|nilai|cost|biaya|price|harga)/i;

function fmtOf(col: string, spec?: ChartSpec): string | undefined {
  return spec?.formats[col] ?? (PCT.test(col) ? "percent" : CUR.test(col) ? "currency" : undefined);
}

export default function ResultTable({ columns, rows, spec, onShowMap, initialRows = 8 }: Props) {
  const [sort, setSort] = useState<{ col: string; dir: 1 | -1 } | null>(null);
  const [all, setAll] = useState(false);

  const numeric = useMemo(() => {
    const out: Record<string, boolean> = {};
    for (const c of columns) {
      const vals = rows.slice(0, 50).map((r) => r[c]).filter((v) => v != null && v !== "");
      out[c] = vals.length > 0 && vals.every((v) => toNum(v) != null);
    }
    return out;
  }, [columns, rows]);

  const growthCol = columns.find((c) => numeric[c] && GROWTH.test(c));
  const labelCol = spec?.map_key ?? spec?.x ?? columns.find((c) => !numeric[c]);

  const sorted = useMemo(() => {
    if (!sort) return rows;
    return [...rows].sort((a, b) => {
      const x = a[sort.col], y = b[sort.col];
      const nx = toNum(x), ny = toNum(y);
      if (nx != null && ny != null) return (nx - ny) * sort.dir;
      return String(x ?? "").localeCompare(String(y ?? ""), "id") * sort.dir;
    });
  }, [rows, sort]);
  const shown = all ? sorted : sorted.slice(0, initialRows);

  const toggle = (col: string) =>
    setSort((s) => (s?.col === col ? (s.dir === -1 ? { col, dir: 1 } : null) : { col, dir: -1 }));

  return (
    <div className="rt">
      <div className="ui-table-wrap">
        <table className="ui-table rt-table">
          <thead>
            <tr>
              {columns.map((c) => (
                <th key={c} className={numeric[c] ? "num" : ""} aria-sort={sort?.col === c ? (sort.dir === 1 ? "ascending" : "descending") : "none"}>
                  <button type="button" className="rt-sort" onClick={() => toggle(c)}>
                    {humanize(c)}
                    {sort?.col === c && (sort.dir === 1 ? <ArrowUp size={12} /> : <ArrowDown size={12} />)}
                  </button>
                </th>
              ))}
              {onShowMap && labelCol && <th aria-label="Aksi" />}
            </tr>
          </thead>
          <tbody>
            {shown.map((r, i) => {
              const g = growthCol ? toNum(r[growthCol]) : null;
              return (
                <tr key={i} className={i === 0 && !sort && g != null && g < 0 ? "hl" : ""}>
                  {columns.map((c) => {
                    const v = r[c];
                    if (c === growthCol && toNum(v) != null) {
                      const n = toNum(v)!;
                      return (
                        <td key={c} className="num">
                          <span className={`ui-delta lg ${n > 0 ? "up" : n < 0 ? "down" : "flat"}`}>
                            {n >= 0 ? <TrendingUp size={12} /> : <TrendingDown size={12} />}
                            {formatValue(Math.abs(n), fmtOf(c, spec) ?? "percent")}
                          </span>
                        </td>
                      );
                    }
                    if (c === labelCol) {
                      return (
                        <td key={c}>
                          <span className="rt-label">
                            {g != null && <span className={`rt-dot ${g < -2 ? "bad" : g < 0 ? "warn" : "ok"}`} />}
                            {dateLabel(v) ?? String(v ?? "–")}
                          </span>
                        </td>
                      );
                    }
                    return (
                      <td key={c} className={numeric[c] ? "num" : ""}>
                        {numeric[c] && !dateLabel(v) ? formatValue(toNum(v), fmtOf(c, spec), false) : dateLabel(v) ?? String(v ?? "–")}
                      </td>
                    );
                  })}
                  {onShowMap && labelCol && (
                    <td>
                      <button type="button" className="ui-link" onClick={() => onShowMap(labelCol, String(r[labelCol] ?? ""))}>
                        Lihat di peta <ArrowRight size={14} />
                      </button>
                    </td>
                  )}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      {rows.length > initialRows && (
        <button type="button" className="rt-more" onClick={() => setAll((v) => !v)}>
          {all ? "Ringkas tabel" : `Tampilkan semua ${rows.length.toLocaleString("id-ID")} baris`}
        </button>
      )}
    </div>
  );
}
