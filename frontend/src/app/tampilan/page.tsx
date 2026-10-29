"use client";
import { useEffect, useState } from "react";
import { Check, Database, Monitor, Moon, Palette, Sparkles, Sun, TrendingDown, TrendingUp, Wallet } from "lucide-react";
import AppShell from "../components/shell/AppShell";
import PageHero from "../components/ui/PageHero";
import { DEFAULT_PREFS, getPrefs, PREFS_EVENT, setPrefs, type AccentPref, type DensityPref, type ThemePref, type UiPrefs } from "@/lib/prefs";
import "./tampilan.css";

const THEMES: { key: ThemePref; label: string; icon: typeof Sun }[] = [
  { key: "light", label: "Terang", icon: Sun },
  { key: "dark", label: "Gelap", icon: Moon },
  { key: "system", label: "Ikuti sistem", icon: Monitor },
];
const ACCENTS: { key: AccentPref; label: string }[] = [
  { key: "teal", label: "Teal" }, { key: "zamrud", label: "Zamrud" }, { key: "laut", label: "Laut" },
  { key: "amber", label: "Amber" }, { key: "grafit", label: "Grafit" },
];
const DENSITIES: { key: DensityPref; label: string }[] = [
  { key: "lega", label: "Lega" }, { key: "standar", label: "Standar" }, { key: "ringkas", label: "Ringkas" },
];
const TOGGLES: { key: "animation" | "tooltip" | "targetLine"; label: string; sub: string }[] = [
  { key: "animation", label: "Animasi transisi", sub: "Perpindahan halus saat filter dan drill-down" },
  { key: "tooltip", label: "Tooltip & crosshair saat hover", sub: "Tampilkan nilai di titik yang ditunjuk" },
  { key: "targetLine", label: "Tampilkan garis target", sub: "Garis putus-putus pada grafik KPI" },
];

export default function TampilanPage() {
  const [p, setP] = useState<UiPrefs>(DEFAULT_PREFS);

  useEffect(() => {
    const sync = () => setP(getPrefs());
    const t = setTimeout(sync, 0);
    window.addEventListener(PREFS_EVENT, sync);
    return () => { clearTimeout(t); window.removeEventListener(PREFS_EVENT, sync); };
  }, []);

  const update = (patch: Partial<UiPrefs>) => setP(setPrefs(patch));
  const accentLabel = ACCENTS.find((a) => a.key === p.accent)?.label.toLowerCase() ?? "teal";

  return (
    <AppShell>
      <div className="ui-page tp">
        <PageHero
          icon={<Palette size={30} strokeWidth={1.6} />}
          art="/illustrations/hero_ai_orb.svg"
          eyebrow="Pengaturan"
          title="Tampilan"
          sub="Atur tema, warna aksen, kepadatan dan perilaku grafik. Perubahan langsung terlihat di pratinjau."
        />

        <div className="tp-body">
          <div className="tp-settings">
            <section className="ui-card tp-card" aria-labelledby="tp-tema">
              <h2 id="tp-tema" className="tp-h">Tema</h2>
              <p className="tp-sub">Mode gelap memakai variabel warna yang sama (mode “Gelap”).</p>
              <div className="tp-themes" role="radiogroup" aria-label="Tema">
                {THEMES.map(({ key, label, icon: Icon }) => (
                  <button key={key} role="radio" aria-checked={p.theme === key} className="tp-theme" onClick={() => update({ theme: key })}>
                    <span className={`tp-thumb ${key}`} aria-hidden="true">
                      <i className="side" /><i className="bar" /><i className="c1" /><i className="c2" />
                    </span>
                    <span className="tp-theme-lbl"><Icon size={16} /> {label}<span className="tp-radio" /></span>
                  </button>
                ))}
              </div>
            </section>

            <section className="ui-card tp-card" aria-labelledby="tp-aksen">
              <h2 id="tp-aksen" className="tp-h">Warna aksen</h2>
              <p className="tp-sub">Teal adalah warna utama brand; aksen lain untuk preferensi pribadi.</p>
              <div className="tp-accents" role="radiogroup" aria-label="Warna aksen">
                {ACCENTS.map((a) => (
                  <button key={a.key} role="radio" aria-checked={p.accent === a.key} className={`tp-accent a-${a.key}`}
                    onClick={() => update({ accent: a.key })}>
                    <span className="tp-swatch">{p.accent === a.key && <Check size={18} strokeWidth={2.5} />}</span>
                    {a.label}
                  </button>
                ))}
              </div>
            </section>

            <section className="ui-card tp-card" aria-labelledby="tp-kepadatan">
              <h2 id="tp-kepadatan" className="tp-h">Kepadatan &amp; teks</h2>
              <p className="tp-sub">Ringkas memperkecil padding tabel dan kartu.</p>
              <div className="tp-line">
                <span className="tp-lbl">Kepadatan</span>
                <div className="ui-seg tp-seg" role="group" aria-label="Kepadatan">
                  {DENSITIES.map((d) => (
                    <button key={d.key} aria-pressed={p.density === d.key} onClick={() => update({ density: d.key })}>{d.label}</button>
                  ))}
                </div>
              </div>
              <div className="tp-line">
                <label className="tp-lbl" htmlFor="tp-text">Ukuran teks</label>
                <span className="tp-a sm" aria-hidden="true">A</span>
                <input id="tp-text" type="range" min={85} max={120} step={5} value={p.textScale} className="tp-range"
                  style={{ ["--v" as string]: `${((p.textScale - 85) / 35) * 100}%` }}
                  onChange={(e) => update({ textScale: +e.target.value })} aria-valuetext={`${p.textScale}%`} />
                <span className="tp-a lg" aria-hidden="true">A</span>
                <b className="tp-pct">{p.textScale}%</b>
              </div>
            </section>

            <section className="ui-card tp-card" aria-labelledby="tp-grafik">
              <h2 id="tp-grafik" className="tp-h">Grafik &amp; interaksi</h2>
              <p className="tp-sub">Berlaku untuk dashboard, jawaban agent dan peta.</p>
              <ul className="tp-toggles">
                {TOGGLES.map((t) => (
                  <li key={t.key}>
                    <div><b id={`tg-${t.key}`}>{t.label}</b><span>{t.sub}</span></div>
                    <button className="ui-switch" role="switch" aria-checked={p[t.key]} aria-labelledby={`tg-${t.key}`}
                      onClick={() => update({ [t.key]: !p[t.key] })} />
                  </li>
                ))}
              </ul>
            </section>
          </div>

          <aside className="tp-preview" aria-label="Pratinjau langsung">
            <span className="tp-prev-title">Pratinjau langsung</span>
            <Preview mode="light" accent={p.accent} accentLabel={accentLabel} target={p.targetLine} density={p.density} />
            <Preview mode="dark" accent={p.accent} accentLabel={accentLabel} target={p.targetLine} density={p.density} />
          </aside>
        </div>
      </div>
    </AppShell>
  );
}

