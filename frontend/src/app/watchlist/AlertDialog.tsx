"use client";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  Activity, BellRing, CalendarDays, Check, MapPin, Plus, Radio, SlidersHorizontal, TrendingUp, Users, Wifi, X,
} from "lucide-react";
import Sparkline from "../components/ui/Sparkline";
import { authFetch } from "@/lib/auth";

export type Metric = { key: string; label: string; unit: string; icon: string };
export type Rule = {
  id: number; name: string; metric: string; metric_label: string; icon: string; unit: string;
  scope_level: string; scope_value: string; scope_label: string;
  condition: string; threshold: number; threshold_label: string; days: number;
  notify_inapp: boolean; notify_email: boolean; active: boolean; status: string;
  value: number | null; value_label: string; level: number | null; breach_streak: number;
  trend: (number | null)[]; source_question: string | null;
};
type Scope = { level: string; value: string };
type Preview = { points: { month_id: number; value: number | null; breach: boolean }[]; fires: number; error?: string };

export const METRIC_ICONS: Record<string, typeof Activity> = {
  activity: Activity, users: Users, wifi: Wifi, radio: Radio, "trending-up": TrendingUp,
};
const LEVELS = [
  { key: "region", label: "Region" }, { key: "kabkota", label: "Kab/Kota" },
  { key: "branch", label: "Branch" }, { key: "circle", label: "Circle" },
];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

export function scopeName(s: Scope): string {
  const v = s.value.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase());
  if (s.level === "circle") return s.value.toUpperCase() === "JAVA" ? "Jawa" : v;
  if (s.level === "branch") return `Branch ${v}`;
  return v.replace(/^Kab\.?\s/, "Kab. ").replace(/\bDiy\b/, "DIY");
}

/** Guesses metric and region from the question the user asked the agent. */
export function guessFromQuestion(q: string): { metric?: string; scope?: Scope; condition?: string } {
  const s = q.toLowerCase();
  const metric = /availab|ketersediaan|site/.test(s) ? "availability"
    : /payload|trafik|data usage/.test(s) ? "payload"
    : /gross ?add|ga\b|akuisisi/.test(s) ? (/fwa/.test(s) ? "fwa_rgu" : "gross_add")
    : /churn/.test(s) ? "net_churn"
    : /fwa/.test(s) ? "fwa_revenue"
    : /pelanggan|rgu|subscriber/.test(s) ? "subs"
    : /revenue|pendapatan/.test(s) ? "revenue" : undefined;
  const region = /jawa barat|jabar/.test(s) ? "JAWA BARAT"
    : /jawa tengah|jateng|diy|yogya/.test(s) ? "JAWA TENGAH & DIY"
    : /jawa timur|jatim/.test(s) ? "JAWA TIMUR" : undefined;
  const kab = s.match(/\b(kab(?:upaten|\.)?|kota)\s+([a-z]+(?:\s[a-z]+)?)/);
  const condition = /naik|tumbuh/.test(s) && !/turun/.test(s) ? "naik" : undefined;
  const scope = kab ? { level: "kabkota", value: `${kab[1].startsWith("kota") ? "KOTA" : "KAB."} ${kab[2].replace(/\s(turun|naik|bulan|minggu|vs|dan|di)$/, "").toUpperCase()}` }
    : region ? { level: "region", value: region } : undefined;
  return { metric, scope, condition };
}

type Props = {
  metrics: Metric[];
  edit?: Rule | null;
  prefill?: { metric?: string; scope?: Scope; condition?: string; question?: string };
  onClose: () => void;
  onSaved: () => void;
};

