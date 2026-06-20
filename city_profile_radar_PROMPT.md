# BUILD PROMPT: City Profile Radar (Mobile + Web)

You are a senior full-stack engineer. Add a new feature to an existing mobile and web
application that already stores prepaid telecom performance data per geography
(circle, kabkota, kecamatan). Build a single menu screen, "City Profile", that scores
any geography across 6 pillars and renders a radar chart plus scorecards, with drill-down
from kabkota to kecamatan. Follow this spec exactly. Where the host app already defines a
pattern (framework, router, data layer, theme), adapt to it; do not introduce a parallel stack.

Hard rules:
- Do not use em-dashes anywhere in code, comments, copy, or labels.
- The scoring engine is one shared, pure, unit-tested module used by both web and mobile. No duplicated math.
- Every radar axis must be a normalized 0 to 100 score, never a raw value. Raw volumes are forbidden on the radar.

---

## 1. Goal and scope

One new menu item ("City Profile" / "Profil Kota") that lets a user:
1. Pick a geography and drill Circle to Kabkota to Kecamatan.
2. See an overall health score (0 to 100) with a tier (Win, Watch, Risk).
3. See a 6-axis radar of pillar scores.
4. Inspect each pillar's sub-signals (raw value, normalized score, contribution).
5. Compare up to 3 geographies on one radar.
6. Switch scoring lens (Level vs Growth) and period basis (YoY vs MoM).
7. Drill into a parent's children ranked by overall score.

Single source of truth for the model is the config in Section 4. It must be editable
without touching engine code.

---

## 2. Scoring model (three layers)

Layer 1, Signal score (0 to 100): normalize each sub-metric by its TYPE.
Layer 2, Pillar score (0 to 100): weighted mean of its signals. This is one radar axis.
Layer 3, Overall (0 to 100): weighted mean of the 6 pillars. Shown at radar center and in the hero.

Normalization, one formula per type:

GROWTH (intrinsic zero at flat; for lower-is-better metrics pass invert=true so g becomes -g):
```
s = clip(50 + (g / band) * 50, 0, 100)
```
g = growth percent. band = growth that earns full marks. Flat (0%) scores 50, +band scores 100, -band scores 0.

SIZE (absolute Rp or subs, only comparable against peers via percentile anchoring):
```
s = clip((v - p10) / (p90 - p10) * 100, 0, 100)
```
p10 and p90 are the 10th and 90th percentiles of the peer set (siblings at the same geo level).
If fewer than MIN_PEERS peers, disable this signal's percentile path and fall back (see Section 6).

RATIO (already a percent, has a healthy target):
```
s = clip(v / target * 100, 0, 100)
```

RANK (ordinal vs named competitors):
```
s = (N - rank) / (N - 1) * 100
```
N = number of competitor groups. rank 1 scores 100, last scores 0.

SHARE_VS_FAIR (optional smarter mode for SoGA): score acquisition share relative to held share.
```
s = clip(50 + ((soga_pct - ms_pct) / fair_band) * 50, 0, 100)
```
soga above ms means winning more than fair share, which scores above 50.

Aggregation:
```
pillar  = sum(w_i * s_i)      with sum(w_i) = 1
overall = sum(W_p * pillar_p) with sum(W_p) = 1
```

Tiers (applied to any 0 to 100 score):
```
Win   if score >= 60
Watch if 40 <= score < 60
Risk  if score < 40
```

---

## 3. Metric tree mapped to source fields

The host data uses MTD, LMTD, LLMTD columns plus precomputed MoM and YoY per metric and
per operator (IOH, IM3, 3ID, and competitor groups TSEL, XL+SF). Use IOH (IM3+3ID) unless noted.

| Pillar | Signal | Source field | Type | Period | Invert |
|---|---|---|---|---|---|
| 1 Revenue | Growth Prepaid | Rev Prepaid | growth | YoY | no |
| | Growth VSD | Rev VSD | growth | YoY | no |
| | Growth Rev Data (ASSUMED, confirm) | Rev Data | growth | YoY | no |
| 2 Subscriber | Growth VLR | Avg VLR Daily | growth | YoY | no |
| | Growth RGU 90D | RGU 90D | growth | YoY | no |
| | Growth Data UU Daily | Data UU Daily | growth | YoY | no |
| 3 Acquisition | Growth Gross Add | Gross Add | growth | MoM | no |
| | Acquisition Quality | GA 500MB+ % of GA | ratio | MTD | no |
| | SoGA | FB SoGA % | share_vs_fair (or ratio) | LMTD if MTD=0 | no |
| 4 Productivity | Revenue per Site | Avg Rev / Base Site | size | MTD | no |
| | Growth Rev per Site | Avg Rev / Base Site | growth | YoY | no |
| 5 Subs Productivity | ARPU Size | ARPU 90D | size | MTD | no |
| | Pack Subs Growth | Pack Subs | growth | YoY | no |
| | HVC Ratio | Ratio HVC Stay | ratio | MTD | no |
| 6 Competition | Market Share Size | FB MS % | ratio (target = fair share) | LMTD if MTD=0 | no |
| | Market Growth YoY | FB MS amount | growth | YoY | no |
| | Market Share Rank | rank by FB MS % among operator groups | rank | LMTD if MTD=0 | no |

