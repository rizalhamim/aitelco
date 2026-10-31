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
    "revenue": {"label": "Revenue", "expr": "x.rev_prepaid", "unit": "IDR", "icon": "trending-up"},
    "rev_data": {"label": "Revenue data", "expr": "x.rev_data", "unit": "IDR", "icon": "trending-up"},
    "payload": {"label": "Payload data", "expr": "x.usg_data_gb", "unit": "GB", "icon": "activity"},
    "gross_add": {"label": "Gross add", "expr": "x.gross_add", "unit": "Subs", "icon": "users"},
    "subs": {"label": "Pelanggan aktif (RGU 90D)", "expr": "x.rgu_90d", "unit": "Subs", "icon": "users"},
    "net_churn": {"label": "Net churn 90D", "expr": "x.net_churn_90d", "unit": "Subs", "icon": "users"},
    "fwa_rgu": {"label": "FWA RGU 90D", "expr": "x.fwa_rgu90", "unit": "Subs", "icon": "wifi"},
    "fwa_revenue": {"label": "Revenue FWA", "expr": "x.rev_fwa_total", "unit": "IDR", "icon": "wifi"},
    "availability": {"label": "Site availability 4G", "expr": None, "unit": "%", "icon": "radio"},
}
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


def metric_history(metric: str, level: str, value: str, months: int = 13) -> list[tuple[int, Optional[float]]]:
    """[(month_id, level)] oldest → newest for a metric at a territory."""
    m = METRICS[metric]
    if metric == "availability":
        rows = run_query(f"""
SELECT CAST(month_id AS INT64) AS month_id, AVG(mean_avg_avail_pct_4g) AS v
FROM {_AVAIL}
WHERE territory_level = '{_AVAIL_LEVEL.get(level, level)}' AND UPPER(territory_name) = UPPER('{_esc(value)}')
GROUP BY month_id ORDER BY month_id DESC LIMIT {months}
""", row_limit=months)["rows"]
    else:
        col = _SCOPE_COL[level]
        rows = run_query(f"""
SELECT x.month_id AS month_id, SUM({m['expr']}) AS v
FROM {_MTD} x
LEFT JOIN {_TERR} t ON x.kec_id = t.kec_id
WHERE UPPER({col}) = UPPER('{_esc(value)}')
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
    if rule_metric == "availability":
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


def fmt_value(metric: str, condition: str, v: Optional[float]) -> str:
    if v is None:
        return "–"
    if condition in ("di_bawah", "di_atas"):
        if METRICS[metric]["unit"] == "%":
            return f"{v:.2f}".replace(".", ",") + "%"
        return _short(v, METRICS[metric]["unit"])
    unit = " pp" if metric == "availability" else "%"
    sign = "+" if v > 0 else "−" if v < 0 else ""
    return f"{sign}{abs(v):.1f}".replace(".", ",") + unit


def fmt_threshold(rule: WatchRule) -> str:
    t = rule.threshold
    if rule.condition in ("di_bawah", "di_atas"):
        op = "<" if rule.condition == "di_bawah" else ">"
        unit = "%" if METRICS[rule.metric]["unit"] == "%" else ""
        return f"{op} {t:g}".replace(".", ",") + unit
    unit = " pp" if rule.metric == "availability" else "%"
    op = {"turun": "≤ −", "naik": "≥ +", "berubah": "± "}[rule.condition]
    return f"{op}{abs(t):g}".replace(".", ",") + unit


def _short(v: float, unit: str) -> str:
    a = abs(v)
    body = (f"{v / 1e12:.2f} T" if a >= 1e12 else f"{v / 1e9:.1f} M" if a >= 1e9
            else f"{v / 1e6:.1f} jt" if a >= 1e6 else f"{v / 1e3:.1f} rb" if a >= 1e4 else f"{v:,.0f}")
    body = body.replace(".", ",")
    return f"Rp {body}" if unit == "IDR" else body


def scope_label(rule: WatchRule) -> str:
    v = (rule.scope_value or "").title()
    return {"kabkota": v, "branch": f"Branch {v}", "region": v, "circle": "Jawa" if v.upper() == "JAVA" else v}.get(rule.scope_level, v)


# ── Evaluation ─────────────────────────────────────────────────────────────

def evaluate_rule(db: Session, rule: WatchRule, force: bool = False) -> Optional[WatchAlert]:
    """Check one rule (once per WIB day unless forced). Returns a new alert, if any."""
    today = _today_wib()
    if rule.last_checked_on == today and not force:
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
                label = METRICS[rule.metric]["label"]
                verb = {"turun": "turun", "naik": "naik", "berubah": "berubah",
                        "di_bawah": "di bawah ambang", "di_atas": "di atas ambang"}[rule.condition]
                title = f"{label} {scope_label(rule)} {verb} {fmt_value(rule.metric, rule.condition, v).lstrip('+−')}"
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
                               title=f"Pulih: {METRICS[rule.metric]['label']} {scope_label(rule)}",
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
    days: int = Field(1, ge=1, le=30)
    notify_inapp: bool = True
    notify_email: bool = False
    active: bool = True
    source_question: Optional[str] = Field(None, max_length=1000)


class RulePatch(BaseModel):
    name: Optional[str] = Field(None, max_length=160)
    threshold: Optional[float] = None
    condition: Optional[str] = None
    days: Optional[int] = Field(None, ge=1, le=30)
    notify_inapp: Optional[bool] = None
    notify_email: Optional[bool] = None
    active: Optional[bool] = None


def _validate(metric: str, level: str, condition: str):
    if metric not in METRICS:
        raise HTTPException(422, f"Metrik tidak dikenal: {metric}")
    if level not in _SCOPE_COL:
        raise HTTPException(422, f"Level wilayah tidak dikenal: {level}")
    if condition not in CONDITIONS:
        raise HTTPException(422, f"Kondisi tidak dikenal: {condition}")


def _rule_json(db: Session, r: WatchRule) -> dict:
    samples = (db.query(WatchSample).filter(WatchSample.rule_id == r.id)
               .order_by(WatchSample.day.desc()).limit(7).all())
    m = METRICS[r.metric]
    return {
        "id": r.id, "name": r.name, "metric": r.metric, "metric_label": m["label"], "icon": m["icon"],
        "unit": m["unit"], "scope_level": r.scope_level, "scope_value": r.scope_value, "scope_label": scope_label(r),
        "condition": r.condition, "threshold": r.threshold, "threshold_label": fmt_threshold(r), "days": r.days,
        "notify_inapp": r.notify_inapp, "notify_email": r.notify_email, "active": r.active,
        "status": r.status if r.active else "nonaktif",
        "value": r.last_value, "value_label": fmt_value(r.metric, r.condition, r.last_value),
        "level": r.last_level, "breach_streak": r.breach_streak,
        "trend": [s.value for s in reversed(samples)],
        "last_checked_on": r.last_checked_on, "source_question": r.source_question,
        "created_at": r.created_at.isoformat() + "Z" if r.created_at else None,
    }


def _alert_json(a: WatchAlert, rule: Optional[WatchRule]) -> dict:
    return {
        "id": a.id, "rule_id": a.rule_id, "severity": a.severity, "title": a.title, "message": a.message,
        "value": a.value, "created_at": a.created_at.isoformat() + "Z" if a.created_at else None,
        "resolved": a.resolved_at is not None, "acknowledged": a.acknowledged_at is not None,
        "scope_label": scope_label(rule) if rule else None,
        "metric_label": METRICS[rule.metric]["label"] if rule else None,
    }


@router.get("/meta")
def meta(user: User = Depends(get_current_user)):
    return {
        "metrics": [{"key": k, **{kk: v for kk, v in m.items() if kk != "expr"}} for k, m in METRICS.items()],
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
    name = (body.name or "").strip() or f"{METRICS[body.metric]['label']} {body.scope_value.title()}"
    r = WatchRule(user_id=user.id, name=name, metric=body.metric, scope_level=body.scope_level,
                  scope_value=body.scope_value.strip(), condition=body.condition, threshold=body.threshold,
                  days=body.days, notify_inapp=body.notify_inapp, notify_email=body.notify_email,
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
