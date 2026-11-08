"""Synthetic Performance dump for the v3 feature tests (no BigQuery, no disk).

Latest dumped day is Wed 4 Nov 2026. West Java falls, mostly in Garut (Cikajang first)
and Cianjur, through fewer subscribers; East Java grows. The tables have the same columns
as the real dump (perf_dump.py).
"""
from datetime import date, timedelta

from app import perf_dump

LAST = date(2026, 11, 4)

AREAS = [  # region, kabupaten, provinsi, kecamatan, kec_id, base revenue per day (IDR), trend per month
    ("WEST JAVA", "GARUT", "JAWA BARAT", "CIKAJANG", 1, 60e6, -0.14),
    ("WEST JAVA", "GARUT", "JAWA BARAT", "PAMEUNGPEUK", 2, 50e6, -0.12),
    ("WEST JAVA", "GARUT", "JAWA BARAT", "BUNGBULANG", 3, 40e6, -0.10),
    ("WEST JAVA", "GARUT", "JAWA BARAT", "TAROGONG KIDUL", 4, 80e6, 0.0),
    ("WEST JAVA", "CIANJUR", "JAWA BARAT", "CIBEBER", 5, 70e6, -0.12),
    ("WEST JAVA", "BANDUNG", "JAWA BARAT", "CICALENGKA", 6, 120e6, 0.01),
    ("WEST JAVA", "SUKABUMI", "JAWA BARAT", "CIBADAK", 7, 65e6, -0.06),
    ("CENTRAL JAVA", "SEMARANG", "JAWA TENGAH", "TEMBALANG", 8, 140e6, 0.02),
    ("CENTRAL JAVA", "KOTA PEKALONGAN", "JAWA TENGAH", "PEKALONGAN UTARA", 9, 20e6, 0.06),
    ("EAST JAVA", "MALANG", "JAWA TIMUR", "LAWANG", 10, 150e6, 0.04),
    ("EAST JAVA", "SIDOARJO", "JAWA TIMUR", "WARU", 11, 130e6, 0.035),
    ("EAST JAVA", "SURABAYA", "JAWA TIMUR", "GUBENG", 12, 210e6, 0.02),
]
DOW = [1.0, 0.98, 0.99, 1.0, 1.04, 1.08, 1.06]  # Mon..Sun


def _level(base: float, trend: float, d: date) -> float:
    months = (d.year - LAST.year) * 12 + (d.month - LAST.month) + (d.day - LAST.day) / 30
    return base * (1 + trend) ** months


def _kec_daily(start: date, end: date):
    d = start
    while d <= end:
        for reg, kab, prov, kec, kid, base, tr in AREAS:
            rev = _level(base, tr, d) * DOW[d.weekday()]
            subs = _level(base, tr, d) / 2000 * 1.0  # stock: ARPU ~ 2000 per day per RGU
            yield {"dt_id": d, "region": reg, "kabupaten": kab, "provinsi": prov, "kecamatan": kec, "kec_id": kid,
                   "revenue": rev, "payload_gb": rev / 1.2e5, "subs": subs, "gross_add": rev / 4e5, "fwa_gross_add": rev / 4e6}
        d += timedelta(days=1)


