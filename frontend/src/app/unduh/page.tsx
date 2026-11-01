"use client";
// Redesign v2 page 09: Unduh aplikasi Android. Hero with the APK button, phone preview and QR,
// what is new, install steps, FAQ, file authenticity, version history and a share link.
import { useEffect, useState } from "react";
import AppShell, { TopBar } from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { PUBLIC_ORIGIN, Qr } from "../components/v2/Qr";
import { authFetch } from "@/lib/auth";
import "./unduh2.css";

type Highlight = { icon: string; title: string; text: string };
type Version = {
  version_name: string | null; version_code: number; notes: string; mandatory: boolean; download_url: string; size_bytes: number;
  available: boolean; released_at: string | null; apk_filename?: string; sha256?: string | null; min_android?: string;
  summary?: string; highlights?: Highlight[];
};
type Release = {
  version_name: string; version_code: number | null; released_at: string | null; notes: string[]; summary?: string;
  mandatory: boolean; latest: boolean; available?: boolean; download_url?: string;
};

const ANDROID_NAMES: Record<string, string> = { "7.0": "Nougat", "8.0": "Oreo", "9": "Pie", "9.0": "Pie" };
const HL_COLORS: Record<string, [string, string]> = {
  map: ["#E3F7FA", "#0E6F7C"], pulse: ["#F4FCE3", "#5E8A12"], bell: ["#FBE2E8", "#B33A5B"], user: ["#E6F7F5", "#0A6A5F"],
};
const HL_FALLBACK: [string, string][] = [["#E3F7FA", "#0E6F7C"], ["#F4FCE3", "#5E8A12"], ["#FBE2E8", "#B33A5B"], ["#E6F7F5", "#0A6A5F"]];
const FAQ = [
  { q: "Kenapa harus izinkan sumber tidak dikenal?", a: "Agent Java dibagikan langsung sebagai APK internal, bukan lewat Play Store. Izin ini hanya untuk file yang kamu buka sendiri." },
  { q: "Apakah update otomatis?", a: "Aplikasi memeriksa versi baru setiap kali dibuka. Jika ada, muncul tawaran unduh. Versi bertanda wajib harus dipasang sebelum lanjut." },
  { q: "Data saya aman?", a: "Koneksi memakai HTTPS ke server kantor, token login tersimpan di perangkat, data dibaca read-only dan kolom data pribadi pelanggan selalu diblokir." },
];
const mb = (b: number) => `${Math.round(b / 1048576)} MB`;
const share = `${PUBLIC_ORIGIN}/unduh`;

