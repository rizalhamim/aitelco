export const DAYS = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"];
export const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

/** "1.42.3" → sortable number. */
export function versionKey(v: string | null | undefined): number {
  const [a = 0, b = 0, c = 0] = (v || "").split(".").map((p) => parseInt(p, 10) || 0);
  return a * 1e6 + b * 1e3 + c;
}

/** "2026-10-06" → "6 Okt". */
export function dateLabel(iso: string): string {
  const d = new Date(iso.length <= 10 ? `${iso}T00:00:00` : iso);
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

const dayStart = (t: number) => { const d = new Date(t); d.setHours(0, 0, 0, 0); return d.getTime(); };
const hm = (d: Date) => `${String(d.getHours()).padStart(2, "0")}.${String(d.getMinutes()).padStart(2, "0")}`;

/** "2 mnt lalu", "3 jam lalu", "Kemarin", "6 hari lalu" — calendar days, like the mockup. */
export function relAgo(iso: string | null | undefined, now: number): string {
  if (!iso || !now) return "";
  const t = new Date(iso).getTime();
  const s = (now - t) / 1000;
  if (s < 60) return "baru saja";
  if (s < 3600) return `${Math.floor(s / 60)} mnt lalu`;
  const days = Math.round((dayStart(now) - dayStart(t)) / 864e5);
  if (days <= 0) return `${Math.floor(s / 3600)} jam lalu`;
  if (days === 1) return "Kemarin";
  return `${days} hari lalu`;
}

/** "30 Okt 09.14"; with `relative`, today/yesterday read "Hari ini 08.02" / "Kemarin 07.58". */
export function stamp(iso: string, now: number, relative: boolean): string {
  const d = new Date(iso);
  if (relative && now) {
    const days = Math.round((dayStart(now) - dayStart(d.getTime())) / 864e5);
    if (days === 0) return `Hari ini ${hm(d)}`;
    if (days === 1) return `Kemarin ${hm(d)}`;
  }
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${hm(d)}`;
}

const TONES = ["rose", "amber", "teal", "blue", "violet", "green"];

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] ?? "") + (parts.length > 1 ? parts[parts.length - 1][0] : "")).toUpperCase() || "?";
}

export function Avatar({ name, size }: { name: string; size?: "lg" }) {
  let h = 0;
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) >>> 0;
  return <span className={`st-av t-${TONES[h % TONES.length]} ${size ?? ""}`} aria-hidden="true">{initials(name)}</span>;
}
