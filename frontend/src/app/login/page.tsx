"use client";
import { useState, FormEvent, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { login, isLoggedIn } from "@/lib/auth";
import { startFluid } from "@/lib/fluid";

const AGENT_CAPABILITIES = [
  { icon: "SQL", label: "SQL Writer", desc: "Auto-generates optimized queries" },
  { icon: "DA", label: "Data Engine", desc: "Warehouse-scale analytics" },
  { icon: "AN", label: "Analyst", desc: "Intent analysis & validation" },
  { icon: "EX", label: "Export", desc: "XLSX & PDF branded reports" },
];

const PIPELINE_STEPS = [
  "Analyst Agent",
  "Orchestrator",
  "Domain Agent",
  "SQL Writer",
  "Data Engine",
  "Synthesizer",
];

const LOGIN_STATS = [
  { num: "13", label: "Agents" },
  { num: "5", label: "Domains" },
  { num: "~15s", label: "Avg Query" },
  { num: "24/7", label: "Ready" },
];

export default function LoginPage() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const leftRef = useRef<HTMLDivElement>(null);
  const blobRef = useRef<HTMLCanvasElement>(null);
  const flowRef = useRef<HTMLCanvasElement>(null);
  const rightRef = useRef<HTMLDivElement>(null);
  const rightBlobRef = useRef<HTMLCanvasElement>(null);
  const [activeStep, setActiveStep] = useState(0);
  const [typedText, setTypedText] = useState("");
  const [mode, setMode] = useState<"login" | "forgot" | "reset">("login");
  const [forgotEmail, setForgotEmail] = useState("");
  const [forgotSent, setForgotSent] = useState(false);
  const [resetToken, setResetToken] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [newPasswordConfirm, setNewPasswordConfirm] = useState("");
  const [successMsg, setSuccessMsg] = useState("");

  const TYPING_QUERIES = [
    "Top 5 kecamatan revenue data tertinggi...",
    "Market share IM3 vs Telkomsel...",
    "Pertumbuhan revenue per district bulan ini...",
    "Profile lengkap kota Surabaya...",
    "Traffic 5G per region bulan terakhir...",
  ];

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (isLoggedIn()) {
      window.location.href = "/";
      return;
    }
    const params = new URLSearchParams(window.location.search);
    const tok = params.get("reset");
    if (tok) {
      const timer = window.setTimeout(() => { setResetToken(tok); setMode("reset"); }, 0);
      return () => window.clearTimeout(timer);
    }
  }, [router]);

  useEffect(() => {
    let queryIdx = 0;
    let charIdx = 0;
    let isDeleting = false;
    let timeout: ReturnType<typeof setTimeout>;

    function tick() {
      const currentQuery = TYPING_QUERIES[queryIdx];
      if (!isDeleting) {
        charIdx++;
        setTypedText(currentQuery.slice(0, charIdx));
        if (charIdx >= currentQuery.length) {
          isDeleting = true;
          timeout = setTimeout(tick, 2200);
          return;
        }
        timeout = setTimeout(tick, 45 + Math.random() * 35);
      } else {
        charIdx--;
        setTypedText(currentQuery.slice(0, charIdx));
        if (charIdx <= 0) {
          isDeleting = false;
          queryIdx = (queryIdx + 1) % TYPING_QUERIES.length;
          timeout = setTimeout(tick, 400);
          return;
        }
        timeout = setTimeout(tick, 20);
      }
    }
    timeout = setTimeout(tick, 1000);
    return () => clearTimeout(timeout);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const id = setInterval(() => {
      setActiveStep((s) => (s + 1) % PIPELINE_STEPS.length);
    }, 2000);
    return () => clearInterval(id);
  }, []);

  // Fluid background: liquid mesh + flow particles on the left, a slow faint
  // mesh behind the form so both halves read as one surface.
  useEffect(() => {
    if (!blobRef.current) return;

    // Phones drop the particle layer entirely (battery). Low-core desktops keep
    // it but with a smaller swarm, since core count under-reports on many machines.
    const cores = navigator.hardwareConcurrency || 4;
    const coarse = window.matchMedia("(hover: none)");
    const wide = window.matchMedia("(min-width: 900px)");
    const swarm = cores <= 4 ? 700 : 1400;

    let stopLeft: (() => void) | undefined;
    let stopRight: (() => void) | undefined;

    function build() {
      if (!blobRef.current) return;
      const light = !wide.matches || coarse.matches;

      stopLeft = startFluid({
        blobCanvas: blobRef.current,
        flowCanvas: light ? null : flowRef.current,
        pointerTarget: leftRef.current,
        blobs: light ? 4 : 6,
        particles: light ? 0 : swarm,
        speed: 1,
        blobAlpha: 0.78,
        flowAlpha: 0.22,
        seed: 20260829,
      });

      // below the breakpoint the right canvas is display:none, so skip it
      if (!light && rightBlobRef.current) {
        stopRight = startFluid({
          blobCanvas: rightBlobRef.current,
          flowCanvas: null,
          pointerTarget: rightRef.current,
          blobs: 3,
          particles: 0,
          speed: 0.4,
          blobAlpha: 0.5,
          seed: 77113,
        });
      }
    }

    function teardown() {
      stopLeft?.();
      stopRight?.();
      stopLeft = undefined;
      stopRight = undefined;
    }

    // rebuild on rotation or window resize across the breakpoint, so the tier
    // never stays stuck at whatever it was on first paint
    function rebuild() {
      teardown();
      build();
    }

    build();
    wide.addEventListener("change", rebuild);
    coarse.addEventListener("change", rebuild);

    return () => {
      wide.removeEventListener("change", rebuild);
      coarse.removeEventListener("change", rebuild);
      teardown();
    };
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await login(username, password);
      window.location.href = "/";
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : "Something went wrong";
      setError(message);
      setLoading(false);
    }
  }

  async function handleForgot(e: FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      const res = await fetch("/api/auth/forgot-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: forgotEmail }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: "Failed" }));
        throw new Error(err.detail || "Failed");
      }
      setForgotSent(true);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }

  async function handleReset(e: FormEvent) {
    e.preventDefault();
    setError("");
    if (newPassword !== newPasswordConfirm) {
      setError("Passwords do not match");
      return;
    }
    setLoading(true);
    try {
      const res = await fetch("/api/auth/reset-password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token: resetToken, new_password: newPassword }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: "Failed" }));
        throw new Error(err.detail || "Failed");
      }
      setSuccessMsg("Password berhasil direset. Silakan login.");
      setMode("login");
      setNewPassword("");
      setNewPasswordConfirm("");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-shell">
      <div className="login-left" ref={leftRef}>
        <canvas ref={blobRef} className="login-blob-canvas" />
        <canvas ref={flowRef} className="login-flow-canvas" />
        <div className="login-left-veil" />

        <div className="login-brand-content">
          <div className="login-logo-row login-rise" style={{ animationDelay: "0.05s" }}>
            <div className="login-logo-img-wrap">
              <Image
                src="/icon_circle_java.png"
                alt="IOH Java"
                width={64}
                height={64}
                priority
                className="login-logo-img"
              />
              <div className="login-logo-ring" />
            </div>
            <div>
              <div className="login-logo-name">Bizplan Java Agent</div>
              <div className="login-logo-sub">Business Planning Circle Java</div>
            </div>
          </div>

          <h1 className="login-headline login-rise" style={{ animationDelay: "0.14s" }}>
            Your data, <span className="red">answered</span> by AI agents.
          </h1>

          <p className="login-lede login-rise" style={{ animationDelay: "0.2s" }}>
            13 specialized AI agents analyze your business data across revenue, network,
            market share, forecast, and KPI domains, delivering insights in seconds.
          </p>

          {/* AI Typing Demo */}
          <div className="login-typing-demo login-rise" style={{ animationDelay: "0.26s" }}>
            <div className="login-typing-label">
              <span className="login-typing-dot" />
              AI Agent Processing
            </div>
            <div className="login-typing-query">
              <span className="login-typing-prompt">&gt;</span>
              <span className="login-typing-text">{typedText}</span>
              <span className="login-typing-cursor" />
            </div>
          </div>

          {/* Agent Pipeline Animation */}
          <div className="login-pipeline login-rise" style={{ animationDelay: "0.32s" }}>
            <div className="login-pipeline-label">Agent Pipeline</div>
            <div className="login-pipeline-steps">
              {PIPELINE_STEPS.map((step, i) => (
                <div key={step} className="login-pipeline-step-wrap">
                  <div className={`login-pipeline-step ${i === activeStep ? "active" : ""} ${i < activeStep ? "done" : ""}`}>
                    <div className="login-pipeline-step-dot" />
                    <span>{step}</span>
                  </div>
                  {i < PIPELINE_STEPS.length - 1 && (
                    <div className={`login-pipeline-connector ${i < activeStep ? "done" : ""}`} />
                  )}
                </div>
              ))}
            </div>
          </div>

          {/* Agent Capability Cards */}
          <div className="login-agents-grid login-rise" style={{ animationDelay: "0.38s" }}>
            {AGENT_CAPABILITIES.map((agent) => (
              <div key={agent.label} className="login-agent-card">
                <div className="login-agent-icon">{agent.icon}</div>
                <div>
                  <div className="login-agent-name">{agent.label}</div>
                  <div className="login-agent-desc">{agent.desc}</div>
                </div>
              </div>
            ))}
          </div>

          <div className="login-stats login-rise" style={{ animationDelay: "0.44s" }}>
            {LOGIN_STATS.map((s) => (
              <div key={s.label} className="login-stat">
                <div className="login-stat-num">{s.num}</div>
                <div className="login-stat-label">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
        <div className="login-footer-left">Confidential · Internal Use Only</div>
      </div>

      <div className="login-right" ref={rightRef}>
        <canvas ref={rightBlobRef} className="login-blob-canvas login-blob-canvas-right" />
        <div className="login-form-card">
          <div className="login-form-header">
            <div className="login-form-logo-wrap">
              <Image src="/icon_circle_java.png" alt="IOH" width={48} height={48} className="login-form-logo" />
            </div>
            <div className="login-form-eyebrow">
              {mode === "login" ? "Welcome Back" : mode === "forgot" ? "Password Recovery" : "New Password"}
            </div>
            <div className="login-form-title">
              {mode === "login" ? "Sign in to your account" : mode === "forgot" ? "Reset your password" : "Create new password"}
            </div>
          </div>

          {successMsg && (
            <div className="login-success">{successMsg}</div>
          )}

          {error && (
            <div className="login-error">
              <svg viewBox="0 0 16 16" width="14" height="14" fill="var(--ioh-danger)">
                <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 10.5a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM8.75 4.5v4a.75.75 0 0 1-1.5 0v-4a.75.75 0 0 1 1.5 0z"/>
              </svg>
              {error}
            </div>
          )}

          {mode === "login" && (
            <form onSubmit={handleSubmit} key="login" className="login-pane">
              <div className="login-field">
                <label className="login-label">Username</label>
                <div className="login-input-wrap">
                  <svg className="login-input-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <circle cx="10" cy="7" r="3.5" />
                    <path d="M3 17.5c0-3.5 3-5.5 7-5.5s7 2 7 5.5" strokeLinecap="round" />
                  </svg>
                  <input type="text" placeholder="Enter your username" value={username} onChange={(e) => setUsername(e.target.value)} required className="login-input" autoComplete="username" />
                </div>
              </div>
              <div className="login-field">
                <label className="login-label">Password</label>
                <div className="login-input-wrap">
                  <svg className="login-input-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <rect x="4" y="9" width="12" height="8" rx="2" />
                    <path d="M7 9V6a3 3 0 0 1 6 0v3" />
                    <circle cx="10" cy="13.5" r="1" fill="currentColor" stroke="none" />
                  </svg>
                  <input type="password" placeholder="Enter your password" value={password} onChange={(e) => setPassword(e.target.value)} required className="login-input" autoComplete="current-password" />
                </div>
              </div>
              <div className="login-forgot-link">
                <button type="button" onClick={() => { setMode("forgot"); setError(""); setSuccessMsg(""); }}>Forgot password?</button>
              </div>
              <button type="submit" disabled={loading} className="login-submit">
                {loading ? (<span className="login-submit-loading"><span className="login-spinner" />Signing in...</span>) : "Sign In"}
              </button>
            </form>
          )}

          {mode === "forgot" && !forgotSent && (
            <form onSubmit={handleForgot} key="forgot" className="login-pane">
              <div className="login-field">
                <label className="login-label">Email Address</label>
                <div className="login-input-wrap">
                  <svg className="login-input-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <rect x="2" y="4" width="16" height="12" rx="2" />
                    <path d="M2 6l8 5 8-5" />
                  </svg>
                  <input type="email" placeholder="Enter your registered email" value={forgotEmail} onChange={(e) => setForgotEmail(e.target.value)} required className="login-input" />
                </div>
              </div>
              <button type="submit" disabled={loading} className="login-submit">
                {loading ? (<span className="login-submit-loading"><span className="login-spinner" />Sending...</span>) : "Send Reset Link"}
              </button>
              <div className="login-back-link">
                <button type="button" onClick={() => { setMode("login"); setError(""); }}>Back to login</button>
              </div>
            </form>
          )}

          {mode === "forgot" && forgotSent && (
            <div className="login-sent-msg login-pane">
              <div className="login-sent-icon">
                <svg viewBox="0 0 24 24" width="40" height="40" fill="none" stroke="var(--ioh-teal)" strokeWidth="2">
                  <path d="M22 2L11 13" strokeLinecap="round" />
                  <path d="M22 2L15 22L11 13L2 9L22 2Z" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              </div>
              <p>Jika email terdaftar, link reset password telah dikirim ke <strong>{forgotEmail}</strong>. Cek inbox atau folder spam.</p>
              <p className="login-sent-sub">Link berlaku 30 menit.</p>
              <button type="button" className="login-submit" onClick={() => { setMode("login"); setForgotSent(false); setError(""); }}>Back to Login</button>
            </div>
          )}

          {mode === "reset" && (
            <form onSubmit={handleReset} key="reset" className="login-pane">
              <div className="login-field">
                <label className="login-label">New Password</label>
                <div className="login-input-wrap">
                  <svg className="login-input-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <rect x="4" y="9" width="12" height="8" rx="2" />
                    <path d="M7 9V6a3 3 0 0 1 6 0v3" />
                    <circle cx="10" cy="13.5" r="1" fill="currentColor" stroke="none" />
                  </svg>
                  <input type="password" placeholder="Min 6 characters" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} required minLength={6} className="login-input" />
                </div>
              </div>
              <div className="login-field">
                <label className="login-label">Confirm New Password</label>
                <div className="login-input-wrap">
                  <svg className="login-input-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5">
                    <rect x="4" y="9" width="12" height="8" rx="2" />
                    <path d="M7 9V6a3 3 0 0 1 6 0v3" />
                    <circle cx="10" cy="13.5" r="1" fill="currentColor" stroke="none" />
                  </svg>
                  <input type="password" placeholder="Re-enter new password" value={newPasswordConfirm} onChange={(e) => setNewPasswordConfirm(e.target.value)} required minLength={6} className="login-input" />
                </div>
              </div>
              <button type="submit" disabled={loading} className="login-submit">
                {loading ? (<span className="login-submit-loading"><span className="login-spinner" />Resetting...</span>) : "Reset Password"}
              </button>
            </form>
          )}

          <div className="login-form-footer">
            Need an account?{" "}
            <span className="login-contact-admin">Contact your administrator</span>
          </div>
        </div>
      </div>
    </div>
  );
}