export default function UnduhPage() {
  const [ver, setVer] = useState<Version | null>(null);
  const [releases, setReleases] = useState<Release[]>([]);
  const [open, setOpen] = useState(0);
  const [copied, setCopied] = useState<string | null>(null);
  const [mail, setMail] = useState<{ busy?: boolean; msg?: string }>({});

  useEffect(() => {
    let live = true;
    fetch("/api/app/version").then((r) => (r.ok ? r.json() : null)).then((v) => { if (live && v) setVer(v); }).catch(() => {});
    fetch("/api/app/releases").then((r) => (r.ok ? r.json() : null)).then((j) => { if (live && j) setReleases(j.releases); }).catch(() => {});
    return () => { live = false; };
  }, []);

  const name = ver?.version_name ?? "";
  const short = name.split(".").slice(0, 2).join(".");
  const minAndroid = ver?.min_android ?? "8.0";
  const sha = ver?.sha256 ?? "";
  const shaShort = sha ? `SHA-256 ${sha.slice(0, 8)} ${sha.slice(8, 16)} … ${sha.slice(-8)}` : "SHA-256 tersedia setelah APK diunggah ke server";
  const highlights: Highlight[] = ver?.highlights?.length ? ver.highlights
    : (ver?.notes ?? "").split("\n").map((s) => s.replace(/^[-•\s]+/, "").trim()).filter(Boolean).slice(0, 4).map((t) => ({ icon: "check", title: t, text: "" }));
  const free = ver?.size_bytes ? Math.ceil((ver.size_bytes / 1048576) * 3 / 10) * 10 : 80;

  const copy = async (key: string, text: string) => {
    try { await navigator.clipboard.writeText(text); setCopied(key); setTimeout(() => setCopied(null), 1600); } catch { /* clipboard blocked */ }
  };
  const sendMail = async () => {
    setMail({ busy: true });
    const r = await authFetch("/api/app/send-link", { method: "POST" }).catch(() => null);
    const j = r ? await r.json().catch(() => null) : null;
    setMail({ msg: r?.ok ? `Link terkirim ke ${j?.to ?? "email kamu"}.` : (j?.detail ?? "Email gagal dikirim.") });
    setTimeout(() => setMail({}), 5000);
  };

  return (
    <AppShell>
      <TopBar title="Unduh aplikasi Android" subtitle="Hanya untuk pengguna yang sudah login. Link dan QR berlaku untuk akun internal." />
      <div className="dlx">
        <div className="hero9">
          <span className="glow" aria-hidden="true" />
          <div className="tx">
            <span className="eb">Agent Java untuk Android</span>
            <h3>Semua yang kamu pakai di web, <span>kini di saku</span></h3>
            <p>Tanya agent, dashboard, Performance, Peta, laporan, dan alert push. Satu akun dengan web.</p>
            <div className="meta">
              <span>Versi {name || "-"}{ver ? ` (${ver.version_code})` : ""}</span>
              {ver?.size_bytes ? <span>{mb(ver.size_bytes)}</span> : null}
              <span>Android {minAndroid.split(".")[0]} ke atas</span>
            </div>
            <div className="cta">
              {ver?.available
                ? <a className="bigdl" href="/api/app/download?src=web" download={ver.apk_filename}><Icon name="dl" />Unduh APK {name}</a>
                : <span className="bigdl off" aria-disabled="true"><Icon name="dl" />{ver ? "APK belum tersedia" : "Memuat..."}</span>}
              <button className="ghost" onClick={sendMail} disabled={mail.busy}><Icon name="mail" />Kirim ke email saya</button>
              {mail.msg && <span className="note" role="status">{mail.msg}</span>}
            </div>
          </div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <div className="ph9"><img src="/media/unduh-dashboard.jpg" alt="Layar Dashboard Agent Java di Android" /></div>
          <div className="qr9"><Qr text={share} /><b>Pindai untuk unduh</b><small>Buka kamera HP, arahkan ke kode ini</small></div>
        </div>

        <div className="pcol">
          <section className="card">
            <div className="ch"><div><h3>Apa yang baru di {short || "versi ini"}</h3><p>{ver?.summary || "Catatan rilis terbaru"}</p></div><span className="grow" />
              <span className="ctag" style={{ background: "#F4FCE3", color: "#5E8A12" }}>Terbaru</span></div>
            <div className="wn2">
              {highlights.map((h, i) => {
                const [bg, fg] = HL_COLORS[h.icon] ?? HL_FALLBACK[i % HL_FALLBACK.length];
                return (
                  <div className="wn" key={h.title}><div className="wi"><i style={{ background: bg, color: fg }}><Icon name={h.icon} /></i><b>{h.title}</b>{h.text && <small>{h.text}</small>}</div></div>
                );
              })}
            </div>
          </section>
          <section className="card">
            <div className="ch"><div><h3>Cara instal</h3><p>Tiga langkah, kurang dari satu menit</p></div></div>
            <div className="steps9">
              <div><em>1</em><b>Unduh file APK</b><small>Pindai QR atau ketuk Unduh APK di HP.</small></div>
              <div><em>2</em><b>Izinkan sumber tidak dikenal</b><small>Android meminta izin sekali untuk aplikasi di luar Play Store.</small></div>
              <div><em>3</em><b>Buka file, lalu masuk</b><small>Pakai akun yang sama dengan web. OTP dikirim ke email.</small></div>
            </div>
          </section>
          <section className="card faq">
            <div className="ch"><div><h3>Pertanyaan yang sering diajukan</h3></div></div>
            {FAQ.map((f, i) => (
              <div className={`fq${open === i ? " open" : ""}`} key={f.q}>
                <button aria-expanded={open === i} onClick={() => setOpen(open === i ? -1 : i)} style={{ display: "block", width: "100%" }}>
                  <b>{f.q}<Icon name="chev" /></b>
                </button>
                {open === i && <small>{f.a}</small>}
              </div>
            ))}
          </section>
        </div>

        <div className="pcol">
          <section className="card">
            <div className="ch"><div><h3>Keaslian file</h3><p>Cocokkan sebelum instal</p></div></div>
            <div className="sha" title={sha || undefined}><Icon name="shield" /><span>{shaShort}</span>
              {sha && <button className={copied === "sha" ? "ok" : ""} onClick={() => copy("sha", sha)} aria-label="Salin SHA-256"><Icon name={copied === "sha" ? "check" : "copy"} /></button>}</div>
            <div className="req">
              <div><small>Android</small><b>{minAndroid}{ANDROID_NAMES[minAndroid] ? ` ${ANDROID_NAMES[minAndroid]}` : ""} ke atas</b></div>
              <div><small>Ruang kosong</small><b>{free} MB</b></div>
              <div><small>Koneksi</small><b>4G atau Wi-Fi</b></div>
              <div><small>Ditandatangani</small><b>Kunci yang sama sejak 1.0</b></div>
            </div>
          </section>
          <section className="card vh">
            <div className="ch"><div><h3>Riwayat versi</h3><p>Versi lama tetap bisa diunduh</p></div></div>
            {releases.map((r) => (
              <div className="vr" key={r.version_name} title={r.notes.join("\n") || undefined}>
                <b>{r.version_name}{r.version_code ? ` (${r.version_code})` : ""} {r.latest && <span className="pl g">Terbaru</span>}</b>
                <small>{r.summary || r.notes[0] || "-"}</small>
                {r.available
                  ? <a className="dlx2" href={`${r.download_url ?? "/api/app/download"}${(r.download_url ?? "").includes("?") ? "&" : "?"}src=web`} aria-label={`Unduh ${r.version_name}`}><Icon name="dl" /></a>
                  : <span className="dlx2 off" title="File versi ini tidak disimpan di server"><Icon name="dl" /></span>}
              </div>
            ))}
          </section>
          <section className="card">
            <div className="ch"><div><h3>Bagikan ke rekan</h3><p>Link butuh login akun internal</p></div></div>
            <div className="sha"><Icon name="dl" /><span>{share.replace(/^https:\/\//, "")}</span>
              <button className={copied === "link" ? "ok" : ""} onClick={() => copy("link", share)} aria-label="Salin link"><Icon name={copied === "link" ? "check" : "copy"} /></button></div>
          </section>
        </div>
      </div>
    </AppShell>
  );
}
