"use client";
import { useState, FormEvent, useEffect, useRef } from "react";
import { login, isLoggedIn } from "@/lib/auth";
import { useMounted } from "@/lib/useMounted";
import { Icon } from "@/app/components/v2/Icon";
import "./login.css";

type Mode = "login" | "forgot" | "reset" | "request";
const REGIONS = [["JAVA", "Circle Java"], ["WEST JAVA", "West Java"], ["CENTRAL JAVA", "Central Java"], ["EAST JAVA", "East Java"]];
const DEPARTMENTS = ["Business Planning", "Sales", "Marketing", "Network", "Finance", "Operations"];

export default function LoginPage() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [mode, setMode] = useState<Mode>("login");
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotSent, setForgotSent] = useState(false);
  const [req, setReq] = useState({ full_name: "", email: "", department: "", region: "JAVA" });
  const [reqSent, setReqSent] = useState(false);
  const [resetToken, setResetToken] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newPasswordConfirm, setNewPasswordConfirm] = useState("");
  const [successMsg, setSuccessMsg] = useState("");
  const [readUrl, setReadUrl] = useState(false);
  const [remember, setRemember] = useState(true);
  // Video: plays unless the user prefers reduced motion or pressed pause. The poster
  // stays underneath until the first frame plays, and the bar follows the seconds.
  const [paused, setPaused] = useState(true);
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(0);
  const videoRef = useRef<HTMLVideoElement>(null);
  const mounted = useMounted();

  // A reset link opens the page as /login?reset=<token>.
  if (mounted && !readUrl) {
    setReadUrl(true);
    const tok = new URLSearchParams(window.location.search).get("reset");
    if (tok) {
      setResetToken(tok);
      setMode("reset");
    }
  }

  useEffect(() => {
    if (isLoggedIn()) window.location.href = "/";
  }, []);

  useEffect(() => {
    if (!mounted) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    // starting playback is a sync with the browser, done once after mount
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (!reduce) setPaused(false);
  }, [mounted]);

  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    if (paused) v.pause();
    else v.play().catch(() => setPaused(true));
  }, [paused]);

  function switchMode(m: Mode) {
    setMode(m);
    setError("");
    setForgotSent(false);
    if (m !== "login") setSuccessMsg("");
  }

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(username, password, remember);
      window.location.href = "/";
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Terjadi kesalahan");
      setLoading(false);
    }
  }

  async function postJson(url: string, body: object) {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: "Gagal" }));
      throw new Error(err.detail || "Gagal");
    }
  }

  async function handleForgot(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await postJson("/api/auth/forgot-password", { email: forgotEmail });
      setForgotSent(true);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Terjadi kesalahan");
    } finally {
      setLoading(false);
    }
  }

  async function handleRequest(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await postJson("/api/auth/request-access", req);
      setReqSent(true);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Terjadi kesalahan");
    } finally {
      setLoading(false);
    }
  }

  async function handleReset(e: FormEvent) {
    e.preventDefault();
    setError("");
    if (newPassword !== newPasswordConfirm) {
      setError("Password tidak sama");
      return;
    }
    setLoading(true);
    try {
      await postJson("/api/auth/reset-password", { token: resetToken, new_password: newPassword });
      setSuccessMsg("Password berhasil direset. Silakan masuk.");
      setMode("login");
      setNewPassword("");
      setNewPasswordConfirm("");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Terjadi kesalahan");
    } finally {
      setLoading(false);
    }
  }

  const pwField = (id: string, value: string, set: (v: string) => void, auto: string, label: string, extra?: { autoFocus?: boolean; minLength?: number }) => (
    <div className="fld">
      <label htmlFor={id}>{label}</label>
      <div className="inp">
        <Icon name="llock" />
        <input id={id} type={showPw ? "text" : "password"} value={value} onChange={(e) => set(e.target.value)}
          placeholder="••••••••••" autoComplete={auto} required {...extra} />
        <button type="button" onClick={() => setShowPw((v) => !v)} aria-label={showPw ? "Sembunyikan password" : "Tampilkan password"}>
          <Icon name={showPw ? "leyeoff" : "leye"} size={19} />
        </button>
      </div>
    </div>
  );

  const cta = (label: string, disabled = false) => (
    <button className="cta" type="submit" disabled={loading || disabled}>
      {loading ? <span className="spin" aria-label="Memproses" /> : <><span>{label}</span><Icon name="arrowr" /></>}
    </button>
  );

  return (
    <main className="lgv2">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img className="media" src="/media/login-bg-poster.jpg" alt="" />
      <video ref={videoRef} className="media" src="/media/login-bg.mp4" muted loop playsInline preload={paused && !playing ? "none" : "auto"} aria-hidden="true"
        style={{ opacity: playing ? 1 : 0 }}
        onPlaying={() => setPlaying(true)}
        onTimeUpdate={(e) => { const v = e.currentTarget; if (v.duration) setProgress(v.currentTime / v.duration); }} />
      <div className="shade" aria-hidden="true" />
      <div className="glow" aria-hidden="true" />

      <div className="wlogo">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <span className="tile"><img src="/brand/icon_circle_java.png" alt="Logo Agent Java" /></span>
        <b>Agent <em>Java</em></b>
      </div>
      <div className="hero">
        <h2 className="tagline">Winning<br />Every <span>Second</span></h2>
        <div className="sec-bar" aria-hidden="true"><i style={{ width: `${progress * 100}%` }} /></div>
      </div>

      {mode === "login" && (
        <form className="card" onSubmit={handleSubmit} noValidate>
          <div className="grab" aria-hidden="true" />
          <div><h1>Masuk</h1><p className="sub">Selamat datang kembali.</p></div>
          <div className="fld">
            <label htmlFor="lg-user">Username</label>
            <div className="inp">
              <Icon name="luser" />
              <input id="lg-user" value={username} onChange={(e) => setUsername(e.target.value)}
                placeholder="nama.pengguna" autoComplete="username" required />
            </div>
          </div>
          {pwField("lg-pass", password, setPassword, "current-password", "Password")}
          <div className="row">
            <label className="remember">
              <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
              <span className="tgl"><i /></span>Ingat saya
            </label>
            <button type="button" className="link" onClick={() => switchMode("forgot")}>Lupa password?</button>
          </div>
          {cta("Masuk")}
          <p className={`msg${error ? " err" : ""}`} role="status" aria-live="polite">{error || successMsg}</p>
          <p className="ask">Belum punya akun? <button type="button" className="link" onClick={() => switchMode("request")}>Minta akses</button></p>
        </form>
      )}

      {mode === "request" && (
        <form className="card" onSubmit={handleRequest} noValidate>
          <div className="grab" aria-hidden="true" />
          <div>
            <h1>Minta akses</h1>
            <p className="sub">{reqSent ? "Admin akan meninjau. Link untuk membuat password dikirim ke email saat akun disetujui." : "Isi data diri. Admin menyetujui setiap akun baru."}</p>
          </div>
          {reqSent ? (
            <p className="msg">Permintaan untuk <strong>{req.email}</strong> sudah terkirim.</p>
          ) : (
            <>
              <div className="fld">
                <label htmlFor="rq-name">Nama lengkap</label>
                <div className="inp"><Icon name="luser" />
                  <input id="rq-name" value={req.full_name} onChange={(e) => setReq({ ...req, full_name: e.target.value })} autoComplete="name" required autoFocus /></div>
              </div>
              <div className="fld">
                <label htmlFor="rq-mail">Email kantor</label>
                <div className="inp"><Icon name="mail" />
                  <input id="rq-mail" type="email" value={req.email} onChange={(e) => setReq({ ...req, email: e.target.value })} placeholder="nama@kantor.co.id" autoComplete="email" required /></div>
              </div>
              <div className="fld">
                <label htmlFor="rq-dept">Departemen</label>
                <div className="inp"><Icon name="users" />
                  <input id="rq-dept" list="rq-depts" value={req.department} onChange={(e) => setReq({ ...req, department: e.target.value })} placeholder="Business Planning" /></div>
                <datalist id="rq-depts">{DEPARTMENTS.map((d) => <option key={d} value={d} />)}</datalist>
              </div>
              <div className="fld">
                <label htmlFor="rq-region">Region</label>
                <div className="inp"><Icon name="pin" />
                  <select id="rq-region" value={req.region} onChange={(e) => setReq({ ...req, region: e.target.value })}>
                    {REGIONS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                  </select></div>
              </div>
              {cta("Kirim permintaan", req.full_name.trim().length < 2 || !req.email.includes("@"))}
              <p className={`msg${error ? " err" : ""}`} role="status" aria-live="polite">{error}</p>
            </>
          )}
          <button type="button" className="link back" onClick={() => switchMode("login")}><Icon name="arrowr" />Kembali ke Masuk</button>
        </form>
      )}

      {mode === "forgot" && (
        <form className="card" onSubmit={handleForgot} noValidate>
          <div className="grab" aria-hidden="true" />
          <div>
            <h1>Lupa password</h1>
            <p className="sub">{forgotSent ? "Cek kotak masuk atau folder spam. Tautan berlaku 30 menit." : "Kami kirim tautan untuk membuat password baru."}</p>
          </div>
          {forgotSent ? (
            <p className="msg">Jika email terdaftar, tautan reset sudah dikirim ke <strong>{forgotEmail}</strong>.</p>
          ) : (
            <>
              <div className="fld">
                <label htmlFor="lg-mail">Email kantor</label>
                <div className="inp">
                  <Icon name="mail" />
                  <input id="lg-mail" type="email" value={forgotEmail} onChange={(e) => setForgotEmail(e.target.value)}
                    placeholder="nama@kantor.co.id" autoComplete="email" required autoFocus />
                </div>
              </div>
              {cta("Kirim tautan reset", !forgotEmail)}
              <p className={`msg${error ? " err" : ""}`} role="status" aria-live="polite">{error}</p>
            </>
          )}
          <button type="button" className="link back" onClick={() => switchMode("login")}><Icon name="arrowr" />Kembali ke Masuk</button>
        </form>
      )}

      {mode === "reset" && (
        <form className="card" onSubmit={handleReset} noValidate>
          <div className="grab" aria-hidden="true" />
          <div><h1>Buat password baru</h1><p className="sub">Minimal 8 karakter.</p></div>
          {pwField("lg-new", newPassword, setNewPassword, "new-password", "Password baru", { autoFocus: true, minLength: 8 })}
          {pwField("lg-new2", newPasswordConfirm, setNewPasswordConfirm, "new-password", "Ulangi password")}
          {cta("Simpan password", !newPassword)}
          <p className={`msg${error ? " err" : ""}`} role="status" aria-live="polite">{error}</p>
          <button type="button" className="link back" onClick={() => switchMode("login")}><Icon name="arrowr" />Kembali ke Masuk</button>
        </form>
      )}

      <div className="bottom">
        <button type="button" className="vctl" onClick={() => setPaused((p) => !p)} aria-label={paused ? "Putar video" : "Jeda video"}>
          <Icon name={paused ? "play" : "pause"} /><span>{paused ? "Putar video" : "Jeda video"}</span>
        </button>
        <span className="foot">© 2026 Agent Java</span>
      </div>
    </main>
  );
}
