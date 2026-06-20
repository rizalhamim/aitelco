"use client";

// All API calls use relative paths — Next.js rewrites /api/* to backend
const API = "";

export interface UserInfo {
  id: number;
  username: string;
  email: string;
  full_name: string;
  role: string;
  is_active: boolean;
  created_at: string;
  last_login: string | null;
  login_count: number;
}

export interface AuthTokens {
  access_token: string;
  refresh_token: string;
  token_type: string;
  user: UserInfo;
}

// ── Token Storage ──

export function saveTokens(tokens: AuthTokens) {
  localStorage.setItem("access_token", tokens.access_token);
  localStorage.setItem("refresh_token", tokens.refresh_token);
  localStorage.setItem("user", JSON.stringify(tokens.user));
}

export function getAccessToken(): string | null {
  if (typeof window === "undefined") return null;
  return localStorage.getItem("access_token");
}

export function getUser(): UserInfo | null {
  if (typeof window === "undefined") return null;
  const raw = localStorage.getItem("user");
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

export function clearAuth() {
  localStorage.removeItem("access_token");
  localStorage.removeItem("refresh_token");
  localStorage.removeItem("user");
}

export function isLoggedIn(): boolean {
  return !!getAccessToken();
}

export function isAdmin(): boolean {
  const u = getUser();
  return u?.role === "admin";
}

export function getUserRole(): string {
  return getUser()?.role || "end_user";
}

export function canViewSQL(): boolean {
  const r = getUserRole();
  return r === "admin" || r === "analyst";
}

export function canExport(): boolean {
  const r = getUserRole();
  return r === "admin" || r === "analyst" || r === "data_user";
}

// ── API Helpers ──

export async function authFetch(path: string, options: RequestInit = {}): Promise<Response> {
  const token = getAccessToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(options.headers as Record<string, string> || {}),
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }
  const res = await fetch(`${API}${path}`, { ...options, headers });

  // Auto-refresh if 401
  if (res.status === 401 && typeof window !== "undefined") {
    const refreshed = await tryRefresh();
    if (refreshed) {
      headers["Authorization"] = `Bearer ${getAccessToken()}`;
      return fetch(`${API}${path}`, { ...options, headers });
    } else {
      clearAuth();
      window.location.href = "/login";
    }
  }
  return res;
}

async function tryRefresh(): Promise<boolean> {
  const rt = localStorage.getItem("refresh_token");
  if (!rt) return false;
  try {
    const res = await fetch(`${API}/api/auth/refresh`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: rt }),
    });
    if (!res.ok) return false;
    const data = await res.json();
    localStorage.setItem("access_token", data.access_token);
    return true;
  } catch {
    return false;
  }
}

// ── Auth Actions ──

export async function login(username: string, password: string): Promise<AuthTokens> {
  const res = await fetch(`${API}/api/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ detail: "Login failed" }));
    throw new Error(err.detail || "Login failed");
  }
  const tokens: AuthTokens = await res.json();
  saveTokens(tokens);
  return tokens;
}

export function logout() {
  clearAuth();
  window.location.href = "/login";
}
