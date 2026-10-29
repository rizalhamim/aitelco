from datetime import datetime

from app.database import ReportSchedule
from app.report_schedule import _recipients, describe, is_due, report_html


def _s(**kw):
    base = dict(active=True, frequency="mingguan", weekday=0, monthday=1, hour=8, last_sent_on=None, name="Performa Jawa")
    base.update(kw)
    return ReportSchedule(**base)


def test_weekly_due_only_on_day_after_hour():
    mon_9 = datetime(2026, 11, 2, 9, 0)   # Monday
    assert is_due(_s(), mon_9)
    assert not is_due(_s(), datetime(2026, 11, 2, 7, 59))
    assert not is_due(_s(), datetime(2026, 11, 3, 9, 0))
    assert not is_due(_s(last_sent_on="2026-11-02"), mon_9)
    assert not is_due(_s(active=False), mon_9)


def test_monthly_due():
    assert is_due(_s(frequency="bulanan", monthday=5), datetime(2026, 11, 5, 8, 0))
    assert not is_due(_s(frequency="bulanan", monthday=5), datetime(2026, 11, 6, 8, 0))


def test_describe_and_recipients():
    assert describe(_s()) == "tiap Senin 08.00 WIB"
    assert describe(_s(frequency="bulanan", monthday=3, hour=7)) == "tiap tanggal 3 07.00 WIB"
    assert _recipients("a@x.co, bad; b@y.id") == ["a@x.co", "b@y.id"]


def test_report_html_has_numbers():
    ov = {
        "scope": {"region": None}, "month_label": "Okt 2026",
        "summary": {"text": "Revenue Jawa **naik 1,2% MoM**."},
        "kpis": [{"label": "Revenue", "format": "currency", "value": 1.84e12, "pct_change": 1.2}],
        "regions": [{"region": "JAWA TIMUR", "revenue": 788e9, "mom_pct": 2.1, "subs": 17.6e6, "payload_gb": 36.4e6}],
    }
    out = report_html(ov, "Performa mingguan Jawa")
    assert "Rp 1,84 T" in out and "Jawa Timur" in out and "naik 1,2% MoM" in out and "**" not in out
