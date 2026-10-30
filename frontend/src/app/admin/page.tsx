"use client";
import { useEffect, useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { Users } from "lucide-react";
import AppShell from "../components/shell/AppShell";
import PageHero from "../components/ui/PageHero";
import { authFetch, getUser, isAdmin, isLoggedIn, UserInfo } from "@/lib/auth";

interface Stats {
  total_users: number;
  active_users: number;
  new_users_7d: number;
  total_sessions: number;
  total_messages: number;
  today_logins: number;
  today_queries: number;
  top_users: { username: string; full_name: string; query_count: number }[];
  domain_distribution: { domain: string; count: number }[];
  daily_activity: { date: string; logins: number; queries: number }[];
}

interface UserDetail extends UserInfo {
  total_sessions: number;
  total_messages: number;
  recent_sessions: { session_id: string; title: string; message_count: number; updated_at: string }[];
}

interface UserActivity {
  user: UserInfo;
  total_queries: number;
  avg_latency_ms: number | null;
  daily_activity: { date: string; queries: number }[];
  domain_breakdown: { domain: string; count: number }[];
  qa_pairs: {
    session_id: string;
    question: string;
    answer: string | null;
    domain: string | null;
    sql_query: string | null;
    row_count: number | null;
    latency_ms: number | null;
    asked_at: string | null;
  }[];
}

interface HistoryItem {
  session_id: string;
  title: string;
  username: string;
  full_name: string;
  message_count: number;
  created_at: string;
  updated_at: string;
}

interface SessionMessages {
  session_id: string;
  title: string;
  messages: {
    role: string;
    content: string;
    domain: string | null;
    sql_query: string | null;
    row_count: number | null;
    latency_ms: number | null;
    created_at: string;
  }[];
}

type Tab = "overview" | "users" | "history";

export default function AdminPage() {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>("overview");
  const [stats, setStats] = useState<Stats | null>(null);
  const [users, setUsers] = useState<UserInfo[]>([]);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [selectedUser, setSelectedUser] = useState<UserDetail | null>(null);
  const [selectedSession, setSelectedSession] = useState<SessionMessages | null>(null);
  const [userActivity, setUserActivity] = useState<UserActivity | null>(null);
  const [loading, setLoading] = useState(true);
  const [qaExpanded, setQaExpanded] = useState<Record<number, boolean>>({});

  const loadData = useCallback(async () => {
    setLoading(true);
    try {
      if (tab === "overview") {
        const res = await authFetch("/api/admin/stats");
        if (res.ok) setStats(await res.json());
      } else if (tab === "users") {
        const res = await authFetch("/api/admin/users");
        if (res.ok) setUsers(await res.json());
      } else if (tab === "history") {
        const res = await authFetch("/api/admin/history?limit=100");
        if (res.ok) setHistory(await res.json());
      }
    } catch (e) { console.error(e); }
    setLoading(false);
  }, [tab]);

  useEffect(() => {
    if (!isLoggedIn()) { router.push("/login"); return; }
    if (!isAdmin()) { router.push("/"); return; }
    const t = setTimeout(loadData, 0);
    return () => clearTimeout(t);
  }, [loadData, router]);

  async function loadUserDetail(userId: number) {
    const [detailRes, activityRes] = await Promise.all([
      authFetch(`/api/admin/users/${userId}`),
      authFetch(`/api/admin/users/${userId}/activity`),
    ]);
    if (detailRes.ok) setSelectedUser(await detailRes.json());
    if (activityRes.ok) setUserActivity(await activityRes.json());
    setQaExpanded({});
  }

  async function loadSessionDetail(sessionId: string) {
    const res = await authFetch(`/api/history/sessions/${sessionId}`);
    if (res.ok) setSelectedSession(await res.json());
  }

  async function toggleUserActive(userId: number, isActive: boolean) {
    await authFetch(`/api/admin/users/${userId}`, {
      method: "PUT",
      body: JSON.stringify({ is_active: !isActive }),
    });
    loadData();
  }

  async function changeUserRole(userId: number, newRole: string) {
    await authFetch(`/api/admin/users/${userId}`, {
      method: "PUT",
      body: JSON.stringify({ role: newRole }),
    });
    loadData();
  }

  async function deleteUser(userId: number, username: string) {
    if (!confirm(`Delete user "${username}"? All their sessions and messages will be permanently removed.`)) return;
    const res = await authFetch(`/api/admin/users/${userId}`, { method: "DELETE" });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: "Failed" }));
      alert(err.detail || "Failed to delete user");
      return;
    }
    loadData();
  }

  const me = getUser();

  return (
    <AppShell>
    <div className="ui-page wide">
      <PageHero icon={<Users size={30} strokeWidth={1.6} />} eyebrow="Admin" title="Kelola pengguna" sub={`Masuk sebagai ${me?.full_name || me?.username || "admin"}`} />

      {/* Tabs */}
      <div style={{
        display: "flex", gap: 0,
        borderBottom: `1px solid ${IOH.rule}`,
        padding: "0 12px", borderRadius: 16, border: `1px solid ${IOH.rule}`,
        background: IOH.white,
      }}>
        {(["overview", "users", "history"] as Tab[]).map((t) => (
          <button
            key={t}
            onClick={() => { setTab(t); setSelectedUser(null); setSelectedSession(null); }}
            style={{
              padding: "14px 28px",
              border: "none",
              borderBottom: tab === t ? `3px solid ${IOH.red}` : "3px solid transparent",
              background: "transparent",
              color: tab === t ? IOH.ink : IOH.mute,
              cursor: "pointer",
              fontFamily: "var(--font-display)",
              fontSize: 14,
              fontWeight: tab === t ? 700 : 500,
              textTransform: "capitalize",
              transition: "color 0.15s, border-color 0.15s",
              letterSpacing: "0.01em",
            }}
          >
            {t === "overview" ? "Overview" : t === "users" ? "Users" : "History"}
          </button>
        ))}
      </div>

      {/* Content */}
      <div style={{ padding: "28px 32px", maxWidth: 1280, margin: "0 auto" }}>
        {loading && <div style={{ color: IOH.mute, padding: 40, textAlign: "center", fontFamily: "var(--font-display)", fontWeight: 500, fontSize: 14 }}>Loading...</div>}

        {/* -- Overview Tab -- */}
        {!loading && tab === "overview" && stats && (
          <div>
            <div style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))",
              gap: 16, marginBottom: 32,
            }}>
              <StatCard label="Total Users" value={stats.total_users} color={IOH.red} />
              <StatCard label="Active Users" value={stats.active_users} color={IOH.teal} />
              <StatCard label="New (7d)" value={stats.new_users_7d} color={IOH.pink} />
              <StatCard label="Total Sessions" value={stats.total_sessions} color={IOH.magenta} />
              <StatCard label="Total Messages" value={stats.total_messages} color={IOH.yellow} />
              <StatCard label="Logins Today" value={stats.today_logins} color={IOH.teal} />
              <StatCard label="Queries Today" value={stats.today_queries} color={IOH.red} />
            </div>

            {/* Daily Activity Chart */}
            {stats.daily_activity && stats.daily_activity.length > 0 && (
              <div style={{ ...cardStyle, marginBottom: 24 }}>
                <h3 style={cardTitle}>Daily Activity (30 Days)</h3>
                <ActivityChart data={stats.daily_activity} />
              </div>
            )}

            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 24 }}>
              {/* Top Users */}
              <div style={cardStyle}>
                <h3 style={cardTitle}>Top Users by Queries</h3>
                {stats.top_users.length === 0 && <div style={{ color: IOH.mute }}>No data yet</div>}
                {stats.top_users.map((u, i) => (
                  <div key={i} style={{
                    display: "flex", justifyContent: "space-between",
                    padding: "8px 0",
                    borderBottom: `1px solid ${IOH.rule}`,
                  }}>
                    <span style={{ color: IOH.ink }}>{u.full_name || u.username}</span>
                    <span style={badgeStyle}>{u.query_count}</span>
                  </div>
                ))}
              </div>

              {/* Domain Distribution */}
              <div style={cardStyle}>
                <h3 style={cardTitle}>Domain Distribution</h3>
                {stats.domain_distribution.length === 0 && <div style={{ color: IOH.mute }}>No data yet</div>}
                {stats.domain_distribution.map((d, i) => (
                  <div key={i} style={{
                    display: "flex", justifyContent: "space-between",
                    padding: "8px 0",
                    borderBottom: `1px solid ${IOH.rule}`,
                  }}>
                    <span style={{ textTransform: "capitalize", color: IOH.ink }}>{d.domain}</span>
                    <span style={badgeStyle}>{d.count}</span>
                  </div>
                ))}
              </div>
            </div>

            {/* Notification Sender */}
            <NotifSender />
          </div>
        )}

        {/* -- Users Tab -- */}
        {!loading && tab === "users" && !selectedUser && (
          <div>
            {/* Create User Form */}
            <CreateUserForm onCreated={loadData} />

            <div style={{ ...cardStyle, marginTop: 16 }}>
            <h3 style={cardTitle}>All Users ({users.length})</h3>
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ borderBottom: `1px solid ${IOH.rule}` }}>
                  {["ID", "Username", "Full Name", "Email", "Role", "Status", "Logins", "Last Login", "Actions"].map((h) => (
                    <th key={h} style={thStyle}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.id} style={{ borderBottom: `1px solid ${IOH.rule}` }}>
                    <td style={tdStyle}>{u.id}</td>
                    <td style={tdStyle}>
                      <button onClick={() => loadUserDetail(u.id)} style={linkBtn}>
                        {u.username}
                      </button>
                    </td>
                    <td style={tdStyle}>{u.full_name}</td>
                    <td style={tdStyle}>{u.email}</td>
                    <td style={tdStyle}>
                      <span style={{
                        ...badgeStyle,
                        background: u.role === "admin" ? IOH.yellow : IOH.rule,
                        color: u.role === "admin" ? IOH.ink : "#5A6B68",
                      }}>{u.role}</span>
                    </td>
                    <td style={tdStyle}>
                      <span style={{
                        ...badgeStyle,
                        background: u.is_active ? IOH.teal : IOH.red,
                        color: IOH.white,
                      }}>{u.is_active ? "Active" : "Inactive"}</span>
                    </td>
                    <td style={{ ...tdStyle, fontVariantNumeric: "tabular-nums" }}>{u.login_count}</td>
                    <td style={{ ...tdStyle, fontVariantNumeric: "tabular-nums" }}>{u.last_login ? new Date(u.last_login).toLocaleString() : "\u2014"}</td>
                    <td style={tdStyle}>
                      <div style={{ display: "flex", gap: 6 }}>
                        <button
                          onClick={() => toggleUserActive(u.id, u.is_active)}
                          style={{
                            ...smallBtn,
                            borderColor: u.is_active ? IOH.red : IOH.teal,
                            color: u.is_active ? IOH.red : IOH.teal,
                          }}
                        >
                          {u.is_active ? "Deactivate" : "Activate"}
                        </button>
                        <select
                          value={u.role}
                          onChange={(e) => changeUserRole(u.id, e.target.value)}
                          style={{ ...smallBtn, borderColor: IOH.yellow, color: "#8B6914", padding: "3px 4px", fontSize: 10, cursor: "pointer" }}
                        >
                          <option value="end_user">End User</option>
                          <option value="data_user">Data User</option>
                          <option value="analyst">Analyst</option>
                          <option value="admin">Admin</option>
                        </select>
                        <button
                          onClick={() => deleteUser(u.id, u.username)}
                          style={{ ...smallBtn, borderColor: "#ccc", color: IOH.mute }}
                        >
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          </div>
        )}

        {/* User Detail */}
        {!loading && tab === "users" && selectedUser && (
          <div>
            <button onClick={() => { setSelectedUser(null); setUserActivity(null); }} style={navBtn}>Back to Users</button>

            {/* User header + stats */}
            <div style={{ ...cardStyle, marginTop: 16 }}>
              <h3 style={cardTitle}>
                {selectedUser.full_name || selectedUser.username}
                <span style={{
                  ...badgeStyle, marginLeft: 8,
                  background: selectedUser.role === "admin" ? IOH.yellow : IOH.rule,
                  color: selectedUser.role === "admin" ? IOH.ink : "#5A6B68",
                }}>{selectedUser.role}</span>
                {selectedUser.email && (
                  <span style={{ fontSize: 13, color: IOH.mute, marginLeft: 12, fontWeight: 400 }}>{selectedUser.email}</span>
                )}
              </h3>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 14, margin: "16px 0" }}>
                <StatCard label="Sessions" value={selectedUser.total_sessions} color={IOH.magenta} />
                <StatCard label="Messages" value={selectedUser.total_messages} color={IOH.pink} />
                <StatCard label="Logins" value={selectedUser.login_count} color={IOH.teal} />
                <StatCard label="Total Queries" value={userActivity?.total_queries ?? 0} color={IOH.red} />
                <StatCard label="Avg Latency" value={userActivity?.avg_latency_ms ? `${(userActivity.avg_latency_ms / 1000).toFixed(1)}s` : "-"} color={IOH.yellow} />
              </div>
            </div>

            {/* Activity Chart + Domain Breakdown */}
            {userActivity && (
              <div style={{ display: "grid", gridTemplateColumns: "2fr 1fr", gap: 20, marginTop: 20 }}>
                <div style={cardStyle}>
                  <h3 style={cardTitle}>Query Activity (30 Days)</h3>
                  {userActivity.daily_activity.some(d => d.queries > 0) ? (
                    <UserActivityChart data={userActivity.daily_activity} />
                  ) : (
                    <div style={{ color: IOH.mute, fontSize: 13, padding: "20px 0", textAlign: "center" }}>No query data yet</div>
                  )}
                </div>
                <div style={cardStyle}>
                  <h3 style={cardTitle}>Domain Breakdown</h3>
                  {userActivity.domain_breakdown.length === 0 ? (
                    <div style={{ color: IOH.mute, fontSize: 13, padding: "20px 0", textAlign: "center" }}>No data yet</div>
                  ) : (
                    <>
                      <DomainDonut data={userActivity.domain_breakdown} />
                      <div style={{ marginTop: 12 }}>
                        {userActivity.domain_breakdown.map((d, i) => {
                          const total = userActivity.domain_breakdown.reduce((s, x) => s + x.count, 0);
                          const pct = total > 0 ? ((d.count / total) * 100).toFixed(0) : "0";
                          return (
                            <div key={i} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "6px 0", borderBottom: `1px solid ${IOH.rule}` }}>
                              <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                                <div style={{ width: 10, height: 10, borderRadius: 3, background: DOMAIN_COLORS[i % DOMAIN_COLORS.length] }} />
                                <span style={{ fontSize: 13, color: IOH.ink, textTransform: "capitalize" }}>{d.domain}</span>
                              </div>
                              <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                                <span style={{ fontSize: 12, color: IOH.mute }}>{pct}%</span>
                                <span style={{ ...badgeStyle, minWidth: 32, textAlign: "center" }}>{d.count}</span>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </>
                  )}
                </div>
              </div>
            )}

            {/* Recent Sessions */}
            <div style={{ ...cardStyle, marginTop: 20 }}>
              <h3 style={cardTitle}>Recent Sessions</h3>
              {selectedUser.recent_sessions.length === 0 ? (
                <div style={{ color: IOH.mute, fontSize: 13 }}>No sessions yet</div>
              ) : selectedUser.recent_sessions.map((s, i) => (
                <div key={i} style={{
                  display: "flex", justifyContent: "space-between",
                  padding: "10px 0",
                  borderBottom: `1px solid ${IOH.rule}`,
                }}>
                  <button onClick={() => loadSessionDetail(s.session_id)} style={linkBtn}>
                    {s.title}
                  </button>
                  <div style={{ display: "flex", gap: 12, color: IOH.mute, fontSize: 12, fontVariantNumeric: "tabular-nums" }}>
                    <span>{s.message_count} msgs</span>
                    <span>{s.updated_at ? new Date(s.updated_at).toLocaleString() : ""}</span>
                  </div>
                </div>
              ))}
            </div>

            {/* Q&A Knowledge Base */}
            {userActivity && userActivity.qa_pairs.length > 0 && (
              <div style={{ ...cardStyle, marginTop: 20 }}>
                <h3 style={cardTitle}>Questions & AI Responses ({userActivity.qa_pairs.length})</h3>
                <div style={{ maxHeight: 600, overflowY: "auto" }}>
                  {userActivity.qa_pairs.map((qa, i) => (
                    <div key={i} style={{
                      borderBottom: `1px solid ${IOH.rule}`,
                      padding: "14px 0",
                    }}>
                      <div style={{ display: "flex", alignItems: "flex-start", gap: 10, marginBottom: 6 }}>
                        <div style={{ flexShrink: 0, width: 6, height: 6, borderRadius: "50%", background: IOH.red, marginTop: 6 }} />
                        <div style={{ flex: 1 }}>
                          <div style={{ fontSize: 14, fontWeight: 600, color: IOH.ink, lineHeight: 1.5 }}>{qa.question}</div>
                          <div style={{ display: "flex", gap: 8, marginTop: 4, flexWrap: "wrap" }}>
                            {qa.domain && <span style={{ ...badgeStyle, background: IOH.red + "18", color: IOH.red }}>{qa.domain}</span>}
                            {qa.row_count != null && <span style={{ ...badgeStyle }}>{qa.row_count} rows</span>}
                            {qa.latency_ms != null && <span style={{ ...badgeStyle }}>{(qa.latency_ms / 1000).toFixed(1)}s</span>}
                            {qa.asked_at && <span style={{ fontSize: 11, color: IOH.mute, fontVariantNumeric: "tabular-nums" }}>{new Date(qa.asked_at).toLocaleString()}</span>}
                          </div>
                        </div>
                        <button
                          onClick={() => setQaExpanded(p => ({ ...p, [i]: !p[i] }))}
                          style={{ background: "none", border: `1px solid ${IOH.rule}`, borderRadius: 6, padding: "3px 10px", cursor: "pointer", fontSize: 11, color: IOH.mute, fontWeight: 600, flexShrink: 0 }}
                        >
                          {qaExpanded[i] ? "Hide" : "Show"} Answer
                        </button>
                      </div>
                      {qaExpanded[i] && qa.answer && (
                        <div style={{ marginLeft: 16, marginTop: 8 }}>
                          <div style={{
                            background: IOH.panel, borderRadius: 10, padding: "14px 16px",
                            borderLeft: `3px solid ${IOH.teal}`,
                            fontSize: 13, lineHeight: 1.65, color: IOH.ink,
                            whiteSpace: "pre-wrap", maxHeight: 300, overflowY: "auto",
                          }}>
                            {qa.answer}
                          </div>
                          {qa.sql_query && (
                            <details style={{ marginTop: 8 }}>
                              <summary style={{ cursor: "pointer", color: IOH.mute, fontSize: 12, fontWeight: 600 }}>SQL Query</summary>
                              <pre style={{
                                background: IOH.ink, color: "#E8E8EA", padding: 12, borderRadius: 8,
                                fontSize: 11, overflowX: "auto", whiteSpace: "pre-wrap", marginTop: 4,
                              }}>{qa.sql_query}</pre>
                            </details>
                          )}
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}

        {/* -- History Tab -- */}
        {!loading && tab === "history" && !selectedSession && (
          <div style={cardStyle}>
            <h3 style={cardTitle}>All Chat History ({history.length})</h3>
            <table style={{ width: "100%", borderCollapse: "collapse" }}>
              <thead>
                <tr style={{ borderBottom: `1px solid ${IOH.rule}` }}>
                  {["User", "Session Title", "Messages", "Created", "Last Updated"].map((h) => (
                    <th key={h} style={thStyle}>{h}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {history.map((h, i) => (
                  <tr key={i} style={{ borderBottom: `1px solid ${IOH.rule}` }}>
                    <td style={tdStyle}>{h.full_name || h.username}</td>
                    <td style={tdStyle}>
                      <button onClick={() => loadSessionDetail(h.session_id)} style={linkBtn}>
                        {h.title}
                      </button>
                    </td>
                    <td style={{ ...tdStyle, fontVariantNumeric: "tabular-nums" }}>{h.message_count}</td>
                    <td style={{ ...tdStyle, fontVariantNumeric: "tabular-nums" }}>{h.created_at ? new Date(h.created_at).toLocaleString() : ""}</td>
                    <td style={{ ...tdStyle, fontVariantNumeric: "tabular-nums" }}>{h.updated_at ? new Date(h.updated_at).toLocaleString() : ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Session Detail / Messages */}
        {!loading && selectedSession && (
          <div>
            <button onClick={() => setSelectedSession(null)} style={navBtn}>Back</button>
            <div style={{ ...cardStyle, marginTop: 16 }}>
              <h3 style={cardTitle}>{selectedSession.title}</h3>
              <div style={{ maxHeight: "70vh", overflowY: "auto", paddingRight: 8 }}>
                {selectedSession.messages.map((m, i) => (
                  <div key={i} style={{
                    padding: "12px 16px",
                    margin: "8px 0",
                    borderRadius: 10,
                    background: m.role === "user" ? IOH.panel : IOH.white,
                    borderLeft: m.role === "user"
                      ? `4px solid ${IOH.red}`
                      : `4px solid ${IOH.teal}`,
                    border: `1px solid ${IOH.rule}`,
                    borderLeftWidth: 4,
                    borderLeftColor: m.role === "user" ? IOH.red : IOH.teal,
                  }}>
                    <div style={{
                      display: "flex", justifyContent: "space-between",
                      marginBottom: 6,
                    }}>
                      <span style={{
                        fontWeight: 700, fontSize: 11,
                        color: m.role === "user" ? IOH.red : IOH.teal,
                        textTransform: "uppercase",
                        letterSpacing: "0.5px",
                      }}>{m.role}</span>
                      <div style={{ display: "flex", gap: 8, fontSize: 11, color: IOH.mute, fontVariantNumeric: "tabular-nums" }}>
                        {m.domain && <span style={badgeStyle}>{m.domain}</span>}
                        {m.row_count != null && <span>{m.row_count} rows</span>}
                        {m.latency_ms != null && <span>{(m.latency_ms / 1000).toFixed(1)}s</span>}
                        <span>{m.created_at ? new Date(m.created_at).toLocaleTimeString() : ""}</span>
                      </div>
                    </div>
                    <div style={{ whiteSpace: "pre-wrap", fontSize: 13, lineHeight: 1.5, color: IOH.ink }}>
                      {m.content}
                    </div>
                    {m.sql_query && (
                      <details style={{ marginTop: 8 }}>
                        <summary style={{ cursor: "pointer", color: IOH.mute, fontSize: 12 }}>
                          SQL Query
                        </summary>
                        <pre style={{
                          background: IOH.panel,
                          padding: 10,
                          borderRadius: 6,
                          fontSize: 11,
                          overflowX: "auto",
                          color: IOH.ink,
                          marginTop: 4,
                          border: `1px solid ${IOH.rule}`,
                        }}>{m.sql_query}</pre>
                      </details>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
    </AppShell>
  );
}

// -- Create User Form --

function CreateUserForm({ onCreated }: { onCreated: () => void }) {
  const [open, setOpen] = useState(false);
  const [username, setUsername] = useState("");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [role, setRole] = useState("end_user");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);

  async function handleCreate(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setSaving(true);
    try {
      const res = await authFetch("/api/admin/users", {
        method: "POST",
        body: JSON.stringify({ username, email: email || undefined, password, full_name: fullName, role }),
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({ detail: "Failed" }));
        throw new Error(err.detail || "Failed to create user");
      }
      setUsername(""); setFullName(""); setEmail(""); setPassword(""); setRole("end_user");
      setOpen(false);
      onCreated();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "Failed");
    } finally {
      setSaving(false);
    }
  }

  if (!open) {
    return (
      <div style={{ marginBottom: 16 }}>
        <button onClick={() => setOpen(true)} style={{
          padding: "10px 24px", borderRadius: 10, border: "none", cursor: "pointer",
          background: IOH.red, color: IOH.white,
          fontFamily: "var(--font-display)",
          fontWeight: 700, fontSize: 14,
          boxShadow: `0 3px 12px rgba(21, 166, 151,0.25)`,
          transition: "background 0.15s, box-shadow 0.15s, transform 0.1s",
          letterSpacing: "0.01em",
        }}>+ Create User</button>
      </div>
    );
  }

  return (
    <div style={{
      ...cardStyle, marginBottom: 16,
      border: `1px solid ${IOH.rule}`,
    }}>
      <h3 style={cardTitle}>Create New User</h3>
      <form onSubmit={handleCreate}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12, marginBottom: 12 }}>
          <input placeholder="Username *" value={username} onChange={e => setUsername(e.target.value)} required style={formInput} />
          <input placeholder="Full Name" value={fullName} onChange={e => setFullName(e.target.value)} style={formInput} />
          <input placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} style={formInput} />
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12 }}>
          <input type="password" placeholder="Password *" value={password} onChange={e => setPassword(e.target.value)} required minLength={6} style={formInput} />
          <select value={role} onChange={e => setRole(e.target.value)} style={{ ...formInput, cursor: "pointer" }}>
            <option value="end_user">End User</option>
            <option value="data_user">Data User</option>
            <option value="analyst">Analyst</option>
            <option value="admin">Admin</option>
          </select>
          <div style={{ display: "flex", gap: 8 }}>
            <button type="submit" disabled={saving} style={{
              flex: 1, padding: "8px", borderRadius: 6, border: "none", cursor: saving ? "wait" : "pointer",
              background: saving ? IOH.mute : IOH.red, color: IOH.white, fontWeight: 700,
            }}>{saving ? "..." : "Create"}</button>
            <button type="button" onClick={() => setOpen(false)} style={{
              padding: "8px 14px", borderRadius: 6, border: `1px solid ${IOH.rule}`,
              background: "transparent", color: IOH.mute, cursor: "pointer",
            }}>Cancel</button>
          </div>
        </div>
        {error && <div style={{ color: IOH.red, fontSize: 12, marginTop: 8 }}>{error}</div>}
      </form>
    </div>
  );
}


// -- Notification Sender --

function NotifSender() {
  const [title, setTitle] = useState("");
  const [message, setMessage] = useState("");
  const [kind, setKind] = useState("info");
  const [sendEmail, setSendEmail] = useState(false);
  const [sending, setSending] = useState(false);
  const [result, setResult] = useState("");

  async function handleSend(e: React.FormEvent) {
    e.preventDefault();
    if (!message.trim()) return;
    setSending(true);
    setResult("");
    try {
      const res = await authFetch("/api/admin/notify", {
        method: "POST",
        body: JSON.stringify({ title: title || "Notification", message, kind, send_email: sendEmail }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "Failed");
      setResult(`Sent to ${data.notified} users`);
      setTitle(""); setMessage("");
    } catch (e: unknown) {
      setResult(e instanceof Error ? e.message : "Failed");
    } finally {
      setSending(false);
    }
  }

  return (
    <div style={{ ...cardStyle, marginTop: 24 }}>
      <h3 style={cardTitle}>Send Notification</h3>
      <form onSubmit={handleSend}>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 12 }}>
          <input placeholder="Title" value={title} onChange={e => setTitle(e.target.value)} style={formInput} />
          <select value={kind} onChange={e => setKind(e.target.value)} style={{ ...formInput, cursor: "pointer" }}>
            <option value="info">Info</option>
            <option value="success">Success</option>
            <option value="warn">Warning</option>
            <option value="alert">Alert</option>
          </select>
        </div>
        <textarea
          placeholder="Notification message (sent to all active users)..."
          value={message} onChange={e => setMessage(e.target.value)}
          rows={3} required
          style={{ ...formInput, width: "100%", resize: "vertical", marginBottom: 12 }}
        />
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <label style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 13, color: IOH.ink, cursor: "pointer" }}>
            <input type="checkbox" checked={sendEmail} onChange={e => setSendEmail(e.target.checked)} />
            Also send via email
          </label>
          <button type="submit" disabled={sending} style={{
            padding: "8px 20px", borderRadius: 8, border: "none", cursor: sending ? "wait" : "pointer",
            background: sending ? IOH.mute : IOH.red, color: IOH.white,
            fontFamily: "var(--font-display)", fontWeight: 700, fontSize: 13,
          }}>
            {sending ? "Sending..." : "Send to All"}
          </button>
          {result && <span style={{ fontSize: 12, color: IOH.teal, fontWeight: 600 }}>{result}</span>}
        </div>
      </form>
    </div>
  );
}

// -- Chart Components --

const DOMAIN_COLORS = ["#15A697", "#0E8579", "#F5A623", "#33BCAD", "#0A6A5F", "#5A6B68", "#FF6B35", "#6C63FF"];

function ActivityChart({ data }: { data: { date: string; logins: number; queries: number }[] }) {
  const maxVal = Math.max(...data.map(d => Math.max(d.logins, d.queries)), 1);
  const W = 900, H = 180, padL = 40, padR = 10, padT = 10, padB = 28;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const step = innerW / Math.max(data.length - 1, 1);

  function points(key: "logins" | "queries") {
    return data.map((d, i) => {
      const x = padL + i * step;
      const y = padT + innerH - (d[key] / maxVal) * innerH;
      return `${x},${y}`;
    }).join(" ");
  }

  const ticks = [0, Math.round(maxVal * 0.5), maxVal];

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} style={{ display: "block" }}>
      {ticks.map((t, i) => {
        const y = padT + innerH - (t / maxVal) * innerH;
        return (
          <g key={i}>
            <line x1={padL} x2={W - padR} y1={y} y2={y} stroke="#E1E9E7" strokeWidth={1} />
            <text x={padL - 6} y={y + 3} fontSize={10} fontWeight={500} fill="#5A6B68" textAnchor="end">{t}</text>
          </g>
        );
      })}
      <polyline points={points("queries")} fill="none" stroke="#15A697" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
      <polyline points={points("logins")} fill="none" stroke="#33BCAD" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" strokeDasharray="4 3" />
      {data.map((d, i) => {
        if (i % 5 !== 0 && i !== data.length - 1) return null;
        const x = padL + i * step;
        const label = d.date.slice(5);
        return <text key={i} x={x} y={H - 4} fontSize={9} fill="#5A6B68" textAnchor="middle">{label}</text>;
      })}
      <g transform={`translate(${W - padR - 160}, ${padT})`}>
        <line x1={0} y1={6} x2={16} y2={6} stroke="#15A697" strokeWidth={2} />
        <text x={20} y={10} fontSize={10} fill="#5A6B68" fontWeight={600}>Queries</text>
        <line x1={80} y1={6} x2={96} y2={6} stroke="#33BCAD" strokeWidth={2} strokeDasharray="4 3" />
        <text x={100} y={10} fontSize={10} fill="#5A6B68" fontWeight={600}>Logins</text>
      </g>
    </svg>
  );
}

function UserActivityChart({ data }: { data: { date: string; queries: number }[] }) {
  const maxVal = Math.max(...data.map(d => d.queries), 1);
  const W = 600, H = 140, padL = 32, padR = 8, padT = 8, padB = 24;
  const innerW = W - padL - padR, innerH = H - padT - padB;
  const barW = Math.min(14, (innerW / data.length) - 2);

  return (
    <svg width="100%" viewBox={`0 0 ${W} ${H}`} style={{ display: "block" }}>
      <line x1={padL} x2={W - padR} y1={padT + innerH} y2={padT + innerH} stroke="#E1E9E7" strokeWidth={1} />
      {data.map((d, i) => {
        const x = padL + (i / data.length) * innerW + (innerW / data.length - barW) / 2;
        const h = d.queries > 0 ? Math.max((d.queries / maxVal) * innerH, 2) : 0;
        const y = padT + innerH - h;
        return (
          <g key={i}>
            <rect x={x} y={y} width={barW} height={h} fill="#15A697" rx={2} opacity={d.queries > 0 ? 0.85 : 0.15} />
            {d.queries > 0 && <text x={x + barW / 2} y={y - 4} fontSize={8} fill="#15A697" fontWeight={700} textAnchor="middle">{d.queries}</text>}
            {(i % 7 === 0 || i === data.length - 1) && (
              <text x={x + barW / 2} y={H - 4} fontSize={8} fill="#5A6B68" textAnchor="middle">{d.date.slice(5)}</text>
            )}
          </g>
        );
      })}
    </svg>
  );
}

function DomainDonut({ data }: { data: { domain: string; count: number }[] }) {
  const total = data.reduce((s, d) => s + d.count, 0);
  if (total === 0) return null;

  const size = 160, cx = size / 2, cy = size / 2, r = 55, cutout = 0.68;
  const innerR = r * cutout;
  const starts = data.reduce<number[]>((acc, d, i) => [...acc, (acc[i] ?? -Math.PI / 2) + (d.count / total) * Math.PI * 2], [-Math.PI / 2]);

  const segments = data.map((d, i) => {
    const angle = (d.count / total) * Math.PI * 2;
    const startAngle = starts[i];
    const endAngle = starts[i + 1];

    const x1 = cx + r * Math.cos(startAngle);
    const y1 = cy + r * Math.sin(startAngle);
    const x2 = cx + r * Math.cos(endAngle);
    const y2 = cy + r * Math.sin(endAngle);
    const ix1 = cx + innerR * Math.cos(endAngle);
    const iy1 = cy + innerR * Math.sin(endAngle);
    const ix2 = cx + innerR * Math.cos(startAngle);
    const iy2 = cy + innerR * Math.sin(startAngle);
    const largeArc = angle > Math.PI ? 1 : 0;

    const path = `M ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2} L ${ix1} ${iy1} A ${innerR} ${innerR} 0 ${largeArc} 0 ${ix2} ${iy2} Z`;
    return <path key={i} d={path} fill={DOMAIN_COLORS[i % DOMAIN_COLORS.length]} stroke="#fff" strokeWidth={2} />;
  });

  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ display: "block", margin: "0 auto" }}>
      {segments}
      <text x={cx} y={cy - 4} textAnchor="middle" fontSize={20} fontWeight={800} fill="#0F1F1D">{total}</text>
      <text x={cx} y={cy + 12} textAnchor="middle" fontSize={9} fontWeight={600} fill="#5A6B68" style={{ textTransform: "uppercase", letterSpacing: "0.06em" }}>QUERIES</text>
    </svg>
  );
}

// -- Reusable Components --

function StatCard({ label, value, color }: { label: string; value: number | string; color: string }) {
  return (
    <div style={{
      padding: "20px 24px",
      borderRadius: 16,
      background: IOH.white,
      border: `1px solid ${IOH.rule}`,
      boxShadow: "0 2px 6px rgba(45,41,38,.04), 0 1px 2px rgba(45,41,38,.03)",
      borderTop: `4px solid ${color}`,
      transition: "box-shadow 0.2s, transform 0.2s",
    }}>
      <div style={{
        fontFamily: "var(--font-display)", fontSize: 30, fontWeight: 800,
        color: IOH.ink, fontVariantNumeric: "tabular-nums", lineHeight: 1,
      }}>{value}</div>
      <div style={{
        fontFamily: "var(--font-display)", fontSize: 11, color: IOH.mute,
        marginTop: 6, fontWeight: 700, textTransform: "uppercase",
        letterSpacing: "0.06em",
      }}>{label}</div>
    </div>
  );
}

// -- IOH Brand Colors --

const IOH = {
  red: "#15A697",
  pink: "#0E8579",
  yellow: "#F5A623",
  teal: "#33BCAD",
  magenta: "#0A6A5F",
  ink: "#0F1F1D",
  mute: "#5A6B68",
  rule: "#E1E9E7",
  panel: "#F5F9F8",
  white: "#FFFFFF",
} as const;

// -- Styles --

const cardStyle: React.CSSProperties = {
  background: IOH.white,
  border: `1px solid ${IOH.rule}`,
  borderRadius: 16,
  padding: 28,
  boxShadow: "0 2px 6px rgba(45,41,38,.04), 0 1px 2px rgba(45,41,38,.03)",
};

const cardTitle: React.CSSProperties = {
  fontFamily: "var(--font-display)",
  fontSize: 18,
  fontWeight: 700,
  color: IOH.ink,
  marginTop: 0,
  marginBottom: 18,
  letterSpacing: "-0.01em",
};

const badgeStyle: React.CSSProperties = {
  padding: "2px 8px",
  borderRadius: 6,
  fontSize: 11,
  fontWeight: 600,
  background: IOH.panel,
  color: IOH.mute,
};

const thStyle: React.CSSProperties = {
  textAlign: "left",
  padding: "12px 14px",
  fontFamily: "var(--font-display)",
  fontSize: 11,
  fontWeight: 700,
  color: IOH.mute,
  textTransform: "uppercase",
  letterSpacing: "0.06em",
};

const tdStyle: React.CSSProperties = {
  padding: "10px 12px",
  fontSize: 13,
  color: IOH.ink,
};

const navBtn: React.CSSProperties = {
  padding: "8px 18px",
  borderRadius: 8,
  border: `1px solid ${IOH.rule}`,
  background: "transparent",
  color: IOH.mute,
  cursor: "pointer",
  fontFamily: "var(--font-display)",
  fontSize: 13,
  fontWeight: 600,
  transition: "all 0.15s",
};

const linkBtn: React.CSSProperties = {
  background: "none",
  border: "none",
  color: IOH.red,
  cursor: "pointer",
  fontSize: 13,
  textAlign: "left",
  padding: 0,
  textDecoration: "underline",
  textDecorationColor: "rgba(21, 166, 151,0.3)",
};

const smallBtn: React.CSSProperties = {
  padding: "3px 8px",
  borderRadius: 4,
  border: "1px solid",
  background: "transparent",
  cursor: "pointer",
  fontSize: 11,
  fontWeight: 600,
};

const formInput: React.CSSProperties = {
  padding: "10px 14px",
  borderRadius: 10,
  border: `1.5px solid ${IOH.rule}`,
  background: IOH.white,
  color: IOH.ink,
  fontSize: 13,
  outline: "none",
  transition: "border-color 0.15s, box-shadow 0.15s",
};
