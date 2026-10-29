"use client";
import { useEffect, useMemo, useState } from "react";
import {
  CalendarDays, Check, CircleHelp, Copy, Cpu, Database, Download, History, Minus, Plus, Rocket, ShieldCheck, Smartphone, Sparkles, Wifi,
} from "lucide-react";
import qrcode from "qrcode-generator";
import AppShell from "../components/shell/AppShell";
import { MONTHS_FULL } from "@/lib/format";
import "./unduh.css";

type Version = {
  version_name: string | null; version_code: number; notes: string; mandatory: boolean; download_url: string;
  size_bytes: number; available: boolean; released_at: string | null; apk_filename?: string; sha256?: string | null; min_android?: string;
};
type Release = { version_name: string; released_at: string | null; notes: string[]; mandatory: boolean; latest: boolean };

const ANDROID_NAMES: Record<string, string> = {
  "7.0": "Nougat", "8.0": "Oreo", "9": "Pie", "9.0": "Pie", "10": "Android 10", "11": "Android 11", "12": "Android 12", "13": "Android 13",
};
const MON = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
const fmtDate = (iso: string | null | undefined, long = false) => {
  if (!iso) return "";
  const d = new Date(iso.length <= 10 ? `${iso}T00:00:00` : iso);
  return `${d.getDate()} ${(long ? MONTHS_FULL : MON)[d.getMonth()]} ${d.getFullYear()}`;
};
const mb = (b: number) => `${(b / 1048576).toLocaleString("id-ID", { maximumFractionDigits: 1 })} MB`;

const FEATURES = [
  { img: "/illustrations/duo_chat.svg", title: "Tanya agent", text: "Jawaban beranalisis dari BigQuery, tervalidasi sebelum tampil." },
  { img: "/illustrations/iso_dashboard.svg", title: "Dashboard saku", text: "KPI Jawa, region dan kabupaten dengan grafik interaktif.", wide: true },
  { img: "/illustrations/duo_alert.svg", title: "Alert real-time", text: "Notifikasi push saat KPI melewati ambang batas." },
  { img: "/illustrations/duo_report.svg", title: "Laporan PDF & XLSX", text: "Ekspor dan bagikan laporan langsung dari ponsel." },
];

const FAQ = [
  { q: "Kenapa harus izinkan “sumber tidak dikenal”?", a: "APK dibagikan internal, bukan lewat Play Store. Izin hanya untuk browser yang Anda pakai mengunduh." },
  { q: "Apakah update otomatis?", a: "Aplikasi memeriksa versi baru setiap kali dibuka. Jika ada, muncul tawaran unduh; versi bertanda Wajib harus dipasang sebelum lanjut." },
  { q: "Lupa password?", a: "Gunakan “Lupa password” di layar masuk untuk menerima tautan reset ke email kantor, atau hubungi admin Bizplan." },
  { q: "Data saya aman?", a: "Koneksi memakai HTTPS ke server kantor, token login tersimpan terenkripsi di perangkat, dan data tidak dibagikan ke pihak ketiga." },
];

function Qr({ text }: { text: string }) {
  const cells = useMemo(() => {
    const q = qrcode(0, "H");
    q.addData(text);
    q.make();
    const n = q.getModuleCount();
    const out: [number, number][] = [];
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (q.isDark(r, c)) out.push([c, r]);
    return { n, out };
  }, [text]);
  const { n, out } = cells;
  const hole = Math.round(n * 0.26) | 1; // centre square kept clear for the logo (level H tolerates it)
  const h0 = (n - hole) / 2;
  return (
    <span className="un-qr-code">
      <svg viewBox={`0 0 ${n} ${n}`} shapeRendering="crispEdges" role="img" aria-label="Kode QR tautan unduh APK">
        {out.filter(([x, y]) => !(x >= h0 - 0.5 && x < h0 + hole && y >= h0 - 0.5 && y < h0 + hole))
          .map(([x, y]) => <rect key={`${x}-${y}`} x={x} y={y} width="1.02" height="1.02" fill="#0F1F1D" />)}
      </svg>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src="/brand/icon_circle_java.png" alt="" />
    </span>
  );
}