Notes the agent must respect:
- Gross Add YoY is unreliable in source (tracking change; GA Trade and Biometric have no YoY). Use MoM. Keep period configurable.
- FB MS and FB SoGA MTD columns are 0 until month close. When the requested period's MTD share equals 0, fall back to LMTD for those signals and surface a "partial month" badge.
- Acquisition Quality lower bound is the share collapsing; do not invert, higher is better.
- The third Revenue signal was not fully specified by the product owner. Defaulted to Rev Data. Make it a one-line config change to swap to Rev Base or Rev Acquisition.

---

## 4. Model config (single source of truth, editable)

Ship this as a config file (YAML or JSON). The engine reads it; changing weights, bands,
or targets must not require code changes.

```yaml
scoring:
  tiers: { win: 60, watch: 40 }
  min_peers: 5            # below this, size/percentile signals fall back
  default_band: 20        # growth band for revenue and base pillars
  pillars:
    revenue:
      weight: 0.20
      signals:
        - { key: growth_prepaid, field: rev_prepaid, type: growth, period: yoy, band: 20, weight: 0.34 }
        - { key: growth_vsd,     field: rev_vsd,     type: growth, period: yoy, band: 20, weight: 0.33 }
        - { key: growth_data,    field: rev_data,    type: growth, period: yoy, band: 20, weight: 0.33 }
    subscriber:
      weight: 0.18
      signals:
        - { key: growth_vlr,     field: vlr_daily,   type: growth, period: yoy, band: 10, weight: 0.30 }
        - { key: growth_rgu90,   field: rgu_90d,     type: growth, period: yoy, band: 15, weight: 0.40 }
        - { key: growth_uu_daily,field: data_uu_daily,type: growth,period: yoy, band: 15, weight: 0.30 }
    acquisition:
      weight: 0.18
      signals:
        - { key: growth_ga,      field: gross_add,   type: growth, period: mom, band: 30, weight: 0.34 }
        - { key: acq_quality,    field: ga_500mb_pct,type: ratio,  target: 70,           weight: 0.33 }
        - { key: soga,           field: fb_soga_pct, type: share_vs_fair, fair_field: fb_ms_pct, fair_band: 5, weight: 0.33 }
    productivity:
      weight: 0.14
      signals:
        - { key: rev_per_site,   field: rev_per_base_site, type: size,  weight: 0.50 }
        - { key: growth_rev_site,field: rev_per_base_site, type: growth, period: yoy, band: 15, weight: 0.50 }
    subs_productivity:
      weight: 0.15
      signals:
        - { key: arpu_size,      field: arpu_90d,    type: size,                          weight: 0.34 }
        - { key: pack_growth,    field: pack_subs,   type: growth, period: yoy, band: 10, weight: 0.33 }
        - { key: hvc_ratio,      field: hvc_stay_pct,type: ratio,  target: 90,            weight: 0.33 }
    competition:
      weight: 0.15
      signals:
        - { key: ms_size,        field: fb_ms_pct,   type: ratio,  target: 33.3,          weight: 0.34 }
        - { key: ms_growth,      field: fb_ms_amount,type: growth, period: yoy, band: 10, weight: 0.33 }
        - { key: ms_rank,        field: fb_ms_rank,  type: rank,   n: 3,                  weight: 0.33 }
```

---

## 5. Data contract

The feature consumes two read functions exposed by the existing data layer. Match the host's
naming and transport (REST, GraphQL, RPC, or local store). Required shapes:

