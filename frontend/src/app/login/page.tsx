"use client";
import { useState, FormEvent, useEffect } from "react";
import { Users, Lock, Eye, EyeOff, Mail, ArrowLeft } from "lucide-react";
import { login, isLoggedIn } from "@/lib/auth";
import { useMounted } from "@/lib/useMounted";
import "./login.css";

type Mode = "login" | "forgot" | "reset";

export default function LoginPage() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [mode, setMode] = useState<Mode>("login");
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotSent, setForgotSent] = useState(false);
  const [resetToken, setResetToken] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newPasswordConfirm, setNewPasswordConfirm] = useState("");
  const [successMsg, setSuccessMsg] = useState("");
  const [readUrl, setReadUrl] = useState(false);
  const mounted = useMounted();
  const reduceMotion = mounted && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

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
      await login(username, password);
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

  return (
    <main className="lg-root">
      {reduceMotion ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img className="lg-media" src="/media/login-bg-poster.jpg" alt="" />
      ) : (
        <video className="lg-media" src="/media/login-bg.mp4" poster="/media/login-bg-poster.jpg"
          autoPlay muted loop playsInline preload="auto" aria-hidden="true" />
      )}
      <div className="lg-shade" aria-hidden="true" />
      <div className="lg-glow" aria-hidden="true" />

      <div className="lg-layout">
        <section className="lg-brand">
          <div className="lg-product">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img className="lg-logo" src="/brand/icon_circle_java.png" alt="Circle Java" width={72} height={72} />
            <span className="lg-product-name">Bizplan Java Agent</span>
          </div>
          <h1 className="lg-headline">Winning<br />Every Second</h1>
          <span className="lg-accent" aria-hidden="true" />
        </section>

        <section className="lg-card" aria-live="polite">
          {mode === "login" && (
            <form onSubmit={handleSubmit} className="lg-form">
              <h2 className="lg-title">Masuk</h2>
              {successMsg && <p className="lg-msg ok">{successMsg}</p>}
              <label className="lg-group">
                <span className="lg-label">Username</span>
                <span className="lg-field">
                  <Users size={18} aria-hidden="true" />
                  <input value={username} onChange={(e) => setUsername(e.target.value)}
                    placeholder="nama.pengguna" autoComplete="username" required />
                </span>
              </label>
              <label className="lg-group">
                <span className="lg-label">Password</span>
                <span className="lg-field">
                  <Lock size={18} aria-hidden="true" />
                  <input type={showPw ? "text" : "password"} value={password}
                    onChange={(e) => setPassword(e.target.value)} placeholder="••••••••••"
                    autoComplete="current-password" required />
                  <button type="button" className="lg-eye" onClick={() => setShowPw((v) => !v)}
                    aria-label={showPw ? "Sembunyikan password" : "Tampilkan password"}>
                    {showPw ? <EyeOff size={18} /> : <Eye size={18} />}
                  </button>
                </span>
              </label>
              <div className="lg-options">
                <button type="button" className="lg-link" onClick={() => switchMode("forgot")}>Lupa password?</button>
              </div>
              {error && <p className="lg-msg err" role="alert">{error}</p>}
              <button type="submit" className="lg-submit" disabled={loading}>
                {loading ? <span className="lg-spin" aria-label="Memproses" /> : "Masuk"}
              </button>
            </form>
          )}

          {mode === "forgot" && (
            <form onSubmit={handleForgot} className="lg-form">
              <h2 className="lg-title">Lupa password</h2>
              {forgotSent ? (
                <>
                  <p className="lg-msg ok">Jika email terdaftar, tautan reset sudah dikirim ke <strong>{forgotEmail}</strong>. Periksa kotak masuk atau folder spam. Tautan berlaku 30 menit.</p>
                  <button type="button" className="lg-submit" onClick={() => switchMode("login")}>Kembali ke Masuk</button>
                </>
              ) : (
                <>
                  <p className="lg-sub">Masukkan email kantor Anda. Kami kirim tautan untuk membuat password baru.</p>
                  <label className="lg-group">
                    <span className="lg-label">Email</span>
                    <span className="lg-field">
                      <Mail size={18} aria-hidden="true" />
                      <input type="email" value={forgotEmail} onChange={(e) => setForgotEmail(e.target.value)}
                        placeholder="nama@ioh.co.id" autoComplete="email" required autoFocus />
                    </span>
                  </label>
                  {error && <p className="lg-msg err" role="alert">{error}</p>}
                  <button type="submit" className="lg-submit" disabled={loading || !forgotEmail}>
                    {loading ? <span className="lg-spin" aria-label="Memproses" /> : "Kirim tautan reset"}
                  </button>
                  <button type="button" className="lg-back" onClick={() => switchMode("login")}>
                    <ArrowLeft size={16} aria-hidden="true" /> Kembali ke Masuk
                  </button>
                </>
              )}
            </form>
          )}

          {mode === "reset" && (
            <form onSubmit={handleReset} className="lg-form">
              <h2 className="lg-title">Buat password baru</h2>
              <label className="lg-group">
                <span className="lg-label">Password baru</span>
                <span className="lg-field">
                  <Lock size={18} aria-hidden="true" />
                  <input type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)}
                    autoComplete="new-password" minLength={8} required autoFocus />
                </span>
              </label>
              <label className="lg-group">
                <span className="lg-label">Ulangi password</span>
                <span className="lg-field">
                  <Lock size={18} aria-hidden="true" />
                  <input type="password" value={newPasswordConfirm}
                    onChange={(e) => setNewPasswordConfirm(e.target.value)} autoComplete="new-password" required />
                </span>
              </label>
              {error && <p className="lg-msg err" role="alert">{error}</p>}
              <button type="submit" className="lg-submit" disabled={loading || !newPassword}>
                {loading ? <span className="lg-spin" aria-label="Memproses" /> : "Simpan password"}
              </button>
              <button type="button" className="lg-back" onClick={() => switchMode("login")}>
                <ArrowLeft size={16} aria-hidden="true" /> Kembali ke Masuk
              </button>
            </form>
          )}
        </section>
      </div>
    </main>
  );
}
