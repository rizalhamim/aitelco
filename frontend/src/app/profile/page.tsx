"use client";
// Redesign v2 page 08: Profil dan pengaturan. Identity and usage, Android app (QR and APK),
// admin shortcuts, security and devices, account form, display settings shared with Android,
// and notification channels per kind.
import { useEffect, useRef, useState, type FormEvent, type ReactNode } from "react";
import Link from "next/link";
import AppShell, { TopBar } from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { PUBLIC_ORIGIN, Qr } from "../components/v2/Qr";
import { authFetch, logout, updateStoredUser } from "@/lib/auth";
import { setPrefs, type AccentPref, type DensityPref, type ThemePref } from "@/lib/prefs";
import "./profil.css";

type Channel = { email: boolean; push: boolean };
type Prefs = {
  theme: ThemePref; accent: AccentPref; density: DensityPref; lang: string; targetLine: boolean; animation: boolean;
  default_region: string; notify: Record<string, Channel>; quiet_hours: boolean;
};
type Device = { id: number | null; kind: "web" | "android"; name: string; sub: string; current: boolean; can_sign_out: boolean };
type Profile = {
  user: { username: string; full_name: string; email: string; department: string | null; role: string; default_region: string; default_region_label: string; updated_at: string | null };
  stats: { last_login: string | null; login_count: number; questions_month: number; month_short: string };
  security: { password_changed_at: string | null; password_days: number | null };
  devices: Device[];
  apk: { installed_devices: number };
  prefs: Prefs;
  options: { regions: { key: string; label: string }[]; departments: string[] };
  admin?: { active_users_7d: number; version_name: string | null; downloads_current: number; accounts: number; inactive: number };
};
type Version = { version_name: string | null; version_code: number; size_bytes: number; available: boolean; min_android?: string };
type Notif = { id: number; title: string; message: string; is_read: boolean; created_at: string | null };

const ACCENTS: { key: AccentPref; label: string; c: string }[] = [
  { key: "teal", label: "Teal", c: "#0E8579" }, { key: "laut", label: "Laut", c: "#22B8C9" }, { key: "zamrud", label: "Zamrud", c: "#1F9D55" },
  { key: "amber", label: "Amber", c: "#D98E0B" }, { key: "grafit", label: "Grafit", c: "#3D4C49" },
];
const KINDS: { key: string; label: string; sub: string }[] = [
  { key: "alert_kritis", label: "Alert kritis", sub: "Dari Watchlist" },
  { key: "alert_peringatan", label: "Alert peringatan", sub: "Dari Watchlist" },
  { key: "laporan", label: "Laporan terjadwal", sub: "Setelah laporan terkirim" },
  { key: "versi", label: "Versi aplikasi baru", sub: "APK Android" },
];
const SECTIONS = [
  { key: "akun", label: "Akun", icon: "user" }, { key: "tampilan", label: "Tampilan", icon: "palette" },
  { key: "notifikasi", label: "Notifikasi", icon: "bell" }, { key: "keamanan", label: "Keamanan", icon: "shield" },
] as const;
// The QR and the emailed link always point at the public site (a phone cannot open a dev host).

const hm = (iso: string) => new Date(iso).toLocaleTimeString("id-ID", { hour: "2-digit", minute: "2-digit" });
const dmy = (iso: string) => new Date(iso).toLocaleDateString("id-ID", { day: "numeric", month: "short", year: "numeric" });
function dayWord(iso: string): string {
  const d = new Date(iso), now = new Date();
  const days = Math.round((new Date(now.toDateString()).getTime() - new Date(d.toDateString()).getTime()) / 86400000);
  return days === 0 ? "hari ini" : days === 1 ? "kemarin" : d.toLocaleDateString("id-ID", { day: "numeric", month: "short" });
}


const Toggle = ({ on, label, onChange }: { on: boolean; label: string; onChange: (v: boolean) => void }) => (
  <button className={`tgl${on ? "" : " off"}`} role="switch" aria-checked={on} aria-label={label} onClick={() => onChange(!on)}><i /></button>
);

