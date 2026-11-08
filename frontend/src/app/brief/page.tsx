"use client";
/* v3 02 Brief Pagi (design/mockup-v3/features/02-brief-pagi.html): the personal 06.00 brief.
   Every number comes from /api/brief, which computes it from the Performance dump; the
   sentences are templates, so the audio and the WhatsApp text say exactly what is on screen. */
import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import AppShell from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { getJson, plain, Rich, Spark, Tap, V3State, V3Top, Wave, type Seg } from "../components/v3/V3";
import { authFetch } from "@/lib/auth";
import "../v3.css";

type Story = {
  n: number; key: string; tone: "k" | "w" | "g"; tone_label: string; topic: string; metric: string; title: string;
  value_label: string; value_note: string; spark: number[]; text: string; share: string; peek: string;
  region: string; kabupaten: string | null;
  diagnosa?: Record<string, string>; simulasi?: Record<string, string>;
  pin?: Record<string, unknown>; task?: Record<string, unknown>;
};
type Bar = { metric: string; label: string; value_label: string; real_pct: number; band_pct: number; tick_pct: number; color: string; note: string };
type Agenda = { kind: "task" | "report" | "alert"; icon: string; title: string; sub: string; time: string; urgent: boolean; task_id?: number };
type Chip = { key: string; label: string; on: boolean };
export type Brief = {
  greeting: string; subtitle: string; date_short: string; headline: Seg[]; month_chip: string;
  audio: { text: string; seconds: number };
  basis: { dump: string; period: string; focus: string };
  stories: Story[]; targets: Bar[]; agent_says: Seg[] | null; target_title: string; target_sub: string;
  agenda: Agenda[];
  prefs: { send?: boolean; push: boolean; email: boolean; send_label: string; days_label: string; email_label: string };
  topics: Chip[]; regions: Chip[]; vote: string | null;
};

const SPARK: Record<string, string> = { k: "#C42B2B", w: "#F5A623", g: "#0E8579" };
const NOTE: Record<string, string> = { k: "dn", w: "wn", g: "up" };
const AGENDA_LOOK: Record<string, [string, string]> = { task: ["#FBE2E8", "#C23A5B"], report: ["#FCEDD3", "#B7791F"], alert: ["#FDECEC", "#C42B2B"] };

const qs = (o?: Record<string, unknown>) => new URLSearchParams(Object.entries(o || {}).filter(([, v]) => v != null && v !== "").map(([k, v]) => [k, String(v)])).toString();

export function shareText(text: string) {
  const url = typeof window !== "undefined" ? `${window.location.origin}/brief` : "";
  const body = `${text}\n${url}`;
  if (typeof navigator !== "undefined" && navigator.share) navigator.share({ text: body }).catch(() => {});
  else window.open(`https://wa.me/?text=${encodeURIComponent(body)}`, "_blank", "noopener");
}

