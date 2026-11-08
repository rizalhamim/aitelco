"use client";
/* Ctrl K quick search (v3 sidebar "Cari cepat"): jump to any page, Statistik, Unduh APK,
   Profil, or one of the user's conversations. Arrow keys move, Enter opens, Esc closes. */
import { useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Icon } from "@/app/components/v2/Icon";
import { NAV_GROUPS, type HistoryItem } from "./AppShell";

type Hit = { key: string; label: string; sub: string; icon: string; bg: string; fg: string; go: () => void };

export default function QuickSearch({ onClose, history, admin, onOpenSession }: {
  onClose: () => void; history: HistoryItem[]; admin: boolean; onOpenSession: (sid: string) => void;
}) {
  const router = useRouter();
  const [q, setQ] = useState("");
  const [sel, setSel] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  useEffect(() => { input.current?.focus(); }, []);

  const hits = useMemo(() => {
    const go = (href: string) => () => { onClose(); router.push(href); };
    const pages: Hit[] = NAV_GROUPS.flatMap((g) => g.items.map((it) => ({
      key: it.href, label: it.label, sub: g.title, icon: it.icon, bg: it.bg, fg: it.fg, go: go(it.href),
    })));
    pages.push({ key: "/unduh", label: "Unduh APK", sub: "Aplikasi Android", icon: "dl", bg: "#E6F7F5", fg: "#0A6A5F", go: go("/unduh") });
    pages.push({ key: "/profile", label: "Profil", sub: "Akun", icon: "user", bg: "#ECF3F1", fg: "#3D4C49", go: go("/profile") });
    if (admin) pages.push({ key: "/statistik", label: "Statistik", sub: "Admin", icon: "bars", bg: "#ECE5FA", fg: "#6A4CB5", go: go("/statistik") });
    const chats: Hit[] = history.map((h) => ({
      key: "s:" + h.session_id, label: h.title || "Percakapan tanpa judul", sub: "Riwayat percakapan", icon: "hist",
      bg: "#ECF3F1", fg: "#5A6B68", go: () => onOpenSession(h.session_id),
    }));
    const t = q.trim().toLowerCase();
    const all = [...pages, ...chats];
    return (t ? all.filter((h) => (h.label + " " + h.sub).toLowerCase().includes(t)) : [...pages, ...chats.slice(0, 6)]).slice(0, 40);
  }, [q, history, admin, onClose, onOpenSession, router]);

  const cur = Math.min(sel, Math.max(0, hits.length - 1));
  function onKey(e: React.KeyboardEvent) {
    if (e.key === "Escape") onClose();
    else if (e.key === "ArrowDown") { e.preventDefault(); setSel(Math.min(cur + 1, hits.length - 1)); }
    else if (e.key === "ArrowUp") { e.preventDefault(); setSel(Math.max(cur - 1, 0)); }
    else if (e.key === "Enter" && hits[cur]) hits[cur].go();
  }

  return (
    <div className="qs-scrim" onClick={onClose}>
      <div className="qs" role="dialog" aria-modal="true" aria-label="Cari cepat" onClick={(e) => e.stopPropagation()} onKeyDown={onKey}>
        <label className="qs-in"><Icon name="search" />
          <input ref={input} value={q} onChange={(e) => { setQ(e.target.value); setSel(0); }} placeholder="Cari halaman atau percakapan" aria-label="Cari halaman atau percakapan" />
          <span className="kbd">Esc</span>
        </label>
        <div className="qs-list" role="listbox">
          {hits.length === 0 && <p className="qs-empty">Tidak ada yang cocok</p>}
          {hits.map((h, i) => (
            <button key={h.key} role="option" aria-selected={i === cur} className={i === cur ? "on" : ""} onMouseEnter={() => setSel(i)} onClick={h.go}>
              <span className="nt" style={{ background: h.bg, color: h.fg }}><Icon name={h.icon} /></span>
              <span className="lb">{h.label}</span><small>{h.sub}</small>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
