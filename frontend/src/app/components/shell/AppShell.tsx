"use client";
import { Fragment, ReactNode, useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { Menu } from "lucide-react";
import { authFetch, getUser, isAdmin, isLoggedIn } from "@/lib/auth";
import { Icon } from "@/app/components/v2/Icon";
import { applyPrefs, getPrefs } from "@/lib/prefs";
import { useMounted } from "@/lib/useMounted";
import QuickSearch from "./QuickSearch";

export type HistoryItem = { session_id: string; title: string; message_count: number; updated_at: string | null };

type NavItem = {
  href: string;
  label: string;
  icon: string;
  bg: string;
  fg: string;
  isNew?: boolean;
  /** Other routes that light this item (Diagnosa opens from Performance). */
  also?: string[];
};

/* Same groups, order, colors and labels as the approved v3 sidebar (design/mockup-v3/tools/build.py NAV). */
export const NAV_GROUPS: { title: string; items: NavItem[] }[] = [
  { title: "Pantau", items: [
    { href: "/brief", label: "Brief Pagi", icon: "sun", bg: "#FFEDE7", fg: "#B5401F", isNew: true },
    { href: "/dashboard", label: "Dashboard", icon: "grid", bg: "#E1ECFA", fg: "#2C6CB0" },
    { href: "/ruang", label: "Ruang Saya", icon: "layers", bg: "#F4FCE3", fg: "#5E8A12", isNew: true },
    { href: "/klasemen", label: "Klasemen", icon: "bars", bg: "#FDF3E2", fg: "#B7791F", isNew: true },
  ] },
  { title: "Analisis", items: [
    { href: "/", label: "Tanya Agent", icon: "chat", bg: "#C0EDE8", fg: "#0A6A5F" },
    { href: "/performance", label: "Performance", icon: "pulse", bg: "#E6F7F5", fg: "#0E8579", also: ["/diagnosa"] },
    { href: "/simulasi", label: "Simulasi Target", icon: "up", bg: "#ECE5FA", fg: "#6A4CB5", isNew: true },
    { href: "/map", label: "Peta Agent", icon: "map", bg: "#E3F7FA", fg: "#0E6F7C" },
  ] },
  { title: "Bertindak", items: [
    { href: "/watchlist", label: "Watchlist dan Alert", icon: "bell", bg: "#FDECEC", fg: "#C42B2B" },
    { href: "/tindak", label: "Tindak Lanjut", icon: "check", bg: "#FBE2E8", fg: "#C23A5B" },
    { href: "/reports", label: "Laporan", icon: "file", bg: "#FCEDD3", fg: "#B7791F" },
  ] },
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

/** Routes counted on the admin Statistik page, by feature key. */
const PAGE_KEYS: Record<string, string> = {
  "/": "tanya", "/dashboard": "dashboard", "/performance": "performance", "/map": "peta", "/reports": "laporan", "/watchlist": "watchlist",
  "/brief": "brief", "/diagnosa": "diagnosa", "/klasemen": "klasemen", "/ruang": "ruang", "/tindak": "tindak", "/simulasi": "simulasi",
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
  const [palette, setPalette] = useState(false);
  const [alertCount, setAlertCount] = useState(0);
  const [taskCount, setTaskCount] = useState(0);
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
    authFetch("/api/tindak/count").then((r) => (r.ok ? r.json() : null))
      .then((d) => typeof d?.open_mine === "number" && setTaskCount(d.open_mine)).catch(() => {});
  }, [mounted, router]);

  // Ctrl K (or Cmd K) opens the quick search palette from any page.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") { e.preventDefault(); setPalette(true); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const loadHistory = useCallback(() => {
    authFetch("/api/history/sessions")
      .then((r) => (r.ok ? r.json() : []))
      .then((d) => setHistory(Array.isArray(d) ? d : d.sessions || []))
      .catch(() => {});
  }, []);
  useEffect(() => { if (ready) loadHistory(); }, [ready, historyVersion, loadHistory]);

  // One "Pemakaian fitur" session per page (the server merges repeats within 30 minutes).
  useEffect(() => {
    if (!ready) return;
    const page = PAGE_KEYS[pathname === "/" ? "/" : "/" + pathname.split("/")[1]];
    if (page) authFetch("/api/usage/view", { method: "POST", body: JSON.stringify({ page }) }).catch(() => {});
  }, [ready, pathname]);

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
  const onChat = pathname === "/";
  const name = user?.full_name || user?.username || "";
  const initial = (name.trim()[0] || "U").toUpperCase();

  const navLink = (it: NavItem) => {
    const active = isActive(it.href) || !!it.also?.some(isActive);
    const badge = it.href === "/watchlist" ? alertCount : it.href === "/tindak" ? taskCount : 0;
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

        <button className="search" onClick={() => setPalette(true)} aria-label="Cari cepat" aria-keyshortcuts="Control+K">
          <Icon name="search" />Cari cepat<span className="kbd">Ctrl K</span>
        </button>

        <nav className="nav">
          {NAV_GROUPS.map((g) => (
            <Fragment key={g.title}>
              <div className="navh">{g.title}</div>
              {g.items.map(navLink)}
            </Fragment>
          ))}
        </nav>

        {/* Conversation history stays next to the chat it belongs to; elsewhere it is one Ctrl K away. */}
        {onChat && (<>
          <div className="navh">Riwayat</div>
          <div className="hist">
            {history.length === 0 && <span className="empty">Belum ada percakapan</span>}
            {history.slice(0, 30).map((h) => (
              <button key={h.session_id} className={h.session_id === activeSession ? "on" : ""}
                onClick={() => openSession(h.session_id)} disabled={busy} title={h.title}>
                <Icon name="hist" />
                <span>{h.title || "Percakapan tanpa judul"}</span>
              </button>
            ))}
          </div>
        </>)}

        <div className="spacer" />
        {(onChat || onApk) && (
          <Link href="/unduh" className={`apk ${onApk ? "on" : ""}`}>
            <span className="ai"><Icon name="dl" /></span>
            <div><b>Aplikasi Android</b><small>Agent Java {apkVersion ? shortVersion(apkVersion) : ""}{apkVersion ? " · " : ""}Unduh APK</small></div>
          </Link>
        )}
        <Link href="/profile" className={`me ${onProfile ? "on" : ""}`} aria-current={onProfile ? "page" : undefined}>
          <span className="avatar">{initial}</span>
          <div><b>{name}</b><small>{roleLabel} · Circle Java</small></div>
          <Icon name="chev" />
        </Link>
      </aside>

      <div className={`main ${mainClassName ?? ""}`}>{children}</div>
      {palette && <QuickSearch onClose={() => setPalette(false)} history={history} admin={admin}
        onOpenSession={(sid) => { setPalette(false); openSession(sid); }} />}
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