export default function AlertDialog({ metrics, edit, prefill, onClose, onSaved }: Props) {
  const [metric, setMetric] = useState(edit?.metric ?? prefill?.metric ?? "payload");
  const [scopes, setScopes] = useState<Scope[]>(
    edit ? [{ level: edit.scope_level, value: edit.scope_value }] : prefill?.scope ? [prefill.scope] : [{ level: "circle", value: "JAVA" }],
  );
  const isPct = metrics.find((m) => m.key === metric)?.unit === "%";
  const conditions = isPct
    ? [{ key: "di_bawah", label: "Di bawah" }, { key: "turun", label: "Turun" }, { key: "naik", label: "Naik" }]
    : [{ key: "turun", label: "Turun" }, { key: "naik", label: "Naik" }, { key: "berubah", label: "Berubah" }];
  const [condition, setCondition] = useState(edit?.condition ?? prefill?.condition ?? "turun");
  const [threshold, setThreshold] = useState(String(edit?.threshold ?? 5).replace(".", ","));
  const [days, setDays] = useState(edit?.days ?? 3);
  const [inapp, setInapp] = useState(edit?.notify_inapp ?? true);
  const [email, setEmail] = useState(edit?.notify_email ?? true);
  const [picker, setPicker] = useState(false);
  const [level, setLevel] = useState("region");
  const [options, setOptions] = useState<Record<string, string[]>>({});
  const [search, setSearch] = useState("");
  const [preview, setPreview] = useState<Preview | null>(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const pickerRef = useRef<HTMLDivElement>(null);
  const t = parseFloat(threshold.replace(",", "."));

  // Keep the condition valid when switching between level and change metrics.
  const [prevPct, setPrevPct] = useState(isPct);
  if (prevPct !== isPct) {
    setPrevPct(isPct);
    if (!conditions.some((c) => c.key === condition)) {
      setCondition(conditions[0].key);
      setThreshold(isPct ? "99" : "5");
    }
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  useEffect(() => {
    if (!picker || level === "circle" || options[level]) return;
    authFetch(`/api/reports/scope-options?level=${level}`).then((r) => r.json())
      .then((d) => setOptions((o) => ({ ...o, [level]: d.values ?? [] }))).catch(() => {});
  }, [picker, level, options]);

  useEffect(() => {
    if (!picker) return;
    const close = (e: MouseEvent) => { if (!pickerRef.current?.contains(e.target as Node)) setPicker(false); };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [picker]);

  const first = scopes[0];
  useEffect(() => {
    if (!first || !Number.isFinite(t)) return;
    let alive = true;
    const qs = new URLSearchParams({ metric, scope_level: first.level, scope_value: first.value, condition, threshold: String(t) });
    const timer = setTimeout(() => {
      authFetch(`/api/watchlist/preview?${qs}`).then((r) => r.json())
        .then((d) => { if (alive) setPreview(d); }).catch(() => {});
    }, 300);
    return () => { alive = false; clearTimeout(timer); };
  }, [metric, first, condition, t]);

  const shown = useMemo(() => {
    const all = options[level] ?? [];
    const q = search.trim().toLowerCase();
    return (q ? all.filter((v) => v.toLowerCase().includes(q)) : all).slice(0, 60);
  }, [options, level, search]);

  const absolute = condition === "di_bawah" || condition === "di_atas";
  const unit = absolute ? (isPct ? "%" : "") : metric === "availability" ? " pp" : "%";
  const op = { turun: "≥", naik: "≥", berubah: "±", di_bawah: "<", di_atas: ">" }[condition] ?? "≥";
  const ref = !Number.isFinite(t) ? null : absolute ? t : condition === "turun" ? -Math.abs(t) : Math.abs(t);
  const refLabel = ref == null ? "" : `${ref > 0 && !absolute ? "+" : ""}${String(ref).replace(".", ",")}${unit.trim()}`;

  function addScope(s: Scope) {
    setScopes((cur) => (edit ? [s] : cur.some((c) => c.level === s.level && c.value === s.value) ? cur
      : cur.length === 1 && cur[0].level === "circle" ? [s] : [...cur, s]));
    setPicker(false);
    setSearch("");
  }

  async function save() {
    if (!Number.isFinite(t)) { setError("Isi ambang dengan angka."); return; }
    if (!scopes.length) { setError("Pilih minimal satu wilayah."); return; }
    setSaving(true);
    setError("");
    try {
      if (edit) {
        const r = await authFetch(`/api/watchlist/rules/${edit.id}`, {
          method: "PATCH", headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ condition, threshold: t, days, notify_inapp: inapp, notify_email: email }),
        });
        if (!r.ok) throw new Error((await r.json()).detail || `HTTP ${r.status}`);
      } else {
        for (const s of scopes) {
          const r = await authFetch("/api/watchlist/rules", {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              metric, scope_level: s.level, scope_value: s.value, condition, threshold: t, days,
              notify_inapp: inapp, notify_email: email, source_question: prefill?.question || null,
            }),
          });
          if (!r.ok) throw new Error((await r.json()).detail || `HTTP ${r.status}`);
        }
      }
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan");
      setSaving(false);
    }
  }

  const MIcon = METRIC_ICONS[metrics.find((m) => m.key === metric)?.icon ?? "activity"] ?? Activity;
  const pts = preview?.points ?? [];

  return (
    <div className="ui-modal-scrim" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="ui-modal wl-dialog" role="dialog" aria-modal="true" aria-labelledby="wl-dlg-title">
        <div className="ui-modal-head">
          <span className="ui-modal-ico"><BellRing size={20} /></span>
          <div>
            <h2 id="wl-dlg-title">{edit ? "Ubah alert" : "Buat alert baru"}</h2>
            <p>Agent akan memantau dan memberi tahu saat ambang terlampaui.</p>
          </div>
          <button className="ui-iconbtn ghost" onClick={onClose} aria-label="Tutup"><X size={18} /></button>
        </div>

        <div className="ui-field">
          <label htmlFor="wl-metric">Metrik</label>
          <div className="ui-input">
            <MIcon size={22} strokeWidth={1.6} />
            <select id="wl-metric" value={metric} onChange={(e) => setMetric(e.target.value)} disabled={!!edit}>
              {metrics.map((m) => <option key={m.key} value={m.key}>{m.label}{m.unit === "GB" ? " (PB)" : ""}</option>)}
            </select>
          </div>
        </div>

        <div className="ui-field">
          <span className="ui-field-label">Wilayah</span>
          <div className="wl-chips" ref={pickerRef}>
            {scopes.map((s) => (
              <span key={`${s.level}:${s.value}`} className="wl-scope">
                <MapPin size={16} /> {scopeName(s)}
                {!edit && scopes.length > 1 && (
                  <button aria-label={`Hapus ${scopeName(s)}`} onClick={() => setScopes((c) => c.filter((x) => x !== s))}><X size={14} /></button>
                )}
              </span>
            ))}
            {!edit && (
              <button className="wl-add" onClick={() => setPicker((v) => !v)} aria-expanded={picker}>
                <Plus size={20} strokeWidth={1.6} /> Tambah wilayah
              </button>
            )}
            {picker && (
              <div className="ui-popover wl-picker">
                <div className="ui-seg wl-picker-levels">
                  {LEVELS.map((l) => <button key={l.key} aria-pressed={level === l.key} onClick={() => setLevel(l.key)}>{l.label}</button>)}
                </div>
                {level === "circle" ? (
                  <button onClick={() => addScope({ level: "circle", value: "JAVA" })}>Circle Jawa</button>
                ) : (
                  <>
                    <input className="wl-picker-search" autoFocus placeholder="Cari wilayah…" value={search} onChange={(e) => setSearch(e.target.value)} />
                    <div className="wl-picker-list">
                      {!options[level] && <span className="wl-picker-empty">Memuat…</span>}
                      {options[level] && shown.length === 0 && <span className="wl-picker-empty">Tidak ada yang cocok</span>}
                      {shown.map((v) => <button key={v} onClick={() => addScope({ level, value: v })}>{scopeName({ level, value: v })}</button>)}
                    </div>
                  </>
                )}
              </div>
            )}
          </div>
        </div>

        <div className="ui-field">
          <span className="ui-field-label">Kondisi</span>
          <div className="wl-cond">
            <div className="ui-seg" role="group" aria-label="Kondisi">
              {conditions.map((c) => <button key={c.key} aria-pressed={condition === c.key} onClick={() => setCondition(c.key)}>{c.label}</button>)}
            </div>
            <label className="ui-input wl-thr" title="Ambang">
              <SlidersHorizontal size={22} strokeWidth={1.6} />
              <span className="wl-op">{op}</span>
              <input inputMode="decimal" value={threshold} onChange={(e) => setThreshold(e.target.value)} aria-label="Ambang" />
              <span className="wl-unit">{unit.trim()}</span>
            </label>
            <label className="ui-input wl-days">
              <CalendarDays size={22} strokeWidth={1.6} />
              <select value={days} onChange={(e) => setDays(Number(e.target.value))} aria-label="Lama kondisi">
                {[1, 2, 3, 5, 7, 14].map((d) => <option key={d} value={d}>selama {d} hari</option>)}
              </select>
            </label>
          </div>
        </div>

        <div className="ui-field">
          <span className="ui-field-label">Pratinjau</span>
          <div className="wl-preview">
            <span className="wl-preview-cap">
              {preview?.error ? "Pratinjau belum tersedia untuk wilayah ini"
                : !preview ? "Menghitung pratinjau…"
                : `Pratinjau ${pts.length} bulan · alert akan terpicu ${preview.fires} kali`}
              {scopes.length > 1 && ` · ${scopeName(first)}`}
            </span>
            <div className="wl-preview-chart">
              <Sparkline
                values={pts.map((p) => p.value)}
                labels={pts.map((p) => `${MONTHS[(p.month_id % 100) - 1]} ${String(Math.floor(p.month_id / 100)).slice(2)}`)}
                height={90} reference={ref} referenceLabel={refLabel}
                format={(v) => `${v > 0 && !absolute ? "+" : ""}${v.toLocaleString("id-ID", { maximumFractionDigits: 2 })}${unit.trim()}`}
              />
            </div>
          </div>
        </div>

        <div className="ui-field">
          <span className="ui-field-label">Notifikasi</span>
          <div className="wl-channels">
            <label className="ui-check"><input type="checkbox" checked={inapp} onChange={(e) => setInapp(e.target.checked)} /> In-app</label>
            <label className="ui-check"><input type="checkbox" checked={email} onChange={(e) => setEmail(e.target.checked)} /> Email</label>
            <label className="ui-check" title="Segera hadir"><input type="checkbox" disabled /> WhatsApp</label>
          </div>
        </div>

        {error && <p className="wl-error" role="alert">{error}</p>}

        <div className="ui-modal-foot">
          <button className="ui-btn lg" onClick={onClose}>Batal</button>
          <button className="ui-btn lg primary" onClick={save} disabled={saving}>
            <Check size={20} strokeWidth={2} /> {saving ? "Menyimpan…" : edit ? "Simpan perubahan" : scopes.length > 1 ? `Simpan ${scopes.length} alert` : "Simpan alert"}
          </button>
        </div>
      </div>
    </div>
  );
}
