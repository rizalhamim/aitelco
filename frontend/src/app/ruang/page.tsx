"use client";
/* v3 04 Ruang Saya (design/mockup-v3/features/04-ruang-saya.html): boards of pins saved
   from agent answers. A pin stores the question (its spec), not the numbers, so every
   open reads the latest dump. Pins move by drag and drop (pointer events, so touch works),
   boards can be shared and sent as a dated PDF on a schedule. */
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { getJson, Tap, V3State, V3Top } from "../components/v3/V3";
import { authFetch } from "@/lib/auth";
import "../v3.css";

type Note = { id: number; user: string; initial: string; color: string; text: string; at_label: string };
type PinData = {
  status: "ok" | "unavailable" | "error" | "frozen"; message?: string; detail?: string;
  value_label?: string; growth_pct?: number | null; growth_label?: string; cur?: (number | null)[]; prev?: (number | null)[]; days?: number;
  month?: string; prev_month?: string; scale?: number; axis_unit?: string;
  tiles?: { label: string; value: string; delta_label: string; good: boolean }[];
  rows?: { name: string; pct_label: string; abs_label: string; pct?: number }[]; basis?: string;
  w?: number; h?: number; shapes?: { name: string; d: string; fill: string; x: number; y: number }[];
  labels?: { name: string; text: string; dark: boolean; good?: boolean }[]; legend?: { color: string; label: string }[];
  for_title?: string | null; notes?: Note[];
  title?: string; summary?: { t: string; s?: string }[];
  estimate?: number; target?: number | null; gap?: number | null; need_per_day?: number | null; per_day?: number; metric?: string;
  question?: string; text?: string; columns?: string[];
};
type Pin = { id: number; board_id: number; kind: string; title: string; subtitle: string | null; origin: string; origin_label: string;
  spec: Record<string, unknown> & { type?: string; for_pin?: number; level?: string }; col: number; position: number; data: PinData | null; ask: string | null; notes_count: number };
type Member = { id: number; name: string; initial: string; color: string; role: string };
export type Board = { id: number; name: string; role: string; summary: string; pins: Pin[]; members: Member[]; columns: number;
  schedule: null | { weekday: number; hour: number; minute: number; label: string; recipients: number; format: string };
  fresh: { ok: boolean; label: string }; month_chip: string };
type BoardList = { boards: { id: number; name: string; pins: number }[]; shared: { id: number; name: string; pins: number }[]; shared_pins: number };

const SRC: Record<string, [string, string, string]> = {
  daily_compare: ["c", "line", "Grafik"], diagnosa: ["c", "spark", "Diagnosa"], simulasi: ["c", "up", "Simulasi"],
  kpi_watch: ["k", "grid", "KPI"], unavailable: ["k", "db", "KPI"], rank_table: ["t", "table", "Tabel"],
  map_change: ["m", "map", "Peta"], notes: ["n", "chat", "Catatan"], answer: ["t", "table", "Jawaban"],
};
const DAYS = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"];
const NOUN: Record<string, string> = { region: "Region", kabupaten: "Kabupaten", kecamatan: "Kecamatan" };

type Drag = { id: number; x0: number; y0: number; dx: number; dy: number; on: boolean; col: number; index: number };

