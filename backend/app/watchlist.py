"""Watchlist & Alert API.

A rule watches one metric at one territory and fires when its condition holds
for `days` consecutive daily checks:

    turun / naik / berubah   month-to-date change vs last month, in percent
                             (percentage points for availability)
    di_bawah / di_atas       the metric level itself (e.g. availability < 99%)

Rules are checked at most once per WIB day each, by the background loop in
main.py and whenever the user opens the Watchlist page. A firing rule writes a
WatchAlert plus an in-app Notification (which the Android app also shows) and,
when enabled, an email. When a breached rule returns to normal a "pulih" alert
closes the episode.
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from . import config, email_service
from .auth import get_current_user
from .bigquery_tool import run_query
from .database import Notification, SessionLocal, User, WatchAlert, WatchRule, WatchSample, get_db, utcnow

log = logging.getLogger("watchlist")
router = APIRouter(prefix="/api/watchlist", tags=["watchlist"])

_P, _D = config.BQ_PROJECT, config.BQ_DATASET
_MTD = f"`{_P}.{_D}.rham_mkt_highlevel_mtd`"
_TERR = f"`{_P}.{_D}.rham_ref_territory`"
_AVAIL = f"`{_P}.{_D}.rham_avail_stat_territory_monthly`"

# Metrics a rule can watch. `expr` sums over rham_mkt_highlevel_mtd (alias x).
METRICS: dict[str, dict] = {
    # Performance
    "payload": {"label": "Payload data", "short": "Payload", "expr": "x.usg_data_gb", "unit": "GB", "icon": "activity", "micon": "db", "group": "perf"},
    "revenue": {"label": "Revenue", "short": "Revenue", "expr": "x.rev_prepaid", "unit": "IDR", "icon": "trending-up", "micon": "wallet", "group": "perf"},
    "rev_data": {"label": "Revenue data", "short": "Revenue data", "expr": "x.rev_data", "unit": "IDR", "icon": "trending-up", "micon": "wallet", "group": "perf"},
    "availability": {"label": "Site availability 4G", "short": "Availability", "expr": None, "unit": "%", "icon": "radio", "micon": "tower", "group": "perf", "period": "harian"},
    "gross_add": {"label": "Gross add", "short": "Gross add", "expr": "x.gross_add", "unit": "Subs", "icon": "users", "micon": "users", "group": "perf"},
    "fwa_rgu": {"label": "FWA RGU 90D", "short": "FWA RGU 90D", "expr": "x.fwa_rgu90", "unit": "Subs", "icon": "wifi", "micon": "users", "group": "perf"},
    "fwa_revenue": {"label": "Revenue FWA", "short": "Revenue FWA", "expr": "x.rev_fwa_total", "unit": "IDR", "icon": "wifi", "micon": "wallet", "group": "perf"},
    # Site productivity (from the Performance dump: revenue and RGU over sites with traffic)
    "rev_site": {"label": "Revenue per site", "short": "Revenue / site", "expr": None, "unit": "IDR", "icon": "radio", "micon": "tower", "group": "prod", "source": "dump"},
    "rgu_site": {"label": "RGU 90D per site", "short": "RGU 90D / site", "expr": None, "unit": "Subs", "icon": "users", "micon": "users", "group": "prod", "source": "dump"},
    "vlr_site": {"label": "VLR per site", "short": "VLR / site", "expr": None, "unit": "Subs", "icon": "activity", "micon": "pulse", "group": "prod", "available": False},
    # Profile wilayah
    "subs": {"label": "Pelanggan aktif (RGU 90D)", "short": "Pelanggan aktif", "expr": "x.rgu_90d", "unit": "Subs", "icon": "users", "micon": "users", "group": "prof"},
    "net_churn": {"label": "Net churn 90D", "short": "Net churn 90D", "expr": "x.net_churn_90d", "unit": "Subs", "icon": "users", "micon": "users", "group": "prof"},
    "market_share": {"label": "Market share", "short": "Market share", "expr": None, "unit": "%", "icon": "users", "micon": "pin", "group": "prof", "pp": True, "available": False},
    "fwa_pen": {"label": "Penetrasi FWA", "short": "Penetrasi FWA", "expr": None, "unit": "%", "icon": "wifi", "micon": "wallet", "group": "prof", "pp": True, "available": False},
}
GROUPS = {"perf": "Performance", "prod": "Site productivity", "prof": "Profile wilayah"}
REGION_NAME = {"WEST JAVA": "West Java", "CENTRAL JAVA": "Central Java", "EAST JAVA": "East Java", "JAWA BARAT": "West Java",
               "JAWA TENGAH & DIY": "Central Java", "JAWA TENGAH": "Central Java", "JAWA TIMUR": "East Java", "JAVA": "Circle Java"}

_SCOPE_COL = {"circle": "t.circle", "region": "t.region", "kabkota": "t.kabkot", "branch": "t.branch_im3"}
_AVAIL_LEVEL = {"circle": "circle", "region": "region", "kabkota": "kabkot", "branch": "branch"}
CONDITIONS = ("turun", "naik", "berubah", "di_bawah", "di_atas")


def _esc(v: str) -> str:
    return (v or "").replace("'", "").replace("\\", "")


def _today_wib() -> str:
    return (datetime.now(timezone.utc) + timedelta(hours=7)).date().isoformat()


def _month_add(mid: int, n: int) -> int:
    y, m = divmod(mid, 100)
    k = y * 12 + (m - 1) + n
    return (k // 12) * 100 + (k % 12) + 1


def available(metric: str) -> bool:
    return METRICS[metric].get("available", True)


def _dump_history(metric: str, level: str, value: str) -> list[tuple[int, Optional[float]]]:
    """Site productivity from the Performance dump: [(prev month, v), (latest month, v)]."""
    from . import performance as pf
    kec, site, _avail, _src = pf._data()
    if not site:
        return []
    kab_region = {pf.norm(r.get("kabupaten")): str(r.get("region") or "").upper() for r in kec if r.get("kabupaten")}
    want = pf.norm(value)

    def inside(kab: Optional[str], region: Optional[str] = None) -> bool:
        k = pf.norm(kab)
        if level == "kabkota":
            return k == want
        if level == "region":
            return (region or kab_region.get(k, "")).upper() == value.upper()
        return True

    months = sorted({int(s["month_id"]) for s in site})[-2:]
    out = []
    for mid in months:
        rows = [s for s in site if int(s["month_id"]) == mid and inside(s.get("kabupaten"))]
        n = len(rows)
        if not n:
            out.append((mid, None))
            continue
        if metric == "rev_site":
            out.append((mid, sum(float(s.get("revenue") or 0) for s in rows) / n))
        else:
            subs = sum(float(r.get("subs") or 0) for r in kec if int(r["month_id"]) == mid and inside(r.get("kabupaten"), r.get("region")))
            out.append((mid, subs / n if subs else None))
    return out


def metric_history(metric: str, level: str, value: str, months: int = 13) -> list[tuple[int, Optional[float]]]:
    """[(month_id, level)] oldest → newest for a metric at a territory."""
    m = METRICS[metric]
    if not available(metric):
        return []
    if m.get("source") == "dump":
        return _dump_history(metric, level, value)
    if metric == "availability":
        rows = run_query(f"""
