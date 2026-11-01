"use client";
import { ReactNode, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Menu } from "lucide-react";
import { authFetch, getUser, isAdmin, isLoggedIn } from "@/lib/auth";
import { Icon } from "@/app/components/v2/Icon";
import { applyPrefs, getPrefs } from "@/lib/prefs";
import { useMounted } from "@/lib/useMounted";

export type HistoryItem = { session_id: string; title: string; message_count: number; updated_at: string | null };

type NavItem = {
  href: string;
  label: string;
  icon: string;
  bg: string;
  fg: string;
  isNew?: boolean;
};

/* Same order, colors and labels as the approved v2 sidebar (design/mockup-v2). */
const MENU: NavItem[] = [
  { href: "/", label: "Tanya Agent", icon: "chat", bg: "#C0EDE8", fg: "#0A6A5F" },
  { href: "/dashboard", label: "Dashboard", icon: "grid", bg: "#E1ECFA", fg: "#2C6CB0" },
  { href: "/performance", label: "Performance", icon: "pulse", bg: "#F4FCE3", fg: "#5E8A12", isNew: true },
  { href: "/map", label: "Peta Agent", icon: "map", bg: "#E3F7FA", fg: "#0E6F7C", isNew: true },
  { href: "/reports", label: "Laporan", icon: "file", bg: "#FCEDD3", fg: "#B7791F" },
  { href: "/watchlist", label: "Watchlist dan Alert", icon: "bell", bg: "#FBE2E8", fg: "#C23A5B" },
];
const ADMIN: NavItem[] = [
  { href: "/statistik", label: "Statistik", icon: "bars", bg: "#ECE5FA", fg: "#6A4CB5" },
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
    const active = isActive(it.href);
    const badge = it.href === "/watchlist" ? alertCount : 0;
    return (
      <Link key={it.href} href={it.href} className={active ? "on" : ""} aria-current={active ? "page" : undefined}>
        <span className="nt" style={{ background: it.bg, color: it.fg }}><Icon name={it.icon} /></span>
        {it.label}
        {it.isNew && !badge && <span className="new">Baru</span>}
        {!!badge && <span className="cnt">{badge}</span>}
      </Link>
    );
  };

  if (!ready) return <div className="ui-boot" />;

  const roleLabel = user?.role === "admin" ? "Admin" : "Pengguna";
  const onProfile = isActive("/profile");
  const onApk = isActive("/unduh");

  return (
    <div className="v2 app">
      <header className="mbar">
        <button className="btn-ic" onClick={() => setOpen(true)} aria-label="Buka menu"><Menu size={20} /></button>
        <b>Agent <em>Java</em></b>
        <span className="grow" />
        <Link href="/watchlist" className="btn-ic" aria-label="Alert">
          <Icon name="bell" />{alertCount > 0 && <span className="badge">{alertCount}</span>}
        </Link>
        <Link href="/profile" className="avatar" aria-label="Profil" style={{ width: 34, height: 34, fontSize: 13 }}>{initial}</Link>
      </header>

      <div className={`scrim ${open ? "open" : ""}`} onClick={() => setOpen(false)} />

      <aside className={`side ${open ? "open" : ""}`} aria-label="Navigasi utama">
        <Link href="/" className="brand">
          <span className="tile" style={{ width: 44, height: 44, borderRadius: 13 }}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/brand/icon_circle_java.png" alt="Logo Agent Java" />
          </span>
          <div><b>Agent <em>Java</em></b><small>Circle Java</small></div>
        </Link>

        <button className="newchat" onClick={newChat} disabled={busy}><Icon name="plus" />Percakapan baru</button>

        <label className="search">
          <Icon name="search" />
          <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Cari percakapan…" aria-label="Cari percakapan" />
        </label>

        <div className="navh">Menu</div>
        <nav className="nav">{MENU.map(navLink)}</nav>
        {admin && (<>
          <div className="navh">Admin</div>
          <nav className="nav">{ADMIN.map(navLink)}</nav>
        </>)}

        <div className="navh">Riwayat</div>
        <div className="hist">
          {filtered.length === 0 && <span className="empty">{query ? "Tidak ada yang cocok" : "Belum ada percakapan"}</span>}
          {filtered.slice(0, 30).map((h) => (
            <button key={h.session_id} className={pathname === "/" && h.session_id === activeSession ? "on" : ""}
              onClick={() => openSession(h.session_id)} disabled={busy} title={h.title}>
              <Icon name="hist" />
              <span>{h.title || "Percakapan tanpa judul"}</span>
            </button>
          ))}
        </div>

        <div className="spacer" />
        <Link href="/unduh" className={`apk ${onApk ? "on" : ""}`}>
          <span className="ai"><Icon name="dl" /></span>
          <div><b>Aplikasi Android</b><small>Agent Java {apkVersion ? shortVersion(apkVersion) : ""}{apkVersion ? " · " : ""}Unduh APK</small></div>
        </Link>
        <Link href="/profile" className={`me ${onProfile ? "on" : ""}`} aria-current={onProfile ? "page" : undefined}>
          <span className="avatar">{initial}</span>
          <div><b>{name}</b><small>{roleLabel} · Circle Java</small></div>
          <Icon name="chev" />
        </Link>
      </aside>

      <div className={`main ${mainClassName ?? ""}`}>{children}</div>
    </div>
  );
}

/** "1.50.0" -> "1.50", the way the sidebar card shows it. */
function shortVersion(v: string) {
  const m = v.match(/^(\d+)\.(\d+)/);
  return m ? `${m[1]}.${m[2]}` : v;
}

type TopBarProps = { title: string; subtitle?: ReactNode; actions?: ReactNode; ringAvatar?: boolean };

/** Page top bar from the v2 mockups: title, subtitle, page actions, alert bell and avatar. */
export function TopBar({ title, subtitle, actions, ringAvatar }: TopBarProps) {
  const mounted = useMounted();
  const user = mounted ? getUser() : null;
  const [alertCount, setAlertCount] = useState(0);
  useEffect(() => {
    authFetch("/api/watchlist/alerts/count").then((r) => (r.ok ? r.json() : null))
      .then((d) => typeof d?.active === "number" && setAlertCount(d.active)).catch(() => {});
  }, []);
  const name = user?.full_name || user?.username || "";
  const initial = (name.trim()[0] || "U").toUpperCase();
  return (
    <header className="top">
      <div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div>
      <div className="grow" />
      {actions}
      <Link href="/watchlist" className="btn-ic" aria-label="Alert">
        <Icon name="bell" className="ic" />{alertCount > 0 && <span className="badge">{alertCount}</span>}
      </Link>
      <Link href="/profile" className={`avatar ${ringAvatar ? "ring" : ""}`} aria-label="Profil">{initial}</Link>
    </header>
  );
}
