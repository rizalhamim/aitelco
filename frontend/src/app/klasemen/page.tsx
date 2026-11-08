"use client";
/* v3 03 Klasemen (design/mockup-v3/features/03-klasemen.html): region / kabupaten /
   kecamatan ranked against target, MTD vs LMTD on the same days (apple-to-apple), growth in
   percent and rupiah, small bases flagged, and the user's watched area highlighted. */
import { Suspense, useCallback, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import AppShell from "../components/shell/AppShell";
import { Icon } from "../components/v2/Icon";
import { getJson, Tap, V3State, V3Top } from "../components/v3/V3";
import { authFetch } from "@/lib/auth";
import "../v3.css";

type Row = {
  rank: number; key: string; name: string; region: string; region_label: string; region_color: string;
  growth_pct: number | null; achievement_pct: number | null; small_base: boolean; move?: number | null; mine?: boolean;
  ach_label: string | null; growth_label: string; abs_label: string; move_label: string | null;
};
type Region = { rank: number; key: string; name: string; color: string; achievement_pct: number | null; growth_pct: number | null; ach_label: string | null; growth_label: string; abs_label: string };
export type Klas = {
  level: string; metric: string; metric_label: string; sort: string; title: string; month_chip: string; vs_label: string;
  basis: { kind: string; label: string }; source: { label_wib?: string }; small_base_label: string; target_note: string | null; has_targets: boolean;
  total: number; noun: string; rows: Row[]; best: Row[]; worst: Row[];
  mine: null | { rank: number; total: number; name: string; key: string; region: string; move_label: string | null; need_fmt: string | null; need_label: string | null; cause: string | null };
  regions: Region[]; badges: { kind: string; icon: string; title: string; text: string }[];
};

const LEVELS = [["region", "Region"], ["kabupaten", "Kabupaten/kota"], ["kecamatan", "Kecamatan"]] as const;
const METRICS = [["revenue", "Revenue"], ["payload", "Payload"], ["subs", "RGU 90D"], ["rev_site", "Revenue per site"], ["availability", "Availability"]] as const;
const HEAD: Record<string, string> = { region: "Region", kabupaten: "Kabupaten/kota", kecamatan: "Kecamatan" };
const BADGE: Record<string, [string, string]> = { climber: ["#F4FCE3", "#5E8A12"], network: ["#E3F7FA", "#0E6F7C"], rise: ["#FFEDE7", "#B5401F"] };
const TOP = 6, BOTTOM = 3;

const achColor = (a: number | null) => a == null ? "#9FB1AD" : a >= 100 ? "#2FA84F" : a >= 94 ? "#F5A623" : "#C42B2B";
const dotLeft = (g: number | null) => Math.max(0, Math.min(100, 50 + (g ?? 0) * 5));
const sign = (g: number | null) => (g ?? 0) < 0 ? "dn" : "up";

function KlasemenView() {
  const router = useRouter();
  const sp = useSearchParams();
  const level = sp.get("level") || "kabupaten";
  const metric = sp.get("metric") || "revenue";
  const sort = sp.get("sort") || "achievement";
  const region = sp.get("region") || "";
  const [data, setData] = useState<Klas | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [all, setAll] = useState(false);

  useEffect(() => {
    authFetch(`/api/klasemen?${new URLSearchParams({ level, metric, sort, region })}`).then((r) => getJson<Klas>(r))
      .then((d) => { setData(d); setError(null); }).catch((e) => setError(e.message));
  }, [level, metric, sort, region]);

  const go = useCallback((patch: Record<string, string>) => {
    const q = new URLSearchParams({ level, metric, sort, region, ...patch });
    for (const [k, v] of [...q.entries()]) if (!v) q.delete(k);
    setAll(false);
    router.replace(`/klasemen?${q}`);
  }, [level, metric, sort, region, router]);

  /** Visible rows: top 6, the watched row, the bottom 3, with one gap row (or every row). */
  let shown: (Row | { gap: true; from: number; to: number })[] = [];
  if (data) {
    const rows = data.rows, n = rows.length;
    if (all || n <= TOP + BOTTOM + 2) shown = rows;
    else {
      const mine = rows.find((r) => r.mine && r.rank > TOP && r.rank <= n - BOTTOM);
      const firstHidden = TOP + 1, lastHidden = (mine ? mine.rank : n - BOTTOM + 1) - 1;
      shown = [...rows.slice(0, TOP), { gap: true, from: firstHidden, to: lastHidden }, ...(mine ? [mine] : []), ...rows.slice(n - BOTTOM)];
    }
  }
  const hasAch = !!data?.has_targets;

  async function shareImage() {
    if (!data) return;
    const blob = await rankingPng(data);
    const file = new File([blob], "klasemen.png", { type: "image/png" });
    if (navigator.canShare?.({ files: [file] })) { navigator.share({ files: [file], title: data.title }).catch(() => {}); return; }
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob); a.download = "klasemen.png"; a.click();
    window.setTimeout(() => URL.revokeObjectURL(a.href), 2000);
  }

  return (
    <AppShell>
      <V3Top title="Klasemen" subtitle="Peringkat wilayah terhadap target, apple-to-apple" region={region} onRegion={(v) => go({ region: v })} month={data?.month_chip} />
      <div className="v3 f-03-klasemen">
        <V3State error={error} loading={!data && !error} />
        {data && (
          <div className="body">
            <div className="hd">
              <div><div className="eb">Klasemen · {data.metric_label}</div><h1>{data.title}</h1>
                <div className="basis"><span><Icon name="cal" />{data.basis.label}</span>{data.source?.label_wib && <span><Icon name="db" />{data.source.label_wib}</span>}
                  <span><Icon name="info" />{data.small_base_label}</span></div></div>
              <div className="grow" />
              <button className="linkbtn" onClick={shareImage}><Icon name="share" />Bagikan gambar</button>
            </div>
            <div className="ctrl">
              <div className="seg">{LEVELS.map(([k, l]) => <button key={k} className={level === k ? "on" : ""} onClick={() => go({ level: k })}>{l}</button>)}</div>
              <div className="mchips">{METRICS.map(([k, l]) => <Tap key={k} className={metric === k ? "on" : ""} pressed={metric === k} onClick={() => go({ metric: k })}>{l}</Tap>)}</div>
              <span style={{ flex: 1 }} />
              <div className="seg" style={{ background: "#fff", border: "1px solid #E1E9E7" }}>
                <button className={sort === "achievement" ? "on" : ""} onClick={() => go({ sort: "achievement" })}>Urut: pencapaian target</button>
                <button className={sort === "growth" ? "on" : ""} onClick={() => go({ sort: "growth" })}>Pertumbuhan</button>
              </div>
            </div>
            {data.target_note && <div className="v3err" style={{ margin: 0, background: "#FDF3E2", color: "#6B4A0E" }}><Icon name="info" />{data.target_note}</div>}
            <div className="g2">
              <div style={{ display: "flex", flexDirection: "column", gap: 16, minWidth: 0 }}>
                {data.worst.length > 0 && (
                  <div className="pod">
                    <Podium title="Paling unggul" kind="best" rows={data.best} hasAch={hasAch} />
                    <Podium title="Perlu dorongan" kind="worst" rows={data.worst} hasAch={hasAch} />
                  </div>
                )}
                <section className="card" aria-label="Tabel klasemen" style={{ padding: "6px 0 10px" }}>
                  <div style={{ overflowX: "auto" }}>
                    <table className="kt">
                      <thead><tr><th style={{ paddingLeft: 20 }}>#</th><th></th><th>{HEAD[level]}</th><th>{hasAch ? "Pencapaian (proyeksi)" : "Nilai"}</th><th>Pertumbuhan</th><th className="n" style={{ paddingRight: 20 }}>{data.vs_label}</th></tr></thead>
                      <tbody>
                        {shown.map((r) => "gap" in r ? (
                          <tr key="gap" className="gaprow"><td colSpan={6}><Tap onClick={() => setAll(true)}>Peringkat {r.from} sampai {r.to} · Lihat semua {data.total} {data.noun}</Tap></td></tr>
                        ) : (
                          <tr key={r.key} className={r.mine ? "mrow" : ""} onClick={() => router.push(`/diagnosa?${new URLSearchParams({ metric: ["revenue", "payload", "subs"].includes(metric) ? metric : "revenue", basis: data.basis.kind === "mtd" ? "mtd" : "month", ...(level === "region" ? { region: r.key } : level === "kabupaten" ? { region: r.region, kabupaten: r.key } : { region: r.region }) })}`)} style={{ cursor: "pointer" }}>
                            <td className="rk" style={{ paddingLeft: 20 }}>{r.rank}</td>
                            <td><Move m={r.move} /></td>
                            <td className="nm"><b>{r.name}{r.small_base && <span className="small">Basis kecil</span>}</b><small><i className="rd" style={{ background: r.region_color }} />{r.region_label}{r.mine ? " · Wilayah pantauan kamu" : ""}</small></td>
                            <td>{r.achievement_pct != null
                              ? <><span className="bul"><i style={{ width: `${Math.min(100, r.achievement_pct * 0.8)}%`, background: achColor(r.achievement_pct) }} /><em /></span><span className="ach">{r.ach_label}</span></>
                              : <span className="ach" style={{ width: "auto", marginLeft: 0 }}>–</span>}</td>
                            <td><span className="dot"><i style={{ left: `${dotLeft(r.growth_pct)}%`, background: (r.growth_pct ?? 0) < 0 ? "#C42B2B" : "#2FA84F", ...(r.small_base ? { opacity: 0.55 } : {}) }} /></span></td>
                            <td className="n gp" style={{ paddingRight: 20 }}><b className={sign(r.growth_pct)}>{r.growth_label}</b><small>{r.abs_label}</small></td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                  <div className="foot" style={{ padding: "10px 20px 0" }}><Icon name="info" />Garis hitam = target 100%. Titik pertumbuhan di sumbu −10% sd +10%, titik pudar = basis kecil. Pencapaian adalah proyeksi akhir bulan (estimasi).<span className="grow" /></div>
                </section>
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: 16, minWidth: 0 }}>
                {data.mine && (
                  <section className="mine"><span className="t">Wilayah pantauan kamu</span>
                    <div className="r"><b>#{data.mine.rank}</b><span>dari {data.mine.total} · {data.mine.name}{data.mine.move_label && <><br />{data.mine.move_label}</>}</span></div>
                    {(data.mine.need_fmt || data.mine.cause) && (
                      <p>{data.mine.need_fmt && data.mine.need_label && <>Butuh tambahan <b>{data.mine.need_fmt}</b> sampai akhir bulan {data.mine.need_label}. </>}
                        {data.mine.cause && <>Penyebab terbesar: {data.mine.cause}.</>}</p>
                    )}
                    <div className="lk">
                      <Tap onClick={() => router.push(`/diagnosa?${new URLSearchParams({ metric: ["revenue", "payload", "subs"].includes(metric) ? metric : "revenue", basis: data.basis.kind === "mtd" ? "mtd" : "month", region: data.mine!.region, ...(level === "kabupaten" ? { kabupaten: data.mine!.key } : {}) })}`)}><Icon name="spark" />Kenapa?</Tap>
                      <Tap onClick={() => router.push(`/simulasi?${new URLSearchParams({ metric: metric === "subs" ? "subs" : "revenue", region: data.mine!.region })}`)}><Icon name="up" />Simulasi</Tap>
                    </div>
                  </section>
                )}
                <section className="card" aria-label="Klasemen region"><div className="ch"><div><h3>Klasemen region</h3><p>{hasAch ? `Proyeksi pencapaian target ${data.metric_label.toLowerCase()}` : `Pertumbuhan ${data.metric_label.toLowerCase()} ${data.vs_label}`}</p></div></div>
                  <div className="rcard">
                    {data.regions.map((r) => {
                      const top = Math.max(...data.regions.map((x) => (hasAch ? x.achievement_pct : Math.abs(x.growth_pct ?? 0)) ?? 0)) || 1;
                      const v = (hasAch ? r.achievement_pct : Math.abs(r.growth_pct ?? 0)) ?? 0;
                      return (
                        <div key={r.key} className="rrow"><span className="rk">{r.rank}</span>
                          <div><b>{r.name}</b><div className="bar"><i style={{ width: `${Math.round((v / top) * 100)}%`, background: r.color }} /></div></div>
                          <div className="v">{hasAch ? r.ach_label : r.growth_label}<small className={sign(r.growth_pct)}>{r.growth_label} · {r.abs_label}</small></div></div>
                      );
                    })}
                  </div></section>
                {data.badges.length > 0 && (
                  <section className="card" aria-label="Lencana"><div className="ch"><div><h3>Lencana minggu ini</h3><p>Diberikan otomatis dari data, dibagikan ke tim</p></div></div>
                    <div className="badges">{data.badges.map((b) => {
                      const [bg, fg] = BADGE[b.kind] ?? BADGE.climber;
                      return <div key={b.kind}><i style={{ background: bg, color: fg }}><Icon name={b.icon} /></i><b>{b.title}</b><small>{b.text}</small></div>;
                    })}</div></section>
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    </AppShell>
  );
}

function Move({ m }: { m?: number | null }) {
  if (m == null) return <span className="mv s">·</span>;
  if (m === 0) return <span className="mv s">=</span>;
  return <span className={`mv ${m > 0 ? "u" : "d"}`}>{m > 0 ? "▲" : "▼"}{Math.abs(m)}</span>;
}

function Podium({ title, kind, rows, hasAch }: { title: string; kind: "best" | "worst"; rows: Row[]; hasAch: boolean }) {
  return (
    <section className={`pc ${kind}`}><h3><Icon name="up" style={kind === "worst" ? { transform: "rotate(180deg)" } : undefined} />{title}</h3>
      {rows.map((r) => (
        <div key={r.key} className="pr"><span className="rk">{r.rank}</span><div><b>{r.name}</b><small>{r.region_label}{r.move_label ? ` · ${r.move_label}` : ""}</small></div>
          <div className="v">{hasAch ? r.ach_label : r.growth_label}<small className={sign(r.growth_pct)}>{r.growth_label} · {r.abs_label}</small></div></div>
      ))}
    </section>
  );
}

/** "Bagikan gambar": the ranking as a PNG card drawn on a canvas (title, basis, top and bottom rows). */
async function rankingPng(d: Klas): Promise<Blob> {
  const rows = d.rows.length > 13 ? [...d.rows.slice(0, 10), ...d.rows.slice(-3)] : d.rows;
  const W = 900, H = 170 + rows.length * 44 + 50, c = document.createElement("canvas");
  c.width = W * 2; c.height = H * 2;
  const g = c.getContext("2d")!;
  g.scale(2, 2);
  g.fillStyle = "#F5F9F8"; g.fillRect(0, 0, W, H);
  g.fillStyle = "#0A6A5F"; g.fillRect(0, 0, W, 8);
  const font = (w: number, s: number) => `${w} ${s}px Poppins, "Segoe UI", sans-serif`;
  g.fillStyle = "#0F1F1D"; g.font = font(800, 26); g.fillText(d.title, 32, 56);
  g.fillStyle = "#5A6B68"; g.font = font(500, 14); g.fillText(`${d.metric_label} · ${d.basis.label}${d.source?.label_wib ? " · " + d.source.label_wib : ""}`, 32, 84);
  g.font = font(600, 12); g.fillText("#", 32, 130); g.fillText(HEAD[d.level].toUpperCase(), 80, 130);
  g.fillText(d.has_targets ? "PENCAPAIAN" : "", 520, 130); g.fillText("PERTUMBUHAN", 700, 130);
  rows.forEach((r, i) => {
    const y = 170 + i * 44;
    if (i === 10 && d.rows.length > 13) { g.fillStyle = "#8A9A97"; g.font = font(500, 12); g.fillText("…", 32, y - 16); }
    g.fillStyle = r.mine ? "#FFF8F5" : "#fff"; g.fillRect(24, y - 26, W - 48, 38);
    g.fillStyle = "#0F1F1D"; g.font = font(700, 15); g.fillText(String(r.rank), 32, y);
    g.font = font(600, 15); g.fillText(r.name, 80, y);
    g.fillStyle = r.region_color; g.fillRect(80, y + 5, 7, 7);
    g.fillStyle = "#5A6B68"; g.font = font(400, 11); g.fillText(r.region_label, 92, y + 12);
    g.fillStyle = achColor(r.achievement_pct); g.font = font(700, 15); g.fillText(r.ach_label ?? "", 520, y);
    g.fillStyle = (r.growth_pct ?? 0) < 0 ? "#C42B2B" : "#1F7A3A"; g.fillText(`${r.growth_label}  ${r.abs_label}`, 700, y);
  });
  g.fillStyle = "#5A6B68"; g.font = font(500, 12); g.fillText("Agent Java · Circle Java", 32, H - 22);
  return new Promise((ok) => c.toBlob((b) => ok(b!), "image/png"));
}

export default function KlasemenPage() {
  return <Suspense fallback={<div className="ui-boot" />}><KlasemenView /></Suspense>;
}
