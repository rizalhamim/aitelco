"use client";
import { useEffect, useState } from "react";
import { CalendarClock, Check, X } from "lucide-react";
import { authFetch, getUser } from "@/lib/auth";

export type Schedule = {
  id: number; name: string; region: string; frequency: "mingguan" | "bulanan"; weekday: number; monthday: number;
  hour: number; recipients: string[]; active: boolean; description: string; last_sent_on: string | null;
};

const DAYS = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"];
const title = (s: string) => s.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()).replace(/\bDiy\b/, "DIY");

type Props = { regions: string[]; edit?: Schedule | null; onClose: () => void; onSaved: () => void };

export default function ScheduleDialog({ regions, edit, onClose, onSaved }: Props) {
  const [frequency, setFrequency] = useState<"mingguan" | "bulanan">(edit?.frequency ?? "mingguan");
  const [weekday, setWeekday] = useState(edit?.weekday ?? 0);
  const [monthday, setMonthday] = useState(edit?.monthday ?? 1);
  const [hour, setHour] = useState(edit?.hour ?? 8);
  const [region, setRegion] = useState(edit?.region ?? "");
  const [recipients, setRecipients] = useState(edit?.recipients.join(", ") ?? getUser()?.email ?? "");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);

  async function save() {
    setSaving(true);
    setError("");
    try {
      const body = { frequency, weekday, monthday, hour, recipients, ...(edit ? {} : { region }) };
      const r = await authFetch(edit ? `/api/report-schedules/${edit.id}` : "/api/report-schedules", {
        method: edit ? "PATCH" : "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
      });
      const d = await r.json();
      if (!r.ok) throw new Error(typeof d.detail === "string" ? d.detail : `HTTP ${r.status}`);
      onSaved();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Gagal menyimpan");
      setSaving(false);
    }
  }

  return (
    <div className="ui-modal-scrim" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="ui-modal" role="dialog" aria-modal="true" aria-labelledby="rp-sched-title">
        <div className="ui-modal-head">
          <span className="ui-modal-ico"><CalendarClock size={20} /></span>
          <div>
            <h2 id="rp-sched-title">{edit ? "Ubah jadwal laporan" : "Jadwalkan laporan otomatis"}</h2>
            <p>Agent menyusun laporan performa dan mengirimkannya lewat email.</p>
          </div>
          <button className="ui-iconbtn ghost" onClick={onClose} aria-label="Tutup"><X size={18} /></button>
        </div>

        <div className="ui-field">
          <label htmlFor="rp-region">Wilayah</label>
          <div className="ui-input">
            <select id="rp-region" value={region} onChange={(e) => setRegion(e.target.value)} disabled={!!edit}>
              <option value="">Semua region Jawa</option>
              {regions.map((r) => <option key={r} value={r}>{title(r)}</option>)}
            </select>
          </div>
        </div>

        <div className="ui-field">
          <span className="ui-field-label">Frekuensi</span>
          <div className="rp-sched-row">
            <div className="ui-seg" role="group" aria-label="Frekuensi">
              <button aria-pressed={frequency === "mingguan"} onClick={() => setFrequency("mingguan")}>Mingguan</button>
              <button aria-pressed={frequency === "bulanan"} onClick={() => setFrequency("bulanan")}>Bulanan</button>
            </div>
            <div className="ui-input">
              {frequency === "mingguan" ? (
                <select value={weekday} onChange={(e) => setWeekday(Number(e.target.value))} aria-label="Hari">
                  {DAYS.map((d, i) => <option key={d} value={i}>Tiap {d}</option>)}
                </select>
              ) : (
                <select value={monthday} onChange={(e) => setMonthday(Number(e.target.value))} aria-label="Tanggal">
                  {Array.from({ length: 28 }, (_, i) => <option key={i} value={i + 1}>Tiap tanggal {i + 1}</option>)}
                </select>
              )}
            </div>
            <div className="ui-input rp-hour">
              <select value={hour} onChange={(e) => setHour(Number(e.target.value))} aria-label="Jam">
                {Array.from({ length: 24 }, (_, h) => <option key={h} value={h}>{String(h).padStart(2, "0")}.00 WIB</option>)}
              </select>
            </div>
          </div>
        </div>

        <div className="ui-field">
          <label htmlFor="rp-to">Penerima</label>
          <div className="ui-input">
            <input id="rp-to" value={recipients} onChange={(e) => setRecipients(e.target.value)} placeholder="nama@ioh.co.id, …" />
          </div>
          <span className="rp-hint">Pisahkan dengan koma. Kosongkan untuk mengirim ke email Anda.</span>
        </div>

        {error && <p className="wl-error" role="alert">{error}</p>}

        <div className="ui-modal-foot">
          <button className="ui-btn lg" onClick={onClose}>Batal</button>
          <button className="ui-btn lg primary" onClick={save} disabled={saving}>
            <Check size={20} /> {saving ? "Menyimpan…" : "Simpan jadwal"}
          </button>
        </div>
      </div>
    </div>
  );
}