SELECT CAST(month_id AS INT64) AS month_id, AVG(mean_avg_avail_pct_4g) AS v
FROM {_AVAIL}
WHERE territory_level = '{_AVAIL_LEVEL.get(level, level)}' AND UPPER(territory_name) = UPPER('{_esc(value)}')
GROUP BY month_id ORDER BY month_id DESC LIMIT {months}
""", row_limit=months)["rows"]
    else:
        col = _SCOPE_COL[level]
        where = f"UPPER({col}) = UPPER('{_esc(value)}')"
        if level == "kabkota":
            # "KAB. GARUT", "KABUPATEN GARUT" and "GARUT" are the same kabupaten
            from .performance import norm
            where = f"REGEXP_REPLACE(UPPER({col}), r'^(KABUPATEN|KAB\\.?)\\s+', '') = '{_esc(norm(value))}'"
        rows = run_query(f"""
SELECT x.month_id AS month_id, SUM({m['expr']}) AS v
FROM {_MTD} x
LEFT JOIN {_TERR} t ON x.kec_id = t.kec_id
WHERE {where}
GROUP BY month_id ORDER BY month_id DESC LIMIT {months}
""", row_limit=months)["rows"]
    return [(int(r["month_id"]), float(r["v"]) if r.get("v") is not None else None) for r in reversed(rows)]


def observed(rule_metric: str, condition: str, hist: list[tuple[int, Optional[float]]]) -> tuple[Optional[float], Optional[float]]:
    """(value compared with the threshold, current level) from a monthly history."""
    if not hist:
        return None, None
    cur = hist[-1][1]
    if condition in ("di_bawah", "di_atas"):
        return cur, cur
    prev = hist[-2][1] if len(hist) >= 2 else None
    if cur is None or prev in (None, 0):
        return None, cur
    if rule_metric == "availability" or METRICS[rule_metric].get("pp"):
        return cur - prev, cur          # percentage points
    return (cur - prev) / abs(prev) * 100, cur


def breached(condition: str, threshold: float, v: Optional[float]) -> bool:
    if v is None:
        return False
    t = abs(threshold)
    return {
        "turun": v <= -t, "naik": v >= t, "berubah": abs(v) >= t,
        "di_bawah": v < threshold, "di_atas": v > threshold,
    }[condition]


def severity(condition: str, threshold: float, v: float) -> str:
    """Twice past the threshold (or 1 point past an absolute floor) is critical."""
    if condition in ("di_bawah", "di_atas"):
        return "kritis" if abs(v - threshold) >= 1 else "peringatan"
    return "kritis" if abs(v) >= 1.5 * abs(threshold) else "peringatan"


def _pp(metric: str) -> bool:
    return metric == "availability" or bool(METRICS[metric].get("pp"))


def fmt_level(metric: str, v: Optional[float]) -> str:
    """A metric level as the mockup writes it: 99,31% / Rp 71 jt / 1,9 rb / 84,2 PB."""
    if v is None:
        return "–"
    unit = METRICS[metric]["unit"]
    if unit == "%":
        return f"{v:.2f}".replace(".", ",") + "%" if metric == "availability" else f"{v:.1f}".replace(".", ",") + "%"
    if unit == "GB":
        a = abs(v)
        return (f"{v / 1e6:.1f} PB" if a >= 1e6 else f"{v / 1e3:.1f} TB" if a >= 1e3 else f"{v:.0f} GB").replace(".", ",")
    return _short(v, unit)


def fmt_value(metric: str, condition: str, v: Optional[float]) -> str:
    if v is None:
        return "–"
    if condition in ("di_bawah", "di_atas"):
        return fmt_level(metric, v)
    unit = " pp" if _pp(metric) else "%"
    sign = "+" if v > 0 else "−" if v < 0 else ""
    return f"{sign}{abs(v):.1f}".replace(".", ",") + unit


def _num(t: float) -> str:
    return f"{t:g}".replace(".", ",")


def fmt_threshold(rule: WatchRule) -> str:
    t = rule.threshold
    if rule.condition in ("di_bawah", "di_atas"):
        op = "<" if rule.condition == "di_bawah" else ">"
        if METRICS[rule.metric]["unit"] == "%":
            return f"{op} {t:.1f}".replace(".", ",") + "%"
        return f"{op} {fmt_level(rule.metric, t)}"
    if _pp(rule.metric):
        return {"turun": f"turun > {_num(abs(t))} pp", "naik": f"naik > {_num(abs(t))} pp", "berubah": f"berubah > {_num(abs(t))} pp"}[rule.condition]
    return {"turun": f"< −{_num(abs(t))}%", "naik": f"> +{_num(abs(t))}%", "berubah": f"± {_num(abs(t))}%"}[rule.condition]


def fmt_period(rule: WatchRule) -> str:
    """Second line under the threshold: how long, or how often it is checked."""
    d = rule.days or 1
    if d > 1:
        return f"selama {d // 30} bulan" if d % 30 == 0 else f"selama {d} hari"
    return METRICS[rule.metric].get("period", "bulanan")


def near(rule: WatchRule, v: Optional[float]) -> bool:
    """Not breached yet but within reach of the threshold (the "Mendekati ambang" tile)."""
    if v is None or breached(rule.condition, rule.threshold, v):
        return False
    t = rule.threshold
    if rule.condition == "turun":
        return v <= -0.75 * abs(t)
    if rule.condition == "naik":
        return v >= 0.75 * abs(t)
    if rule.condition == "berubah":
        return abs(v) >= 0.75 * abs(t)
    margin = 0.25 if METRICS[rule.metric]["unit"] == "%" else 0.06 * abs(t)
    return v < t + margin if rule.condition == "di_bawah" else v > t - margin


def _short(v: float, unit: str) -> str:
    a = abs(v)
    if unit == "IDR":
        if a < 1e6:
            return "Rp " + f"{v:,.0f}".replace(",", ".")
        body = f"{v / 1e12:.2f} T" if a >= 1e12 else f"{v / 1e9:.1f} M" if a >= 1e9 else f"{v / 1e6:.0f} jt"
        return "Rp " + body.replace(".", ",")
    body = (f"{v / 1e6:.1f} jt" if a >= 1e7 else f"{v / 1e6:.2f} jt" if a >= 1e6 else f"{v / 1e3:.0f} rb" if a >= 1e5
            else f"{v / 1e3:.1f} rb" if a >= 1e3 else f"{v:,.0f}")
    return body.replace(".", ",")


def region_name(v: str) -> str:
    return REGION_NAME.get((v or "").upper(), (v or "").title())


def kab_name(v: str) -> str:
    from .performance import norm, title
    n = norm(v)
    return "Kota " + title(n[5:]) if n.startswith("KOTA ") else "Kab. " + title(n)


def _kab_region(v: str) -> Optional[str]:
    try:
        from . import performance as pf
        kec = pf._data()[0]
    except Exception:
        return None
    want = pf.norm(v)
    return next((region_name(r.get("region")) for r in kec if pf.norm(r.get("kabupaten")) == want and r.get("region")), None)


def scope_label(rule: WatchRule, with_region: bool = False) -> str:
    v = rule.scope_value or ""
    if rule.scope_level == "kabkota":
        name = kab_name(v)
        reg = _kab_region(v) if with_region else None
        return f"{name}, {reg}" if reg else name
    if rule.scope_level == "branch":
        return f"Branch {v.title()}"
    return region_name(v) if rule.scope_level in ("region", "circle") else v.title()


# ── Evaluation ─────────────────────────────────────────────────────────────

def evaluate_rule(db: Session, rule: WatchRule, force: bool = False) -> Optional[WatchAlert]:
    """Check one rule (once per WIB day unless forced). Returns a new alert, if any."""
    today = _today_wib()
    if rule.last_checked_on == today and not force:
        return None
    if not available(rule.metric):
        # Watched as soon as the table is governed; until then the page says "Belum ada data".
        rule.status, rule.last_checked_on = "nodata", today
        db.commit()
        return None
    try:
        hist = metric_history(rule.metric, rule.scope_level, rule.scope_value, months=3)
    except Exception as e:
        log.warning(f"watch rule {rule.id} query failed: {e}")
        rule.status = "error"
        rule.last_checked_on = today
        db.commit()
        return None
    v, level = observed(rule.metric, rule.condition, hist)
    rule.last_value, rule.last_level = v, level
    new_day = rule.last_checked_on != today
    rule.last_checked_on = today

    sample = db.query(WatchSample).filter(WatchSample.rule_id == rule.id, WatchSample.day == today).first()
    if sample:
        sample.value = v
    else:
        db.add(WatchSample(rule_id=rule.id, day=today, value=v))

    alert = None
    was_breached = rule.status in ("peringatan", "kritis")
    if breached(rule.condition, rule.threshold, v):
        if new_day:
            rule.breach_streak = (rule.breach_streak or 0) + 1
        if rule.breach_streak >= max(1, rule.days):
            sev = severity(rule.condition, rule.threshold, v)
            open_alert = (db.query(WatchAlert)
                          .filter(WatchAlert.rule_id == rule.id, WatchAlert.resolved_at.is_(None),
                                  WatchAlert.severity != "pulih")
                          .first())
            if not open_alert or (sev == "kritis" and open_alert.severity != "kritis"):
                label = METRICS[rule.metric]["short"]
                verb = {"turun": "turun", "naik": "naik", "berubah": "berubah",
                        "di_bawah": "di bawah ambang", "di_atas": "di atas ambang"}[rule.condition]
                title = f"{label} {scope_label(rule).replace('Kab. ', '')} {verb} {fmt_value(rule.metric, rule.condition, v).lstrip('+−')}"
                days_txt = f" selama {rule.breach_streak} hari" if rule.breach_streak > 1 else ""
                msg = f"Ambang {fmt_threshold(rule)}{days_txt}. Nilai saat ini {fmt_value(rule.metric, rule.condition, v)}."
                alert = WatchAlert(rule_id=rule.id, user_id=rule.user_id, severity=sev, title=title, message=msg, value=v)
                db.add(alert)
                if open_alert:
                    open_alert.resolved_at = utcnow()
            rule.status = sev
    else:
        rule.breach_streak = 0
        if was_breached:
            db.query(WatchAlert).filter(WatchAlert.rule_id == rule.id, WatchAlert.resolved_at.is_(None)).update(
                {WatchAlert.resolved_at: utcnow()})
            alert = WatchAlert(rule_id=rule.id, user_id=rule.user_id, severity="pulih",
                               title=f"Pulih: {METRICS[rule.metric]['short']} {scope_label(rule).replace('Kab. ', '')}",
                               message=f"Kembali normal di {fmt_value(rule.metric, rule.condition, v)}.",
                               value=v, resolved_at=utcnow())
            db.add(alert)
        rule.status = "normal" if v is not None else "error"
    db.commit()

    if alert is not None:
        _notify(db, rule, alert)
    return alert


def _notify(db: Session, rule: WatchRule, alert: WatchAlert) -> None:
    if rule.notify_inapp:
        db.add(Notification(user_id=rule.user_id, title=alert.title, message=alert.message,
                            kind="success" if alert.severity == "pulih" else "alert"))
        db.commit()
    if rule.notify_email and alert.severity != "pulih":
        user = db.get(User, rule.user_id)
        if user and user.email:
            try:
                email_service.send_notification(user.email, f"[Alert] {alert.title}", alert.message)
            except Exception as e:
                log.warning(f"alert email failed: {e}")


def evaluate_all(user_id: Optional[int] = None) -> int:
    """Check every active rule (optionally one user's). Returns alerts created."""
    db = SessionLocal()
    made = 0
    try:
        q = db.query(WatchRule).filter(WatchRule.active.is_(True))
        if user_id is not None:
            q = q.filter(WatchRule.user_id == user_id)
        for rule in q.all():
            if evaluate_rule(db, rule) is not None:
                made += 1
    finally:
        db.close()
    return made


# ── API ────────────────────────────────────────────────────────────────────

class RuleIn(BaseModel):
    name: Optional[str] = Field(None, max_length=160)
    metric: str
    scope_level: str = "circle"
    scope_value: str = "JAVA"
    condition: str = "turun"
    threshold: float = 5.0
    days: int = Field(1, ge=1, le=90)
    notify_inapp: bool = True
    notify_email: bool = False
    notify_push: bool = False
    active: bool = True
    source_question: Optional[str] = Field(None, max_length=1000)


class RulePatch(BaseModel):
    name: Optional[str] = Field(None, max_length=160)
    threshold: Optional[float] = None
    condition: Optional[str] = None
    days: Optional[int] = Field(None, ge=1, le=90)
    notify_inapp: Optional[bool] = None
    notify_email: Optional[bool] = None
    notify_push: Optional[bool] = None
    active: Optional[bool] = None


def _validate(metric: str, level: str, condition: str):
    if metric not in METRICS:
        raise HTTPException(422, f"Metrik tidak dikenal: {metric}")
    if level not in _SCOPE_COL:
        raise HTTPException(422, f"Level wilayah tidak dikenal: {level}")
    if condition not in CONDITIONS:
        raise HTTPException(422, f"Kondisi tidak dikenal: {condition}")


def _title(r: WatchRule) -> str:
    m = METRICS[r.metric]
    mom = m["group"] == "perf" and r.condition in ("turun", "naik", "berubah") and not _pp(r.metric)
    return m["short"] + (" MoM" if mom else "")


def _rule_json(db: Session, r: WatchRule) -> dict:
    samples = (db.query(WatchSample).filter(WatchSample.rule_id == r.id)
               .order_by(WatchSample.day.desc()).limit(7).all())
    m = METRICS[r.metric]
    is_near = r.active and r.status == "normal" and near(r, r.last_value)
    return {
        "id": r.id, "name": r.name, "title": _title(r), "metric": r.metric, "metric_label": m["label"], "icon": m["icon"],
        "micon": m["micon"], "group": m["group"], "group_label": GROUPS[m["group"]], "available": available(r.metric),
        "unit": m["unit"], "scope_level": r.scope_level, "scope_value": r.scope_value, "scope_label": scope_label(r, True),
        "kabupaten": r.scope_value if r.scope_level == "kabkota" else None,
        "condition": r.condition, "threshold": r.threshold, "threshold_label": fmt_threshold(r),
        "threshold_sub": fmt_period(r), "days": r.days,
        "notify_inapp": r.notify_inapp, "notify_email": r.notify_email, "notify_push": bool(r.notify_push), "active": r.active,
        "status": r.status if r.active else "nonaktif", "near": is_near,
        "value": r.last_value, "value_label": fmt_value(r.metric, r.condition, r.last_value),
        "value_sub": "dekat ambang" if is_near else None,
        "level": r.last_level, "level_label": fmt_level(r.metric, r.last_level), "breach_streak": r.breach_streak,
        "trend": [s.value for s in reversed(samples)],
        "last_checked_on": r.last_checked_on, "source_question": r.source_question,
        "created_at": r.created_at.isoformat() + "Z" if r.created_at else None,
    }


def _alert_json(a: WatchAlert, rule: Optional[WatchRule]) -> dict:
    m = METRICS[rule.metric] if rule else None
    return {
        "id": a.id, "rule_id": a.rule_id, "severity": a.severity, "title": a.title, "message": a.message,
        "value": a.value, "created_at": a.created_at.isoformat() + "Z" if a.created_at else None,
        "resolved": a.resolved_at is not None, "acknowledged": a.acknowledged_at is not None,
        "resolved_at": a.resolved_at.isoformat() + "Z" if a.resolved_at else None,
        "acknowledged_at": a.acknowledged_at.isoformat() + "Z" if a.acknowledged_at else None,
        "scope_label": scope_label(rule) if rule else None,
        "metric_label": m["label"] if m else None, "rule_title": _title(rule) if rule else None,
        "group": m["group"] if m else None, "group_label": GROUPS[m["group"]] if m else None,
        "kabupaten": rule.scope_value if rule and rule.scope_level == "kabkota" else None,
        "notify_push": bool(rule.notify_push) if rule else False,
        "value_label": fmt_value(rule.metric, rule.condition, a.value) if rule else None,
    }


@router.get("/meta")
def meta(user: User = Depends(get_current_user)):
    return {
        "metrics": [{"key": k, **{kk: v for kk, v in m.items() if kk != "expr"}, "available": available(k),
                     "group_label": GROUPS[m["group"]]} for k, m in METRICS.items()],
        "groups": [{"key": k, "label": v} for k, v in GROUPS.items()],
        "levels": [{"key": "circle", "label": "Circle"}, {"key": "region", "label": "Region"},
                   {"key": "branch", "label": "Branch"}, {"key": "kabkota", "label": "Kab/Kota"}],
        "conditions": list(CONDITIONS),
    }


@router.get("/rules")
def list_rules(check: bool = True, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rules = db.query(WatchRule).filter(WatchRule.user_id == user.id).order_by(WatchRule.created_at.desc()).all()
    if check:
        for r in rules:
            if r.active:
                evaluate_rule(db, r)
    return {"rules": [_rule_json(db, r) for r in rules]}


@router.post("/rules")
def create_rule(body: RuleIn, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    _validate(body.metric, body.scope_level, body.condition)
    if db.query(WatchRule).filter(WatchRule.user_id == user.id).count() >= 50:
        raise HTTPException(400, "Maksimal 50 watchlist per pengguna")
    name = (body.name or "").strip() or f"{METRICS[body.metric]['short']} {scope_label(WatchRule(scope_level=body.scope_level, scope_value=body.scope_value))}"
    r = WatchRule(user_id=user.id, name=name, metric=body.metric, scope_level=body.scope_level,
                  scope_value=body.scope_value.strip(), condition=body.condition, threshold=body.threshold,
                  days=body.days, notify_inapp=body.notify_inapp, notify_email=body.notify_email, notify_push=body.notify_push,
                  active=body.active, source_question=body.source_question)
    db.add(r)
    db.commit()
    db.refresh(r)
    evaluate_rule(db, r, force=True)
    return _rule_json(db, r)


@router.patch("/rules/{rule_id}")
def update_rule(rule_id: int, body: RulePatch, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    r = db.query(WatchRule).filter(WatchRule.id == rule_id, WatchRule.user_id == user.id).first()
    if not r:
        raise HTTPException(404, "Watchlist tidak ditemukan")
    data = body.model_dump(exclude_unset=True)
    if "condition" in data:
        _validate(r.metric, r.scope_level, data["condition"])
    for k, v in data.items():
        setattr(r, k, v)
    db.commit()
    if {"threshold", "condition", "days"} & data.keys():
        r.breach_streak = 0
        evaluate_rule(db, r, force=True)
    return _rule_json(db, r)


@router.delete("/rules/{rule_id}")
def delete_rule(rule_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    r = db.query(WatchRule).filter(WatchRule.id == rule_id, WatchRule.user_id == user.id).first()
    if not r:
        raise HTTPException(404, "Watchlist tidak ditemukan")
    db.query(WatchSample).filter(WatchSample.rule_id == r.id).delete()
    db.query(WatchAlert).filter(WatchAlert.rule_id == r.id).delete()
    db.delete(r)
    db.commit()
    return {"ok": True}


@router.get("/preview")
def preview(metric: str, scope_level: str = "circle", scope_value: str = "JAVA", condition: str = "turun",
            threshold: float = 5.0, user: User = Depends(get_current_user)):
    """Monthly history with how often the rule would have fired, for the create dialog."""
    _validate(metric, scope_level, condition)
    try:
        hist = metric_history(metric, scope_level, scope_value, months=13)
    except Exception as e:
        return {"error": str(e)[:200]}
    points = []
    for i in range(1, len(hist)):
        v, _ = observed(metric, condition, hist[: i + 1])
        points.append({"month_id": hist[i][0], "value": v, "level": hist[i][1],
                       "breach": breached(condition, threshold, v)})
    return {"points": points, "fires": sum(p["breach"] for p in points),
            "current": points[-1] if points else None}


@router.get("/alerts")
def list_alerts(status: str = Query("open", pattern="^(open|all)$"), limit: int = Query(50, le=200),
                user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    q = db.query(WatchAlert).filter(WatchAlert.user_id == user.id)
    if status == "open":
        q = q.filter(WatchAlert.resolved_at.is_(None), WatchAlert.severity != "pulih")
    alerts = q.order_by(WatchAlert.created_at.desc()).limit(limit).all()
    rules = {r.id: r for r in db.query(WatchRule).filter(WatchRule.user_id == user.id).all()}
    return {"alerts": [_alert_json(a, rules.get(a.rule_id)) for a in alerts]}


@router.get("/alerts/count")
def alert_count(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    n = (db.query(WatchAlert)
         .filter(WatchAlert.user_id == user.id, WatchAlert.resolved_at.is_(None),
                 WatchAlert.acknowledged_at.is_(None), WatchAlert.severity != "pulih")
         .count())
    return {"active": n}


@router.post("/alerts/{alert_id}/ack")
def acknowledge(alert_id: int, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    a = db.query(WatchAlert).filter(WatchAlert.id == alert_id, WatchAlert.user_id == user.id).first()
    if not a:
        raise HTTPException(404, "Alert tidak ditemukan")
    a.acknowledged_at = utcnow()
    db.commit()
    return {"ok": True}


# ── Stats and sentence parsing (Redesign v2 page 07) ───────────────────────

@router.get("/stats")
def stats(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Alerts in the last 30 days per group, time to "Ditangani", and repeating watches."""
    now = utcnow()
    since, before = now - timedelta(days=30), now - timedelta(days=60)
    rules = {r.id: r for r in db.query(WatchRule).filter(WatchRule.user_id == user.id).all()}
    alerts = (db.query(WatchAlert).filter(WatchAlert.user_id == user.id, WatchAlert.severity != "pulih",
                                          WatchAlert.created_at >= before).all())
    cur = [a for a in alerts if a.created_at >= since]
    prev = [a for a in alerts if a.created_at < since]
    by_group = {k: 0 for k in GROUPS}
    per_rule: dict[int, int] = {}
    for a in cur:
        r = rules.get(a.rule_id)
        if r:
            by_group[METRICS[r.metric]["group"]] += 1
        per_rule[a.rule_id] = per_rule.get(a.rule_id, 0) + 1

    def handled(xs: list) -> Optional[float]:
        hrs = [(a.acknowledged_at - a.created_at).total_seconds() / 3600 for a in xs if a.acknowledged_at]
        return round(sum(hrs) / len(hrs), 1) if hrs else None

    h_cur, h_prev = handled(cur), handled(prev)
    repeat = [rules[i] for i, n in sorted(per_rule.items(), key=lambda x: -x[1]) if n >= 2 and i in rules]
    return {
        "alerts_30d": len(cur),
        "by_group": [{"key": k, "label": GROUPS[k], "count": by_group[k]} for k in GROUPS],
        "handled_hours": h_cur, "handled_prev_hours": h_prev,
        "handled_delta_hours": round(h_cur - h_prev, 1) if h_cur is not None and h_prev is not None else None,
        "repeating": [{"rule_id": r.id, "title": f"{_title(r)} {scope_label(r)}"} for r in repeat],
    }


class ParseIn(BaseModel):
    text: str = Field(..., min_length=3, max_length=500)


_KW = [
    (r"revenue\s*(per|/)\s*(new\s*)?site|rev\s*(per|/)\s*site", "rev_site"),
    (r"rgu\s*(90d?\s*)?(per|/)\s*site", "rgu_site"),
    (r"vlr", "vlr_site"),
    (r"market\s*share|pangsa\s*pasar", "market_share"),
    (r"penetrasi\s*fwa", "fwa_pen"),
    (r"availab|ketersediaan", "availability"),
    (r"payload|trafik|data usage", "payload"),
    (r"gross\s*add.*fwa|fwa.*gross\s*add|rgu\s*fwa|fwa\s*rgu", "fwa_rgu"),
    (r"revenue\s*fwa|fwa\s*revenue", "fwa_revenue"),
    (r"gross\s*add|akuisisi", "gross_add"),
    (r"churn", "net_churn"),
    (r"pelanggan|rgu|subscriber", "subs"),
    (r"revenue\s*data", "rev_data"),
    (r"revenue|pendapatan", "revenue"),
]
_REGIONS = [(r"west\s*java|jawa\s*barat|jabar", "WEST JAVA"), (r"central\s*java|jawa\s*tengah|jateng|diy|yogya", "CENTRAL JAVA"),
            (r"east\s*java|jawa\s*timur|jatim", "EAST JAVA")]
_MULT = {"t": 1e12, "triliun": 1e12, "m": 1e9, "miliar": 1e9, "jt": 1e6, "juta": 1e6, "rb": 1e3, "ribu": 1e3}


def _parse_num(txt: str) -> Optional[float]:
    m = re.search(r"(rp\.?\s*)?(\d+(?:[.,]\d+)?)\s*(triliun|miliar|juta|ribu|jt|rb|t|m)?\b\s*(%|pp)?", txt)
    if not m:
        return None
    v = float(m.group(2).replace(".", "").replace(",", ".") if re.match(r"^\d{1,3}(\.\d{3})+$", m.group(2)) else m.group(2).replace(",", "."))
    return v * _MULT.get((m.group(3) or "").lower(), 1)


def parse_sentence(text: str) -> dict:
    """Rule draft from a sentence ("Kabari saya kalau revenue per site di Kab. Garut turun di bawah Rp 180 jt selama 2 bulan")."""
    s = text.lower()
    metric = next((k for pat, k in _KW if re.search(pat, s)), None)
    level, value = "circle", "JAVA"
    kab = re.search(r"\b(kab(?:upaten|\.)?|kota)\s+([a-z]+(?:\s[a-z]+)?)", s)
    if kab:
        name = re.sub(r"\s(turun|naik|di|bulan|minggu|vs|dan|kalau|selama|lebih|kurang)$", "", kab.group(2)).strip()
        level, value = "kabkota", ("KOTA " if kab.group(1).startswith("kota") else "") + name.upper()
    else:
        reg = next((v for pat, v in _REGIONS if re.search(pat, s)), None)
        if reg:
            level, value = "region", reg
    condition, threshold = None, None
    lvl = re.search(r"(di\s*bawah|kurang\s*dari|<)\s*(.+)", s)
    hi = re.search(r"(di\s*atas|lebih\s*dari|>)\s*(.+)", s)
    chg = re.search(r"(turun|naik|berubah)\s*(lebih\s*dari\s*|>\s*)?(\d+(?:[.,]\d+)?)\s*(%|pp)", s)
    if chg:
        condition, threshold = chg.group(1), float(chg.group(3).replace(",", "."))
    elif lvl:
        condition, threshold = "di_bawah", _parse_num(lvl.group(2))
    elif hi:
        condition, threshold = "di_atas", _parse_num(hi.group(2))
    elif re.search(r"turun|drop|anjlok", s):
        condition, threshold = "turun", 5.0
    days = 1
    dm = re.search(r"(\d+)\s*(hari|minggu|bulan)", s)
    if dm:
        n = int(dm.group(1))
        days = min(90, n * {"hari": 1, "minggu": 7, "bulan": 30}[dm.group(2)])
    missing = [k for k, v in (("metric", metric), ("condition", condition), ("threshold", threshold)) if v is None]
    out = {"metric": metric, "scope_level": level, "scope_value": value, "condition": condition, "threshold": threshold,
           "days": days, "missing": missing, "source_question": text}
    if metric:
        m = METRICS[metric]
        draft = WatchRule(metric=metric, scope_level=level, scope_value=value, condition=condition or "turun",
                          threshold=threshold if threshold is not None else 5.0, days=days)
        out.update({
            "metric_label": m["short"], "group": m["group"], "group_label": GROUPS[m["group"]], "available": available(metric),
            "scope_label": scope_label(draft, True),
            "condition_label": (fmt_threshold(draft) + (f", {fmt_period(draft).replace('selama ', '')}" if days > 1 else "")) if condition else None,
            "name": f"{m['short']} {scope_label(draft)}",
        })
    return out


@router.post("/parse")
def parse(body: ParseIn, user: User = Depends(get_current_user)):
    return parse_sentence(body.text)