def tables() -> dict:
    start = LAST - timedelta(days=69)
    kd = list(_kec_daily(start, LAST))
    kab: dict = {}
    reg: dict = {}
    for r in kd:
        k = (r["dt_id"], r["region"], r["kabupaten"])
        a = kab.setdefault(k, {"dt_id": r["dt_id"], "region": r["region"], "kabupaten": r["kabupaten"],
                               "revenue": 0.0, "payload_gb": 0.0, "subs": 0.0, "gross_add": 0.0, "fwa_gross_add": 0.0})
        b = reg.setdefault((r["dt_id"], r["region"]), {"dt_id": r["dt_id"], "region": r["region"],
                                                        "revenue": 0.0, "payload_gb": 0.0, "subs": 0.0, "gross_add": 0.0})
        for c in ("revenue", "payload_gb", "subs", "gross_add"):
            a[c] += r[c]
            b[c] += r[c]
        a["fwa_gross_add"] += r["fwa_gross_add"]
    # kec_mtd: MTD 1-4 Nov and LMTD 1-4 Okt, subs at the last day of each window
    kec_mtd: dict = {}
    for r in kd:
        d = r["dt_id"]
        if date(2026, 11, 1) <= d <= LAST:
            per, lastd = "mtd", LAST
        elif date(2026, 10, 1) <= d <= date(2026, 10, 4):
            per, lastd = "lmtd", date(2026, 10, 4)
        else:
            continue
        a = kec_mtd.setdefault((r["kec_id"], per), {"kec_id": r["kec_id"], "region": r["region"], "kabupaten": r["kabupaten"],
                                                     "kecamatan": r["kecamatan"], "period": per, "revenue": 0.0, "payload_gb": 0.0,
                                                     "gross_add": 0.0, "subs": 0.0})
        a["revenue"] += r["revenue"]
        a["payload_gb"] += r["payload_gb"]
        a["gross_add"] += r["gross_add"]
        if d == lastd:
            a["subs"] += r["subs"]
    # kec_month: 25 months up to Nov 2026 (Nov is MTD)
    kec_month = []
    m = perf_dump.month_add(202611, -24)
    while m <= 202611:
        y, mo = divmod(m, 100)
        first = date(y, mo, 1)
        nxt = date(y + (mo == 12), mo % 12 + 1, 1)
        end = min(LAST, nxt - timedelta(days=1))
        ndays = (end - first).days + 1
        mid = first + timedelta(days=ndays // 2)
        for reg_, kab_, prov, kec, kid, base, tr in AREAS:
            lvl = _level(base, tr, mid)
            kec_month.append({"month_id": m, "kec_id": kid, "region": reg_, "kabupaten": kab_, "provinsi": prov, "kecamatan": kec,
                              "revenue": lvl * ndays, "payload_gb": lvl * ndays / 1.2e5, "subs": _level(base, tr, end) / 2000,
                              "gross_add": lvl * ndays / 4e5})
        m = perf_dump.month_add(m, 1)
    # sites: six in Cikajang (all falling), two in Pameungpeuk, one in Malang
    site_month = []
    sites = [("CKJ-%03d" % n, "CIKAJANG", "GARUT", "JAWA BARAT", 0.4 + n / 100) for n in (12, 7, 21, 3, 15, 9)]
    sites += [("PMP-001", "PAMEUNGPEUK", "GARUT", "JAWA BARAT", 0.5), ("PMP-002", "PAMEUNGPEUK", "GARUT", "JAWA BARAT", 0.3),
              ("MLG-001", "LAWANG", "MALANG", "JAWA TIMUR", 0.8)]
    for i, (sid, kec, kab_, prov, base) in enumerate(sites):
        for mm, fac in ((202611, 0.15), (202610, 1.0), (202609, 1.0 + 0.04 + i * 0.01), (202608, 1.06), (202510, 1.1)):
            site_month.append({"site_id": sid, "month_id": mm, "site_name": sid, "kecamatan": kec, "kabupaten": "KAB. " + kab_,
                               "provinsi": prov, "lat": -7.3 + i / 50, "lon": 107.7 + i / 50 if i != 8 else None,
                               "payload_gb": base * 1e4 * fac, "revenue": base * 1e9 * fac, "avail": 99.6 + i * 0.05})
    avail = []
    for mm in (202609, 202610, 202611):
        avail.append({"level": "circle", "name": "JAVA", "month_id": mm, "avail": 99.6, "below_sla": 40})
        for r_ in ("WEST JAVA", "CENTRAL JAVA", "EAST JAVA"):
            avail.append({"level": "region", "name": r_, "month_id": mm, "avail": 99.5, "below_sla": 10})
        for k_ in {a[1] for a in AREAS}:
            avail.append({"level": "kabkot", "name": k_, "month_id": mm, "avail": 99.9 if k_ == "MALANG" else 99.6, "below_sla": 1})
    return {"kab_daily": list(kab.values()), "region_daily": list(reg.values()), "kec_mtd": list(kec_mtd.values()),
            "kec_month": kec_month, "site_month": site_month, "avail_month": avail}


SOURCE = {"kind": "dump", "label": "Dump Performance 5 Nov 05.00", "label_wib": "Dump Performance 5 Nov 05.00 WIB",
          "short": "Dump 5 Nov", "created_at": "2026-11-04T22:00:00+00:00"}

TARGETS = {"revenue": {"EAST JAVA": 15.5e9, "CENTRAL JAVA": 5.0e9, "WEST JAVA": 15.0e9},
           "fwa_gross_add": {"CENTRAL JAVA": 5000}}


def patch(monkeypatch, *modules):
    t = tables()

    def fake(*names):
        return {n: t.get(n, []) for n in names}, dict(SOURCE)
    for m in modules:
        monkeypatch.setattr(m, "tables", fake)
        if hasattr(m, "load_targets"):
            monkeypatch.setattr(m, "load_targets", lambda: TARGETS)
    return t