export default function BriefPage() {
  const router = useRouter();
  const [data, setData] = useState<Brief | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);
  const [playing, setPlaying] = useState(false);
  const [played, setPlayed] = useState(0);
  const timer = useRef<number | null>(null);

  const load = useCallback(() => {
    authFetch("/api/brief").then((r) => getJson<Brief>(r)).then((d) => { setData(d); setError(null); })
      .catch((e) => setError(e.message));
  }, []);
  useEffect(() => { load(); }, [load]);
  useEffect(() => () => { if (timer.current) window.clearInterval(timer.current); window.speechSynthesis?.cancel(); }, []);

  function flash(t: string) { setNote(t); window.setTimeout(() => setNote(null), 2600); }
  function opened(key: string) { authFetch("/api/brief/open", { method: "POST", body: JSON.stringify({ story: key }) }).catch(() => {}); }

  function togglePlay() {
    if (!data) return;
    const synth = window.speechSynthesis;
    if (!synth) { flash("Browser ini belum mendukung suara"); return; }
    if (playing) { synth.cancel(); setPlaying(false); if (timer.current) window.clearInterval(timer.current); return; }
    const u = new SpeechSynthesisUtterance(data.audio.text);
    u.lang = "id-ID";
    const v = synth.getVoices().find((x) => x.lang.toLowerCase().startsWith("id"));
    if (v) u.voice = v;
    const t0 = Date.now();
    u.onend = () => { setPlaying(false); setPlayed(1); if (timer.current) window.clearInterval(timer.current); };
    synth.cancel();
    synth.speak(u);
    setPlaying(true);
    timer.current = window.setInterval(() => setPlayed(Math.min(1, (Date.now() - t0) / 1000 / data.audio.seconds)), 250);
  }

  async function pin(s: Story) {
    opened(s.key);
    const r = await authFetch("/api/ruang/pins", { method: "POST", body: JSON.stringify(s.pin) });
    flash(r.ok ? "Disimpan ke Ruang Saya" : "Pin gagal disimpan");
  }
  async function task(s: Story) {
    opened(s.key);
    const r = await authFetch("/api/tindak/tasks", { method: "POST", body: JSON.stringify(s.task) });
    if (!r.ok) { flash("Tugas gagal dibuat"); return; }
    const t = await r.json();
    router.push(`/tindak?task=${t.id}`);
  }
  async function setPref(body: Record<string, unknown>) {
    const r = await authFetch("/api/brief/prefs", { method: "POST", body: JSON.stringify(body) });
    if (r.ok) load(); else flash("Pengaturan gagal disimpan");
  }
  async function vote(v: "up" | "down") {
    const r = await authFetch("/api/brief/feedback", { method: "POST", body: JSON.stringify({ vote: v }) });
    if (r.ok) { setData((d) => (d ? { ...d, vote: v } : d)); flash("Terima kasih, agent memakai ini untuk brief besok"); }
  }

  const topics = data?.topics.filter((t) => t.on).map((t) => t.key) ?? [];
  const regions = data?.regions.filter((t) => t.on).map((t) => t.key) ?? [];
  const secs = data?.audio.seconds ?? 0;

  return (
    <AppShell>
      <V3Top title="Brief Pagi" subtitle={data?.subtitle} month={data?.month_chip} />
      <div className="v3 f-02-brief-pagi">
        <V3State error={error} loading={!data && !error} />
        {data && (
          <div className="body">
            <div className="col">
              <section className="greet" aria-label="Sapaan">
                <div className="row1"><span className="tag"><Icon name="sun" />Brief harian · 06.00 WIB</span><span className="tag"><Icon name="check" />Angka tervalidasi agent</span></div>
                <h1>{data.greeting}</h1>
                <p><Rich segs={data.headline} /></p>
                <div className="player" aria-label="Audio brief">
                  <button className="pb" onClick={togglePlay} aria-label={playing ? "Jeda brief" : "Dengarkan brief"}><Icon name={playing ? "pause" : "play"} /></button>
                  <div className="meta"><b>{playing ? "Mendengarkan brief" : "Dengarkan brief"}</b><small>{secs} detik · suara Bahasa Indonesia</small></div>
                  <Wave n={48} played={playing || played ? played : 0.38} />
                  <span className="sp">1,0×</span>
                  <button className="sh" onClick={() => shareText(`${data.greeting}. ${plain(data.headline)}`)}><Icon name="share" />Bagikan</button>
                </div>
              </section>
              <div className="basis">
                <span><Icon name="db" />{data.basis.dump}</span><span><Icon name="cal" />{data.basis.period}</span><span><Icon name="pin" />{data.basis.focus}</span>
              </div>

              <div className="sech"><h3>{data.stories.length} hal yang perlu kamu tahu</h3><small>diurutkan dari dampak terbesar ke revenue</small><span className="grow" /></div>
              {data.stories.length === 0 && <p className="v3load" style={{ margin: 0 }}>Tidak ada perubahan besar di wilayah kamu hari ini.</p>}
              <div className="stories">
                {data.stories.map((s) => (
                  <article key={s.key} className={`st ${s.tone}`}>
                    <div className="hd"><span className="n">{s.n}</span>{s.tone_label}</div>
                    <h4>{s.title}</h4>
                    <div className="big"><b>{s.value_label}</b><span className={NOTE[s.tone]}>{s.value_note}</span></div>
                    <Spark values={s.spark} color={SPARK[s.tone]} width={250} height={44} />
                    <p>{s.text}</p>
                    <div className="acts">
                      <Tap className="pri" onClick={() => { opened(s.key); router.push(`/diagnosa?${qs(s.diagnosa)}`); }}><Icon name="spark" />Kenapa?</Tap>
                      <Tap className="ic1" title="Pin ke Ruang Saya" label="Pin ke Ruang Saya" onClick={() => pin(s)}><Icon name="layers" /></Tap>
                      {s.simulasi
                        ? <Tap onClick={() => { opened(s.key); router.push(`/simulasi?${qs(s.simulasi)}`); }}><Icon name="up" />Simulasi</Tap>
                        : <Tap className="ic1" title="Buat tugas" label="Buat tugas" onClick={() => task(s)}><Icon name="check" /></Tap>}
                      <Tap className="ic1" title="Bagikan" label="Bagikan" onClick={() => shareText(s.share)}><Icon name="share" /></Tap>
                    </div>
                  </article>
                ))}
              </div>

              {data.targets.length > 0 && (
                <section className="card" aria-label="Posisi target">
                  <div className="ch"><div><h3>{data.target_title}</h3><p>{data.target_sub}</p></div></div>
                  <div className="tgt">
                    <div className="bul">
                      {data.targets.map((b) => (
                        <div key={b.metric} className="bl">
                          <div className="lb">{b.label}<b>{b.value_label}</b></div>
                          <div className="tr"><i className="fc" style={{ width: `${b.band_pct}%` }} /><i style={{ width: `${b.real_pct}%`, background: b.color }} /><span className="tk" style={{ left: `${b.tick_pct}%` }} /></div>
                          <small>{b.note}</small>
                        </div>
                      ))}
                    </div>
                    {data.agent_says && (
                      <div className="say"><Rich segs={data.agent_says} /><br />
                        <button className="lk" onClick={() => router.push("/simulasi")}><Icon name="up" />Buka Simulasi Target</button></div>
                    )}
                  </div>
                </section>
              )}
            </div>

            <div className="col">
              <section className="card" aria-label="Agenda hari ini">
                <div className="ch"><div><h3>Agenda kamu hari ini</h3><p>Dari Tindak Lanjut, Laporan, dan Alert</p></div></div>
                <div className="ag">
                  {data.agenda.length === 0 && <small style={{ color: "#5A6B68", font: "400 12.5px/1.4 var(--f-body)" }}>Tidak ada tugas, laporan, atau alert untuk hari ini.</small>}
                  {data.agenda.map((a, i) => {
                    const [bg, fg] = AGENDA_LOOK[a.kind];
                    const href = a.kind === "task" ? `/tindak?task=${a.task_id}` : a.kind === "report" ? "/reports" : "/watchlist";
                    return (
                      <button key={i} className="ai" onClick={() => router.push(href)}>
                        <i style={{ background: bg, color: fg }}><Icon name={a.icon} /></i><b>{a.title}</b><small>{a.sub}</small>
                        <span className="tm" style={a.urgent ? { color: "#C42B2B" } : undefined}>{a.time}</span>
                      </button>
                    );
                  })}
                </div>
              </section>
              <section className="card" aria-label="Atur brief">
                <div className="ch"><div><h3>Atur brief kamu</h3><p>Agent belajar dari kartu yang kamu buka</p></div></div>
                <div className="pref">
                  <div><div className="pr" style={{ marginBottom: 8 }}>Topik</div><div className="chips">
                    {data.topics.map((t) => (
                      <Tap key={t.key} className={t.on ? "on" : ""} pressed={t.on}
                        onClick={() => setPref({ topics: t.on ? topics.filter((k) => k !== t.key) : [...topics, t.key] })}>{t.label}</Tap>
                    ))}
                  </div></div>
                  <div><div className="pr" style={{ marginBottom: 8 }}>Wilayah</div><div className="chips">
                    {data.regions.map((t) => (
                      <Tap key={t.key} className={t.on ? "on" : ""} pressed={t.on}
                        onClick={() => setPref({ regions: t.key === "JAVA" ? ["JAVA"] : t.on ? regions.filter((k) => k !== t.key) : [...regions.filter((k) => k !== "JAVA"), t.key] })}>{t.label}</Tap>
                    ))}
                  </div></div>
                  <Toggle label={data.prefs.send_label} sub={data.prefs.days_label} on={data.prefs.send !== false} onChange={(v) => setPref({ send: v })} />
                  <Toggle label="Notifikasi Android" sub="Ringkasan 2 baris di layar kunci" on={data.prefs.push} onChange={(v) => setPref({ push: v })} />
                  <Toggle label="Email" sub={data.prefs.email_label} on={data.prefs.email} onChange={(v) => setPref({ email: v })} />
                </div>
              </section>
              <div className="fb">Brief ini membantu?
                <Tap label="Membantu" pressed={data.vote === "up"} onClick={() => vote("up")} style={data.vote === "up" ? { borderColor: "#0E8579", color: "#0E8579" } : undefined}><Icon name="up" /></Tap>
                <Tap label="Kurang membantu" pressed={data.vote === "down"} onClick={() => vote("down")} style={{ transform: "rotate(180deg)", ...(data.vote === "down" ? { borderColor: "#C42B2B", color: "#C42B2B" } : {}) }}><Icon name="up" /></Tap>
              </div>
              {note && <div className="v3toast" role="status">{note}</div>}
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function Toggle({ label, sub, on, onChange }: { label: string; sub: string; on: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="pr"><div>{label}<small>{sub}</small></div><span className="grow" />
      <span className={`tog ${on ? "" : "off"}`} role="switch" tabIndex={0} aria-checked={on} aria-label={label} onClick={() => onChange(!on)}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); onChange(!on); } }} />
    </div>
  );
}
