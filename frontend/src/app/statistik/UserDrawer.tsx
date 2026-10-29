"use client";
import { useEffect, useRef, useState } from "react";
import { ArrowRight, BellRing, Download, Lock, LogOut, Radio, Monitor, X } from "lucide-react";
import { authFetch } from "@/lib/auth";
import { Avatar, MONTHS, stamp } from "./util";

type Detail = {
  id: number; username: string; full_name: string; email: string; department: string | null; role: string;
  is_active: boolean; status: "aktif" | "tidak_aktif"; app_version: string | null; is_latest: boolean; latest_version: string | null;
  stats: { logins_30d: number; login_total: number; queries: number; exports: number };
  timeline: { at: string; kind: "login" | "logout" | "failed" | "export"; title: string; meta: string[] }[];
  devices: { platform: string; device_model: string | null; app_version: string | null; is_latest: boolean; first_seen: string; last_seen: string }[];
  topics: { topic: string; count: number; pct: number }[];
};

const TABS = [
  { key: "login", label: "Riwayat login" },
  { key: "devices", label: "Perangkat & versi" },
  { key: "topics", label: "Topik" },
] as const;

const ICON = { login: ArrowRight, logout: LogOut, failed: Lock, export: Download };
const nf = (v: number) => v.toLocaleString("id-ID");
const mon = (iso: string) => MONTHS[new Date(iso).getMonth()];

/** "sejak 2 Sep" for the device in use, "Jul–Sep" for earlier ones. */
function span(d: Detail["devices"][number], current: boolean): string {
  const a = new Date(d.first_seen);
  if (current) return `sejak ${a.getDate()} ${mon(d.first_seen)}`;
  const m1 = mon(d.first_seen), m2 = mon(d.last_seen);
  return m1 === m2 ? `${a.getDate()}–${new Date(d.last_seen).getDate()} ${m1}` : `${m1}–${m2}`;
}

