"use client";
/* v3 01 Diagnosa "Kenapa?" (design/mockup-v3/features/01-diagnosa.html). Opened from the
   Kenapa? buttons (Brief Pagi, Performance, alerts). /api/diagnosa splits the change of a KPI
   by area (sums to the total, "Lainnya" always shown), into volume / rate / mix effects, down
   to the sites, and lists rule-based hypotheses with their evidence. */
import { Suspense, useCallback, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { getJson, Rich, Tap, V3State, V3Top, Waterfall, type Seg, type WfBar } from "../components/v3/V3";
import { authFetch } from "@/lib/auth";
import "../v3.css";

type Node = { key: string; name: string; delta: number; delta_label: string; share_pct?: number | null; on: boolean; sites?: number | null };
type Hyp = { key: string; n: number; title: string; confidence: number; confidence_label: string; evidence: { kind: "p" | "m" | "n"; text: string }[] };
export type Diag = {
  metric: string; metric_label: string;
  scope: { level: "circle" | "region" | "kabupaten"; name: string; region: string | null; kabupaten: string | null };
  child_level: string; child_noun: string;
  basis: { kind: string; label: string; cur: string; prev: string };
  source: { label_wib?: string; label?: string };
  coverage_pct: number | null; title: string; month_chip: string;
  total: { delta: number; delta_label: string; detail: string; label: string };
  summary: Seg[];
  waterfall: { bars: WfBar[]; min: number; max: number; unit: string };
  effects: null | { rows: { key: string; label: string; sub: string; short: string; width_pct: number }[]; total_short: string; note: string };
  tree: { level1: Node[]; level2: Node[]; level2_other?: { count: number; delta_label: string; noun: string };
    sites: null | { count: number; kecamatan: string; items: { site_id: string; short: string }[]; note: string } };
  hypotheses: Hyp[]; missing: string; follow_ups: { label: string; question: string }[];
  steps: number; elapsed_s: number;
  task_prefill: { title: string; origin: string; region: string | null; kabupaten: string | null; metric: string; impact: number };
};

const LEVEL_LABEL: Record<string, string> = { region: "Region", kabupaten: "Kabupaten", kecamatan: "Kecamatan" };
const EV_ICON = { p: "check", m: "warn", n: "info" } as const;
const ONE = (n: number) => n.toLocaleString("id-ID", { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const FROM: Record<string, string> = { brief: "Dibuka dari kartu Brief Pagi", alert: "Dibuka dari alert", ruang: "Dibuka dari Ruang Saya", tanya: "Dibuka dari jawaban agent" };

function DiagnosaView() {
  const router = useRouter();
  const sp = useSearchParams();
  const metric = sp.get("metric") || "revenue";
  const region = sp.get("region") || "";
  const kabupaten = sp.get("kabupaten") || "";
  const basis = sp.get("basis") || "month";
  const by = sp.get("by") || "child";
  const from = sp.get("from") || "";
  const [data, setData] = useState<Diag | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState<string | null>(null);

  useEffect(() => {
    const q = new URLSearchParams({ metric, region, kabupaten, basis, by });
    authFetch(`/api/diagnosa?${q}`).then((r) => getJson<Diag>(r)).then((d) => { setData(d); setError(null); })
      .catch((e) => setError(e.message));
  }, [metric, region, kabupaten, basis, by]);

  const go = useCallback((patch: Record<string, string>) => {
    const q = new URLSearchParams({ metric, region, kabupaten, basis, by, from, ...patch });
    for (const [k, v] of [...q.entries()]) if (!v) q.delete(k);
    router.push(`/diagnosa?${q}`);
  }, [metric, region, kabupaten, basis, by, from, router]);

  function flash(t: string) { setNote(t); window.setTimeout(() => setNote(null), 2600); }
  async function pin() {
    if (!data) return;
    const r = await authFetch("/api/ruang/pins", { method: "POST", body: JSON.stringify({
      kind: "chart", title: data.title.replace(/\?$/, ""), subtitle: data.basis.label, origin: "diagnosa",
      spec: { type: "diagnosa", metric, region: data.scope.region, kabupaten: data.scope.kabupaten, basis } }) });
    flash(r.ok ? "Disimpan ke Ruang Saya" : "Pin gagal disimpan");
  }
  async function task() {
    if (!data) return;
    const p = data.task_prefill;
    const r = await authFetch("/api/tindak/tasks", { method: "POST", body: JSON.stringify({
      title: p.title, origin: "diagnosa", origin_ref: { label: data.title }, region: p.region, kabupaten: p.kabupaten, impact: p.impact,
      kpi: { metric: p.metric, mode: "change", op: ">=", threshold: 0, level: p.kabupaten ? "kabupaten" : p.region ? "region" : "circle", name: p.kabupaten || p.region || "JAVA" } }) });
    if (!r.ok) { flash("Tugas gagal dibuat"); return; }
    router.push(`/tindak?task=${(await r.json()).id}`);
  }
  /** Click on a tree node: diagnose that area one level down. */
  function drill(level: string, key: string) {
    if (level === "region") go({ region: key, kabupaten: "", by: "child" });
    else if (level === "kabupaten") go({ kabupaten: key, by: "child" });
  }

  const s = data?.scope;
  const regionName = s?.region ? s.region.toLowerCase().replace(/\b\w/g, (c) => c.toUpperCase()) : null;
  const subtitle = data ? (FROM[from] ?? `Dibuka dari kartu ${data.metric_label} ${s?.name} di Performance`) : undefined;
  const l2level = data ? ({ region: "kabupaten", kabupaten: "kecamatan", kecamatan: "" } as Record<string, string>)[data.child_level] : "";
  const mapHref = s?.kabupaten ? `/map?kabupaten=${encodeURIComponent(s.kabupaten)}` : s?.region ? `/map?region=${encodeURIComponent(s.region)}` : "/map";
  const segOpts = data ? (s?.level === "kabupaten" ? [["child", "Kecamatan"]] : [["child", LEVEL_LABEL[s?.level === "circle" ? "region" : "kabupaten"]], ["kecamatan", "Kecamatan"]]) : [];

  return (
    <AppShell>
      <V3Top title="Diagnosa" subtitle={subtitle} region={region} onRegion={(v) => go({ region: v, kabupaten: "" })} month={data?.month_chip} />
      <div className="v3 f-01-diagnosa">
        <V3State error={error} loading={!data && !error} />
        {data && s && (
          <div className="body">
            <div className="hd">
              <div>
                <div className="crumbs">
                  <Tap onClick={() => router.push("/performance")}>Performance</Tap><Icon name="chev" />
                  {regionName && s.level !== "region" && (<><Tap onClick={() => go({ kabupaten: "" })}>{regionName}</Tap><Icon name="chev" /></>)}
                  {s.level !== "circle" && (<>{s.name}<Icon name="chev" /></>)}
                  <b>Diagnosa {data.metric === "subs" ? "pelanggan aktif" : data.metric_label.toLowerCase()}</b>
                </div>
                <h1>{data.title}</h1>
                <div className="basis">
                  <span><Icon name="cal" />{data.basis.label}</span>
                  {data.source?.label_wib && <span><Icon name="db" />{data.source.label_wib}</span>}
                  {data.coverage_pct != null && <span><Icon name="check" />Cakupan {ONE(data.coverage_pct)}% site terpetakan</span>}
                </div>
              </div>
              <div className="grow" />
              <div className="btnrow">
                <Tap className="bt" onClick={() => router.push(mapHref)}><Icon name="map" />Lihat di Peta</Tap>
                <Tap className="bt" onClick={pin}><Icon name="layers" />Pin</Tap>
                <Tap className="bt pri" onClick={task}><Icon name="check" />Buat tindak lanjut</Tap>
              </div>
            </div>

            <section className="ans" aria-label="Jawaban singkat">
              <div><span className="tag"><Icon name="spark" />Jawaban singkat agent · {data.steps} langkah · {ONE(data.elapsed_s)} dtk</span>
                <p><Rich segs={data.summary} /></p></div>
              <div className="big"><small>{data.total.label}</small><b>{data.total.delta_label}</b><span>{data.total.detail}</span></div>
            </section>

            <div className="g2">
              <div style={{ display: "flex", flexDirection: "column", gap: 16, minWidth: 0 }}>
                <section className="card" aria-label="Waterfall">
                  <div className="ch"><div><h3>Dari mana {data.total.delta_label.replace(/^[−+]/, "")} itu {data.total.delta < 0 ? "hilang" : "datang"}</h3>
                    <p>Kontribusi per {data.child_noun}, {data.waterfall.unit}, diurutkan dari dampak terbesar. Total selalu sama dengan perubahan {s.level === "circle" ? "circle" : s.level === "region" ? "region" : "kabupaten"}.</p></div>
                    <div className="seg">
                      {segOpts.map(([k, lab]) => <button key={k} className={by === k ? "on" : ""} onClick={() => go({ by: k })}>{lab}</button>)}
                      <button disabled title="Tipe site belum tersedia di Performance dump" style={{ cursor: "not-allowed" }}>Tipe site</button>
                    </div></div>
                  <Waterfall bars={data.waterfall.bars} min={data.waterfall.min} max={data.waterfall.max} width={702} height={270} bleed={34} />
                  {data.waterfall.min > 0 && <div className="note"><Icon name="info" />Skala dimulai di {data.waterfall.unit === "Rp miliar" ? `Rp ${data.waterfall.min.toLocaleString("id-ID")} M` : `${data.waterfall.min.toLocaleString("id-ID")} ${data.waterfall.unit}`} (ditandai patahan pada batang total) agar selisih terlihat. &quot;Lainnya&quot; tidak pernah disembunyikan.</div>}
                </section>

                {data.tree.level1.length > 0 && (
                  <section className="card" aria-label="Telusuri">
                    <div className="ch"><div><h3>Telusuri sampai site</h3><p>Klik simpul untuk turun satu tingkat. Jalur terbesar ditandai.</p></div></div>
                    <div className="tree">
                      <div className="stack">{data.tree.level1.map((n, i) => (
                        <Tap key={n.key} className={`nd ${n.on ? "on" : ""}`} onClick={() => drill(data.child_level, n.key)} style={{ display: "grid" }}>
                          <b>{n.name}</b><span>{n.delta_label}</span><small>{n.share_pct != null ? `${n.share_pct}%${i === 0 ? ` dari ${data.total.delta < 0 ? "penurunan" : "kenaikan"}` : ""}` : ""}</small>
                        </Tap>))}</div>
                      <div className="lnk" />
                      <div className="stack">
                        {data.tree.level2.map((n) => (
                          <Tap key={n.key} className={`nd ${n.on ? "on" : ""}`} onClick={() => drill(l2level, n.key)} style={{ display: "grid" }}>
                            <b>{n.name}</b><span>{n.delta_label}</span>{n.sites != null && <small>{n.sites} site</small>}
                          </Tap>))}
                        {data.tree.level2_other && <div className="nd" style={{ opacity: 0.75 }}><b>Lainnya, {data.tree.level2_other.count} {data.tree.level2_other.noun}</b><span>{data.tree.level2_other.delta_label}</span></div>}
                      </div>
                      <div className="lnk" />
                      <div className="stack">
                        {data.tree.sites ? (<>
                          <div style={{ font: "600 12.5px/1.3 var(--f-display)" }}>{data.tree.sites.count} site di {data.tree.sites.kecamatan}</div>
                          <div className="sites">
                            {data.tree.sites.items.map((it) => <span key={it.site_id}>{it.site_id}<b>{it.short}</b></span>)}
                            {data.tree.sites.count > data.tree.sites.items.length && <span className="more">+{data.tree.sites.count - data.tree.sites.items.length} site lain</span>}
                          </div>
                          <div className="note"><Icon name="info" />{data.tree.sites.note}</div>
                        </>) : <div className="note"><Icon name="info" />Data per site untuk basis ini belum tersedia di dump.</div>}
                      </div>
                    </div>
                  </section>
                )}
              </div>

              <div style={{ display: "flex", flexDirection: "column", gap: 16, minWidth: 0 }}>
                {data.effects && (
                  <section className="card" aria-label="Efek">
                    <div className="ch"><div><h3>Volume, rate, atau mix?</h3><p>{data.effects.note}</p></div></div>
                    <div className="eff">
                      {data.effects.rows.map((r, i) => (
                        <div key={r.key} className="ef"><div>{r.label}<small>{r.sub}</small></div>
                          <div className="tr"><i style={{ width: `${r.width_pct}%`, opacity: [1, 0.85, 0.7][i], background: r.short.startsWith("−") ? undefined : "#2FA84F" }} /></div>
                          <b style={r.short.startsWith("−") ? undefined : { color: "#1F7A3A" }}>{r.short}</b></div>
                      ))}
                      <div className="ef sum"><div><b style={{ color: "#0F1F1D", textAlign: "left", display: "block" }}>Total</b></div><div /><b>{data.effects.total_short}</b></div>
                    </div>
                  </section>
                )}
                <section className="card" aria-label="Hipotesis">
                  <div className="ch"><div><h3>Hipotesis agent</h3><p>Bukan kesimpulan. Diurutkan dari bukti terkuat.</p></div></div>
                  {data.hypotheses.map((h) => (
                    <div key={h.key} className={`hy ${h.confidence <= 1 ? "weak" : ""}`}>
                      <div className="h1"><span className="lab">Hipotesis {h.n}</span><b>{h.title}</b>
                        <span className="conf">{[1, 2, 3].map((k) => <i key={k} className={k <= h.confidence ? "on" : ""} />)}{h.confidence_label}</span></div>
                      <ul>{h.evidence.map((e, i) => <li key={i} className={e.kind}><Icon name={EV_ICON[e.kind]} />{e.text}</li>)}</ul>
                    </div>
                  ))}
                  <div className="miss"><Icon name="info" /><span><b>Belum bisa diuji:</b> {data.missing}</span></div>
                  <div className="follow">{data.follow_ups.map((f) => (
                    <Tap key={f.label} onClick={() => router.push(`/?q=${encodeURIComponent(f.question)}`)}><Icon name="spark" />{f.label}</Tap>))}</div>
                </section>
              </div>
            </div>
            {note && <div className="v3toast" role="status">{note}</div>}
          </div>
        )}
      </div>
    </AppShell>
  );
}

export default function DiagnosaPage() {
  return <Suspense fallback={<div className="ui-boot" />}><DiagnosaView /></Suspense>;
}