`getGeoMetrics(geoId, period)` returns one geography:
```json
{
  "geo_id": "kabkota_surabaya",
  "geo_name": "Surabaya",
  "level": "kabkota",
  "parent_id": "circle_java",
  "as_of": "2026-06-11",
  "partial_month": true,
  "metrics": {
    "rev_prepaid":      { "mtd": 430878, "lmtd": 452711, "yoy": 9.0, "mom": -4.8 },
    "rev_vsd":          { "mtd": 397971, "yoy": 8.9, "mom": -0.4 },
    "rev_data":         { "mtd": 395806, "yoy": 9.3, "mom": -0.4 },
    "vlr_daily":        { "mtd": 25794834, "yoy": 1.1, "mom": 1.0 },
    "rgu_90d":          { "mtd": 29383074, "yoy": -8.6, "mom": -1.5 },
    "data_uu_daily":    { "mtd": 15389362, "yoy": -9.6, "mom": 2.8 },
    "gross_add":        { "mtd": 229110, "yoy": -39.4, "mom": 21.3 },
    "ga_500mb_pct":     { "mtd": 41.86 },
    "fb_soga_pct":      { "mtd": 0, "lmtd": 36.31 },
    "fb_ms_pct":        { "mtd": 0, "lmtd": 34.49 },
    "fb_ms_amount":     { "mtd": 0, "lmtd": 19897461, "yoy": null },
    "fb_ms_rank":       { "mtd": null, "lmtd": 2 },
    "rev_per_base_site":{ "mtd": 26607610, "yoy": 9.8 },
    "arpu_90d":         { "mtd": 14664, "yoy": 22.9 },
    "pack_subs":        { "mtd": 9538473, "yoy": 1.2 },
    "hvc_stay_pct":     { "mtd": 86.91 }
  }
}
```

`getPeerMetrics(parentId, level, period)` returns an array of sibling geographies in the same
shape, used to compute p10 and p90 for SIZE signals and to confirm rank. The engine must
accept the peer array and derive percentiles itself.

Field mapping (source field to contract key) lives next to the config so analysts can rewire
it without code edits.

---

## 6. Engine behavior and edge cases

Write the engine as a pure function. No I/O, no framework imports.

```
computeProfile(target, peers, config, options) -> {
  overall: number, overallTier: string,
  pillars: [ { key, label, score, tier, topDriver, signals: [
    { key, label, type, raw, growth, score, contribution, status } ] } ]
}
```

Rules:
- clip(x) = max(0, min(100, x)).
- GROWTH: read metrics[field][period]. If null, score = 50 and mark status "no-data".
- SIZE: build the peer value array, compute p10/p90 (linear interpolation). If peers.length < min_peers, set status "insufficient-peers" and fall back to RATIO against a configured target, or to a neutral 50 if no target. Never crash.
- RATIO: if value missing, status "no-data", score 50.
- share_vs_fair: needs both fb_soga_pct and fb_ms_pct for the same period.
- RANK: if rank missing, status "no-data", score 50.
- partial_month true and a signal needs MTD share that is 0: read lmtd, set signal status "partial-month".
- LYTD or denominator equals 0 in any growth or ratio: treat as null, do not divide by zero.
- contribution = weight_in_pillar * signal_score, so the UI can show which signal lifts or drags the pillar.
- topDriver = signal with the largest absolute deviation from 50 (the one most shaping the pillar).

Determinism: same inputs always produce the same output. Add unit tests covering each type,
the fallbacks, and the golden case in Section 9.

---

## 7. UI and UX

Layout, web (desktop, two columns):
```
+--------------------------------------------------------------+
| Breadcrumb: Circle Java > Surabaya      [Period: YoY v]      |
|                                         [Lens: Level v]      |
+----------------------------+---------------------------------+
| OVERALL HERO               | RADAR (6 pillars)               |
|  73  Win  ^ +4 vs last     |        Revenue                  |
|  Surabaya                  |   Compet.      Subscriber       |
|                            |   SubsProd       Acquisition    |
| PILLAR CARDS (6, 2x3)      |        Productivity             |
|  [Revenue 73 Win]          |  legend: city A / B / C         |
|  [Subscriber 36 Risk] ...  +---------------------------------+
|                            | SIGNAL DETAIL (accordion)       |
| CHILDREN RANKING           |  > Revenue 73                   |
|  Kecamatan by overall      |     Growth Prepaid +9.0  72  Win|
|  1 Rungkut    78           |     Growth VSD     +8.9  72  Win|
|  2 Gubeng     74  ...      |  > Subscriber 36 ...            |
+----------------------------+---------------------------------+
```

Layout, mobile (single column, radar first, swipeable cards):
```
[ Breadcrumb + filters as compact chips ]
[ RADAR, full width ]
[ OVERALL HERO: 73 Win, delta ]
[ Pillar cards: horizontal swipe, tap to expand ]
[ Signal detail: accordion under the tapped pillar ]
[ Children ranking: tappable list, each row drills down ]
```

