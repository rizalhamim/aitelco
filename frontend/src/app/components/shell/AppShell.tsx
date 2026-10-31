"use client";
import { ReactNode, useCallback, useEffect, useRef, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import {
  Activity, Bell, Download, FileText, History, LayoutGrid, LogOut, Map as MapIcon, Menu,
  MessageSquare, MoreHorizontal, Palette, Plus, Search, Smartphone, User, Users, X,
} from "lucide-react";
import { authFetch, getUser, isAdmin, isLoggedIn, logout } from "@/lib/auth";
import { applyPrefs, getPrefs } from "@/lib/prefs";
import { useMounted } from "@/lib/useMounted";

export type HistoryItem = { session_id: string; title: string; message_count: number; updated_at: string | null };

type NavItem = {
  href: string;
  label: string;
  icon: typeof Activity;
  tone: "teal" | "blue" | "rose" | "amber" | "violet" | "green" | "grey";
  badge?: number;
  admin?: boolean;
};

const MENU: NavItem[] = [
  { href: "/", label: "Tanya Agent", icon: MessageSquare, tone: "teal" },
  { href: "/dashboard", label: "Dashboard", icon: LayoutGrid, tone: "blue" },
  { href: "/watchlist", label: "Watchlist & Alert", icon: Bell, tone: "rose" },
  { href: "/reports", label: "Laporan", icon: FileText, tone: "amber" },
  { href: "/map", label: "Peta & Site", icon: MapIcon, tone: "violet" },
];
const ADMIN: NavItem[] = [
  { href: "/statistik", label: "Statistik", icon: Activity, tone: "teal", admin: true },
  { href: "/unduh", label: "Unduh APK", icon: Download, tone: "green" },
];

type Props = {
  children: ReactNode;
  /** Chat page drives the conversation list itself; other pages navigate to "/". */
  activeSession?: string;
  onNewChat?: () => void;
  onOpenSession?: (sid: string) => void;
  /** Bump to make the sidebar reload the conversation list. */
  historyVersion?: number;
  busy?: boolean;
  mainClassName?: string;
};

export default function AppShell({
  children, activeSession, onNewChat, onOpenSession, historyVersion = 0, busy, mainClassName,
}: Props) {
  const pathname = usePathname() || "/";
  const router = useRouter();
  const mounted = useMounted();
  const ready = mounted && isLoggedIn();
  const [open, setOpen] = useState(false);
  const [openedAt, setOpenedAt] = useState(pathname);
  const [history, setHistory] = useState<HistoryItem[]>([]);
  const [query, setQuery] = useState("");
  const [alertCount, setAlertCount] = useState(0);
  const [apkVersion, setApkVersion] = useState<string | null>(null);
  const [userMenu, setUserMenu] = useState(false);
  const userRef = useRef<HTMLDivElement>(null);
  const user = mounted ? getUser() : null;
  const admin = mounted && isAdmin();

  // Close the mobile drawer whenever the route changes.
  if (openedAt !== pathname) {
    setOpenedAt(pathname);
    setOpen(false);
  }

  useEffect(() => {
    if (!mounted) return;
    if (!isLoggedIn()) {
      router.replace("/login");
      return;
    }
    applyPrefs(getPrefs());
    authFetch("/api/app/version").then((r) => (r.ok ? r.json() : null))
      .then((d) => d?.version_name && setApkVersion(d.version_name)).catch(() => {});
    authFetch("/api/watchlist/alerts/count").then((r) => (r.ok ? r.json() : null))
      .then((d) => typeof d?.active === "number" && setAlertCount(d.active)).catch(() => {});
  }, [mounted, router]);

  const loadHistory = useCallback(() => {
    authFetch("/api/history/sessions")
      .then((r) => (r.ok ? r.json() : []))
      .then((d) => setHistory(Array.isArray(d) ? d : d.sessions || []))
      .catch(() => {});
  }, []);
  useEffect(() => { if (ready) loadHistory(); }, [ready, historyVersion, loadHistory]);

  useEffect(() => {
    if (!userMenu) return;
    const close = (e: MouseEvent) => {
      if (!userRef.current?.contains(e.target as Node)) setUserMenu(false);
    };
    document.addEventListener("mousedown", close);
    return () => document.removeEventListener("mousedown", close);
  }, [userMenu]);

  function newChat() {
    setOpen(false);
    if (onNewChat) onNewChat();
    else router.push("/?new=1");
  }
  function openSession(sid: string) {
    setOpen(false);
    if (onOpenSession) onOpenSession(sid);
    else router.push(`/?s=${encodeURIComponent(sid)}`);
  }

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  const filtered = query.trim()
    ? history.filter((h) => (h.title || "").toLowerCase().includes(query.trim().toLowerCase()))
    : history;
  const name = user?.full_name || user?.username || "";
  const initial = (name.trim()[0] || "U").toUpperCase();

  const navLink = (it: NavItem) => {
    const Icon = it.icon;
    const active = isActive(it.href);
    const badge = it.href === "/watchlist" ? alertCount : it.badge;
    return (
      <Link key={it.href} href={it.href} className={`ui-nav ${active ? "active" : ""}`} data-tone={it.tone}
        aria-current={active ? "page" : undefined}>
        <span className="ui-nav-tile"><Icon size={active ? 17 : 22} strokeWidth={active ? 2 : 1.6} /></span>
        <span className="ui-nav-label">{it.label}</span>
        {!!badge && <span className="ui-badge">{badge}</span>}
      </Link>
    );
  };

  if (!ready) return <div className="ui-boot" />;

  return (
    <div className="ui-app">
      <header className="ui-mobilebar">
        <button className="ui-iconbtn" onClick={() => setOpen(true)} aria-label="Buka menu"><Menu size={20} /></button>
        <div className="ui-mobilebar-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/brand/icon_circle_java.png" alt="" width={32} height={32} />
          <span>Bizplan Java Agent</span>
        </div>
        <button className="ui-iconbtn" onClick={newChat} aria-label="Percakapan baru" disabled={busy}><Plus size={20} /></button>
      </header>

      {open && <div className="ui-scrim" onClick={() => setOpen(false)} />}

      <aside className={`ui-sidebar ${open ? "open" : ""}`} aria-label="Navigasi utama">
        <div className="ui-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="ui-brand-logo" src="/brand/icon_circle_java.png" alt="Circle Java" width={52} height={52} />
          <div className="ui-brand-text">
            <span className="ui-brand-name">Bizplan Java Agent</span>
            <span className="ui-brand-sub">Business Planning Circle Java</span>
          </div>
          <button className="ui-iconbtn ui-sidebar-close" onClick={() => setOpen(false)} aria-label="Tutup menu"><X size={18} /></button>
        </div>

        <button className="ui-btn-primary ui-newchat" onClick={newChat} disabled={busy}>
          <Plus size={18} strokeWidth={2.2} /> Percakapan baru
        </button>

        <label className="ui-search">
          <Search size={18} aria-hidden="true" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Cari percakapan…" aria-label="Cari percakapan" />
        </label>

        <nav className="ui-menu">
          <span className="ui-overline">Menu</span>
          {MENU.map(navLink)}
          <span className="ui-overline">Admin</span>
          {ADMIN.filter((i) => !i.admin || admin).map(navLink)}
        </nav>

        <div className="ui-history">
          <span className="ui-overline">Riwayat</span>
          {filtered.length === 0 && <span className="ui-history-empty">{query ? "Tidak ada yang cocok" : "Belum ada percakapan"}</span>}
          <div className="ui-history-list">
            {filtered.slice(0, 30).map((h) => (
              <button key={h.session_id} className={`ui-history-item ${pathname === "/" && h.session_id === activeSession ? "active" : ""}`}
                onClick={() => openSession(h.session_id)} disabled={busy} title={h.title}>
                <History size={16} aria-hidden="true" />
                <span>{h.title || "Percakapan tanpa judul"}</span>
              </button>
            ))}
          </div>
        </div>

        <Link href="/unduh" className="ui-promo">
          <span className="ui-promo-ico"><Smartphone size={18} /></span>
          <span className="ui-promo-text">
            <b>Aplikasi Android</b>
            <span>{apkVersion ? `v${apkVersion} · ` : ""}Unduh APK</span>
          </span>
          <Download size={18} />
        </Link>

        <Link href="/tampilan" className={`ui-nav ${isActive("/tampilan") ? "active" : ""}`} data-tone="grey">
          <span className="ui-nav-tile"><Palette size={isActive("/tampilan") ? 17 : 22} strokeWidth={isActive("/tampilan") ? 2 : 1.6} /></span>
          <span className="ui-nav-label">Tampilan</span>
        </Link>

        <div className="ui-user" ref={userRef}>
          <span className="ui-avatar">{initial}</span>
          <span className="ui-user-text">
            <b>{name}</b>
            <span>{user?.role === "admin" ? "Administrator" : "Bizplan"} · Region Jawa</span>
          </span>
          <button className="ui-iconbtn ghost" onClick={() => setUserMenu((v) => !v)} aria-label="Menu akun" aria-expanded={userMenu}>
            <MoreHorizontal size={18} />
          </button>
          {userMenu && (
            <div className="ui-popover ui-user-menu" role="menu">
              <Link href="/profile" role="menuitem"><User size={16} /> Profil</Link>
              {admin && <Link href="/admin" role="menuitem"><Users size={16} /> Kelola pengguna</Link>}
              <button role="menuitem" onClick={() => logout()}><LogOut size={16} /> Keluar</button>
            </div>
          )}
        </div>

        <div className="ui-ioh">
          <span>Didukung oleh</span>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/brand/logo-ioh-color.png" alt="Indosat Ooredoo Hutchison" height={30} />
        </div>
      </aside>

      <main className={`ui-main ${mainClassName ?? ""}`}>{children}</main>
    </div>
  );
}
