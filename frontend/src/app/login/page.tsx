"use client";
import { useState, FormEvent, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { login, isLoggedIn } from "@/lib/auth";

const AGENT_CAPABILITIES = [
  { icon: "SQL", label: "SQL Writer", desc: "Auto-generates optimized BigQuery" },
  { icon: "BQ", label: "BigQuery", desc: "2.56B rows across 118 tables" },
  { icon: "AN", label: "Analyst", desc: "Intent analysis & validation" },
  { icon: "EX", label: "Export", desc: "XLSX & PDF branded reports" },
];

const PIPELINE_STEPS = [
  "Analyst Agent",
  "Orchestrator",
  "Domain Agent",
  "SQL Writer",
  "BigQuery",
  "Synthesizer",
];

export default function LoginPage() {
  const router = useRouter();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);
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
    "Forecast revenue micro-cluster bulan depan...",
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
      setResetToken(tok);
      setMode("reset");
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

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let animId: number;
    let w = 0;
    let h = 0;

    function resize() {
      if (!canvas) return;
      const rect = canvas.parentElement?.getBoundingClientRect();
      if (!rect) return;
      const dpr = window.devicePixelRatio || 1;
      w = rect.width * dpr;
      h = rect.height * dpr;
      canvas.width = w;
      canvas.height = h;
      canvas.style.width = rect.width + "px";
      canvas.style.height = rect.height + "px";
      if (ctx) ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    resize();
    window.addEventListener("resize", resize);

    const COLORS = ["#15A697", "#0E8579", "#F5A623", "#33BCAD", "#0A6A5F"];

    interface Particle {
      x: number; y: number;
      vx: number; vy: number;
      r: number; color: string;
      alpha: number; pulse: number; pulseSpeed: number;
      isNode: boolean;
    }

    const realW = () => w / (window.devicePixelRatio || 1);
    const realH = () => h / (window.devicePixelRatio || 1);

    const particles: Particle[] = [];
    const NUM = 80;
    for (let i = 0; i < NUM; i++) {
      const isNode = i < 12;
      particles.push({
        x: Math.random() * 1200,
        y: Math.random() * 1200,
        vx: (Math.random() - 0.5) * (isNode ? 0.25 : 0.5),
        vy: (Math.random() - 0.5) * (isNode ? 0.25 : 0.5),
        r: isNode ? (Math.random() * 3 + 3) : (Math.random() * 2 + 0.8),
        color: COLORS[Math.floor(Math.random() * COLORS.length)],
        alpha: isNode ? (Math.random() * 0.3 + 0.4) : (Math.random() * 0.3 + 0.1),
        pulse: Math.random() * Math.PI * 2,
        pulseSpeed: Math.random() * 0.02 + 0.005,
        isNode,
      });
    }

    function hexToRgb(hex: string) {
      const r = parseInt(hex.slice(1, 3), 16);
      const g = parseInt(hex.slice(3, 5), 16);
      const b = parseInt(hex.slice(5, 7), 16);
      return { r, g, b };
    }

    function draw(t: number) {
      if (!ctx) return;
      const rw = realW();
      const rh = realH();
      ctx.clearRect(0, 0, rw, rh);

      const cx = rw * 0.48;
      const cy = rh * 0.42;
      const maxR = Math.min(rw, rh) * 0.32;

      for (let ri = 0; ri < 4; ri++) {
        const rr = maxR * (0.3 + ri * 0.25);
        const rot = t * 0.00025 * (ri % 2 === 0 ? 1 : -1);
        const segments = 80;
        ctx.beginPath();
        for (let s = 0; s <= segments; s++) {
          const angle = (s / segments) * Math.PI * 2 + rot;
          const wobble = Math.sin(angle * 4 + t * 0.0008 + ri) * rr * 0.04;
          const px = cx + Math.cos(angle) * (rr + wobble);
          const py = cy + Math.sin(angle) * (rr + wobble);
          if (s === 0) ctx.moveTo(px, py);
          else ctx.lineTo(px, py);
        }
        ctx.closePath();
        const c = COLORS[ri % COLORS.length];
        const { r, g, b } = hexToRgb(c);
        ctx.strokeStyle = `rgba(${r},${g},${b},0.15)`;
        ctx.lineWidth = 1;
        ctx.stroke();

        const dashes = 8;
        for (let d = 0; d < dashes; d++) {
          const a = ((d / dashes) * Math.PI * 2) + rot * 3 + t * 0.0005;
          const dr = rr + Math.sin(a * 3 + t * 0.001) * rr * 0.04;
          const dx = cx + Math.cos(a) * dr;
          const dy = cy + Math.sin(a) * dr;
          ctx.beginPath();
          ctx.arc(dx, dy, 1.5, 0, Math.PI * 2);
          ctx.fillStyle = `rgba(${r},${g},${b},0.25)`;
          ctx.fill();
        }
      }

      const CONNECTION_DIST = Math.min(rw, rh) * 0.18;
      for (const p of particles) {
        p.x += p.vx;
        p.y += p.vy;
        p.pulse += p.pulseSpeed;
        if (p.x < -20) p.x = rw + 20;
        if (p.x > rw + 20) p.x = -20;
        if (p.y < -20) p.y = rh + 20;
        if (p.y > rh + 20) p.y = -20;
      }

      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const dx = particles[i].x - particles[j].x;
          const dy = particles[i].y - particles[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < CONNECTION_DIST) {
            const a = (1 - dist / CONNECTION_DIST);
            const bothNodes = particles[i].isNode && particles[j].isNode;
            const opacity = bothNodes ? a * 0.2 : a * 0.07;
            const { r, g, b } = hexToRgb(particles[i].color);
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.strokeStyle = `rgba(${r},${g},${b},${opacity})`;
            ctx.lineWidth = bothNodes ? 1.2 : 0.5;
            ctx.stroke();

            if (bothNodes && dist < CONNECTION_DIST * 0.6) {
              const progress = ((t * 0.001 + i * 0.3) % 1);
              const bx = particles[i].x + (particles[j].x - particles[i].x) * progress;
              const by = particles[i].y + (particles[j].y - particles[i].y) * progress;
              ctx.beginPath();
              ctx.arc(bx, by, 1.5, 0, Math.PI * 2);
              ctx.fillStyle = `rgba(${r},${g},${b},${0.4 * a})`;
              ctx.fill();
            }
          }
        }
      }

      for (const p of particles) {
        const pulseR = p.r * (1 + Math.sin(p.pulse) * 0.25);
        const { r, g, b } = hexToRgb(p.color);

        if (p.isNode) {
          ctx.beginPath();
          ctx.arc(p.x, p.y, pulseR * 3, 0, Math.PI * 2);
          ctx.fillStyle = `rgba(${r},${g},${b},0.04)`;
          ctx.fill();

          ctx.beginPath();
          ctx.arc(p.x, p.y, pulseR * 1.8, 0, Math.PI * 2);
          ctx.fillStyle = `rgba(${r},${g},${b},0.08)`;
          ctx.fill();
        }

        ctx.beginPath();
        ctx.arc(p.x, p.y, pulseR, 0, Math.PI * 2);
        ctx.fillStyle = `rgba(${r},${g},${b},${p.alpha + Math.sin(p.pulse) * 0.1})`;
        ctx.fill();
      }

      const scanPeriod = 6000;
      const scanProgress = (t % scanPeriod) / scanPeriod;
      const scanY = rh * scanProgress;
      const scanGrad = ctx.createLinearGradient(0, scanY - 30, 0, scanY + 30);
      scanGrad.addColorStop(0, "rgba(21, 166, 151,0)");
      scanGrad.addColorStop(0.5, "rgba(21, 166, 151,0.03)");
      scanGrad.addColorStop(1, "rgba(21, 166, 151,0)");
      ctx.fillStyle = scanGrad;
      ctx.fillRect(0, scanY - 30, rw, 60);

      const pulseAlpha = (Math.sin(t * 0.002) * 0.5 + 0.5) * 0.06;
      const centerGrad = ctx.createRadialGradient(cx, cy, 0, cx, cy, maxR * 1.2);
      centerGrad.addColorStop(0, `rgba(21, 166, 151,${pulseAlpha})`);
      centerGrad.addColorStop(0.5, `rgba(236,0,140,${pulseAlpha * 0.5})`);
      centerGrad.addColorStop(1, "rgba(21, 166, 151,0)");
      ctx.fillStyle = centerGrad;
      ctx.fillRect(0, 0, rw, rh);

      animId = requestAnimationFrame(draw);
    }

    animId = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(animId);
      window.removeEventListener("resize", resize);
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
      <div className="login-left">
        <canvas ref={canvasRef} className="login-canvas" />

        <div className="login-brand-content">
          <div className="login-logo-row">
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

          <h1 className="login-headline">
            Your data, <span className="red">answered</span> by AI agents.
          </h1>

          <p className="login-lede">
            13 specialized AI agents analyze your BigQuery data across revenue, network, market share, forecast, and KPI domains — delivering insights in seconds.
          </p>

          {/* AI Typing Demo */}
          <div className="login-typing-demo">
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
          <div className="login-pipeline">
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
          <div className="login-agents-grid">
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

          <div className="login-stats">
            {[
              { num: "13", label: "Agents" },
              { num: "118", label: "Tables" },
              { num: "2.56B", label: "Rows" },
              { num: "~15s", label: "Avg Query" },
            ].map((s) => (
              <div key={s.label} className="login-stat">
                <div className="login-stat-num">{s.num}</div>
                <div className="login-stat-label">{s.label}</div>
              </div>
            ))}
          </div>
        </div>
        <div className="login-footer-left">Confidential · Internal Use Only</div>
      </div>

      <div className="login-right">
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
              <svg viewBox="0 0 16 16" width="14" height="14" fill="var(--ioh-red)">
                <path d="M8 1a7 7 0 1 0 0 14A7 7 0 0 0 8 1zm0 10.5a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5zM8.75 4.5v4a.75.75 0 0 1-1.5 0v-4a.75.75 0 0 1 1.5 0z"/>
              </svg>
              {error}
            </div>
          )}

          {mode === "login" && (
            <form onSubmit={handleSubmit}>
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
            <form onSubmit={handleForgot}>
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
            <div className="login-sent-msg">
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
            <form onSubmit={handleReset}>
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
