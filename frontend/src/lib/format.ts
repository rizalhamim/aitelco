import { shortNum } from "@/app/components/charts/SmartChart";

const id1 = new Intl.NumberFormat("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const id2 = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 2 });

export const MONTHS_FULL = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];

/** Rp 1,84 T · Rp 412,6 M · Rp 18,4 jt */
export function idr(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return "–";
  const a = Math.abs(v);
  if (a >= 1e12) return `Rp ${id2.format(+(v / 1e12).toFixed(2))} T`;
  if (a >= 1e9) return `Rp ${id1.format(v / 1e9)} M`;
  if (a >= 1e6) return `Rp ${id1.format(v / 1e6)} jt`;
  return `Rp ${id2.format(v)}`;
}

/** 41,3 jt · 286 rb */
export function count(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return "–";
  const a = Math.abs(v);
  if (a >= 1e6) return `${id1.format(v / 1e6)} jt`;
  if (a >= 1e3) return `${Math.round(v / 1e3).toLocaleString("id-ID")} rb`;
  return Math.round(v).toLocaleString("id-ID");
}

/** Gigabytes → 84,2 PB / 312,0 TB / 820 GB */
export function gb(v: number | null | undefined): string {
  if (v == null || !Number.isFinite(v)) return "–";
  const a = Math.abs(v);
  if (a >= 1e6) return `${id1.format(v / 1e6)} PB`;
  if (a >= 1e3) return `${id1.format(v / 1e3)} TB`;
  return `${id1.format(v)} GB`;
}

export function pct(v: number | null | undefined, digits = 1): string {
  if (v == null || !Number.isFinite(v)) return "–";
  return `${v.toLocaleString("id-ID", { minimumFractionDigits: digits, maximumFractionDigits: digits })}%`;
}

export function byFormat(fmt: string, v: number | null | undefined): string {
  if (fmt === "currency") return idr(v);
  if (fmt === "gb") return gb(v);
  if (fmt === "percent") return pct(v, 2);
  return v == null ? "–" : count(v);
}

/** "12 mnt", "3 jam", "2 hari" since an ISO time. */
export function ago(iso: string | null | undefined): string {
  if (!iso) return "";
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return "baru saja";
  if (s < 3600) return `${Math.floor(s / 60)} mnt`;
  if (s < 86400) return `${Math.floor(s / 3600)} jam`;
  return `${Math.floor(s / 86400)} hari`;
}

export { shortNum };