function Card({ id, title, sub, extra, children, className }: { id?: string; title: string; sub?: string; extra?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section id={id} className={`card ${className ?? ""}`} aria-label={title}>
      <div className="ch"><div><h3>{title}</h3>{sub && <p>{sub}</p>}</div>{extra}</div>
      {children}
    </section>
  );
}

export default function ProfilePage() {
  const [p, setP] = useState<Profile | null>(null);
  const [ver, setVer] = useState<Version | null>(null);
  const [error, setError] = useState("");
  const [form, setForm] = useState({ full_name: "", email: "", department: "", default_region: "JAVA" });
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const [section, setSection] = useState<string>("akun");
  const [pwOpen, setPwOpen] = useState(false);
  const [inbox, setInbox] = useState<Notif[]>([]);
  const [version, setVersion] = useState(0);
  const refs = useRef<Record<string, HTMLElement | null>>({});

  useEffect(() => {
    let alive = true;
    authFetch("/api/profile").then(async (r) => {
      const d = await r.json();
      if (!r.ok) throw new Error(d.detail || `HTTP ${r.status}`);
      if (!alive) return;
      setP(d);
      setForm({ full_name: d.user.full_name || "", email: d.user.email || "", department: d.user.department || "", default_region: d.user.default_region });
      const pr: Prefs = d.prefs;
      setPrefs({ theme: pr.theme, accent: pr.accent, density: pr.density, animation: pr.animation, targetLine: pr.targetLine });
    }).catch((e) => alive && setError(e instanceof Error ? e.message : "Gagal memuat profil"));
    authFetch("/api/auth/me/notifications?limit=20").then((r) => (r.ok ? r.json() : null))
      .then((d) => alive && d?.notifications && setInbox(d.notifications.filter((x: Notif) => !x.is_read))).catch(() => {});
    return () => { alive = false; };
  }, [version]);

  useEffect(() => {
    fetch("/api/app/version").then((r) => (r.ok ? r.json() : null)).then((d) => d && setVer(d)).catch(() => {});
  }, []);

  async function savePrefs(patch: Partial<Prefs>) {
    if (!p) return;
    const next = { ...p.prefs, ...patch, notify: { ...p.prefs.notify, ...(patch.notify ?? {}) } };
    setP({ ...p, prefs: next });
    const local: Record<string, unknown> = {};
    for (const k of ["theme", "accent", "density", "animation", "targetLine"] as const) if (k in patch) local[k] = patch[k];
    if (Object.keys(local).length) setPrefs(local);
    await authFetch("/api/profile/prefs", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ prefs: patch }) }).catch(() => {});
  }

  const dirty = !!p && (form.full_name !== (p.user.full_name || "") || form.email !== (p.user.email || "")
    || form.department !== (p.user.department || "") || form.default_region !== p.user.default_region);

  async function saveAccount() {
    if (!p || !dirty) return;
    setSaving(true); setMsg(null);
    try {
      const r = await authFetch("/api/auth/me/profile", {
        method: "PUT", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ full_name: form.full_name.trim(), email: form.email.trim(), department: form.department }),
      });
      const d = await r.json();
      if (!r.ok) throw new Error(d.detail || "Gagal menyimpan");
      if (form.default_region !== p.user.default_region) await savePrefs({ default_region: form.default_region });
      updateStoredUser(d);
      setMsg({ ok: true, text: "Tersimpan" });
      setVersion((v) => v + 1);
    } catch (e) {
      setMsg({ ok: false, text: e instanceof Error ? e.message : "Gagal menyimpan" });
    }
    setSaving(false);
  }

  async function signOut(d: Device) {
    if (d.id == null || !confirm(`Keluarkan ${d.name} (${d.sub})? Perangkat itu harus masuk lagi untuk memakai akun ini.`)) return;
    await authFetch(`/api/profile/devices/${d.id}/sign-out`, { method: "POST" }).catch(() => {});
    setVersion((v) => v + 1);
  }

  async function readAll() {
    setInbox([]);
    await authFetch("/api/auth/me/notifications/read-all", { method: "PUT" }).catch(() => {});
  }

  function go(key: string) {
    setSection(key);
    refs.current[key]?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  const u = p?.user;
  const name = u?.full_name || u?.username || "";
  const pr = p?.prefs;
  const region = p?.options.regions.find((r) => r.key === form.default_region)?.label ?? "Circle Java";
  const mb = ver?.size_bytes ? Math.round(ver.size_bytes / 1048576) : null;
  const shortVer = (ver?.version_name || "").split(".").slice(0, 2).join(".");
  const sec = p?.security;
  const devices = p?.devices ?? [];
  const qrOrigin = PUBLIC_ORIGIN;

  return (
    <AppShell>
      <TopBar title="Profil dan pengaturan" subtitle="Akun, tampilan, notifikasi, keamanan, dan aplikasi Android." ringAvatar />
      <div className="pf">
        {error && <p className="msg err" style={{ gridColumn: "1 / -1", margin: 0 }}>Profil belum bisa dimuat: {error}</p>}
        <div className="pcol">
          <div className="idc" aria-label="Identitas">
            <span className="glow" />
            <div className="who">
              <span className="bigav">{(name.trim()[0] || "U").toUpperCase()}<span className="cam" title="Foto profil belum bisa diganti"><Icon name="cam" /></span></span>
              <div><b>{name}</b><small>@{u?.username}{u?.department ? ` · ${u.department}` : ""}</small><small>{u?.email}</small></div>
            </div>
            <div className="tags">
              <span className="l">{u?.role === "admin" ? "Admin" : "Pengguna"}</span>
              <span>{u?.default_region_label ?? "Circle Java"}</span>
              <span>Akses semua region</span>
            </div>
            <div className="st3">
              <div><b>{p?.stats.last_login ? hm(p.stats.last_login) : "-"}</b><small>Login terakhir{p?.stats.last_login ? `, ${dayWord(p.stats.last_login)}` : ""}</small></div>
              <div><b>{p?.stats.login_count.toLocaleString("id-ID") ?? "-"}</b><small>Total login</small></div>
              <div><b>{p?.stats.questions_month.toLocaleString("id-ID") ?? "-"}</b><small>Pertanyaan ke agent, {p?.stats.month_short}</small></div>
            </div>
          </div>

          <Card title="Aplikasi Android" sub="Pindai QR dari HP atau unduh langsung" className="apkc">
            <div className="row2">
              <div className="qrbox"><Qr text={`${qrOrigin}/unduh`} /></div>
              <div className="ver">
                <small>Versi terbaru</small>
                <b>Agent Java {ver?.version_name ?? "-"}</b>
                <small>Build {ver?.version_code ?? "-"}{mb ? ` · ${mb} MB` : ""} · Android {(ver?.min_android || "8").split(".")[0]} ke atas</small>
                {p && (p.apk.installed_devices > 0
                  ? <span className="okchip"><Icon name="check" />Terpasang di {p.apk.installed_devices} perangkat</span>
                  : <span className="okchip no">Belum terpasang di HP Anda</span>)}
              </div>
            </div>
            <div className="btnrow">
              <a className="btn-p" href="/api/app/download?src=web" download><Icon name="dl" />Unduh APK</a>
              <a className="linkbtn" href={`mailto:${encodeURIComponent(u?.email ?? "")}?subject=${encodeURIComponent("Unduh Agent Java untuk Android")}&body=${encodeURIComponent(`${qrOrigin}/unduh`)}`}><Icon name="mail" />Kirim link</a>
            </div>
          </Card>

          {p?.admin && (
            <Card title="Admin" sub="Hanya terlihat oleh peran Admin" className="adm" extra={<span className="ctag">Admin</span>}>
              <Link className="ai2" href="/statistik">
                <i style={{ background: "#ECE5FA", color: "#6A4CB5" }}><Icon name="bars" /></i><b>Statistik aplikasi</b>
                <small>{p.admin.active_users_7d} pengguna aktif 7 hari · {p.admin.downloads_current} unduhan APK {shortVer || p.admin.version_name}</small>
                <Icon name="chevr" className="go" />
              </Link>
              <Link className="ai2" href="/admin">
                <i style={{ background: "#E1ECFA", color: "#2C6CB0" }}><Icon name="users" /></i><b>Pengguna dan akses</b>
                <small>{p.admin.accounts} akun · {p.admin.inactive} nonaktif</small>
                <Icon name="chevr" className="go" />
              </Link>
            </Card>
          )}

          <section className="card" aria-label="Keamanan" ref={(el) => { refs.current.keamanan = el; }}>
            <div className="ch"><div><h3>Keamanan</h3><p>
              {sec?.password_days != null ? `Password diubah ${sec.password_days} hari lalu` : "Password belum pernah diubah"} · {devices.length} perangkat masuk
            </p></div></div>
            {devices.map((d, i) => (
              <div key={`${d.kind}-${d.id ?? i}`} className="ses">
                <i><Icon name={d.kind === "android" ? "phone" : "monitor"} /></i>
                <b>{d.name}{d.current && <span className="now">Perangkat ini</span>}</b>
                <small>{d.sub}</small>
                {d.can_sign_out && <button className="lo" onClick={() => signOut(d)}>Keluarkan</button>}
              </div>
            ))}
            <div className="foot2">
              <button className="linkbtn" style={{ flex: 1, justifyContent: "center" }} onClick={() => setPwOpen(true)}><Icon name="lock" />Ubah password</button>
              <button className="outbtn" style={{ flex: 1 }} onClick={() => logout()}><Icon name="logout" />Keluar</button>
            </div>
          </section>
        </div>

        <div className="pcol">
          <div className="pfnav" role="tablist" aria-label="Bagian">
            {SECTIONS.map((s) => (
              <button key={s.key} role="tab" aria-selected={section === s.key} className={section === s.key ? "on" : ""} onClick={() => go(s.key)}>
                <Icon name={s.icon} />{s.label}
              </button>
            ))}
          </div>

          <section className="card" aria-label="Informasi akun" ref={(el) => { refs.current.akun = el; }}>
            <div className="ch"><div><h3>Informasi akun</h3><p>Nama dan departemen tampil di laporan yang kamu bagikan</p></div></div>
            <div className="fgrid">
              <div className="fld"><label htmlFor="pf-name">Nama lengkap</label>
                <div className="inp"><input id="pf-name" value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} /></div></div>
              <div className="fld"><label>Username <em>tidak bisa diubah</em></label><div className="inp ro"><Icon name="lock" />{u?.username}</div></div>
              <div className="fld"><label htmlFor="pf-mail">Email</label>
                <div className="inp"><Icon name="mail" /><input id="pf-mail" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div></div>
              <div className="fld"><label htmlFor="pf-dept">Departemen</label>
                <div className="inp">{form.department || "Pilih departemen"}<span className="grow" /><Icon name="chev" />
                  <select id="pf-dept" value={form.department} onChange={(e) => setForm({ ...form, department: e.target.value })}>
                    {!form.department && <option value="">Pilih departemen</option>}
                    {[...new Set([...(p?.options.departments ?? []), ...(form.department ? [form.department] : [])])].map((d) => <option key={d} value={d}>{d}</option>)}
                  </select></div></div>
              <div className="fld"><label>Peran <em>diatur Admin</em></label><div className="inp ro"><Icon name="lock" />{u?.role === "admin" ? "Admin" : "Pengguna"}</div></div>
              <div className="fld"><label htmlFor="pf-reg">Wilayah default <em>dipakai di Dashboard dan Peta</em></label>
                <div className="inp">{region}<span className="grow" /><Icon name="chev" />
                  <select id="pf-reg" value={form.default_region} onChange={(e) => setForm({ ...form, default_region: e.target.value })}>
                    {(p?.options.regions ?? []).map((r) => <option key={r.key} value={r.key}>{r.label}</option>)}
                  </select></div></div>
            </div>
            <div className="foot2">
              {msg ? <small className={`msg${msg.ok ? "" : " err"}`}>{msg.text}</small> : <small>{u?.updated_at ? `Terakhir diubah ${dmy(u.updated_at)}` : ""}</small>}
              <span className="grow" />
              <button className="linkbtn" disabled={!dirty || saving} onClick={() => { if (p) setForm({ full_name: p.user.full_name || "", email: p.user.email || "", department: p.user.department || "", default_region: p.user.default_region }); setMsg(null); }}>Batal</button>
              <button className="btn-p" style={{ height: 36, boxShadow: "none" }} disabled={saving} onClick={saveAccount}>{saving ? "Menyimpan..." : "Simpan perubahan"}</button>
            </div>
          </section>

          <section className="card" aria-label="Tampilan" ref={(el) => { refs.current.tampilan = el; }}>
            <div className="ch"><div><h3>Tampilan</h3><p>Berlaku di web dan Android</p></div><Link className="chlink" href="/tampilan">Ukuran teks dan lainnya</Link></div>
            {pr && (
              <div className="tgrid">
                <div>
                  <div className="prow"><div><b>Tema</b></div><div className="seg">
                    {([["light", "Terang", "sun"], ["dark", "Gelap", "moon"], ["system", "Sistem", ""]] as const).map(([k, l, ic]) => (
                      <button key={k} className={pr.theme === k ? "on" : ""} onClick={() => savePrefs({ theme: k })}>{ic && <Icon name={ic} />}{l}</button>
                    ))}</div></div>
                  <div className="prow"><div><b>Warna aksen</b></div><div className="sws">
                    {ACCENTS.map((a) => (
                      <button key={a.key} className={pr.accent === a.key ? "on" : ""} aria-pressed={pr.accent === a.key} onClick={() => savePrefs({ accent: a.key })}><i style={{ background: a.c }} />{a.label}</button>
                    ))}</div></div>
                  <div className="prow"><div><b>Kepadatan</b></div><div className="seg">
                    {([["ringkas", "Ringkas"], ["standar", "Standar"], ["lega", "Lega"]] as const).map(([k, l]) => (
                      <button key={k} className={pr.density === k ? "on" : ""} onClick={() => savePrefs({ density: k })}>{l}</button>
                    ))}</div></div>
                  <div className="prow"><div><b>Bahasa</b></div><div className="seg">
                    <button className="on">Indonesia</button><button disabled title="Bahasa Inggris belum tersedia">English</button>
                  </div></div>
                </div>
                <div>
                  <div className="prow tg"><div><b>Garis target di grafik</b><small>Garis putus-putus pada grafik KPI</small></div>
                    <Toggle on={pr.targetLine} label="Garis target di grafik" onChange={(v) => savePrefs({ targetLine: v })} /></div>
                  <div className="prow tg"><div><b>Animasi transisi</b><small>Perpindahan halus saat filter dan drill-down</small></div>
                    <Toggle on={pr.animation} label="Animasi transisi" onChange={(v) => savePrefs({ animation: v })} /></div>
                  <div className="mini" aria-label="Pratinjau gaya grafik">
                    <small>Pratinjau</small><b>Rp 1,84 T</b><em>▲ 3,2% vs Sep</em>
                    <svg viewBox="0 0 200 56" preserveAspectRatio="none" aria-hidden="true">
                      {pr.targetLine && <line x1="0" x2="200" y1="20" y2="20" stroke="#C42B2B" strokeDasharray="4 4" opacity=".5" />}
                      <path d="M0 44 L33 40 L66 42 L100 33 L133 28 L166 22 L200 16" fill="none" stroke={ACCENTS.find((a) => a.key === pr.accent)?.c} strokeWidth="2.5" strokeLinejoin="round" />
                      <circle cx="200" cy="16" r="3.5" fill={ACCENTS.find((a) => a.key === pr.accent)?.c} />
                    </svg>
                  </div>
                </div>
              </div>
            )}
          </section>

          <section className="card" aria-label="Notifikasi" ref={(el) => { refs.current.notifikasi = el; }}>
            <div className="ch"><div><h3>Notifikasi</h3><p>Kanal per jenis pemberitahuan. In-app selalu aktif.</p></div></div>
            {pr && (
              <>
                <table className="nm">
                  <thead><tr><th>Jenis</th><th>In-app</th><th>Email</th><th>Push</th></tr></thead>
                  <tbody>
                    {KINDS.map((k) => (
                      <tr key={k.key}>
                        <td><b>{k.label}</b><small>{k.sub}</small></td>
                        <td><span className="cb lock" title="In-app selalu aktif"><Icon name="check" /></span></td>
                        {(["email", "push"] as const).map((c) => {
                          const on = pr.notify[k.key]?.[c] ?? false;
                          return (
                            <td key={c}>
                              <button className={`cb${on ? "" : " off"}`} role="checkbox" aria-checked={on} aria-label={`${k.label} lewat ${c === "email" ? "email" : "push"}`}
                                onClick={() => savePrefs({ notify: { [k.key]: { ...pr.notify[k.key], [c]: !on } } })}>{on && <Icon name="check" />}</button>
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
                <div className="prow tg" style={{ borderTop: 0, paddingBottom: 0 }}>
                  <div><b>Jam tenang 22.00 sampai 06.00</b><small>Push ditahan, kecuali alert kritis</small></div>
                  <Toggle on={pr.quiet_hours} label="Jam tenang" onChange={(v) => savePrefs({ quiet_hours: v })} />
                </div>
                {inbox.length > 0 && (
                  <div className="inbox">
                    <div className="ih">Pesan belum dibaca <span className="ctag" style={{ marginLeft: 0 }}>{inbox.length}</span><button onClick={readAll}>Tandai dibaca</button></div>
                    {inbox.slice(0, 5).map((n) => (
                      <div key={n.id} className="it"><b>{n.title}</b><small>{n.message}</small>{n.created_at && <em>{dmy(n.created_at)}</em>}</div>
                    ))}
                  </div>
                )}
              </>
            )}
          </section>
        </div>
      </div>
      {pwOpen && <PasswordDialog onClose={() => setPwOpen(false)} onDone={() => { setPwOpen(false); setVersion((v) => v + 1); }} />}
    </AppShell>
  );
}

function PasswordDialog({ onClose, onDone }: { onClose: () => void; onDone: () => void }) {
  const [oldPw, setOld] = useState("");
  const [pw, setPw] = useState("");
  const [pw2, setPw2] = useState("");
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  async function submit(e: FormEvent) {
    e.preventDefault();
    if (pw.length < 6) return setErr("Password baru minimal 6 karakter");
    if (pw !== pw2) return setErr("Konfirmasi password tidak sama");
    setBusy(true); setErr("");
    const r = await authFetch("/api/auth/me/password", { method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ old_password: oldPw, new_password: pw }) }).catch(() => null);
    setBusy(false);
    if (r?.ok) onDone();
    else setErr(r?.status === 400 ? "Password lama salah" : "Gagal mengubah password");
  }
  return (
    <div className="pwd" role="dialog" aria-modal="true" aria-label="Ubah password" onClick={onClose}>
      <form onSubmit={submit} onClick={(e) => e.stopPropagation()}>
        <h3>Ubah password</h3>
        <div className="fld"><label htmlFor="pw-old">Password lama</label><div className="inp"><input id="pw-old" type="password" autoComplete="current-password" value={oldPw} onChange={(e) => setOld(e.target.value)} /></div></div>
        <div className="fld"><label htmlFor="pw-new">Password baru</label><div className="inp"><input id="pw-new" type="password" autoComplete="new-password" value={pw} onChange={(e) => setPw(e.target.value)} /></div></div>
        <div className="fld"><label htmlFor="pw-new2">Ulangi password baru</label><div className="inp"><input id="pw-new2" type="password" autoComplete="new-password" value={pw2} onChange={(e) => setPw2(e.target.value)} /></div></div>
        {err && <span className="msg err">{err}</span>}
        <div className="row"><button type="button" className="linkbtn" onClick={onClose}>Batal</button><button type="submit" className="btn-p" disabled={busy}>{busy ? "Menyimpan..." : "Simpan password"}</button></div>
      </form>
    </div>
  );
}
