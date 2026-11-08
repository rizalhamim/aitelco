"use client";
/* v3 05 Tindak Lanjut (design/mockup-v3/features/05-tindak-lanjut.html): alerts and
   insights become tasks with a PIC, due date, checklist and field photos. A task with a KPI
   criterion closes only when the KPI is proven better (14 days before vs 14 days after, same
   weekdays), checked daily by the server. Cards move between lanes by drag and drop. */
import { Suspense, useCallback, useEffect, useRef, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { getJson, REGION_OPTIONS, Tap, V3State, V3Top } from "../components/v3/V3";
import { authFetch } from "@/lib/auth";
import "../v3.css";

type Person = { id: number | null; name: string; full_name: string; unit: string | null; initial: string; color: string };
type Card = {
  id: number; title: string; status: string; origin: string; origin_label: string; origin_icon: string; origin_tone: string;
  criterion: string | null; progress: number | null; items_done: number; items_total: number; photos: number; pic: Person;
  due: { label: string | null; long?: string; urgent: boolean; late_days?: number }; region: string | null; kabupaten: string | null;
  priority: string; impact: number | null; mine: boolean; verify: null | { text: string; ok: boolean | null }; done_label?: string;
};
type Detail = Card & {
  origin_long: string; scope_label: string; priority_label: string; items: { id: number; text: string; done: boolean }[];
  photos_list: { id: number; caption: string | null; created_at: string }[];
  verify_detail: null | { metric_label: string | null; before_label: string; after_label: string; before_pct: number | null; after_pct: number | null; after_days: number; result: string | null; window: number; reason?: string | null };
  history: { user: string; text: string; at_label: string }[];
};
export type TBoard = {
  stats: { open: number; open_mine: number; due_today: number; late: number; late_days: number; waiting: number; proven: number; verified: number };
  lanes: { baru: Card[]; dikerjakan: Card[]; verifikasi: Card[] }; done_total: number; done: Card[]; month_chip: string;
};

const LANES = [["baru", "Baru", "#9FB1AD"], ["dikerjakan", "Dikerjakan", "#22B8C9"], ["verifikasi", "Verifikasi KPI", "#6A4CB5"]] as const;
const SHOW = 2;
const ONE = (v: number) => (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 }) + "%";
const PHOTO_BG = ["linear-gradient(135deg,#5BCEC3,#0A6A5F)", "linear-gradient(135deg,#8FDFD7,#0E6F7C)", "linear-gradient(135deg,#C0EDE8,#15A697)"];

