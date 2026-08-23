---
title: FTTH / Indosat HiFi
type: domain
updated: 2026-07-26
---

# FTTH / Indosat HiFi

Fixed broadband domain. LIVE in the platform (2026-06). Builder: `reports_ftth.py`.
Full reverse-engineered reference: [[big-docs]] → `FTTH_KNOWLEDGE_BASE.txt` (read only for
legacy/PHP detail; the live truth is here + AGENTS.md).

## Funnel (heart of everything)

`SO → SA → PA`. Each stage counted on ITS OWN event date, never a shared date.
- SO = Service Order · SA = Service Active · PA = **Permanent Active** (the money event)
- AP = Advance Payment product (multi-month prepaid). Product mix AP regex `^(AP|Super ?)[0-9]+`.
- TUR = Take-Up Rate = PA / homepass.

## Own territory vocabulary (does NOT align with IM3 hierarchy)

- Detail tables use `sales_region`; sitewise uses `region_25`, coded like `04. Central Java`,
  `05. East Java`, plus `province`/`city`/`kecamatan`.
- **`sales_region` is a SALES vocabulary, not geography** (verified 2026-08-21 against
  `rham_ftth_so_detail`): `05. East Java` holds 85,644 Jawa Timur rows but ALSO 1,675 Bali
  rows plus stray Jabar/DKI/Jateng/Sumut/Aceh/Banten rows. A question that names a PROVINCE
  ("di Jawa Timur") must filter `province`, not `sales_region`. Chat-agent KB fact added in
  the `ftth` domain; this was the root cause of the funnel question returning nothing useful.
  See [[agent-quality-gates]].
- Detail tables' `shp_kabkota` / `shp_kecamatan` are NULL → FTTH filters on native columns,
  never via `rham_ref_territory`.
- Filter levels: `ftth_region` / `ftth_province` / `ftth_kabkota` / `ftth_kecamatan`
  (helpers `_detail_scope_clause` / `_sitewise_scope_clause`).
- Options: `GET /api/reports/ftth/scope-options?circle=&level=` (from sitewise).
- My Coordinate sends IM3 `kec_id` like `ADIWERNA|KAB. TEGAL`; FTTH stores bare `ADIWERNA`.
  `_norm_kec()` strips the `|kabkota` suffix. IM3 region/area/branch/microcluster have no FTTH
  equivalent → degrade to circle scope.
- Normalize region by NAME (strip `NN. ` prefix) when mixing months — codes were renumbered
  in the 2026-06 restructure (old "03. Central Java" → new "04. Central Java", etc).

## Two grains (never mix at row level)

- **Detail** (`rham_ftth_{so,sa,pa}_detail`): per-customer funnel on each event date.
- **Sitewise** (`rham_ftth_sitewise_monthly`): monthly per-site SUBSCRIBER snapshot —
  `pa` = cumulative active subs, `homepass`, `available_hp`, `ga`, `pa_net_latest`.
  - TUR = SUM(pa) / SUM(homepass) * 100.
  - Total subs = SUM(pa) at MAX(month_id), **never summed across months**.
  - Low TUR site = `pa/homepass < 0.2 AND homepass > 0`.

## Footprint (`project_awal`)

`mplay` = ORBIT · `seahawk`/`spartan` = NON-ORBIT · `iforte` = IFORTE.

## Report specifics

- YTD/LYTD via date range on event-dated detail tables → see [[ytd-lytd-apple-to-apple]].
- Section layouts: `grid` (CompTable), `ftth_counts` (label+number), `hierarchy` (expandable
  SM→TL→AE, sorted SO MTD desc). "FTTH Infrastructure & Utilization" is first section.
- Brand bar (IOH/IM3/3ID) is global EXCEPT hidden on the FTTH tab. See [[reports]].

## Related

- [[reports]] · [[bigquery-tables]] · [[ytd-lytd-apple-to-apple]] · [[geo]]