export default function UnduhPage() {
  const [ver, setVer] = useState<Version | null>(null);
  const [releases, setReleases] = useState<Release[]>([]);
  const [origin, setOrigin] = useState("");
  const [open, setOpen] = useState(0);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let live = true;
    fetch("/api/app/version").then((r) => (r.ok ? r.json() : null)).then((v) => { if (live && v) setVer(v); }).catch(() => {});
    fetch("/api/app/releases").then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && j) setReleases(j.releases); }).catch(() => {});
    const t = setTimeout(() => setOrigin(window.location.origin), 0);
    return () => { live = false; clearTimeout(t); };
  }, []);

  const name = ver?.version_name ?? "";
  const href = "/api/app/download?src=web";
  const fileName = ver?.apk_filename || `bizplan-java-v${name}.apk`;
  const minAndroid = ver?.min_android ?? "8.0";
  const list: Release[] = releases.length ? releases.map((r) => (r.latest && !r.released_at ? { ...r, released_at: ver?.released_at ?? null } : r))
    : ver?.version_name ? [{ version_name: ver.version_name, released_at: ver.released_at, notes: ver.notes.split("\n").map((s) => s.replace(/^[-•\s]+/, "")).filter(Boolean), mandatory: ver.mandatory, latest: true }] : [];
  const sha = ver?.sha256 ?? "";
  const shaShort = sha ? `${sha.slice(0, 4)}…${sha.slice(-20).match(/.{1,4}/g)!.join(" ")}` : "Tersedia setelah APK diunggah ke server";

  async function copySha() {
    if (!sha) return;
    try { await navigator.clipboard.writeText(sha); setCopied(true); setTimeout(() => setCopied(false), 1600); } catch { /* clipboard blocked */ }
  }

  const download = ver?.available
    ? <a className="un-dl" href={href} download={fileName}><Download size={24} /><span><b>Download APK</b><small>v{name} · {mb(ver.size_bytes)}</small></span></a>
    : <span className="un-dl off" aria-disabled="true"><Download size={24} /><span><b>Download APK</b><small>{ver ? "APK belum tersedia di server" : "Memuat…"}</small></span></span>;

  return (
    <AppShell>
      <div className="un">
        <section className="un-hero">
          <span className="un-photo" aria-hidden="true" />
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="un-city" src="/illustrations/iso_city.svg" alt="" aria-hidden="true" />
          <span className="un-fade" aria-hidden="true" />
          <div className="un-hero-text">
            {name && <span className="un-badge"><Rocket size={16} /> Versi baru v{name}{ver?.released_at ? ` · ${fmtDate(ver.released_at)}` : ""}</span>}
            <h1>Winning Every Second,<br />langsung di ponsel Anda.</h1>
            <p>Bizplan Java Agent untuk Android: tanya bisnis Jawa, pantau KPI dan terima alert di mana pun.</p>
            <div className="un-cta">
              {download}
              <a className="un-ghost" href="#riwayat"><Sparkles size={18} /> Apa yang baru</a>
            </div>
            <div className="un-meta">
              {ver?.released_at && <span><CalendarDays size={16} /> Rilis {fmtDate(ver.released_at)}</span>}
              <span><Cpu size={16} /> Android {minAndroid}+</span>
              <span><ShieldCheck size={16} /> Ditandatangani IOH</span>
            </div>
          </div>
          <div className="un-stage" aria-hidden="true">
            <span className="un-phone left">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/media/screens/scr_tanya.png" alt="" /><i />
            </span>
            <span className="un-phone mid">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src="/media/screens/scr_dash.png" alt="" /><i />
            </span>
          </div>
          {origin && ver?.available !== false && (
            <div className="un-qr">
              <Qr text={`${origin}${href}`} />
              <span>Pindai untuk unduh</span>
            </div>
          )}
        </section>

        <section className="un-sec">
          <span className="un-eyebrow">Fitur utama</span>
          <h2 className="un-h2">Semua yang Anda pakai di web, kini di saku</h2>
          <div className="un-features">
            {FEATURES.map((f) => (
              <article key={f.title} className="un-card">
                <span className={`un-art ${f.wide ? "wide" : ""}`}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={f.img} alt="" />
                </span>
                <h3>{f.title}</h3>
                <p>{f.text}</p>
              </article>
            ))}
          </div>
        </section>

        <section className="un-sec">
          <span className="un-eyebrow">Cara instal</span>
          <h2 className="un-h2">Tiga langkah, kurang dari satu menit</h2>
          <ol className="un-steps">
            {[
              { t: "Unduh file APK", d: `Ketuk Download APK atau pindai QR. File ${fileName} tersimpan di Unduhan.` },
              { t: "Izinkan sumber tidak dikenal", d: "Saat diminta, buka Setelan dan aktifkan “Izinkan dari sumber ini” untuk browser Anda." },
              { t: "Buka file, lalu masuk", d: "Ketuk file APK, pilih Instal, lalu masuk dengan username dan password kantor." },
            ].map((s, i) => (
              <li key={s.t} className="un-card">
                <span className="un-art step">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={`/illustrations/install_step${i + 1}.svg`} alt="" />
                </span>
                <h3><span className="un-num">{i + 1}</span>{s.t}</h3>
                <p>{s.d}</p>
              </li>
            ))}
          </ol>
        </section>

        <section className="un-sec un-rel" id="riwayat">
          <div className="un-rel-main">
            <span className="un-eyebrow">Apa yang baru</span>
            <h2 className="un-h2">Riwayat versi</h2>
            {list.length === 0 && <p className="un-muted">Belum ada catatan rilis.</p>}
            {list.map((r) => {
              const Ico = r.latest ? Rocket : r.mandatory ? ShieldCheck : History;
              return (
                <article key={r.version_name} className={`un-release ${r.latest ? "latest" : ""}`}>
                  <span className="un-rel-ico"><Ico size={20} /></span>
                  <div>
                    <div className="un-rel-top">
                      <b>v{r.version_name}</b>
                      {r.latest && <span className="un-chip teal">Terbaru</span>}
                      {r.mandatory && <span className="un-chip amber">Wajib</span>}
                      {r.released_at && <small>{fmtDate(r.released_at)}</small>}
                    </div>
                    {r.notes.length > 0 && (
                      <ul>{r.notes.map((n) => <li key={n}><Check size={16} /> {n}</li>)}</ul>
                    )}
                  </div>
                  {r.latest && ver?.available && <a className="ui-btn un-rel-dl" href={href} download={fileName}><Download size={18} /> Unduh</a>}
                </article>
              );
            })}
          </div>
          <aside className="un-side">
            <div className="un-req">
              <h3>Persyaratan sistem</h3>
              <ul>
                <li><Smartphone size={20} /><div><b>Android</b><span>{minAndroid}{ANDROID_NAMES[minAndroid] ? ` (${ANDROID_NAMES[minAndroid]})` : ""} atau lebih baru</span></div></li>
                <li><Cpu size={20} /><div><b>RAM</b><span>minimal 3 GB</span></div></li>
                <li><Database size={20} /><div><b>Ruang kosong</b><span>{ver?.size_bytes ? mb(Math.round((ver.size_bytes * 2.5) / 10485760) * 10485760) : "120 MB"}</span></div></li>
                <li><Wifi size={20} /><div><b>Koneksi</b><span>4G/Wi-Fi, VPN kantor bila di luar jaringan</span></div></li>
              </ul>
            </div>
            <div className="un-verify">
              <h3>Verifikasi file</h3>
              <span>SHA-256 {fileName}</span>
              <div className="un-hash">
                <code title={sha || undefined}>{shaShort}</code>
                <button onClick={copySha} disabled={!sha} aria-label="Salin SHA-256">{copied ? <Check size={18} /> : <Copy size={18} />}</button>
              </div>
            </div>
          </aside>
        </section>

        <section className="un-sec un-faq-sec">
          <span className="un-eyebrow">FAQ</span>
          <h2 className="un-h2">Pertanyaan yang sering diajukan</h2>
          <div className="un-faq">
            {FAQ.map((f, i) => (
              <div key={f.q} className={`un-q ${open === i ? "open" : ""}`}>
                <button aria-expanded={open === i} onClick={() => setOpen(open === i ? -1 : i)}>
                  <CircleHelp size={20} className="un-q-ico" />
                  <b>{f.q}</b>
                  {open === i ? <Minus size={20} /> : <Plus size={20} />}
                </button>
                {open === i && <p>{f.a}</p>}
              </div>
            ))}
          </div>
        </section>
      </div>
    </AppShell>
  );
}
