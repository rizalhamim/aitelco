"use client";
// 06 Laporan v2: library list, live preview with table of contents, and auto-send schedules.
// Report documents come from /api/report-docs as typed sections, the same JSON the Android app renders.
import { Fragment, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Trash2 } from "lucide-react";
import AppShell, { TopBar } from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import SmartChart, { type ChartSpec } from "../components/charts/SmartChart";
import ResultTable from "../components/ResultTable";
import ScheduleDialog, { type Schedule } from "./ScheduleDialog";
import { authFetch, getUser } from "@/lib/auth";
import { downloadXlsx, logExport } from "@/lib/xlsx";
import "../watchlist/watchlist.css";
import "./reports.css";
import "./laporan.css";

type Tone = "up" | "down";
type Cell = string | null | { v: string | null; tone?: Tone; bar?: { w: number; c: string } };
type Kpi = { label: string; value: string | null; delta: string | null; tone: Tone | null };
type Sec = {
  n: number; title: string; sub?: string; type: "summary" | "table" | "note" | "list";
  text?: string; kpis?: Kpi[]; cols?: string[]; rows?: Cell[][]; note?: string; items?: string[];
};
type Doc = {
  kind: string; kind_label: string; title: string; meta: string; eyebrow: string; heading: string; byline: string;
  month_short: string; toc: { n: number; title: string }[]; pages: Sec[][];
};
type DocRef = { kind: "outlook" | "bulanan" | "profile"; region?: string; kabupaten?: string };
type Kind = "analis" | "bulanan" | "mingguan" | "profile" | "performance" | "adhoc";
type LibItem = { id: string; kind: Kind; title: string; meta: string; doc?: DocRef; href?: string };
type Lib = { month_short: string; month_label: string; lead: LibItem[]; rest: LibItem[] };
type PinItem = { id: string; question: string; title: string; chart: ChartSpec; columns: string[]; rows: Record<string, unknown>[]; pinned_at: string };
type Run = { id: number; schedule_id: number | null; title: string; kind: string; region: string; recipients: number; failed?: number; status: string; created_at: string };
type Item = LibItem & { pin?: PinItem; run?: Run };