export default function UserDrawer({ id, onClose, onRemind, onChanged }: {
  id: number; onClose: () => void; onRemind: (ids: number[]) => Promise<void>; onChanged: () => void;
}) {
  const [data, setData] = useState<Detail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [now, setNow] = useState(0);
  const [tab, setTab] = useState<(typeof TABS)[number]["key"]>("login");
  const [busy, setBusy] = useState<"remind" | "access" | null>(null);
  const [confirm, setConfirm] = useState(false);
  const body = useRef<HTMLDivElement>(null);
  const panel = useRef<HTMLElement>(null);

  useEffect(() => {
    let live = true;
    authFetch(`/api/admin/app-stats/users/${id}`)
      .then(async (r) => {
        if (!r.ok) throw new Error(`Gagal memuat pengguna (${r.status}).`);
        const j = await r.json();
        if (live) { setData(j); setNow(Date.now()); setError(null); }
      })
      .catch((e: Error) => { if (live) setError(e.message); });
    return () => { live = false; };
  }, [id]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    document.addEventListener("keydown", onKey);
    panel.current?.focus();
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  function jump(key: (typeof TABS)[number]["key"]) {
    setTab(key);
    const el = body.current?.querySelector<HTMLElement>(`[data-sec="${key}"]`);
    if (el && body.current) body.current.scrollTo({ top: el.offsetTop - 8, behavior: "smooth" });
  }

  async function toggleAccess() {
    if (!data) return;
    setBusy("access");
    const r = await authFetch(`/api/admin/users/${data.id}`, { method: "PUT", body: JSON.stringify({ is_active: !data.is_active }) });
    setBusy(null);
    setConfirm(false);
    if (r.ok) { setData({ ...data, is_active: !data.is_active }); onChanged(); }
  }

  const name = data?.full_name || data?.username || "";
  return (
    <div className="st-scrim" onClick={onClose}>
      <aside className="st-drawer" ref={panel} tabIndex={-1} role="dialog" aria-modal="true" aria-label={name ? `Detail ${name}` : "Detail pengguna"}
        onClick={(e) => e.stopPropagation()}>
        {error && <p className="st-error">{error}</p>}
        {!data && !error && (
          <div className="st-dr-skel">
            <div className="ui-skel" style={{ height: 64 }} />
            <div className="ui-skel" style={{ height: 68 }} />
            <div className="ui-skel" style={{ height: 280 }} />
          </div>
        )}
        {data && (
          <>
            <header className="st-dr-head">
              <Avatar name={name} size="lg" />
              <div>
                <h2>{name}</h2>
                <p>{[data.department, data.email].filter(Boolean).join(" · ")}</p>
                <div className="st-dr-chips">
                  <span className={`st-status ${data.is_active ? data.status : "off"}`}>
                    {!data.is_active ? "Akses nonaktif" : data.status === "aktif" ? "Aktif" : "Tidak aktif"}
                  </span>
                  {data.app_version && (
                    <span className={`st-ver ${data.is_latest ? "ok" : "old"}`}>
                      v{data.app_version}{data.is_latest ? " · terbaru" : " · perlu update"}
                    </span>
                  )}
                </div>
              </div>
              <button className="st-dr-close" onClick={onClose} aria-label="Tutup"><X size={22} /></button>
            </header>

            <div className="st-dr-stats">
              <div><b>{nf(data.stats.logins_30d)}</b><span>Login 30 hari</span></div>
              <div><b>{nf(data.stats.login_total)}</b><span>Total login</span></div>
              <div><b>{nf(data.stats.queries)}</b><span>Query</span></div>
              <div><b>{nf(data.stats.exports)}</b><span>Export</span></div>
            </div>

            <div className="ui-tabs st-dr-tabs" role="tablist">
              {TABS.map((t) => (
                <button key={t.key} role="tab" aria-selected={tab === t.key} onClick={() => jump(t.key)}>{t.label}</button>
              ))}
            </div>

            <div className="st-dr-body" ref={body}>
              <section data-sec="login">
                {data.timeline.length === 0
                  ? <p className="st-empty">Belum ada riwayat login.</p>
                  : (
                    <ol className="st-tl">
                      {data.timeline.slice(0, 8).map((t, i) => {
                        const Ico = ICON[t.kind] ?? ArrowRight;
                        return (
                          <li key={i} className={t.kind}>
                            <span className="st-tl-ico"><Ico size={14} /></span>
                            <div>
                              <b>{t.title}</b>
                              <span>{[stamp(t.at, now, true), ...t.meta].join(" · ")}</span>
                            </div>
                          </li>
                        );
                      })}
                    </ol>
                  )}
              </section>

              <section data-sec="devices">
                <h3>Riwayat perangkat &amp; versi</h3>
                {data.devices.length === 0
                  ? <p className="st-empty">Belum pernah memakai aplikasi Android.</p>
                  : (
                    <ul className="st-devs">
                      {data.devices.map((d, i) => (
                        <li key={i}>
                          {d.platform === "android" ? <Radio size={16} /> : <Monitor size={16} />}
                          <span className="st-dev-name">{d.device_model || (d.platform === "android" ? "Android" : "Web")}</span>
                          {d.app_version && <span className={`st-ver ${i === 0 ? (d.is_latest ? "ok" : "old") : "plain"}`}>v{d.app_version}</span>}
                          <span className="st-dev-when">{span(d, i === 0)}</span>
                        </li>
                      ))}
                    </ul>
                  )}
              </section>

              <section data-sec="topics">
                <h3>Topik paling sering ditanya</h3>
                {data.topics.length === 0
                  ? <p className="st-empty">Belum ada pertanyaan ke agent.</p>
                  : (
                    <ul className="st-topics">
                      {data.topics.slice(0, 5).map((t) => (
                        <li key={t.topic} title={`${nf(t.count)} pertanyaan`}>
                          <span>{t.topic}</span>
                          <i><s style={{ width: `${t.pct}%` }} /></i>
                          <b>{t.pct}%</b>
                        </li>
                      ))}
                    </ul>
                  )}
              </section>
            </div>

            <footer className="st-dr-foot">
              <button className="ui-btn lg primary" disabled={busy != null || data.is_latest || !data.app_version}
                title={data.is_latest ? "Sudah di versi terbaru" : !data.app_version ? "Belum memakai aplikasi Android" : undefined}
                onClick={async () => { setBusy("remind"); await onRemind([data.id]); setBusy(null); }}>
                <BellRing size={20} /> Kirim pengingat update
              </button>
              {confirm ? (
                <button className="ui-btn lg danger st-confirm" disabled={busy != null} onClick={toggleAccess}>
                  {data.is_active ? "Ya, nonaktifkan" : "Ya, aktifkan"}
                </button>
              ) : (
                <button className="ui-btn lg" disabled={busy != null} onClick={() => setConfirm(true)}>
                  {data.is_active ? "Nonaktifkan akses" : "Aktifkan akses"}
                </button>
              )}
            </footer>
          </>
        )}
      </aside>
    </div>
  );
}