function TindakView() {
  const router = useRouter();
  const sp = useSearchParams();
  const sel = Number(sp.get("task")) || null;
  const [view, setView] = useState<"all" | "mine">("all");
  const [region, setRegion] = useState("");
  const [sort, setSort] = useState<"due" | "priority">("due");
  const [data, setData] = useState<TBoard | null>(null);
  const [loaded, setDetail] = useState<Detail | null>(null);
  const detail = sel && loaded?.id === sel ? loaded : null;
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState<Record<string, boolean>>({});
  const [dialog, setDialog] = useState<null | "new" | "edit">(null);
  const [note, setNote] = useState<string | null>(null);
  const [dragId, setDragId] = useState<number | null>(null);

  const flash = (t: string) => { setNote(t); window.setTimeout(() => setNote(null), 2600); };
  const load = useCallback(() => authFetch(`/api/tindak/tasks?${new URLSearchParams({ view, region })}`).then((r) => getJson<TBoard>(r))
    .then((d) => { setData(d); setError(null); }).catch((e) => setError(e.message)), [view, region]);
  const loadDetail = useCallback((id: number) => authFetch(`/api/tindak/tasks/${id}`).then((r) => getJson<Detail>(r)).then(setDetail).catch(() => setDetail(null)), []);
  useEffect(() => { load(); }, [load]);
  useEffect(() => { if (sel) loadDetail(sel); }, [sel, loadDetail]);

  const select = (id: number | null) => router.replace(id ? `/tindak?task=${id}` : "/tindak");

  async function act(path: string, method: string, body?: unknown, ok?: string) {
    const r = await authFetch(path, { method, body: body !== undefined ? JSON.stringify(body) : undefined });
    if (!r.ok) { let m = "Gagal"; try { m = (await r.json()).detail || m; } catch { /* no body */ } flash(m); return null; }
    if (ok) flash(ok);
    return r.json();
  }
  async function refresh(id?: number) { await load(); if (id ?? sel) loadDetail((id ?? sel)!); }

  async function exportCsv() {
    const r = await authFetch("/api/tindak/export.csv");
    if (!r.ok) { flash("Ekspor gagal"); return; }
    const a = document.createElement("a");
    a.href = URL.createObjectURL(await r.blob()); a.download = "tindak-lanjut.csv"; a.click();
    window.setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }
  async function moveTo(id: number, status: string) {
    if (await act(`/api/tindak/tasks/${id}`, "PATCH", { status }, "Status diperbarui")) refresh(id);
  }

  const sortCards = (cs: Card[]) => sort === "due" ? cs : [...cs].sort((a, b) => Math.abs(b.impact ?? 0) - Math.abs(a.impact ?? 0));
  const s = data?.stats;

  return (
    <AppShell>
      <V3Top title="Tindak Lanjut" subtitle="Dari alert dan insight ke tindakan yang terukur" region={region} onRegion={setRegion} month={data?.month_chip} />
      <div className="v3 f-05-tindak-lanjut">
        <V3State error={error} loading={!data && !error} />
        {data && s && (
          <div className="body" style={detail ? undefined : { gridTemplateColumns: "1fr" }}>
            <div className="col">
              <div className="hd"><div><div className="eb">Tindak lanjut · {view === "mine" ? "milik saya" : "semua tim"}</div><h1>Tindakan tim {region ? REGION_OPTIONS.find((o) => o.key === region)?.label ?? region : "Circle Java"}</h1></div><div className="grow" />
                <Tap className="bt" onClick={exportCsv}><Icon name="dl" />Ekspor</Tap><Tap className="bt pri" onClick={() => setDialog("new")}><Icon name="plus" />Tugas baru</Tap></div>
              <div className="stats">
                <div className="sx"><small>Terbuka</small><b>{s.open}</b><span>{s.open_mine} milik kamu</span></div>
                <div className={`sx ${s.due_today ? "k" : ""}`}><small>Jatuh tempo hari ini</small><b>{s.due_today}</b><span>{s.late ? `${s.late} terlambat ${s.late_days} hari` : "tidak ada yang terlambat"}</span></div>
                <div className="sx"><small>Menunggu verifikasi KPI</small><b>{s.waiting}</b><span>data 14 hari belum lengkap</span></div>
                <div className="sx g"><small>Terbukti memperbaiki KPI</small><b>{s.proven} dari {s.verified}</b><span>tugas selesai, 30 hari terakhir</span></div>
              </div>
              <div className="filt">
                <Tap className={view === "all" && !region ? "on" : ""} onClick={() => { setView("all"); setRegion(""); }}>Semua</Tap>
                <Tap className={view === "mine" ? "on" : ""} onClick={() => setView(view === "mine" ? "all" : "mine")}>Milik saya</Tap>
                {REGION_OPTIONS.slice(1).map((o) => <Tap key={o.key} className={region === o.key ? "on" : ""} onClick={() => setRegion(region === o.key ? "" : o.key)}>{o.label}</Tap>)}
                <div className="grow" />
                <Tap onClick={() => setSort(sort === "due" ? "priority" : "due")}>Urut: {sort === "due" ? "tenggat" : "prioritas"}</Tap>
              </div>
              <div className="board">
                {LANES.map(([k, label, color]) => {
                  const cards = sortCards(data.lanes[k]);
                  const all = open[k];
                  return (
                    <div key={k} className="lane" onDragOver={(e) => e.preventDefault()} onDrop={() => { if (dragId) moveTo(dragId, k); setDragId(null); }}>
                      <div className="lh"><i style={{ background: color }} />{label}<em>{cards.length}</em><span className="grow" />
                        {k === "baru" && <Tap label="Tugas baru" style={{ display: "flex" }} onClick={() => setDialog("new")}><Icon name="plus" /></Tap>}</div>
                      {(all ? cards : cards.slice(0, SHOW)).map((c) => <TaskCard key={c.id} c={c} sel={c.id === sel} onClick={() => select(c.id)} onDrag={setDragId} />)}
                      {cards.length > SHOW && <Tap className="more" onClick={() => setOpen({ ...open, [k]: !all })}>{all ? "Tampilkan lebih sedikit" : `${cards.length - SHOW} tugas lain`}</Tap>}
                      {k === "verifikasi" && data.done_total > 0 && <Tap className="more" onClick={() => setOpen({ ...open, done: !open.done })}>Selesai: {data.done_total} tugas</Tap>}
                      {k === "verifikasi" && open.done && data.done.map((c) => <TaskCard key={c.id} c={c} sel={c.id === sel} onClick={() => select(c.id)} onDrag={setDragId} />)}
                    </div>
                  );
                })}
              </div>
            </div>
            {detail && <Drawer d={detail} onClose={() => select(null)} onEdit={() => setDialog("edit")}
              onItem={async (iid, done) => { if (await act(`/api/tindak/tasks/${detail.id}/items/${iid}`, "PATCH", { done })) refresh(detail.id); }}
              onPhoto={async (data, caption) => {
                const pos = await new Promise<GeolocationPosition | null>((ok) => navigator.geolocation ? navigator.geolocation.getCurrentPosition(ok, () => ok(null), { timeout: 4000 }) : ok(null));
                if (await act(`/api/tindak/tasks/${detail.id}/photos`, "POST", { data, caption, lat: pos?.coords.latitude, lon: pos?.coords.longitude }, "Foto ditambahkan")) refresh(detail.id);
              }} />}
            {note && <div className="v3toast" role="status">{note}</div>}
          </div>
        )}
        {dialog && (
          <div className="v3dlg-scrim" onClick={() => setDialog(null)}>
            <div className="v3dlg" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
              <div className="v3dlg-h"><b>{dialog === "new" ? "Tugas baru" : "Ubah tugas"}</b><button aria-label="Tutup" onClick={() => setDialog(null)}><Icon name="plus" style={{ transform: "rotate(45deg)" }} /></button></div>
              <TaskForm d={dialog === "edit" ? detail : null} onSave={async (body) => {
                const r = dialog === "new" ? await act("/api/tindak/tasks", "POST", body, "Tugas dibuat") : await act(`/api/tindak/tasks/${detail!.id}`, "PATCH", body, "Tugas diperbarui");
                if (r) { setDialog(null); await load(); select(r.id); if (dialog === "edit") loadDetail(r.id); }
              }} />
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function TaskCard({ c, sel, onClick, onDrag }: { c: Card; sel: boolean; onClick: () => void; onDrag: (id: number | null) => void }) {
  return (
    <div className={`tk ${sel ? "sel" : ""}`} role="button" tabIndex={0} draggable onDragStart={() => onDrag(c.id)} onDragEnd={() => onDrag(null)}
      onClick={onClick} onKeyDown={(e) => { if (e.key === "Enter") onClick(); }} style={{ cursor: "pointer" }}>
      <span className={`org ${c.origin_tone}`}><Icon name={c.origin_icon} />{c.origin_label}</span><b>{c.title}</b>
      {c.verify ? <div className="ver" style={c.verify.ok ? { color: "#1F7A3A" } : c.verify.ok === false ? { color: "#C42B2B" } : undefined}><Icon name={c.verify.ok ? "check" : c.verify.ok === false ? "warn" : "hist"} />{c.verify.text}</div>
        : c.criterion && <div className="kpi"><Icon name="check" />{c.criterion}</div>}
      {c.status === "dikerjakan" && c.progress != null && <div className="bar"><i style={{ width: `${Math.round(c.progress * 100)}%` }} /></div>}
      <div className="mt"><span className="av" style={{ background: c.pic.color }}>{c.pic.initial}</span>{c.pic.name}<span className="grow" />
        {c.done_label && (c.status === "verifikasi" || c.status === "selesai") ? c.done_label : (<>
          {c.photos > 0 && <><Icon name="cam" />{c.photos}</>}
          {c.due.label && <span className={`due ${c.due.urgent ? "k" : ""}`}><Icon name="cal" />{c.due.label}</span>}
        </>)}
      </div>
    </div>
  );
}

function Photo({ id, caption, i }: { id: number; caption: string | null; i: number }) {
  const [url, setUrl] = useState<string | null>(null);
  useEffect(() => {
    let u: string | null = null;
    authFetch(`/api/tindak/photos/${id}`).then((r) => (r.ok ? r.blob() : null)).then((b) => { if (b) { u = URL.createObjectURL(b); setUrl(u); } }).catch(() => {});
    return () => { if (u) URL.revokeObjectURL(u); };
  }, [id]);
  return (
    <div style={{ background: url ? `center / cover no-repeat url(${url})` : PHOTO_BG[i % PHOTO_BG.length] }}>
      <Icon name="cam" />{caption}
    </div>
  );
}

function Drawer({ d, onClose, onEdit, onItem, onPhoto }: { d: Detail; onClose: () => void; onEdit: () => void; onItem: (iid: number, done: boolean) => void; onPhoto: (data: string, caption: string) => void }) {
  const v = d.verify_detail;
  const done = d.items.filter((i) => i.done).length;
  const file = useRef<HTMLInputElement>(null);
  function pick(e: React.ChangeEvent<HTMLInputElement>) {
    const f = e.target.files?.[0];
    e.target.value = "";
    if (!f) return;
    const img = new Image(), rd = new FileReader();
    rd.onload = () => {
      img.onload = () => {
        // shrink to at most 1600 px so field photos stay under the 2 MB limit
        const k = Math.min(1, 1600 / Math.max(img.width, img.height)), c = document.createElement("canvas");
        c.width = Math.round(img.width * k); c.height = Math.round(img.height * k);
        c.getContext("2d")!.drawImage(img, 0, 0, c.width, c.height);
        const cap = window.prompt("Keterangan foto (contoh: CKJ-012)", "") || "";
        const day = new Date().toLocaleDateString("id-ID", { day: "numeric", month: "short" }).replace(".", "");
        onPhoto(c.toDataURL("image/jpeg", 0.82), cap ? `${cap} · ${day}` : day);
      };
      img.src = String(rd.result);
    };
    rd.readAsDataURL(f);
  }
  return (
    <aside className="dr" aria-label="Detail tugas">
      <div className="top1"><span className={`org ${d.origin_tone}`}><Icon name={d.origin_icon} />{d.origin_long}</span><span className="grow" />
        <Tap className="x" label="Tutup" onClick={onClose}><Icon name="plus" /></Tap></div>
      <h2>{d.title}</h2>
      <div className="meta" role="button" tabIndex={0} title="Ubah PIC, tenggat, atau status" onClick={onEdit} onKeyDown={(e) => { if (e.key === "Enter") onEdit(); }} style={{ cursor: "pointer" }}>
        <div><small>PIC</small><b><span className="av" style={{ background: d.pic.color }}>{d.pic.initial}</span>{d.pic.full_name.split(" ")[0]}{d.pic.unit ? `, ${d.pic.unit}` : ""}</b></div>
        <div><small>Tenggat</small><b style={d.due.urgent ? { color: "#C42B2B" } : undefined}>{d.due.long || "Belum ada"}</b></div>
        <div><small>Wilayah</small><b>{d.scope_label}</b></div>
        <div><small>Prioritas</small><b>{d.priority_label}</b></div>
      </div>
      {d.items.length > 0 && (
        <div className="sect"><h5>Checklist {done} dari {d.items.length}</h5><div className="chk">
          {d.items.map((it) => (
            <div key={it.id}><i className={it.done ? "on" : ""} role="checkbox" aria-checked={it.done} aria-label={it.text} tabIndex={0} style={{ cursor: "pointer" }}
              onClick={() => onItem(it.id, !it.done)} onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onItem(it.id, !it.done); } }}>{it.done && <Icon name="check" />}</i>
              {it.done ? <span className="done">{it.text}</span> : it.text}</div>
          ))}
        </div></div>
      )}
      <div className="sect"><h5>Bukti lapangan</h5><div className="photos">
        {d.photos_list.slice(-5).map((p, i) => <Photo key={p.id} id={p.id} caption={p.caption} i={i} />)}
        <div className="add" role="button" tabIndex={0} style={{ cursor: "pointer" }} onClick={() => file.current?.click()} onKeyDown={(e) => { if (e.key === "Enter") file.current?.click(); }}>
          <Icon name="plus" />Tambah foto<input ref={file} type="file" accept="image/*" capture="environment" onChange={pick} style={{ display: "none" }} /></div>
      </div></div>
      {v && (
        <div className="vk"><div className="r1"><Icon name="pulse" />Verifikasi KPI otomatis</div>
          <p>{v.result === "manual" ? `${v.reason}. Tugas ditutup setelah PIC atau admin memverifikasi.` : `${v.metric_label} ${d.scope_label.split(" · ")[0]} ${v.window} hari sebelum tindakan dibanding ${v.window} hari sesudah, hari yang sama dalam seminggu. Tugas ditutup otomatis jika target tercapai.`}</p>
          <div className="win">
            <div className={v.before_pct == null ? "wait" : ""}><small>{v.before_label}</small><b style={v.before_pct != null ? { color: v.before_pct < 0 ? "#C42B2B" : "#1F7A3A" } : undefined}>{v.before_pct != null ? ONE(v.before_pct) : "Belum lengkap"}</b></div>
            <div className={v.after_pct == null ? "wait" : ""}><small>{v.after_label}</small><b style={v.after_pct != null ? { color: v.after_pct < 0 ? "#C42B2B" : "#1F7A3A" } : undefined}>{v.after_pct != null ? ONE(v.after_pct) : "Menunggu data"}</b></div>
          </div>
          <div className="tl"><i style={{ width: `${Math.round((v.after_days / v.window) * 100)}%` }} /></div></div>
      )}
      <div className="sect"><h5>Riwayat</h5><div className="log">
        {d.history.map((h, i) => <div key={i}><i style={i === 0 ? { background: "#0E8579" } : undefined} /><span><b>{h.user}</b> {h.text} <small>{h.at_label}</small></span></div>)}
      </div></div>
    </aside>
  );
}

const METRIC_OPTS = [["revenue", "Revenue"], ["payload", "Payload"], ["subs", "RGU 90D"], ["gross_add", "Gross add"], ["fwa_gross_add", "Gross add FWA"]] as const;

function TaskForm({ d, onSave }: { d: Detail | null; onSave: (b: Record<string, unknown>) => void }) {
  const [people, setPeople] = useState<{ id: number; name: string }[]>([]);
  const [title, setTitle] = useState(d?.title ?? "");
  const [pic, setPic] = useState<string>(d?.pic.id ? String(d.pic.id) : "");
  const [due, setDue] = useState("");
  const [status, setStatus] = useState(d?.status ?? "baru");
  const [region, setRegion] = useState(d?.region ?? "");
  const [kab, setKab] = useState(d?.kabupaten ?? "");
  const [metric, setMetric] = useState("");
  const [mode, setMode] = useState("change");
  const [thr, setThr] = useState("0");
  const [items, setItems] = useState("");
  useEffect(() => { authFetch("/api/tindak/people").then((r) => (r.ok ? r.json() : { people: [] })).then((j) => setPeople(j.people || [])).catch(() => {}); }, []);
  return (
    <form className="v3form" onSubmit={(e) => {
      e.preventDefault();
      if (d) { onSave({ title, status, ...(pic ? { assignee_id: Number(pic) } : {}), ...(due ? { due_date: due } : {}) }); return; }
      onSave({ title, origin: "manual", region: region || null, kabupaten: kab.trim().toUpperCase() || null, ...(pic ? { assignee_id: Number(pic) } : {}), ...(due ? { due_date: due } : {}),
        ...(metric ? { kpi: { metric, mode, op: ">=", threshold: Number(thr.replace(",", ".")) || 0, level: kab ? "kabupaten" : region ? "region" : "circle", name: kab.trim().toUpperCase() || region || "JAVA" } } : {}),
        items: items.split("\n").map((x) => x.trim()).filter(Boolean) });
    }}>
      <label>Judul<input required minLength={3} value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Contoh: Cek 14 site Garut selatan" /></label>
      <label>PIC<select value={pic} onChange={(e) => setPic(e.target.value)}><option value="">Belum ada</option>{people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
      <label>Tenggat<input type="date" value={due} onChange={(e) => setDue(e.target.value)} /></label>
      {d ? (
        <label>Status<select value={status} onChange={(e) => setStatus(e.target.value)}>
          <option value="baru">Baru</option><option value="dikerjakan">Dikerjakan</option><option value="verifikasi">Selesai dikerjakan, verifikasi KPI</option><option value="selesai">Selesai</option><option value="batal">Batal</option></select></label>
      ) : (<>
        <label>Region<select value={region} onChange={(e) => setRegion(e.target.value)}>{REGION_OPTIONS.map((o) => <option key={o.key} value={o.key}>{o.key ? o.label : "Circle Java"}</option>)}</select></label>
        <label>Kabupaten/kota (opsional)<input value={kab} onChange={(e) => setKab(e.target.value)} placeholder="Contoh: Garut" /></label>
        <label>KPI penutup (opsional)<select value={metric} onChange={(e) => setMetric(e.target.value)}><option value="">Tanpa KPI, ditutup manual</option>{METRIC_OPTS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></label>
        {metric && <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          <label>Kriteria<select value={mode} onChange={(e) => setMode(e.target.value)}><option value="change">Perubahan % minimal</option><option value="per_day">Rata-rata per hari minimal</option></select></label>
          <label>Nilai<input inputMode="decimal" value={thr} onChange={(e) => setThr(e.target.value)} /></label></div>}
        <label>Checklist (satu baris satu item)<textarea value={items} onChange={(e) => setItems(e.target.value)} /></label>
      </>)}
      <button className="v3btn" type="submit">{d ? "Simpan" : "Buat tugas"}</button>
    </form>
  );
}

export default function TindakPage() {
  return <Suspense fallback={<div className="ui-boot" />}><TindakView /></Suspense>;
}