const SPARK = [40, 44, 50, 46, 38, 30, 34, 26, 32, 22, 12, 24, 28, 20];

function Preview({ mode, accent, accentLabel, target, density }: { mode: "light" | "dark"; accent: AccentPref; accentLabel: string; target: boolean; density: DensityPref }) {
  const w = 400, h = 64;
  const step = w / (SPARK.length - 1);
  let line = `M0,${SPARK[0]}`;
  for (let i = 1; i < SPARK.length; i++) {
    const x0 = (i - 1) * step, x1 = i * step, cx = (x0 + x1) / 2;
    line += ` C${cx},${SPARK[i - 1]} ${cx},${SPARK[i]} ${x1},${SPARK[i]}`;
  }
  const id = `tp-g-${mode}`;
  return (
    <div className={`tp-pv ${mode} pa-${accent} pd-${density}`}>
      <div className="tp-pv-head">
        <b>Dashboard · {mode === "light" ? "Terang" : "Gelap"}</b>
        <span className="tp-pv-chip">Aksen {accentLabel}</span>
      </div>
      <div className="tp-pv-banner"><Sparkles size={18} /> Revenue Jawa naik 1,2% MoM</div>
      <div className="tp-pv-kpis">
        <div className="tp-pv-kpi">
          <div className="tp-pv-top"><span className="tp-pv-ico amber"><Wallet size={16} /></span><span className="up"><TrendingUp size={12} />1,2%</span></div>
          <span className="tp-pv-lbl">Revenue</span><b>Rp 1,84 T</b><small>vs Sep</small>
        </div>
        <div className="tp-pv-kpi">
          <div className="tp-pv-top"><span className="tp-pv-ico violet"><Database size={16} /></span><span className="down"><TrendingDown size={12} />0,4%</span></div>
          <span className="tp-pv-lbl">Payload</span><b>84,2 PB</b><small>vs Sep</small>
        </div>
      </div>
      <svg className="tp-pv-spark" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" aria-hidden="true">
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--pv-accent)" stopOpacity="0.22" />
            <stop offset="1" stopColor="var(--pv-accent)" stopOpacity="0" />
          </linearGradient>
        </defs>
        <path d={`${line} L${w},${h} L0,${h} Z`} fill={`url(#${id})`} />
        <path d={line} fill="none" stroke="var(--pv-accent)" strokeWidth="2" vectorEffect="non-scaling-stroke" />
        {target && <line x1="0" x2={w} y1="30" y2="30" stroke="var(--pv-mute)" strokeDasharray="4 4" vectorEffect="non-scaling-stroke" />}
        <line x1="0" x2={w} y1={h - 1} y2={h - 1} stroke="var(--pv-rule)" vectorEffect="non-scaling-stroke" />
      </svg>
    </div>
  );
}
