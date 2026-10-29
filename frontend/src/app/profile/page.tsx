"use client";
import { useEffect, useState, FormEvent } from "react";
import { useRouter } from "next/navigation";
import { UserRound } from "lucide-react";
import AppShell from "../components/shell/AppShell";
import PageHero from "../components/ui/PageHero";
import { authFetch, getUser, isLoggedIn, UserInfo } from "@/lib/auth";

const IOH = {
  red: "#15A697", pink: "#0E8579", yellow: "#F5A623", teal: "#15A697",
  magenta: "#0A6A5F", ink: "#0F1F1D", mute: "#5A6B68", rule: "#E1E9E7",
  panel: "#F5F9F8", white: "#FFFFFF", danger: "#E13838",
} as const;

export default function ProfilePage() {
  const router = useRouter();
  const [user, setUser] = useState<UserInfo | null>(null);
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [department, setDepartment] = useState("");
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");
  const [oldPw, setOldPw] = useState("");
  const [newPw, setNewPw] = useState("");
  const [newPw2, setNewPw2] = useState("");
  const [pwMsg, setPwMsg] = useState("");
  const [pwErr, setPwErr] = useState("");
  const [pwSaving, setPwSaving] = useState(false);
  const [notifications, setNotifications] = useState<{id:number;title:string;message:string;kind:string;is_read:boolean;created_at:string|null}[]>([]);
  const [unreadCount, setUnreadCount] = useState(0);

  useEffect(() => {
    if (typeof window !== "undefined" && !isLoggedIn()) {
      router.push("/login");
      return;
    }
    loadProfile();
    loadNotifications();
  }, [router]);

  async function loadProfile() {
    const res = await authFetch("/api/auth/me");
    if (res.ok) {
      const u = await res.json();
      setUser(u);
      setFullName(u.full_name || "");
      setEmail(u.email || "");
      setDepartment(u.department || "");
    }
  }

  async function loadNotifications() {
    const res = await authFetch("/api/auth/me/notifications?limit=20");
    if (res.ok) {
      const data = await res.json();
      setNotifications(data.notifications || []);
      setUnreadCount(data.unread_count || 0);
    }
  }

  async function handleSave(e: FormEvent) {
    e.preventDefault();
    setErr(""); setMsg("");
    if (!email || !email.includes("@")) {
      setErr("Email wajib diisi dengan format yang valid");
      return;
    }
    setSaving(true);
    try {
      const res = await authFetch("/api/auth/me/profile", {
        method: "PUT",
        body: JSON.stringify({ full_name: fullName, email, department }),
      });
      if (!res.ok) {
        const e = await res.json().catch(() => ({ detail: "Failed" }));
        throw new Error(e.detail || "Failed");
      }
      const updated = await res.json();
      setUser(updated);
      const stored = getUser();
      if (stored) {
        localStorage.setItem("user", JSON.stringify({ ...stored, ...updated }));
      }
      setMsg("Profile berhasil diupdate");
    } catch (e: unknown) {
      setErr(e instanceof Error ? e.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  async function handleChangePw(e: FormEvent) {
    e.preventDefault();
    setPwErr(""); setPwMsg("");
    if (newPw !== newPw2) { setPwErr("Password baru tidak cocok"); return; }
    setPwSaving(true);
    try {
      const res = await authFetch("/api/auth/me/password", {
        method: "PUT",
        body: JSON.stringify({ old_password: oldPw, new_password: newPw }),
      });
      if (!res.ok) {
        const e = await res.json().catch(() => ({ detail: "Failed" }));
        throw new Error(e.detail || "Failed");
      }
      setPwMsg("Password berhasil diubah");
      setOldPw(""); setNewPw(""); setNewPw2("");
    } catch (e: unknown) {
      setPwErr(e instanceof Error ? e.message : "Failed");
    } finally {
      setPwSaving(false);
    }
  }

  async function markAllRead() {
    await authFetch("/api/auth/me/notifications/read-all", { method: "PUT" });
    loadNotifications();
  }

  if (!user) return <div style={{ minHeight: "100vh", display: "flex", alignItems: "center", justifyContent: "center", background: IOH.panel, color: IOH.mute }}>Loading...</div>;

  const needsEmail = !user.email || !user.email.includes("@") || user.email === `${user.username}@ioh.co.id`;

  return (
    <AppShell>
    <div className="ui-page">
      <PageHero icon={<UserRound size={30} strokeWidth={1.6} />} eyebrow="Akun" title="Profil saya" sub="Informasi akun, password dan notifikasi." pattern />

      <div style={{ width: "100%", maxWidth: 800 }}>
        {needsEmail && (
          <div style={{
            padding: "16px 20px", borderRadius: 12, marginBottom: 24,
            background: "#FDF3E2", border: "1px solid rgba(255,203,5,0.3)",
            borderLeft: `4px solid ${IOH.yellow}`,
            fontFamily: "var(--font-sans)", fontSize: 14, color: IOH.ink, lineHeight: 1.5,
          }}>
            <strong style={{ fontFamily: "var(--font-display)" }}>Email belum diatur.</strong> Harap isi email yang valid untuk menerima notifikasi, reset password, dan summary AI.
          </div>
        )}

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 24 }}>
          <div style={cardStyle}>
            <h3 style={cardTitle}>Account Information</h3>
            <form onSubmit={handleSave}>
              <div style={fieldStyle}>
                <label style={labelStyle}>Username</label>
                <input value={user.username} disabled style={{ ...inputStyle, background: IOH.panel, color: IOH.mute }} />
              </div>
              <div style={fieldStyle}>
                <label style={labelStyle}>Full Name</label>
                <input value={fullName} onChange={e => setFullName(e.target.value)} style={inputStyle} placeholder="Nama lengkap" />
              </div>
              <div style={fieldStyle}>
                <label style={{ ...labelStyle, color: needsEmail ? IOH.red : IOH.ink }}>Email {needsEmail && "*"}</label>
                <input type="email" value={email} onChange={e => setEmail(e.target.value)} required style={{ ...inputStyle, borderColor: needsEmail ? IOH.red : IOH.rule }} placeholder="email@company.com" />
              </div>
              <div style={fieldStyle}>
                <label style={labelStyle}>Department</label>
                <input value={department} onChange={e => setDepartment(e.target.value)} style={inputStyle} placeholder="Optional" />
              </div>
              {err && <div style={{ color: IOH.red, fontSize: 13, marginBottom: 12 }}>{err}</div>}
              {msg && <div style={{ color: IOH.teal, fontSize: 13, marginBottom: 12 }}>{msg}</div>}
              <button type="submit" disabled={saving} style={submitBtn}>{saving ? "Saving..." : "Save Profile"}</button>
            </form>
          </div>

          <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
            <div style={cardStyle}>
              <h3 style={cardTitle}>Change Password</h3>
              <form onSubmit={handleChangePw}>
                <div style={fieldStyle}>
                  <label style={labelStyle}>Current Password</label>
                  <input type="password" value={oldPw} onChange={e => setOldPw(e.target.value)} required style={inputStyle} />
                </div>
                <div style={fieldStyle}>
                  <label style={labelStyle}>New Password</label>
                  <input type="password" value={newPw} onChange={e => setNewPw(e.target.value)} required minLength={6} style={inputStyle} />
                </div>
                <div style={fieldStyle}>
                  <label style={labelStyle}>Confirm Password</label>
                  <input type="password" value={newPw2} onChange={e => setNewPw2(e.target.value)} required minLength={6} style={inputStyle} />
                </div>
                {pwErr && <div style={{ color: IOH.red, fontSize: 13, marginBottom: 12 }}>{pwErr}</div>}
                {pwMsg && <div style={{ color: IOH.teal, fontSize: 13, marginBottom: 12 }}>{pwMsg}</div>}
                <button type="submit" disabled={pwSaving} style={{ ...submitBtn, background: IOH.ink }}>{pwSaving ? "..." : "Change Password"}</button>
              </form>
            </div>

            <div style={cardStyle}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
                <h3 style={{ ...cardTitle, marginBottom: 0 }}>Notifications {unreadCount > 0 && <span style={{ fontFamily: "var(--font-display)", fontSize: 11, padding: "2px 8px", borderRadius: 999, background: IOH.red, color: IOH.white, marginLeft: 8 }}>{unreadCount}</span>}</h3>
                {unreadCount > 0 && <button onClick={markAllRead} style={{ background: "none", border: "none", color: IOH.red, fontSize: 12, fontWeight: 600, cursor: "pointer" }}>Mark all read</button>}
              </div>
              <div style={{ maxHeight: 280, overflowY: "auto" }}>
                {notifications.length === 0 && <div style={{ color: IOH.mute, fontSize: 13, textAlign: "center", padding: 20 }}>No notifications</div>}
                {notifications.map(n => (
                  <div key={n.id} style={{
                    padding: "10px 12px", borderBottom: `1px solid ${IOH.rule}`,
                    background: n.is_read ? "transparent" : "rgba(21, 166, 151,0.03)",
                    borderLeft: n.is_read ? "3px solid transparent" : `3px solid ${IOH.red}`,
                  }}>
                    <div style={{ fontSize: 13, fontWeight: n.is_read ? 400 : 700, color: IOH.ink }}>{n.title}</div>
                    <div style={{ fontSize: 12, color: IOH.mute, marginTop: 2 }}>{n.message.slice(0, 100)}</div>
                    {n.created_at && <div style={{ fontSize: 10, color: IOH.mute, marginTop: 4, fontVariantNumeric: "tabular-nums" }}>{new Date(n.created_at).toLocaleString()}</div>}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        <div style={{ ...cardStyle, marginTop: 24 }}>
          <h3 style={cardTitle}>Account Details</h3>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16 }}>
            <div style={statBox}><div style={statNum}>{user.login_count}</div><div style={statLabel}>Total Logins</div></div>
            <div style={statBox}><div style={statNum}>{user.role}</div><div style={statLabel}>Role</div></div>
            <div style={statBox}><div style={{ ...statNum, color: user.is_active ? IOH.teal : IOH.red }}>{user.is_active ? "Active" : "Inactive"}</div><div style={statLabel}>Status</div></div>
            <div style={statBox}><div style={{ ...statNum, fontSize: 14 }}>{user.last_login ? new Date(user.last_login).toLocaleString() : "-"}</div><div style={statLabel}>Last Login</div></div>
          </div>
        </div>
      </div>
    </div>
    </AppShell>
  );
}

const cardStyle: React.CSSProperties = { background: "#FFFFFF", border: "1px solid #E1E9E7", borderRadius: 16, padding: 28, boxShadow: "0 2px 6px rgba(45,41,38,.04)" };
const cardTitle: React.CSSProperties = { fontFamily: "var(--font-display)", fontSize: 17, fontWeight: 700, color: "#0F1F1D", marginTop: 0, marginBottom: 18 };
const fieldStyle: React.CSSProperties = { marginBottom: 18 };
const labelStyle: React.CSSProperties = { display: "block", fontFamily: "var(--font-display)", fontSize: 12, fontWeight: 600, color: "#0F1F1D", marginBottom: 6 };
const inputStyle: React.CSSProperties = { width: "100%", padding: "11px 14px", borderRadius: 10, border: "1.5px solid #E1E9E7", background: "#FFFFFF", color: "#0F1F1D", fontSize: 14, outline: "none", boxSizing: "border-box" };
const submitBtn: React.CSSProperties = { width: "100%", padding: "13px 0", borderRadius: 10, border: "none", cursor: "pointer", fontFamily: "var(--font-display)", fontSize: 14, fontWeight: 700, background: "#15A697", color: "#FFFFFF", boxShadow: "0 3px 12px rgba(21, 166, 151,0.2)" };
const statBox: React.CSSProperties = { padding: "16px", borderRadius: 12, background: "#F5F9F8", border: "1px solid #E1E9E7", textAlign: "center" };
const statNum: React.CSSProperties = { fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 800, color: "#0F1F1D", fontVariantNumeric: "tabular-nums" };
const statLabel: React.CSSProperties = { fontFamily: "var(--font-display)", fontSize: 10, fontWeight: 700, color: "#5A6B68", textTransform: "uppercase", letterSpacing: "0.06em", marginTop: 4 };