const KIND: Record<Kind, { label: string; kd: string; bg: string; fg: string; icon: string }> = {
  analis: { label: "Analis", kd: "a", bg: "#FCEDD3", fg: "#B7791F", icon: "bars" },
  bulanan: { label: "Bulanan", kd: "t", bg: "#E6F7F5", fg: "#0A6A5F", icon: "file" },
  mingguan: { label: "Mingguan", kd: "b", bg: "#E1ECFA", fg: "#2C6CB0", icon: "file" },
  profile: { label: "Profile wilayah", kd: "c", bg: "#FBE2DA", fg: "#B5401F", icon: "pin" },
  performance: { label: "Performance", kd: "l", bg: "#F4FCE3", fg: "#5E8A12", icon: "pulse" },
  adhoc: { label: "Ad-hoc", kd: "v", bg: "#ECE5FA", fg: "#6A4CB5", icon: "table" },
};
const FILTERS: (Kind | "semua")[] = ["semua", "analis", "bulanan", "mingguan", "profile", "performance", "adhoc"];
const DAYS = ["Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu", "Minggu"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
const userKey = (k: string) => `${k}::${getUser()?.username || "anon"}`;
const docKey = (d: DocRef) => `${d.kind}|${d.region ?? ""}|${d.kabupaten ?? ""}`;

function readJson<T>(key: string, fallback: T): T {
  if (typeof window === "undefined") return fallback;
  try { return JSON.parse(localStorage.getItem(userKey(key)) || "null") ?? fallback; } catch { return fallback; }
}

/** Date parts in WIB, whatever the browser time zone is. */
function wib(iso: string) {
  const t = new Date(new Date(iso).getTime() + 7 * 3600e3);
  return { d: t.getUTCDate(), m: t.getUTCMonth(), wd: (t.getUTCDay() + 6) % 7, hm: `${String(t.getUTCHours()).padStart(2, "0")}.${String(t.getUTCMinutes()).padStart(2, "0")}`, ms: t.getTime() };
}
function sentLabel(iso: string): string {
  const t = wib(iso);
  const recent = Date.now() + 7 * 3600e3 - t.ms < 7 * 86400e3;
  return recent ? `${DAYS[t.wd]} ${t.hm}` : `${t.d} ${MONTHS[t.m]} ${t.hm}`;
}
function runKind(r: Run): Kind { return r.kind === "bulanan" ? "bulanan" : r.kind === "adhoc" ? "adhoc" : "mingguan"; }
function runDoc(r: Run): DocRef { return /outlook/i.test(r.title) ? { kind: "outlook", region: r.region } : { kind: "bulanan", region: r.region }; }
function runLabel(r: Run): string { return /outlook/i.test(r.title) ? "Outlook" : KIND[runKind(r)].label; }
function schedLine(s: Schedule): string {
  const when = s.frequency === "bulanan" ? `Tanggal ${s.monthday} tiap bulan` : `Setiap ${DAYS[s.weekday % 7]}`;
  const n = `${s.recipients.length} penerima`;
  return s.active ? `${when}, ${String(s.hour).padStart(2, "0")}.00 · ${n}` : `${when} · ${n} · dijeda`;
}

function Bold({ text }: { text: string }) {
  return <>{text.split(/(\*\*[^*]+\*\*)/g).map((p, i) => (p.startsWith("**") ? <b key={i}>{p.slice(2, -2)}</b> : <Fragment key={i}>{p}</Fragment>))}</>;
}

function CellView({ c }: { c: Cell }) {
  const o = c && typeof c === "object" ? c : { v: c };
  if (o.v == null) return <td className="na" title="Belum ada di dump Parquet">-</td>;
  return (
    <td className={"tone" in o && o.tone ? o.tone : undefined}>
      {"bar" in o && o.bar && <span className="bx" style={{ width: o.bar.w, background: o.bar.c }} />}{o.v}
    </td>
  );
}

function Section({ s }: { s: Sec }) {
  return (
    <div className="sec" id={`sec-${s.n}`} data-n={s.n}>
      <h4><i>{s.n}</i>{s.title}{s.sub && <small>{s.sub}</small>}</h4>
      {s.type === "summary" && (
        <>
          {s.text && <div className="sum"><Bold text={s.text} /></div>}
          {!!s.kpis?.length && (
            <div className="pk">
              {s.kpis.map((k) => (
                <div key={k.label}><small>{k.label}</small><b>{k.value ?? "-"}</b>
                  {k.delta && <em className={k.tone ?? undefined}>{k.delta}</em>}</div>
              ))}
            </div>
          )}
        </>
      )}
      {s.type === "table" && (
        <div className="tw">
          <table className="pt">
            <thead><tr>{s.cols?.map((c, i) => <th key={i}>{c}</th>)}</tr></thead>
            <tbody>{s.rows?.map((r, i) => <tr key={i}>{r.map((c, j) => <CellView key={j} c={c} />)}</tr>)}</tbody>
          </table>
          {!s.rows?.length && <div className="note">Belum ada baris untuk bagian ini.</div>}
        </div>
      )}
      {s.type === "note" && <div className="ntext">{s.text}</div>}
      {s.type === "list" && <ul className="li">{s.items?.map((t, i) => <li key={i}>{t}</li>)}</ul>}
      {s.note && s.type !== "note" && <div className="note">{s.note}</div>}
    </div>
  );
}

function cellText(c: Cell): string | null { return c && typeof c === "object" ? c.v : c; }

export default function ReportsPage() {
  const router = useRouter();
  const [lib, setLib] = useState<Lib | null>(null);
  const [libError, setLibError] = useState("");
  const [runs, setRuns] = useState<Run[]>([]);
  const [schedules, setSchedules] = useState<Schedule[] | null>(null);
  const [pins] = useState<PinItem[]>(() => readJson<PinItem[]>("dash_pins", []).filter((p) => p?.rows));
  const [docs, setDocs] = useState<Record<string, Doc | { error: string }>>({});
  const [filter, setFilter] = useState<Kind | "semua">("semua");
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState<string | null>(null);
  const [active, setActive] = useState(1);
  const [pageNo, setPageNo] = useState(1);
  const [hidden, setHidden] = useState<Record<string, number[]>>(() => readJson("report_hidden_sections", {}));
  const [arrange, setArrange] = useState(false);
  const [createMenu, setCreateMenu] = useState(false);
  const [schedDialog, setSchedDialog] = useState<{ edit?: Schedule | null } | null>(null);
  const [notice, setNotice] = useState("");
  const [version, setVersion] = useState(0);
  const scroller = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const colRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    authFetch("/api/report-docs/library").then(async (r) => {
      const d = await r.json().catch(() => null);
      if (r.ok && d?.lead) setLib(d); else setLibError(d?.detail || "Pustaka laporan belum bisa dimuat.");
    }).catch(() => setLibError("Pustaka laporan belum bisa dimuat."));
  }, []);
  useEffect(() => {
    authFetch("/api/report-schedules").then((r) => (r.ok ? r.json() : null)).then((d) => setSchedules(d?.schedules ?? [])).catch(() => setSchedules([]));
    authFetch("/api/report-schedules/runs").then((r) => (r.ok ? r.json() : null)).then((d) => d?.runs && setRuns(d.runs)).catch(() => {});
  }, [version]);
  useEffect(() => {
    if (!notice) return;
    const t = setTimeout(() => setNotice(""), 4000);
    return () => clearTimeout(t);
  }, [notice]);

  const items = useMemo<Item[]>(() => {
    const seen = new Set<string>();
    const runItems: Item[] = [];
    for (const r of runs) {
      if (seen.has(r.title)) continue;
      seen.add(r.title);
      runItems.push({
        id: `run:${r.id}`, kind: runKind(r), title: r.title, run: r, doc: runDoc(r),
        meta: r.status === "gagal" ? `Gagal terkirim · ${sentLabel(r.created_at)}` : `Terkirim ${sentLabel(r.created_at)} · ${r.recipients} penerima`,
      });
    }
    const pinItems: Item[] = pins.map((p) => ({ id: `pin:${p.id}`, kind: "adhoc", title: p.title, meta: `XLSX ${p.rows.length} baris · dari chat`, pin: p }));
    return [...(lib?.lead ?? []), ...runItems.slice(0, 1), ...pinItems, ...(lib?.rest ?? []), ...runItems.slice(1)];
  }, [lib, runs, pins]);

  const shown = items.filter((i) => (filter === "semua" || i.kind === filter)
    && (!query.trim() || `${i.title} ${i.meta} ${KIND[i.kind].label}`.toLowerCase().includes(query.trim().toLowerCase())));
  // Wait for the library before choosing a default, so a pinned answer does not flash first.
  const current = items.find((i) => i.id === selected) ?? (lib || libError ? items.find((i) => !i.href) : null) ?? null;
  const ref = current?.doc;
  const key = ref ? docKey(ref) : "";
  const loaded = key ? docs[key] : undefined;
  const doc = loaded && "pages" in loaded ? loaded : null;

  useEffect(() => {
    if (!ref || docs[key]) return;
    const q = new URLSearchParams({ kind: ref.kind, region: ref.region ?? "", kabupaten: ref.kabupaten ?? "" });
    authFetch(`/api/report-docs/doc?${q}`).then(async (r) => {
      const d = await r.json().catch(() => null);
      setDocs((cur) => ({ ...cur, [key]: r.ok && d?.pages ? d : { error: d?.detail || "Laporan belum bisa disusun." } }));
    }).catch(() => setDocs((cur) => ({ ...cur, [key]: { error: "Laporan belum bisa disusun." } })));
  }, [key, ref, docs]);

  // Sections the user switched off with "Atur bagian laporan", per report kind.
  const hiddenNow = useMemo(() => (doc ? hidden[doc.kind] ?? [] : []), [doc, hidden]);
  const pages = useMemo(() => (doc ? doc.pages.map((p) => p.filter((s) => !hiddenNow.includes(s.n))).filter((p) => p.length) : []), [doc, hiddenNow]);

  // Pin (ad-hoc agent answer) previews are built here; they never had a server document.
  const pinView = current?.pin;
  const title = pinView ? pinView.title : doc?.title ?? current?.title ?? "Laporan";
  const meta = pinView
    ? `Ad-hoc · ${pinView.rows.length} baris · disematkan ${new Date(pinView.pinned_at).toLocaleString("id-ID", { dateStyle: "medium", timeStyle: "short" })}`
    : doc ? (current?.run ? `${KIND[current.kind].label} · terkirim ${sentLabel(current.run.created_at)} · ${current.run.recipients} penerima` : doc.meta)
    : loaded && "error" in loaded ? loaded.error : "Menyusun pratinjau…";
  const toc = pinView ? [{ n: 1, title: "Pertanyaan" }, { n: 2, title: "Data" }] : doc?.toc ?? [];
  const totalPages = pinView ? 2 : pages.length;

  // Keep only whole list items visible above the schedule card; the rest scroll.
  const fitList = useCallback(() => {
    const list = listRef.current, col = colRef.current;
    if (!list || !col) return;
    if (window.innerWidth <= 1100) { list.style.maxHeight = ""; return; }
    const others = [...col.children].filter((c) => c !== list).reduce((a, c) => a + (c as HTMLElement).offsetHeight, 0);
    const gaps = (col.children.length - 1) * 12;
    list.style.maxHeight = "";
    const avail = col.clientHeight - others - gaps;
    let h = 0;
    for (const el of [...list.children] as HTMLElement[]) {
      const bottom = el.offsetTop - list.offsetTop + el.offsetHeight + 3;
      if (bottom <= avail) h = bottom; else break;
    }
    list.style.maxHeight = `${Math.max(h, Math.min(avail, 120))}px`;
  }, []);
  useLayoutEffect(() => {
    fitList();
    const ro = new ResizeObserver(fitList);
    if (colRef.current) ro.observe(colRef.current);
    return () => ro.disconnect();
  }, [fitList, shown.length, schedules, runs]);

  function select(it: Item) {
    if (it.href) { router.push(it.href); return; }
    setSelected(it.id);
    setActive(1);
    setPageNo(1);
    setArrange(false);
    scroller.current?.scrollTo({ top: 0, behavior: "auto" });
  }
  function goSection(n: number) {
    setActive(n);
    const el = scroller.current?.querySelector<HTMLElement>(`#sec-${n}`);
    if (el && scroller.current) scroller.current.scrollTo({ top: el.offsetTop - 16 });
  }
  function onScroll() {
    const sc = scroller.current;
    if (!sc) return;
    const top = sc.scrollTop + 40;
    let a = toc[0]?.n ?? 1;
    sc.querySelectorAll<HTMLElement>(".sec").forEach((s) => { if (s.offsetTop <= top) a = Number(s.dataset.n); });
    let p = 1;
    sc.querySelectorAll<HTMLElement>(".lpage").forEach((s, i) => { if (s.offsetTop <= sc.scrollTop + sc.clientHeight / 2) p = i + 1; });
    if (a !== active) setActive(a);
    if (p !== pageNo) setPageNo(p);
  }
  function toggleSection(n: number) {
    if (!doc) return;
    const cur = hidden[doc.kind] ?? [];
    const next = { ...hidden, [doc.kind]: cur.includes(n) ? cur.filter((x) => x !== n) : [...cur, n] };
    setHidden(next);
    try { localStorage.setItem(userKey("report_hidden_sections"), JSON.stringify(next)); } catch { /* ignore */ }
  }

  function exportXlsx() {
    const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 50);
    if (pinView) { downloadXlsx(`agent-java-${slug}`, pinView.columns, pinView.rows, "Hasil", pinView.title); return; }
    if (!doc) return;
    const width = Math.max(1, ...pages.flat().map((s) => s.cols?.length ?? 1));
    const cols = ["Bagian", ...Array.from({ length: width }, (_, i) => `Kolom ${i + 1}`)];
    const rows: Record<string, unknown>[] = [];
    for (const s of pages.flat()) {
      if (s.type === "table" && s.cols) {
        rows.push({ Bagian: `${s.n}. ${s.title}`, ...Object.fromEntries(s.cols.map((c, i) => [`Kolom ${i + 1}`, c])) });
        s.rows?.forEach((r) => rows.push({ Bagian: "", ...Object.fromEntries(r.map((c, i) => [`Kolom ${i + 1}`, cellText(c) ?? "-"])) }));
      } else if (s.type === "summary") {
        rows.push({ Bagian: `${s.n}. ${s.title}`, "Kolom 1": (s.text ?? "").replace(/\*\*/g, "") });
        s.kpis?.forEach((k) => rows.push({ Bagian: "", "Kolom 1": k.label, "Kolom 2": k.value, "Kolom 3": k.delta }));
      } else {
        rows.push({ Bagian: `${s.n}. ${s.title}`, "Kolom 1": s.text ?? s.items?.join(" ") ?? "" });
      }
    }
    downloadXlsx(`agent-java-${slug}`, cols, rows, "Laporan", title);
  }
  async function share() {
    const body = pinView ? { title: pinView.title, columns: pinView.columns, rows: pinView.rows.slice(0, 2000) }
      : { title, region: ref?.region ?? "" };
    try {
      const r = await authFetch("/api/report-links", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      const d = await r.json();
      if (!r.ok) throw new Error(d?.detail);
      const url = `${window.location.origin}${d.path}`;
      await navigator.clipboard?.writeText(url).catch(() => {});
      setNotice(`Tautan disalin, berlaku 7 hari: ${url}`);
    } catch (e) {
      setNotice((e as Error).message || "Tautan belum bisa dibuat.");
    }
  }
  async function sendNow(s: Schedule) {
    setNotice(`Agent menyusun ${s.name}…`);
    try {
      const r = await authFetch(`/api/report-schedules/${s.id}/send-now`, { method: "POST" });
      const d = await r.json();
      setNotice(r.ok ? `${s.name} terkirim ke ${d.sent} dari ${d.recipients} penerima.` : d.detail || "Laporan gagal dikirim.");
    } catch {
      setNotice("Laporan gagal dikirim.");
    }
    setVersion((v) => v + 1);
  }
  async function patchSchedule(s: Schedule, body: Partial<Schedule>) {
    setSchedules((cur) => (cur ?? []).map((x) => (x.id === s.id ? { ...x, ...body } : x)));
    await authFetch(`/api/report-schedules/${s.id}`, { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }).catch(() => {});
  }
  async function deleteSchedule(s: Schedule) {
    if (!confirm(`Hapus jadwal "${s.name}"?`)) return;
    await authFetch(`/api/report-schedules/${s.id}`, { method: "DELETE" }).catch(() => {});
    setVersion((v) => v + 1);
  }

  useEffect(() => {
    if (!createMenu) return;
    const close = () => setCreateMenu(false);
    document.addEventListener("click", close);
    return () => document.removeEventListener("click", close);
  }, [createMenu]);

  const regions = useMemo(() => [...new Set((lib ? [...lib.lead, ...lib.rest] : []).map((i) => i.doc?.kind === "bulanan" ? i.doc.region : "").filter(Boolean) as string[])], [lib]);
  const okRuns = runs.filter((r) => r.status !== "gagal").slice(0, 2);
  const failedRun = runs.slice(0, 5).find((r) => (r.failed ?? 0) > 0 || r.status === "gagal");
  const failedSched = failedRun ? schedules?.find((s) => s.id === failedRun.schedule_id) : undefined;

  return (
    <AppShell mainClassName="lmain">
      <TopBar title="Laporan" subtitle="Pustaka laporan, pratinjau, dan jadwal kirim" ringAvatar
        actions={
          <>
            <span className="chip"><Icon name="cal" />{lib?.month_short ?? "Bulan ini"}</span>
            <div className="lmenu">
              <button className="btn-p" onClick={(e) => { e.stopPropagation(); setCreateMenu((v) => !v); }} aria-expanded={createMenu}>
                <Icon name="plus" />Buat laporan
              </button>
              {createMenu && (
                <div className="menu" role="menu">
                  <button role="menuitem" onClick={() => router.push("/?new=1")}><Icon name="spark" />Minta agent (ad-hoc)</button>
                  <button role="menuitem" onClick={() => setSchedDialog({})}><Icon name="mail" />Jadwalkan kirim otomatis</button>
                  <Link role="menuitem" href="/reports/outlook"><Icon name="bars" />Performance Outlook lengkap</Link>
                </div>
              )}
            </div>
          </>
        } />
      <div className="lap">
        <div className="lcol" ref={colRef}>
          <label className="sbox">
            <Icon name="search" />
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Cari laporan, wilayah, atau isi" aria-label="Cari laporan" />
          </label>
          <div className="fchips" role="group" aria-label="Filter jenis laporan">
            {FILTERS.map((f) => (
              <button key={f} className={filter === f ? "on" : undefined} aria-pressed={filter === f} onClick={() => setFilter(f)}>
                {f === "semua" ? <>Semua <b>{items.length}</b></> : KIND[f].label}
              </button>
            ))}
          </div>
          <div className="rlist2" ref={listRef}>
            {!lib && !libError && [0, 1, 2].map((i) => <div key={i} className="ri"><span className="skel" style={{ height: 40 }} /><span className="skel" /><span /></div>)}
            {libError && <div className="empty">{libError}</div>}
            {lib && shown.length === 0 && (
              <div className="empty">{filter === "adhoc" ? "Belum ada hasil dari agent. Klik \"Pin ke dashboard\" di jawaban Tanya Agent." : "Tidak ada laporan yang cocok."}</div>
            )}
            {shown.map((it) => {
              const k = KIND[it.kind];
              return (
                <button key={it.id} className={`ri ${it.id === current?.id ? "on" : ""}`} onClick={() => select(it)} aria-current={it.id === current?.id || undefined}>
                  <span className="ic2" style={{ background: k.bg, color: k.fg }}><Icon name={k.icon} /></span>
                  <div><b>{it.title}</b><small><span className={`kd ${k.kd}`}>{k.label}</span>{it.meta}</small></div>
                  {it.pin ? <Icon name="pin" className="pin" /> : <Icon name="chevr" className="chev" />}
                </button>
              );
            })}
          </div>
          <div className="sched">
            <div className="hd"><Icon name="mail" /><b>Jadwal kirim otomatis</b><span className="grow" /><button onClick={() => setSchedDialog({})}>+ Jadwal baru</button></div>
            {schedules && schedules.length === 0 && <div className="none">Belum ada jadwal. Agent bisa menyusun dan mengirim laporan lewat email tiap minggu atau tiap bulan.</div>}
            {schedules?.map((s) => (
              <div key={s.id} className="sc">
                <b className="nm">{s.name}</b>
                <small>{schedLine(s)}</small>
                <span className="acts">
                  <button title="Kirim sekarang" aria-label={`Kirim ${s.name} sekarang`} onClick={() => sendNow(s)}><Icon name="send" /></button>
                  <button title="Ubah jadwal" aria-label={`Ubah ${s.name}`} onClick={() => setSchedDialog({ edit: s })}><Icon name="cal" /></button>
                  <button title="Hapus jadwal" aria-label={`Hapus ${s.name}`} onClick={() => deleteSchedule(s)}><Trash2 /></button>
                </span>
                <button className={`tg2 ${s.active ? "" : "off"}`} role="switch" aria-checked={s.active} aria-label={`Aktifkan ${s.name}`}
                  onClick={() => patchSchedule(s, { active: !s.active })}><i /></button>
              </div>
            ))}
            {(okRuns.length > 0 || failedRun) && (
              <div className="runs">
                {okRuns.map((r) => { const t = wib(r.created_at); return <span key={r.id}>✓ {t.d} {MONTHS[t.m]}, {runLabel(r)}: {r.recipients} terkirim</span>; })}
                {failedRun && (
                  <button className="f" onClick={() => failedSched && sendNow(failedSched)} disabled={!failedSched}
                    title={failedSched ? `Kirim ulang ${failedSched.name}` : "Jadwalnya sudah dihapus"}>
                    {failedRun.status === "gagal" && !failedRun.failed ? "Pengiriman gagal" : `${failedRun.failed} email gagal`}, kirim ulang
                  </button>
                )}
              </div>
            )}
          </div>
        </div>

        <section className="pv" aria-label="Pratinjau laporan">
          <div className="tb">
            <div className="ttl"><b>{title}</b><small>{meta}</small></div>
            <span className="grow" />
            <button className="linkbtn" onClick={() => { logExport("PDF", title); window.print(); }} disabled={!doc && !pinView}><Icon name="dl" />PDF</button>
            <button className="linkbtn" onClick={exportXlsx} disabled={!doc && !pinView}><Icon name="table" />XLSX</button>
            <button className="linkbtn" onClick={share} disabled={!doc && !pinView}><Icon name="link" />Bagikan</button>
            <button className="btn-p" onClick={() => setSchedDialog({})}><Icon name="mail" />Jadwalkan</button>
          </div>
          <div className="pvb">
            <nav className="toc" aria-label="Daftar isi">
              <div className="th">Daftar isi</div>
              {toc.map((t) => (
                <a key={t.n} className={`${active === t.n ? "on" : ""} ${hiddenNow.includes(t.n) ? "off" : ""}`.trim() || undefined}
                  onClick={() => !hiddenNow.includes(t.n) && goSection(t.n)} aria-current={active === t.n || undefined}><i>{t.n}</i>{t.title}</a>
              ))}
              {doc && (
                <button className="add" onClick={() => setArrange((v) => !v)} aria-expanded={arrange}><Icon name="plus" />Atur bagian laporan</button>
              )}
              {doc && arrange && (
                <div className="menu">
                  {doc.toc.map((t) => (
                    <label key={t.n}><input type="checkbox" checked={!hiddenNow.includes(t.n)} onChange={() => toggleSection(t.n)} />{t.n}. {t.title}</label>
                  ))}
                </div>
              )}
            </nav>
            <div className="pgw">
              <div className="pgs" ref={scroller} onScroll={onScroll}>
                {pinView ? (
                  <>
                    <article className="lpage">
                      <div className="ph">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <span className="lg2"><img src="/brand/icon_circle_java.png" alt="" /></span>
                        <span className="eb">Hasil ad-hoc dari agent</span><b>{pinView.title}</b>
                        <small>Disematkan dari Tanya Agent · {pinView.rows.length} baris</small>
                      </div>
                      <div className="sec" id="sec-1" data-n={1}>
                        <h4><i>1</i>Pertanyaan</h4>
                        <div className="q">{pinView.question}</div>
                        {pinView.chart && pinView.chart.type !== "none" && <SmartChart spec={pinView.chart} rows={pinView.rows} height={230} bare subtitle="" />}
                      </div>
                    </article>
                    <article className="lpage cont">
                      <div className="sec" id="sec-2" data-n={2}>
                        <h4><i>2</i>Data</h4>
                        <ResultTable columns={pinView.columns} rows={pinView.rows} spec={pinView.chart} initialRows={14} />
                      </div>
                    </article>
                  </>
                ) : doc ? (
                  pages.map((p, i) => (
                    <article key={`${key}-${i}`} className={`lpage ${i ? "cont" : ""}`}>
                      {i === 0 && (
                        <div className="ph">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <span className="lg2"><img src="/brand/icon_circle_java.png" alt="" /></span>
                          <span className="eb">{doc.eyebrow}</span><b>{doc.heading}</b><small>{doc.byline}</small>
                        </div>
                      )}
                      {p.map((s) => <Section key={s.n} s={s} />)}
                    </article>
                  ))
                ) : loaded && "error" in loaded ? (
                  <article className="lpage cont"><div className="sec"><div className="ntext">{loaded.error}</div></div></article>
                ) : (
                  <article className="lpage cont"><div className="sec"><span className="skel" style={{ height: 60 }} /><span className="skel" /><span className="skel" style={{ width: "70%" }} /><span className="skel" style={{ height: 120 }} /></div></article>
                )}
              </div>
              {totalPages > 0 && (
                <div className="pgfoot">
                  <span>Hal {Math.min(pageNo, totalPages)} dari {totalPages}</span>
                  {pageNo < totalPages
                    ? <button onClick={() => { const pg = scroller.current?.querySelectorAll<HTMLElement>(".lpage")[pageNo]; if (pg) scroller.current?.scrollTo({ top: pg.offsetTop - 16 }); }}>↓ Gulir untuk halaman berikutnya</button>
                    : <button onClick={() => scroller.current?.scrollTo({ top: 0 })}>↑ Kembali ke awal</button>}
                </div>
              )}
            </div>
          </div>
        </section>
      </div>
      {notice && <div className="ltoast" role="status">{notice}</div>}
      {schedDialog && (
        <ScheduleDialog regions={regions} edit={schedDialog.edit} onClose={() => setSchedDialog(null)}
          onSaved={() => { setSchedDialog(null); setVersion((v) => v + 1); }} />
      )}
    </AppShell>
  );
}
