"use client";
import { useMemo } from "react";

type Props = { columns: string[]; rows: Record<string, unknown>[]; bytes?: number; sql?: string };

function fmtBytes(b?: number) {
  if (!b) return "0 B";
  const u = ["B", "KB", "MB", "GB", "TB"];
  let i = 0; let n = b;
  while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
  return `${n.toFixed(n < 10 ? 1 : 0)} ${u[i]}`;
}

function fmtCell(v: unknown): { text: string; numeric: boolean } {
  if (v === null || v === undefined) return { text: "—", numeric: false };
  if (typeof v === "number") {
    const numeric = true;
    if (Number.isInteger(v)) return { text: v.toLocaleString("id-ID"), numeric };
    return { text: v.toLocaleString("id-ID", { maximumFractionDigits: 2 }), numeric };
  }
  if (typeof v === "boolean") return { text: v ? "true" : "false", numeric: false };
  return { text: String(v), numeric: false };
}

export default function DataTable({ columns, rows, bytes }: Props) {
  const showCount = Math.min(rows.length, 200);
  const numericCols = useMemo(() => {
    const set = new Set<string>();
    for (const c of columns) {
      const sample = rows.slice(0, 20).map((r) => r[c]);
      if (sample.every((v) => v === null || typeof v === "number")) set.add(c);
    }
    return set;
  }, [columns, rows]);

  return (
    <div className="data-table-wrap tnum">
      <div className="data-table-meta">
        <span>
          {rows.length.toLocaleString("id-ID")} rows
          {rows.length > showCount ? ` · showing first ${showCount}` : ""}
        </span>
        <span>{rows.length > showCount ? "scroll for more" : ""}</span>
      </div>
      <div className="data-table-scroll">
        <table className="data-table">
          <thead>
            <tr>
              {columns.map((c) => (
                <th key={c} className={numericCols.has(c) ? "num" : undefined}>
                  {c}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.slice(0, showCount).map((r, i) => (
              <tr key={i}>
                {columns.map((c) => {
                  const { text, numeric } = fmtCell(r[c]);
                  const isNum = numeric || numericCols.has(c);
                  return (
                    <td key={c} className={isNum ? "num" : undefined}>
                      {text}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