Components to build:
1. GeoSelector + Breadcrumb. Drill down Circle to Kabkota to Kecamatan. Breadcrumb segments are tappable to go back up.
2. Controls: Period toggle (YoY, MoM), Lens toggle (Level, Growth). Level uses size/ratio/rank as configured. Growth recomputes every signal as a growth score for trajectory view.
3. OverallHero: big score, tier pill, delta vs prior period, geo name, partial-month badge when relevant.
4. RadarChart: 6 axes, rings at 0/25/50/75/100, middle ring (50) highlighted as "flat". Tapping an axis selects that pillar and scrolls the detail to it. Supports up to 3 overlaid geographies with distinct colors. Render as scalable vector so it stays crisp on web and mobile; no external chart library unless the host app already bundles one.
5. PillarCards: one per pillar, showing score, tier, and topDriver label. Tap selects the pillar.
6. SignalDetail: accordion or table per pillar listing each signal with raw value, growth or ratio context, normalized score, tier dot, and a contribution bar. Mark "partial-month", "no-data", "insufficient-peers" inline.
7. ChildrenRanking: list of the current geography's children sorted by overall score, each row with a mini score and tier, tap to drill into that child.
8. ComparisonTray: add or remove geographies for overlay (max 3), with a clear and a swap.
9. Legend and TierKey.

Interaction flow:
- Open menu, default to the user's home geography or Circle.
- Selecting a child updates radar, hero, cards, detail, and the children list for the new level.
- Selecting an axis or a pillar card highlights it across radar and detail.
- Lens or Period change recomputes instantly client-side from the same fetched metrics where possible.

States:
- Loading: skeletons for radar, hero, cards.
- Empty: "No data for this geography yet."
- Insufficient peers: size signals show a quiet note and use fallback; do not hide the axis.
- Partial month: badge in hero plus per-signal markers.

Accessibility and quality floor:
- Keyboard focus visible on all controls; radar axes reachable and labeled.
- Respect reduced-motion (no entrance animation when set).
- Color is never the only signal; tiers also carry a label.
- Responsive down to a 360px viewport.

---

## 8. Design system (IOH)

Colors:
- Primary red #ED1C24, Pink #EC008C, Yellow #FFCB05, Teal #32BCAD, Magenta #C6168D.
- Tiers: Win #32BCAD, Watch #FFB000, Risk #ED1C24.
- Overlay series: #ED1C24, #32BCAD, #C6168D.
Type:
- Display and labels: Poppins (600 to 800). Data and body: Prompt (300 to 600).
Tone:
- Action labels say what happens ("Compare", "Clear", "Drill down"). Sentence case. No em-dashes.
Numbers:
- Thousands separators on volumes, one decimal on percents and scores in detail, integer scores on cards and hero.

---

## 9. Golden test (the engine must reproduce this)

Input is Circle Java from the contract example, Level lens, YoY period, equal signal weights,
bands per config above, targets per config, peers absent so size signals use fallback.

Expected, rounded:
- Revenue pillar: Growth Prepaid +9.0 -> 72.5, Growth VSD +8.9 -> 72.3, Growth Data +9.3 -> 73.3. Pillar 73, Win.
- Subscriber pillar: VLR +1.1 (band 10) -> 55.5, RGU 90D -8.6 (band 15) -> 21.3, Data UU -9.6 (band 15) -> 18.0. Pillar approx 32, Risk.

The contrast (Revenue high, Subscriber low) must show as a fat Revenue arm and a collapsed
Subscriber arm on the radar. If the engine smooths this into a middling overall, the
normalization is wrong. Add these as assertions.

---

## 10. Acceptance criteria

- [ ] New "City Profile" menu renders on both web and mobile from the same engine module.
- [ ] Radar shows 6 normalized pillar scores; no raw volume appears on any axis.
- [ ] Drill works Circle to Kabkota to Kecamatan, with a working breadcrumb back up.
- [ ] Children ranking sorts by overall score and drills on tap.
- [ ] Period and Lens toggles recompute correctly and instantly.
- [ ] Comparison overlays up to 3 geographies with distinct colors and a clear control.
- [ ] Partial-month, no-data, and insufficient-peers states are handled, never crash.
- [ ] Golden test in Section 9 passes.
- [ ] No em-dashes anywhere. IOH palette and type applied. Responsive to 360px. Reduced-motion respected.

---

## 11. Deliverables

1. Shared scoring engine module with unit tests (pure, framework-agnostic).
2. Model config file (YAML or JSON) plus the field-mapping file.
3. Feature screen and components for web and mobile, wired to getGeoMetrics and getPeerMetrics.
4. A short README: how to edit pillars, weights, bands, and targets, and how to add a new signal.

Before coding, confirm two open items with the product owner and proceed with the noted
defaults if no answer:
1. Third Revenue signal: default Rev Data. Alternatives Rev Base or Rev Acquisition.
2. Growth basis per pillar: default YoY everywhere except Acquisition Gross Add which uses MoM.
