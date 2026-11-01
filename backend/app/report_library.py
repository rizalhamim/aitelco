"""Laporan library (Redesign v2 page 06): report documents as typed sections.

One JSON shape feeds the web preview and the Android preview, so both render the same
strings. Every number comes from the dashboard overview and the Performance dump
(kec_month, site_month, avail_month). Metrics the dump does not carry yet (market share,
FWA, VLR, revenue per new site, channel) are returned as null cells with a note, never
filled with a guess.

GET /api/report-docs/library                     items for the library list
GET /api/report-docs/doc?kind=outlook&region=     Performance Outlook (9 sections, 6 pages)
GET /api/report-docs/doc?kind=bulanan&region=     Performa Bulanan (2 pages)
GET /api/report-docs/doc?kind=profile&kabupaten=  Profile wilayah of one kabupaten/kota
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from . import performance as pf, perf_dump, reports_cache
from .auth import get_current_user
from .database import User

router = APIRouter(prefix="/api/report-docs", tags=["report-docs"])

WIB = timezone(timedelta(hours=7))
MONTHS_SHORT = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]
MONTHS_FULL = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober",
               "November", "Desember"]
UP, DOWN = "up", "down"
MISSING = "Belum ada di dump Parquet"

OUTLOOK_TOC = ["Ringkasan", "Performance per region", "Revenue dan channel", "Subscriber dan RGU", "Site productivity",
               "Network dan availability", "Profile wilayah", "Market share", "Catatan agent"]
# Page 1 carries the four sections Rizal asked to see first (not only payload).
OUTLOOK_PAGES = [[1, 2, 5, 7], [3], [4], [6], [8], [9]]


# ── Formatting (Indonesian decimals) ─────────────────────────────────────────

def _idn(v: float, d: int) -> str:
    s = f"{v:,.{d}f}"
    return s.replace(",", "#").replace(".", ",").replace("#", ".")


def rp(v: Optional[float]) -> Optional[str]:
    if v is None:
        return None
    a = abs(v)
    if a >= 1e12:
        return f"Rp {_idn(v / 1e12, 2)} T"
    if a >= 1e9:
        return f"Rp {_idn(v / 1e9, 1)} M"
    return f"Rp {_idn(v / 1e6, 0)} jt"


def num(v: Optional[float]) -> Optional[str]:
    if v is None:
        return None
    a = abs(v)
    if a >= 1e7:
        return f"{_idn(v / 1e6, 1)} jt"
    if a >= 1e6:
        return f"{_idn(v / 1e6, 2)} jt"
    if a >= 1e5:
        return f"{_idn(v / 1e3, 0)} rb"
    if a >= 1e3:
        return f"{_idn(v / 1e3, 1)} rb"
    return _idn(v, 0)


def gb(v: Optional[float]) -> Optional[str]:
    if v is None:
        return None
    a = abs(v)
    if a >= 1e6:
        return f"{_idn(v / 1e6, 1)} PB"
    if a >= 1e3:
        return f"{_idn(v / 1e3, 1)} TB"
    return f"{_idn(v, 0)} GB"


def pct(v: Optional[float], d: int = 1) -> Optional[str]:
    return None if v is None else f"{_idn(v, d)}%"


def delta(v: Optional[float], unit: str = "%") -> Optional[dict]:
    """A MoM change cell: "▲ 1,2%" green or "▼ 0,4%" red."""
    if v is None:
        return None
    return {"v": f"{'▲' if v >= 0 else '▼'} {_idn(abs(v), 1)}{' pp' if unit == 'pp' else '%'}", "tone": UP if v >= 0 else DOWN}


def _ch(cur: Optional[float], prev: Optional[float]) -> Optional[float]:
    if cur is None or not prev:
        return None
    return (cur / prev - 1) * 100


def region_name(r: str) -> str:
    return pf.title(r) if r else "Circle Java"


def kab_name(k: str) -> str:
    n = pf.norm(k)
    return "Kota " + pf.title(n[5:]) if n.startswith("KOTA ") else "Kab. " + pf.title(n)


def _stamp(created: Optional[str]) -> datetime:
    try:
        t = datetime.fromisoformat(str(created).replace("Z", "+00:00"))
        return (t if t.tzinfo else t.replace(tzinfo=timezone.utc)).astimezone(WIB)
    except (TypeError, ValueError):
        return datetime.now(WIB)


def _when(t: datetime, year: bool = True) -> str:
    return f"{t.day} {MONTHS_SHORT[t.month - 1]}{' ' + str(t.year) if year else ''} {t.hour:02d}.{t.minute:02d} WIB"


# ── Data ─────────────────────────────────────────────────────────────────────

def _overview(region: str) -> dict:
    from .dashboard import build_overview
    ov = reports_cache.get_or_build("dashboard", f"{region}|6", lambda: build_overview(region, 6))
    if not isinstance(ov, dict) or ov.get("error"):
        raise HTTPException(503, (ov or {}).get("error", "Data laporan belum tersedia"))
    return ov


class Perf:
    """Aggregates of the Performance dump for one month and the month before."""

    def __init__(self, month_id: Optional[int] = None):
        kec, site, avail, src = pf._data()
        self.src = src
        self.kec = kec
        months = sorted({int(r["month_id"]) for r in kec})
        self.latest = int(month_id) if month_id else (months[-1] if months else 0)
        self.prev = perf_dump.month_add(self.latest, -1) if self.latest else 0
        self.months = [m for m in months if m <= self.latest][-6:]
        self.kab_region = {pf.norm(r.get("kabupaten")): r.get("region") for r in kec if r.get("kabupaten")}
        self.sites = [s for s in site if int(s.get("month_id") or 0) == self.latest]
        self.sites_prev = {s["site_id"]: s for s in site if int(s.get("month_id") or 0) == self.prev}
        self.avail = avail

    def total(self, key: str, month: int, region: str = "", kabupaten: str = "", kecamatan: str = "") -> float:
        return sum(float(r.get(key) or 0) for r in self.kec if int(r["month_id"]) == month
                   and (not region or r.get("region") == region)
                   and (not kabupaten or pf.norm(r.get("kabupaten")) == pf.norm(kabupaten))
                   and (not kecamatan or r.get("kecamatan") == kecamatan))

    def site_rows(self, region: str = "", kabupaten: str = "") -> list[dict]:
        out = []
        for s in self.sites:
            k = pf.norm(s.get("kabupaten"))
            if kabupaten and k != pf.norm(kabupaten):
                continue
            if region and self.kab_region.get(k) != region:
                continue
            out.append(s)
        return out

    def kabupaten(self, region: str = "") -> list[dict]:
        keys = sorted({(pf.norm(r.get("kabupaten")), r.get("region")) for r in self.kec
                       if r.get("kabupaten") and (not region or r.get("region") == region)})
        rows = []
        for k, rg in keys:
            sites = self.site_rows(kabupaten=k)
            rows.append({
                "kab": k, "region": rg, "name": kab_name(k),
                "revenue": self.total("revenue", self.latest, kabupaten=k),
                "revenue_prev": self.total("revenue", self.prev, kabupaten=k),
                "payload": self.total("payload_gb", self.latest, kabupaten=k),
                "payload_prev": self.total("payload_gb", self.prev, kabupaten=k),
                "subs": self.total("subs", self.latest, kabupaten=k),
                "gross_add": self.total("gross_add", self.latest, kabupaten=k) or None,
                "sites": len(sites),
            })
        for r in rows:
            r["revenue_mom"] = _ch(r["revenue"], r["revenue_prev"])
            r["payload_mom"] = _ch(r["payload"], r["payload_prev"])
        return rows

    def attention(self, region: str = "", n: int = 3) -> list[dict]:
        """Kabupaten/kota that need attention: steepest payload drop first, then revenue drop."""
        rows = [r for r in self.kabupaten(region) if r["payload_mom"] is not None]
        big = [r for r in rows if r["sites"] >= 10] or rows
        return sorted(big, key=lambda r: (r["payload_mom"], r["revenue_mom"] or 0))[:n]

    def avail_of(self, level: str, name: str, month: int) -> Optional[float]:
        for a in self.avail:
            if a.get("level") == level and str(a.get("name") or "").upper() == name.upper() and int(a.get("month_id") or 0) == month:
                return a.get("avail")
        return None


# ── Section builders ─────────────────────────────────────────────────────────

def _cell(v: Optional[str], tone: Optional[str] = None, bar: Optional[dict] = None):
    if tone is None and bar is None:
        return v
    out: dict = {"v": v}
    if tone:
        out["tone"] = tone
    if bar:
        out["bar"] = bar
    return out


def _target_bar(ach: Optional[float]) -> Optional[dict]:
    if ach is None:
        return None
    color = "#0E8579" if ach >= 100 else "#22B8C9" if ach >= 95 else "#F5A623"
    return {"w": round(max(4.0, min(56.0, (ach - 30) * 0.7))), "c": color}


def _kpis(ov: dict) -> list[dict]:
    k = {x["key"]: x for x in ov.get("kpis", [])}
    out = []
    for key, label, f in (("revenue", "Revenue", rp), ("subs", "Pelanggan aktif", num), ("payload", "Payload", gb)):
        x = k.get(key)
        if not x:
            continue
        d = delta(x.get("pct_change"))
        if d and key == "revenue":
            d["v"] += " MoM"
        out.append({"label": label, "value": f(x.get("value")), "delta": d["v"] if d else None, "tone": d["tone"] if d else None})
    a = k.get("availability")
    if a:
        tgt = a.get("target") or 99.5
        ok = a.get("value") is not None and a["value"] >= tgt
        out.append({"label": "Availability", "value": pct(a.get("value"), 2), "delta": f"target {pct(tgt)}", "tone": UP if ok else DOWN})
    return out


def _summary(ov: dict, perf: Perf, region: str) -> str:
    regs = ov.get("regions") or []
    k = {x["key"]: x for x in ov.get("kpis", [])}
    rev = k.get("revenue", {})
    parts = []
    ch = rev.get("pct_change")
    if ch is not None:
        best = max((r for r in regs if r.get("mom_pct") is not None), key=lambda r: r["mom_pct"], default=None)
        lead = f", ditopang {region_name(best['region'])}" if best and not region and len(regs) > 1 and best["mom_pct"] > 0 else ""
        parts.append(f"Revenue **{'naik' if ch >= 0 else 'turun'} {_idn(abs(ch), 1)}% MoM** ke {rp(rev.get('value'))}{lead}.")
    warn = []
    att = perf.attention(region, 1)
    if att and att[0]["payload_mom"] is not None and att[0]["payload_mom"] < -5:
        nm = att[0]["name"].replace("Kab. ", "")
        warn.append(f"payload {nm} turun {_idn(abs(att[0]['payload_mom']), 1)}%")
    low = [r for r in regs if r.get("achievement_pct") is not None and r["achievement_pct"] < 95]
    if low:
        r = min(low, key=lambda r: r["achievement_pct"])
        warn.append(f"{region_name(r['region'])} di bawah target ({pct(r['achievement_pct'])})")
    if warn:
        parts.append("Perhatian: " + " dan ".join(warn) + ".")
    return " ".join(parts) or (ov.get("summary") or {}).get("text") or "Data bulan ini belum cukup untuk ringkasan."


def sec_summary(n: int, ov: dict, perf: Perf, region: str, title: str = "Ringkasan") -> dict:
    return {"n": n, "title": title, "type": "summary", "text": _summary(ov, perf, region), "kpis": _kpis(ov)}


def sec_regions(n: int, ov: dict, perf: Perf, title: str = "Performance per region") -> dict:
    has_t = bool(ov.get("has_targets"))
    rows = []
    for r in sorted(ov.get("regions") or [], key=lambda r: -(r.get("revenue") or 0)):
        rg = r["region"]
        pay, pay_prev = perf.total("payload_gb", perf.latest, region=rg), perf.total("payload_gb", perf.prev, region=rg)
        if not pay:
            pay, pay_prev = r.get("payload_gb"), None
        val = r.get("achievement_pct") if has_t else r.get("share_pct")
        rows.append([region_name(rg), rp(r.get("revenue")), delta(r.get("mom_pct")), gb(pay), delta(_ch(pay, pay_prev)),
                     _cell(pct(val), bar=_target_bar(val) if has_t else {"w": round((val or 0) * 0.5), "c": "#22B8C9"})])
    return {"n": n, "title": title, "sub": f"MoM terhadap {ov.get('prev_label', '')}".strip(), "type": "table",
            "cols": ["Region", "Revenue", "MoM", "Payload", "MoM", "Capaian target" if has_t else "Kontribusi"], "rows": rows}


def sec_productivity(n: int, ov: dict, perf: Perf, month_full: str) -> dict:
    rows, vals = [], []
    for r in ov.get("regions") or []:
        rg = r["region"]
        sites = perf.site_rows(region=rg)
        cnt = len(sites)
        rev = sum(float(s.get("revenue") or 0) for s in sites)
        per = rev / cnt if cnt and rev else None
        rgu = perf.total("subs", perf.latest, region=rg) / cnt if cnt else None
        vals.append(per or 0)
        rows.append((rg, per, rgu))
    top = max(vals) if vals and max(vals) > 0 else 0
    out = []
    for rg, per, rgu in sorted(rows, key=lambda x: -(x[1] or 0)):
        bar = {"w": round(per / top * 44), "c": "#22B8C9"} if per and top else None
        out.append([region_name(rg), _cell(rp(per), bar=bar), None, num(rgu), None])
    return {"n": n, "title": "Site productivity", "sub": f"point-in-time {month_full}, bukan akumulasi", "type": "table",
            "cols": ["Region", "Rev / base site", "Rev / new site", "RGU 90D / site", "VLR / site"], "rows": out,
            "note": "Rev per new site dan VLR per site belum ada di dump Parquet, jadi ditulis \"-\"."}


def sec_profile_rows(n: int, perf: Perf, region: str) -> dict:
    rows = []
    for r in perf.attention(region):
        rows.append([r["name"], None, num(r["subs"]), num(r["gross_add"]), num(r["sites"]), None])
    return {"n": n, "title": "Profile wilayah", "sub": "kabupaten/kota yang perlu perhatian", "type": "table",
            "cols": ["Kabupaten/kota", "Market share", "Pelanggan", "Gross add", "Site", "Penetrasi FWA"],
            "rows": rows,
            "note": "Profil lengkap tiap kabupaten (revenue, site, payload, kecamatan) bisa dibuka sebagai laporan Profile wilayah "
                    "tersendiri. Market share dan penetrasi FWA belum ada di dump Parquet."}


def sec_revenue_trend(n: int, ov: dict, title: str = "Revenue dan channel") -> dict:
    rb = ov.get("revenue_by_region") or {}
    labels, series = rb.get("labels") or [], rb.get("series") or []
    rows = []
    for i, lb in enumerate(labels):
        vals = [s["values"][i] if i < len(s["values"]) else None for s in series]
        tot = sum(v or 0 for v in vals)
        rows.append([lb, *[rp(v) for v in vals], rp(tot)])
    return {"n": n, "title": title, "sub": f"{len(labels)} bulan terakhir", "type": "table",
            "cols": ["Bulan", *[region_name(s["name"]) for s in series], "Total"], "rows": rows,
            "note": "Rincian per channel belum ada di dump Parquet."}


def sec_subs(n: int, ov: dict, perf: Perf) -> dict:
    rows = []
    for r in ov.get("regions") or []:
        rg = r["region"]
        cur, prev = perf.total("subs", perf.latest, region=rg) or r.get("subs"), perf.total("subs", perf.prev, region=rg)
        rows.append([region_name(rg), num(cur), delta(_ch(cur, prev)), num(perf.total("gross_add", perf.latest, region=rg) or r.get("gross_add") or None)])
    return {"n": n, "title": "Subscriber dan RGU", "sub": "RGU 90 hari", "type": "table",
            "cols": ["Region", "RGU 90D", "MoM", "Gross add"], "rows": rows}


def sec_network(n: int, ov: dict, perf: Perf, region: str = "") -> dict:
    rows = []
    for r in ov.get("regions") or []:
        rg = r["region"]
        sites = perf.site_rows(region=rg)
        crit = 0
        for s in sites:
            p = perf.sites_prev.get(s["site_id"])
            ch = _ch(s.get("payload_gb"), (p or {}).get("payload_gb"))
            if ch is not None and ch <= -10:
                crit += 1
        rows.append([region_name(rg), pct(r.get("availability"), 2), num(len(sites)), _cell(num(crit), DOWN if crit else None)])
    k = {x["key"]: x for x in ov.get("kpis", [])}
    a = k.get("availability") or {}
    note = f"Availability 4G {pct(a.get('value'), 2) or '-'} terhadap target {pct(a.get('target') or 99.5)}."
    if a.get("below_sla"):
        note += f" {a['below_sla']} site di bawah SLA 99%."
    return {"n": n, "title": "Network dan availability", "sub": "4G, rata-rata bulanan", "type": "table",
            "cols": ["Region", "Availability", "Site", "Site payload turun 10% atau lebih"], "rows": rows, "note": note}


def sec_market_share(n: int) -> dict:
    return {"n": n, "title": "Market share", "type": "note",
            "text": "Market share belum ada di dump Parquet. Bagian ini terisi otomatis setelah tabel market share disetujui di governance."}


def sec_notes(n: int, ov: dict, perf: Perf, region: str) -> dict:
    items = []
    for r in perf.attention(region):
        if r["payload_mom"] is not None and r["payload_mom"] < 0:
            items.append(f"{r['name']}: payload turun {_idn(abs(r['payload_mom']), 1)}% MoM, {r['sites']} site. Buka Peta Agent untuk melihat kecamatan yang turun.")
    for r in ov.get("regions") or []:
        if r.get("achievement_pct") is not None and r["achievement_pct"] < 95:
            items.append(f"{region_name(r['region'])} baru {pct(r['achievement_pct'])} dari target revenue.")
    if not items:
        items.append("Tidak ada wilayah yang turun tajam bulan ini.")
    return {"n": n, "title": "Catatan agent", "type": "list", "items": items}


# ── Documents ────────────────────────────────────────────────────────────────

def _month(ov: dict) -> tuple[int, str, str]:
    mid = int(ov["month_id"])
    return mid, f"{MONTHS_FULL[mid % 100 - 1]} {mid // 100}", f"{MONTHS_SHORT[mid % 100 - 1]} {mid // 100}"


def _source(ov: dict, perf: Perf) -> tuple[datetime, str]:
    src = ov.get("source") or {}
    created = src.get("created_at") or perf.src.get("created_at")
    kind = "dump Parquet" if (src.get("kind") == "dump" or perf.src.get("kind") in ("dump", "stale")) else "BigQuery langsung"
    return _stamp(created), kind


def _paginate(secs: dict[int, dict], pages: list[list[int]]) -> list[list[dict]]:
    return [[secs[i] for i in p if i in secs] for p in pages]


def outlook_doc(region: str = "") -> dict:
    ov = _overview(region)
    mid, full, short = _month(ov)
    perf = Perf(mid)
    t, src = _source(ov, perf)
    secs = {1: sec_summary(1, ov, perf, region), 2: sec_regions(2, ov, perf), 3: sec_revenue_trend(3, ov),
            4: sec_subs(4, ov, perf), 5: sec_productivity(5, ov, perf, full), 6: sec_network(6, ov, perf, region),
            7: sec_profile_rows(7, perf, region), 8: sec_market_share(8), 9: sec_notes(9, ov, perf, region)}
    pages = _paginate(secs, OUTLOOK_PAGES)
    scope = region_name(region)
    return {
        "kind": "outlook", "kind_label": "Analis", "title": f"Performance Outlook {scope}",
        "meta": f"Analis · {len(pages)} hlm · Agent Java, {_when(t, False)}",
        "eyebrow": f"Performance Outlook · {src}", "heading": f"{scope}, {full}",
        "byline": f"Disusun Agent Java · {_when(t)} · sumber {src}",
        "month_id": mid, "month_label": full, "month_short": short,
        "toc": [{"n": i + 1, "title": s} for i, s in enumerate(OUTLOOK_TOC)], "pages": pages,
    }


def bulanan_doc(region: str = "") -> dict:
    ov = _overview(region)
    mid, full, short = _month(ov)
    perf = Perf(mid)
    t, src = _source(ov, perf)
    scope = region_name(region)
    secs = {1: sec_summary(1, ov, perf, region)}
    if region:
        rows = []
        for r in sorted(perf.kabupaten(region), key=lambda r: -r["revenue"])[:12]:
            rows.append([r["name"], rp(r["revenue"]), delta(r["revenue_mom"]), gb(r["payload"]), delta(r["payload_mom"]), num(r["sites"])])
        secs[2] = {"n": 2, "title": "Performa per kabupaten/kota", "sub": f"MoM terhadap {ov.get('prev_label', '')}", "type": "table",
                   "cols": ["Kabupaten/kota", "Revenue", "MoM", "Payload", "MoM", "Site"], "rows": rows}
    else:
        secs[2] = sec_regions(2, ov, perf, "Performa per region")
    secs[3] = sec_revenue_trend(3, ov, "Tren revenue")
    secs[4] = sec_network(4, ov, perf, region)
    pages = _paginate(secs, [[1, 2], [3, 4]])
    return {
        "kind": "bulanan", "kind_label": "Bulanan", "title": f"Performa Bulanan {scope}",
        "meta": f"Bulanan · {len(pages)} hlm · Agent Java, {_when(t, False)}",
        "eyebrow": f"Laporan performa bulanan · {src}", "heading": f"{scope}, {full}",
        "byline": f"Disusun Agent Java · {_when(t)} · sumber {src}",
        "month_id": mid, "month_label": full, "month_short": short,
        "toc": [{"n": s["n"], "title": s["title"]} for p in pages for s in p], "pages": pages,
    }


def profile_doc(kabupaten: str) -> dict:
    perf = Perf()
    if not perf.latest:
        raise HTTPException(503, "Dump Performance belum tersedia")
    k = pf.norm(kabupaten)
    row = next((r for r in perf.kabupaten() if r["kab"] == k), None)
    if not row:
        raise HTTPException(404, f"Kabupaten/kota {kabupaten} tidak ditemukan di dump")
    mid = perf.latest
    full, short = f"{MONTHS_FULL[mid % 100 - 1]} {mid // 100}", f"{MONTHS_SHORT[mid % 100 - 1]} {mid // 100}"
    t = _stamp(perf.src.get("created_at"))
    src = "dump Parquet" if perf.src.get("kind") in ("dump", "stale") else "BigQuery langsung"
    sites = perf.site_rows(kabupaten=k)
    av = [s["avail"] for s in sites if s.get("avail") is not None]
    avail = sum(av) / len(av) if av else perf.avail_of("kabkot", k, mid)
    subs_prev = perf.total("subs", perf.prev, kabupaten=k)
    kpis = [
        {"label": "Revenue", "value": rp(row["revenue"]), **_dk(row["revenue_mom"], " MoM")},
        {"label": "Pelanggan", "value": num(row["subs"]), **_dk(_ch(row["subs"], subs_prev))},
        {"label": "Payload", "value": gb(row["payload"]), **_dk(row["payload_mom"])},
        {"label": "Site", "value": num(row["sites"]), "delta": f"availability {pct(avail, 2)}" if avail is not None else None,
         "tone": (UP if avail >= 99 else DOWN) if avail is not None else None},
    ]
    text = (f"Revenue **{'naik' if (row['revenue_mom'] or 0) >= 0 else 'turun'} {_idn(abs(row['revenue_mom'] or 0), 1)}% MoM** "
            f"ke {rp(row['revenue'])}, payload {'naik' if (row['payload_mom'] or 0) >= 0 else 'turun'} "
            f"{_idn(abs(row['payload_mom'] or 0), 1)}% dari {row['sites']} site.")
    kecs = sorted({r.get("kecamatan") for r in perf.kec if pf.norm(r.get("kabupaten")) == k and r.get("kecamatan")})
    krows = []
    for kc in kecs:
        rev, rev_p = perf.total("revenue", mid, kabupaten=k, kecamatan=kc), perf.total("revenue", perf.prev, kabupaten=k, kecamatan=kc)
        pay, pay_p = perf.total("payload_gb", mid, kabupaten=k, kecamatan=kc), perf.total("payload_gb", perf.prev, kabupaten=k, kecamatan=kc)
        n_sites = sum(1 for s in sites if s.get("kecamatan") == kc)
        krows.append((rev, [pf.title(kc), rp(rev), delta(_ch(rev, rev_p)), gb(pay), delta(_ch(pay, pay_p)),
                            num(perf.total("subs", mid, kabupaten=k, kecamatan=kc)), num(n_sites)]))
    srows = []
    for s in sites:
        p = perf.sites_prev.get(s["site_id"]) or {}
        srows.append((_ch(s.get("payload_gb"), p.get("payload_gb")), s))
    srows.sort(key=lambda x: (x[0] is None, x[0] or 0))
    trend = [[f"{MONTHS_SHORT[m % 100 - 1]} {m // 100}", rp(perf.total("revenue", m, kabupaten=k)),
              gb(perf.total("payload_gb", m, kabupaten=k)), num(perf.total("subs", m, kabupaten=k))] for m in perf.months]
    secs = {
        1: {"n": 1, "title": "Ringkasan", "type": "summary", "text": text, "kpis": kpis},
        2: {"n": 2, "title": "Kecamatan", "sub": f"{len(kecs)} kecamatan, urut revenue", "type": "table",
            "cols": ["Kecamatan", "Revenue", "MoM", "Payload", "MoM", "Pelanggan", "Site"],
            "rows": [r for _, r in sorted(krows, key=lambda x: -x[0])]},
        3: {"n": 3, "title": "Site dengan payload turun terdalam", "sub": f"dari {len(sites)} site", "type": "table",
            "cols": ["Site", "Kecamatan", "Payload", "MoM", "Availability"],
            "rows": [[f"{s['site_id']} {s.get('site_name') or ''}".strip(), pf.title(s.get("kecamatan")), gb(s.get("payload_gb")),
                      delta(ch), pct(s.get("avail"), 2)] for ch, s in srows[:10]]},
        4: {"n": 4, "title": "Tren 6 bulan", "type": "table", "cols": ["Bulan", "Revenue", "Payload", "Pelanggan"], "rows": trend},
        5: {"n": 5, "title": "Data yang belum tersedia", "type": "note",
            "text": "Market share, channel, slab, produk, FWA, FTTH dan 5G per kabupaten belum ada di dump Parquet. "
                    "Bagian ini terisi otomatis setelah tabelnya disetujui di governance."},
    }
    pages = _paginate(secs, [[1, 2], [3], [4, 5]])
    name = row["name"]
    return {
        "kind": "profile", "kind_label": "Profile wilayah", "title": f"Profile {name}",
        "meta": f"Profile wilayah · {len(pages)} hlm · Agent Java, {_when(t, False)}",
        "eyebrow": f"Profile wilayah · {src}", "heading": f"{name}, {full}",
        "byline": f"Disusun Agent Java · {_when(t)} · sumber {src}",
        "month_id": mid, "month_label": full, "month_short": short, "kabupaten": k, "sites": len(sites),
        "toc": [{"n": s["n"], "title": s["title"]} for p in pages for s in p], "pages": pages,
    }


def _dk(v: Optional[float], suffix: str = "") -> dict:
    d = delta(v)
    return {"delta": (d["v"] + suffix) if d else None, "tone": d["tone"] if d else None}


def library(region: str = "") -> dict:
    """Generated items for the library list. The client adds sent runs and pinned agent answers."""
    ov = _overview(region)
    mid, full, short = _month(ov)
    perf = Perf(mid)
    regs = [r["region"] for r in ov.get("regions") or []]
    worst = min((r for r in ov.get("regions") or [] if r.get("mom_pct") is not None), key=lambda r: r["mom_pct"], default=None)
    order = ([worst["region"]] if worst else []) + [r for r in regs if not worst or r != worst["region"]]
    items = [{"id": "doc:outlook:", "kind": "analis", "title": "Performance Outlook Circle Java",
              "meta": f"{len(OUTLOOK_TOC)} bagian · termasuk Site productivity", "doc": {"kind": "outlook", "region": ""}}]
    bul = [{"id": f"doc:bulanan:{r}", "kind": "bulanan", "title": f"Performa Bulanan {region_name(r)}",
            "meta": f"PDF 2 hlm · {short}", "doc": {"kind": "bulanan", "region": r}} for r in order]
    bul.append({"id": "doc:bulanan:", "kind": "bulanan", "title": "Performa Bulanan Circle Java", "meta": f"PDF 2 hlm · {short}",
                "doc": {"kind": "bulanan", "region": ""}})
    att = perf.attention()
    prof = [{"id": f"doc:profile:{r['kab']}", "kind": "profile", "title": f"Profile {r['name']}",
             "meta": "5 bagian · revenue, site, payload, kecamatan", "doc": {"kind": "profile", "kabupaten": r["kab"]}} for r in att]
    site = [{"id": f"perf:{r['kab']}", "kind": "performance", "title": f"Site Performance {r['name']}",
             "meta": f"{num(r['sites'])} site · dari dump Parquet", "href": f"/performance?kabupaten={r['kab']}",
             "kabupaten": r["kab"]} for r in att[:1]]
    # Order on screen: outlook, worst region, first attention kabupaten (profile + site), then the rest.
    lead = items + bul[:1] + prof[:1] + site
    rest = bul[1:] + prof[1:]
    return {"month_id": mid, "month_label": full, "month_short": short, "lead": lead, "rest": rest}


@router.get("/library")
def library_endpoint(user: User = Depends(get_current_user)):
    return library()


@router.get("/doc")
def doc_endpoint(kind: str = Query("outlook", pattern="^(outlook|bulanan|profile)$"), region: str = Query("", max_length=60),
                 kabupaten: str = Query("", max_length=80), user: User = Depends(get_current_user)):
    if kind == "profile":
        if not kabupaten:
            raise HTTPException(422, "kabupaten wajib untuk Profile wilayah")
        return profile_doc(kabupaten)
    region = region.strip().upper()
    return outlook_doc(region) if kind == "outlook" else bulanan_doc(region)