function RuangView() {
  const router = useRouter();
  const sp = useSearchParams();
  const [list, setList] = useState<BoardList | null>(null);
  const [board, setBoard] = useState<Board | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [drag, setDrag] = useState<Drag | null>(null);
  const [dialog, setDialog] = useState<null | "share" | "schedule" | "new" | "shared">(null);
  const [menu, setMenu] = useState<number | null>(null);
  const colRefs = useRef<(HTMLDivElement | null)[]>([]);
  const bid = Number(sp.get("board")) || null;

  const flash = (t: string) => { setNote(t); window.setTimeout(() => setNote(null), 2600); };
  const loadList = useCallback(() => authFetch("/api/ruang/boards").then((r) => getJson<BoardList>(r)).then((l) => { setList(l); return l; }), []);
  const loadBoard = useCallback((id: number) => authFetch(`/api/ruang/boards/${id}`).then((r) => getJson<Board>(r)).then((b) => { setBoard(b); setError(null); }), []);

  useEffect(() => {
    loadList().then((l) => loadBoard(bid ?? l.boards[0]?.id)).catch((e) => setError(e.message));
  }, [bid, loadList, loadBoard]);

  const openBoard = (id: number) => router.replace(`/ruang?board=${id}`);
  const current = board?.id;

  // columns of pins, in board order
  const cols: Pin[][] = Array.from({ length: board?.columns ?? 3 }, () => []);
  for (const p of board?.pins ?? []) cols[Math.min(p.col, cols.length - 1)].push(p);

  /* ── drag and drop ── */
  function onDown(e: React.PointerEvent, p: Pin) {
    if ((e.target as HTMLElement).closest("[data-nodrag]") || board?.role === "view") return;
    setDrag({ id: p.id, x0: e.clientX, y0: e.clientY, dx: 0, dy: 0, on: false, col: p.col, index: cols[p.col].filter((x) => x.id !== p.id).indexOf(p) });
  }
  useEffect(() => {
    if (!drag) return;
    const move = (e: PointerEvent) => {
      setDrag((d) => {
        if (!d) return d;
        const dx = e.clientX - d.x0, dy = e.clientY - d.y0;
        const on = d.on || Math.hypot(dx, dy) > 4;
        if (!on) return d;
        // target column under the pointer, then the slot among the other pins
        let col = d.col;
        colRefs.current.forEach((el, i) => { if (el) { const r = el.getBoundingClientRect(); if (e.clientX >= r.left && e.clientX <= r.right) col = i; } });
        const els = [...(colRefs.current[col]?.querySelectorAll<HTMLElement>("[data-pin]") ?? [])].filter((el) => Number(el.dataset.pin) !== d.id);
        let index = els.length;
        for (let i = 0; i < els.length; i++) { const r = els[i].getBoundingClientRect(); if (e.clientY < r.top + r.height / 2) { index = i; break; } }
        return { ...d, dx, dy, on, col, index };
      });
    };
    const up = () => {
      setDrag((d) => {
        if (d?.on && board) {
          const next = cols.map((c) => c.filter((p) => p.id !== d.id).map((p) => p.id));
          next[d.col].splice(d.index, 0, d.id);
          authFetch(`/api/ruang/boards/${board.id}/order`, { method: "PUT", body: JSON.stringify({ columns: next }) })
            .then(() => loadBoard(board.id)).catch(() => flash("Urutan gagal disimpan"));
        }
        return null;
      });
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    return () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [drag?.id, board]);

  async function act(path: string, method: string, body?: unknown, ok?: string) {
    const r = await authFetch(path, { method, body: body ? JSON.stringify(body) : undefined });
    if (!r.ok) { let m = "Gagal"; try { m = (await r.json()).detail || m; } catch { /* no body */ } flash(m); return null; }
    if (ok) flash(ok);
    return r.json();
  }

  /** Render one column with the drop slot where the dragged pin would land. */
  function column(ci: number) {
    const pins = cols[ci];
    const out: React.ReactNode[] = [];
    const others = pins.filter((p) => !drag?.on || p.id !== drag.id);
    let slot = 0;
    for (const p of pins) {
      const dragging = drag?.on && p.id === drag.id;
      if (!dragging && drag?.on && drag.col === ci && slot === drag.index) out.push(<div key="drop" className="drop">Lepas di sini untuk memindah pin</div>);
      out.push(
        <PinCard key={p.id} p={p} dragging={!!dragging} drag={dragging ? drag : null} onDown={(e) => onDown(e, p)}
          menuOpen={menu === p.id} onMenu={() => setMenu(menu === p.id ? null : p.id)}
          boards={list?.boards.filter((b) => b.id !== current) ?? []}
          onAsk={(q) => router.push(`/?q=${encodeURIComponent(q)}`)}
          onDelete={async () => { setMenu(null); if (await act(`/api/ruang/pins/${p.id}`, "DELETE", undefined, "Pin dihapus")) { loadBoard(p.board_id); loadList(); } }}
          onMove={async (to) => { setMenu(null); if (await act(`/api/ruang/pins/${p.id}`, "PATCH", { board_id: to }, "Pin dipindah")) { loadBoard(p.board_id); loadList(); } }}
          onNote={async (text) => { const target = p.spec.for_pin || p.id; if (await act(`/api/ruang/pins/${target}/notes`, "POST", { text })) loadBoard(p.board_id); }} />);
      if (!dragging) slot++;
    }
    if (drag?.on && drag.col === ci && drag.index >= others.length) out.push(<div key="drop" className="drop">Lepas di sini untuk memindah pin</div>);
    if (ci === cols.length - 1 && board) out.push(<Schedule key="sched" board={board} onEdit={() => setDialog("schedule")} />);
    return out;
  }

  return (
    <AppShell>
      <V3Top title="Ruang Saya" subtitle="Papan pantauan pribadi dari jawaban agent" month={board?.month_chip} />
      <div className="v3 f-04-ruang-saya">
        <V3State error={error} loading={!board && !error} />
        {board && list && (
          <div className="body">
            <div className="hd">
              <div><div className="eb">Ruang Saya · {board.role === "owner" ? "papan pribadi" : "papan tim"}</div><h1>{board.name}</h1><p>{board.summary}</p></div>
              <div className="grow" />
              <div className="share">
                <span className="faces">{board.members.slice(0, 5).map((m, i) => <i key={m.id} title={m.name} style={{ background: m.color, ...(i === 0 ? { marginLeft: 0 } : {}) }}>{m.initial}</i>)}</span>
                <Tap className="bt" onClick={() => loadBoard(board.id).then(() => flash("Angka disegarkan dari dump terbaru"))}><Icon name="refresh" />Segarkan</Tap>
                <Tap className="bt" onClick={() => setDialog("schedule")}><Icon name="mail" />Jadwal kirim</Tap>
                <Tap className="bt pri" onClick={() => setDialog("share")}><Icon name="users" />Bagikan papan</Tap>
              </div>
            </div>
            <div className="boards" role="tablist">
              {list.boards.map((b) => <Tap key={b.id} className={b.id === current ? "on" : ""} pressed={b.id === current} onClick={() => openBoard(b.id)}>{b.name}<em>{b.pins}</em></Tap>)}
              {list.shared.length > 0 && <Tap className={list.shared.some((b) => b.id === current) ? "on" : ""} onClick={() => setDialog("shared")}>Dibagikan ke saya<em>{list.shared_pins}</em></Tap>}
              <Tap className="add" onClick={() => setDialog("new")}><Icon name="plus" />Papan baru</Tap>
              <span className="grow" />
              <span className="fresh" style={{ border: 0 }}><i style={board.fresh.ok ? undefined : { background: "#F5A623", boxShadow: "0 0 0 4px #FDF3E2" }} />{board.fresh.label}</span>
            </div>
            {board.pins.length === 0 && (
              <div className="empty" style={{ maxWidth: 520 }}><Icon name="layers" /><b>Papan ini masih kosong</b>
                <p>Tekan Pin di jawaban Tanya Agent, kartu Brief Pagi, Diagnosa, atau Klasemen. Pin menyimpan pertanyaan, jadi angkanya selalu dari dump terbaru.</p></div>
            )}
            <div className="grid">
              {cols.map((_, ci) => <div key={ci} ref={(el) => { colRefs.current[ci] = el; }} style={{ display: "flex", flexDirection: "column", gap: 14, minHeight: 60 }}>{column(ci)}</div>)}
            </div>
            {note && <div className="v3toast" role="status">{note}</div>}
          </div>
        )}
        {dialog && board && list && (
          <Dialog title={{ share: "Bagikan papan", schedule: "Jadwal kirim", new: "Papan baru", shared: "Dibagikan ke saya" }[dialog]} onClose={() => setDialog(null)}>
            {dialog === "new" && <NewBoard onSave={async (name) => { const b = await act("/api/ruang/boards", "POST", { name }, "Papan dibuat"); if (b) { setDialog(null); await loadList(); openBoard(b.id); } }} />}
            {dialog === "shared" && (
              <div className="v3list">{list.shared.map((b) => <button key={b.id} onClick={() => { setDialog(null); openBoard(b.id); }}>{b.name}<small>{b.pins} pin</small></button>)}</div>
            )}
            {dialog === "share" && <ShareForm board={board} onAdd={async (user, role) => { const r = await act(`/api/ruang/boards/${board.id}/members`, "POST", { user, role }, "Papan dibagikan"); if (r) loadBoard(board.id); }}
              onRemove={async (uid) => { if (await act(`/api/ruang/boards/${board.id}/members/${uid}`, "DELETE")) loadBoard(board.id); }} />}
            {dialog === "schedule" && <ScheduleForm board={board} onSave={async (patch) => { const b = await act(`/api/ruang/boards/${board.id}`, "PATCH", patch, "Jadwal disimpan"); if (b) { setBoard(b); setDialog(null); } }}
              onSend={async () => { await act(`/api/ruang/boards/${board.id}/send`, "POST", undefined, "Papan dikirim ke email anggota"); }} />}
          </Dialog>
        )}
      </div>
    </AppShell>
  );
}

function PinCard({ p, dragging, drag, onDown, menuOpen, onMenu, boards, onAsk, onDelete, onMove, onNote }: {
  p: Pin; dragging: boolean; drag: Drag | null; onDown: (e: React.PointerEvent) => void; menuOpen: boolean; onMenu: () => void;
  boards: { id: number; name: string }[]; onAsk: (q: string) => void; onDelete: () => void; onMove: (to: number) => void; onNote: (t: string) => void;
}) {
  const t = p.spec.type || "answer";
  const d = p.data;
  const [cls, ic, lab] = SRC[t] ?? SRC.answer;
  const notesPin = t === "notes";
  const sub = notesPin && d?.for_title ? `Menempel di pin ${d.for_title}` : p.subtitle;
  const style = dragging && drag ? { transform: `translate(${drag.dx}px, ${drag.dy}px) rotate(-1.6deg)`, zIndex: 5, touchAction: "none" as const } : { touchAction: "none" as const };
  return (
    <article className={`pin ${dragging ? "drag" : ""}`} data-pin={p.id} style={style}>
      <div className="ph" onPointerDown={onDown} style={{ cursor: "grab", userSelect: "none" }}>
        <Icon name="dots" className="grip" style={dragging ? { color: "#0E8579" } : undefined} />
        <div><h4>{p.title}</h4>{sub && <small>{sub}</small>}</div>
        <Tap className="dots" label="Menu pin" onClick={onMenu}><span data-nodrag style={{ display: "contents" }}><Icon name="dots" /></span></Tap>
      </div>
      {menuOpen && (
        <div className="v3menu" data-nodrag>
          {boards.map((b) => <button key={b.id} onClick={() => onMove(b.id)}>Pindah ke {b.name}</button>)}
          <button onClick={onDelete} style={{ color: "#C42B2B" }}>Hapus pin</button>
        </div>
      )}
      <PinBody t={t} d={d} p={p} onNote={onNote} />
      <div className="pf"><span className={`src ${cls}`}><Icon name={ic} />{lab}</span>
        {notesPin ? `${d?.notes?.length ?? 0} komentar` : d?.status === "unavailable" ? "Menunggu data" : p.origin_label}
        <span className="grow" />
        {p.ask && t !== "kpi_watch" && t !== "unavailable" && <Tap className="ask" onClick={() => onAsk(p.ask!)}><Icon name="spark" />Tanya lanjut</Tap>}
      </div>
    </article>
  );
}

function PinBody({ t, d, p, onNote }: { t: string; d: PinData | null; p: Pin; onNote: (t: string) => void }) {
  const [reply, setReply] = useState("");
  if (!d || d.status === "error") return <div className="empty"><Icon name="warn" /><b>{d?.message || "Pin ini gagal dihitung"}</b></div>;
  if (d.status === "unavailable") return <div className="empty"><Icon name="info" /><b>{d.message}</b>{d.detail && <p>{d.detail}</p>}</div>;
  if (t === "daily_compare") return (<>
    <div className="big"><b>{d.value_label}</b>{d.growth_label && <span className={(d.growth_pct ?? 0) < 0 ? "dn" : "up"}>{d.growth_label}</span>}</div>
    <DailyChart d={d} />
    <div className="lg2"><span><i style={{ background: "#0E8579" }} />{d.month}</span><span><i style={{ background: "#22B8C9" }} />{d.prev_month}, hari yang sama</span></div>
  </>);
  if (t === "notes") return (<>
    {(d.notes ?? []).map((n) => <div key={n.id} className="note2"><span className="av" style={{ background: n.color }}>{n.initial}</span><div><b>{n.user}<small>{n.at_label}</small></b><p>{n.text}</p></div></div>)}
    <input className="reply" data-nodrag value={reply} onChange={(e) => setReply(e.target.value)} placeholder="Balas atau sebut @nama" aria-label="Balas catatan"
      onKeyDown={(e) => { if (e.key === "Enter" && reply.trim()) { onNote(reply.trim()); setReply(""); } }} />
  </>);
  if (t === "map_change") return (<>
    <svg width={d.w} height={d.h} viewBox={`0 0 ${d.w} ${d.h}`} style={{ flex: "none" }} role="img" aria-label={p.title}>
      <rect width={d.w} height={d.h} rx={14} fill="#EEF5F3" />
      {(d.shapes ?? []).map((s) => <path key={s.name} d={s.d} fill={s.fill} stroke="#fff" strokeWidth={2}><title>{s.name}</title></path>)}
      {(d.labels ?? []).map((l, i) => {
        const s = d.shapes?.find((x) => x.name === l.name);
        if (!s) return null;
        return <text key={l.name} x={s.x} y={s.y} textAnchor="middle" fontSize={10.5} fontWeight={l.good ? 400 : i === 0 ? 700 : 600}
          fill={l.good ? "#1F7A3A" : l.dark ? "#fff" : "#3D4C49"} style={{ fontFamily: "var(--f-display)" }}>{l.text}</text>;
      })}
    </svg>
    <div className="lg2">{(d.legend ?? []).map((l) => <span key={l.label}><i style={{ background: l.color }} />{l.label}</span>)}</div>
  </>);
  if (t === "kpi_watch") return (
    <div className="kgrid">{(d.tiles ?? []).map((k) => <div key={k.label}><small>{k.label}</small><b>{k.value}</b> <span className={k.good ? "up" : "dn"}>{k.delta_label}</span></div>)}</div>
  );
  if (t === "rank_table") return (
    <table className="mt"><thead><tr><th>{NOUN[String(p.spec.level || "kabupaten")]}</th><th className="n">%</th><th className="n">Rp</th></tr></thead>
      <tbody>{(d.rows ?? []).map((r) => <tr key={r.name}><td><b>{r.name}</b></td><td className={`n ${(r.pct ?? 0) < 0 ? "dn" : "up"}`}>{r.pct_label}</td><td className="n">{r.abs_label}</td></tr>)}</tbody></table>
  );
  if (t === "diagnosa") return <p style={{ margin: 0, font: "400 13px/1.5 var(--f-body)", color: "#3D4C49" }}>{(d.summary ?? []).map((s, i) => s.s ? <b key={i}>{s.t}</b> : <span key={i}>{s.t}</span>)}<br /><small style={{ color: "#5A6B68" }}>{d.basis}</small></p>;
  if (t === "simulasi") {
    const rp = (v?: number | null) => v == null ? "–" : `Rp ${(v / 1e9).toLocaleString("id-ID", { maximumFractionDigits: 1 })} M`;
    const isRp = d.metric === "revenue";
    const f = (v?: number | null) => v == null ? "–" : isRp ? rp(v) : Math.round(v).toLocaleString("id-ID");
    return <div className="kgrid"><div><small>Estimasi akhir bulan</small><b>{f(d.estimate)}</b></div><div><small>Target</small><b>{f(d.target)}</b></div>
      <div><small>Gap</small><b className={(d.gap ?? 0) < 0 ? "dn" : "up"}>{f(d.gap)}</b></div><div><small>Perlu per hari</small><b>{f(d.need_per_day)}</b></div></div>;
  }
  // frozen answer
  return (<>
    {d.text && <p style={{ margin: 0, font: "400 13px/1.5 var(--f-body)", color: "#3D4C49" }}>{d.text}</p>}
    {d.columns && d.rows && (
      <table className="mt"><thead><tr>{d.columns.slice(0, 4).map((c) => <th key={c}>{c}</th>)}</tr></thead>
        <tbody>{(d.rows as unknown as Record<string, unknown>[]).slice(0, 8).map((r, i) => <tr key={i}>{d.columns!.slice(0, 4).map((c) => <td key={c}>{String(r[c] ?? "")}</td>)}</tr>)}</tbody></table>
    )}
  </>);
}

/** MTD per day (solid) vs the same days last month (dashed), as the mockup pin chart. */
function DailyChart({ d }: { d: PinData }) {
  const W = 370, H = 110, x0 = 40, x1 = 352, yb = 96, yt = 16;
  const s = d.scale || 1;
  const cur = (d.cur ?? []).map((v) => v == null ? null : v / s), prev = (d.prev ?? []).map((v) => v == null ? null : v / s);
  const n = Math.max(prev.length, cur.length, 2);
  const mx = Math.max(1, ...cur.filter((v): v is number => v != null), ...prev.filter((v): v is number => v != null));
  const step = mx > 20 ? Math.ceil(mx / 20) * 10 : Math.ceil(mx / 2);
  const top = step * 2;
  const X = (i: number) => x0 + ((x1 - x0) * i) / (n - 1), Y = (v: number) => yb - ((yb - yt) * v) / top;
  const path = (a: (number | null)[]) => a.map((v, i) => v == null ? "" : `${i && a[i - 1] != null ? "L" : "M"}${X(i).toFixed(1)} ${Y(v).toFixed(1)}`).join(" ");
  const last = cur.length - 1;
  const every = Math.max(1, Math.ceil(cur.length / 6));
  const T = { fontFamily: "var(--f-display)" };
  const fmt = (v: number) => v.toLocaleString("id-ID", { maximumFractionDigits: 1 });
  return (
    <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} style={{ flex: "none" }} role="img" aria-label={`Harian ${d.month} vs ${d.prev_month}`}>
      <line x1={28} x2={366} y1={yb} y2={yb} stroke="#B9C6C3" /><line x1={28} x2={366} y1={(yb + yt) / 2} y2={(yb + yt) / 2} stroke="#ECF3F1" /><line x1={28} x2={366} y1={yt} y2={yt} stroke="#ECF3F1" />
      {[0, step, top].map((v, i) => <text key={i} x={22} y={[99, 59, 19][i]} textAnchor="end" fontSize={10} fill="#5A6B68" style={T}>{fmt(v)}</text>)}
      <path d={path(prev)} fill="none" stroke="#22B8C9" strokeWidth={2} strokeDasharray="5 4" />
      <path d={path(cur)} fill="none" stroke="#0E8579" strokeWidth={3} strokeLinecap="round" />
      {last >= 0 && cur[last] != null && <circle cx={X(last)} cy={Y(cur[last]!)} r={4} fill="#fff" stroke="#0E8579" strokeWidth={2.5} />}
      {cur.map((_, i) => (i % every === 0 || i === last) && <text key={i} x={X(i)} y={110} textAnchor="middle" fontSize={10} fill="#5A6B68" style={T}>{i + 1}{i === last ? ` ${d.month}` : ""}</text>)}
    </svg>
  );
}

function Schedule({ board, onEdit }: { board: Board; onEdit: () => void }) {
  const s = board.schedule;
  return (
    <div className="sched"><b>Kirim papan ini sebelum rapat</b>
      <p>{s ? `Setiap ${s.label}, ${s.format} ke ${s.recipients} orang. Angka dibekukan saat dikirim dan diberi tanggal data.` : "Belum ada jadwal. Atur hari dan jam, PDF dikirim ke anggota papan dengan angka yang dibekukan dan diberi tanggal data."}</p>
      <div className="row">{s ? (<><span>{s.label}</span><span>{s.format}</span><span>{s.recipients} orang</span></>) : <Tap onClick={onEdit}><span style={{ display: "contents" }}>Atur jadwal</span></Tap>}</div>
    </div>
  );
}

function Dialog({ title, children, onClose }: { title: string; children: React.ReactNode; onClose: () => void }) {
  return (
    <div className="v3dlg-scrim" onClick={onClose}>
      <div className="v3dlg" role="dialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <div className="v3dlg-h"><b>{title}</b><button aria-label="Tutup" onClick={onClose}><Icon name="plus" style={{ transform: "rotate(45deg)" }} /></button></div>
        {children}
      </div>
    </div>
  );
}

function NewBoard({ onSave }: { onSave: (name: string) => void }) {
  const [name, setName] = useState("");
  return <form className="v3form" onSubmit={(e) => { e.preventDefault(); if (name.trim()) onSave(name.trim()); }}>
    <label>Nama papan<input autoFocus value={name} onChange={(e) => setName(e.target.value)} placeholder="Contoh: Rapat Senin" maxLength={120} /></label>
    <button className="v3btn" type="submit">Buat papan</button></form>;
}

function ShareForm({ board, onAdd, onRemove }: { board: Board; onAdd: (user: string, role: string) => void; onRemove: (uid: number) => void }) {
  const [user, setUser] = useState(""), [role, setRole] = useState("view");
  const owner = board.role === "owner";
  return <div className="v3form">
    <div className="v3list">{board.members.map((m) => (
      <div key={m.id} className="v3mem"><i style={{ background: m.color }}>{m.initial}</i><span>{m.name}<small>{m.role === "owner" ? "Pemilik" : m.role === "edit" ? "Bisa mengubah" : "Bisa melihat"}</small></span>
        {owner && m.role !== "owner" && <button onClick={() => onRemove(m.id)}>Hapus</button>}</div>))}</div>
    {owner && <form onSubmit={(e) => { e.preventDefault(); if (user.trim()) { onAdd(user.trim(), role); setUser(""); } }} style={{ display: "grid", gap: 10 }}>
      <label>Username atau email<input value={user} onChange={(e) => setUser(e.target.value)} placeholder="nama atau nama@bizplan-java.com" /></label>
      <label>Akses<select value={role} onChange={(e) => setRole(e.target.value)}><option value="view">Bisa melihat</option><option value="edit">Bisa mengubah</option></select></label>
      <button className="v3btn" type="submit">Bagikan</button></form>}
  </div>;
}

function ScheduleForm({ board, onSave, onSend }: { board: Board; onSave: (p: Record<string, unknown>) => void; onSend: () => void }) {
  const s = board.schedule;
  const [day, setDay] = useState(s ? s.weekday : 0), [time, setTime] = useState(s ? `${String(s.hour).padStart(2, "0")}:${String(s.minute).padStart(2, "0")}` : "07:30");
  const [emails, setEmails] = useState("");
  const owner = board.role === "owner";
  return <form className="v3form" onSubmit={(e) => { e.preventDefault(); const [h, m] = time.split(":").map(Number); onSave({ schedule_weekday: day, schedule_hour: h, schedule_minute: m, ...(emails.trim() ? { schedule_recipients: emails } : {}) }); }}>
    <label>Hari<select value={day} disabled={!owner} onChange={(e) => setDay(Number(e.target.value))}>{DAYS.map((d, i) => <option key={d} value={i}>{d}</option>)}</select></label>
    <label>Jam (WIB)<input type="time" value={time} disabled={!owner} onChange={(e) => setTime(e.target.value)} /></label>
    <label>Email tambahan<input value={emails} disabled={!owner} onChange={(e) => setEmails(e.target.value)} placeholder="pisahkan dengan koma" /></label>
    <p style={{ margin: 0, font: "400 12px/1.45 var(--f-body)", color: "#5A6B68" }}>PDF dikirim ke semua anggota papan dan email tambahan. Angka dibekukan saat dikirim dan diberi tanggal data.</p>
    <div style={{ display: "flex", gap: 8 }}>
      {owner && <button className="v3btn" type="submit">Simpan jadwal</button>}
      {owner && s && <button className="v3btn ghost" type="button" onClick={() => onSave({ schedule_weekday: -1 })}>Hapus jadwal</button>}
      <button className="v3btn ghost" type="button" onClick={onSend}>Kirim sekarang</button>
    </div>
  </form>;
}

export default function RuangPage() {
  return <Suspense fallback={<div className="ui-boot" />}><RuangView /></Suspense>;
}
