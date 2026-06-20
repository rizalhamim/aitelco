"""Email service using SMTP (mail.bizplan-java.com)."""
import os
import smtplib
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.image import MIMEImage

log = logging.getLogger("email_service")

# IOH color logo embedded inline (cid:bizlogo) in the email top band.
_EMAIL_LOGO = os.path.join(os.path.dirname(__file__), "assets", "logo_ioh_color.png")


def _logo_part():
    """Return an inline MIMEImage (Content-ID: bizlogo) or None."""
    try:
        with open(_EMAIL_LOGO, "rb") as f:
            img = MIMEImage(f.read())
        img.add_header("Content-ID", "<bizlogo>")
        img.add_header("Content-Disposition", "inline", filename="logo.png")
        return img
    except Exception:
        return None

SMTP_HOST = os.environ.get("SMTP_HOST", "mail.bizplan-java.com")
SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
SMTP_USER = os.environ.get("SMTP_USER", "notification@bizplan-java.com")
SMTP_PASS = os.environ.get("SMTP_PASS", "Apotoxin4869")
SMTP_FROM = os.environ.get("SMTP_FROM", "Bizplan Java Agent <notification@bizplan-java.com>")
APP_URL = os.environ.get("APP_URL", "http://agent-02.bizplan-java.com:3000")


def _send(to: str, subject: str, html_body: str) -> bool:
    try:
        msg = MIMEMultipart("related")
        msg["From"] = SMTP_FROM
        msg["To"] = to
        msg["Subject"] = subject
        alt = MIMEMultipart("alternative")
        alt.attach(MIMEText(html_body, "html", "utf-8"))
        msg.attach(alt)
        logo = _logo_part()
        if logo:
            msg.attach(logo)

        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=15) as srv:
            srv.ehlo()
            srv.starttls()
            srv.ehlo()
            srv.login(SMTP_USER, SMTP_PASS)
            srv.sendmail(SMTP_USER, [to], msg.as_string())
        log.info(f"Email sent to {to}: {subject}")
        return True
    except Exception as e:
        log.error(f"Email failed to {to}: {e}")
        return False


# Minimal head CSS — only classes that are SAFE in Outlook (Word) are used; all
# critical layout is table-based with inline styles so it renders consistently.
BRAND_CSS = """
body{margin:0;padding:0;background:#F2F3F5;}
table{border-collapse:collapse;}
td{font-family:'Prompt','Segoe UI',Helvetica,Arial,sans-serif;}
h2{font-family:'Poppins','Segoe UI',Helvetica,Arial,sans-serif;font-size:21px;font-weight:bold;color:#1A1A1B;margin:0 0 8px;}
p{font-family:'Prompt','Segoe UI',Helvetica,Arial,sans-serif;font-size:14px;line-height:1.65;color:#4D4D4F;margin:8px 0;}
a{text-decoration:none;}
.eyebrow{font-family:'Poppins','Segoe UI',Helvetica,Arial,sans-serif;font-size:12px;font-weight:bold;text-transform:uppercase;letter-spacing:1px;margin:20px 0 6px;}
.divider{border:none;border-top:1px solid #E5E5E7;margin:18px 0;}
.muted{font-size:12px;color:#7A7A7C;margin-top:14px;line-height:1.55;}
.btn{display:inline-block;padding:12px 28px;border-radius:10px;background:#32BCAD;color:#ffffff;font-family:'Poppins',Helvetica,Arial,sans-serif;font-weight:bold;font-size:14px;}
.kv{font-size:13px;padding:6px 0;border-bottom:1px solid #E5E5E7;}
.kv .k{color:#7A7A7C;font-weight:bold;}.kv .v{font-weight:bold;color:#1A1A1B;}
.tag{display:inline-block;padding:3px 10px;border-radius:999px;font-size:11px;font-weight:bold;text-transform:uppercase;}
.tag-red{background:#E1F4EE;color:#1A9E8F;}
.tag-teal{background:#E1F4EE;color:#1A9E8F;}
ul{margin:6px 0;padding-left:0;}
"""

_FONT_BODY = "'Prompt','Segoe UI',Helvetica,Arial,sans-serif"
_FONT_HEAD = "'Poppins','Segoe UI',Helvetica,Arial,sans-serif"


def _base_html(content: str) -> str:
    """Outlook-desktop-safe wrapper: table-based layout, inline styles, no flexbox."""
    return f"""<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1.0"/>
<meta http-equiv="X-UA-Compatible" content="IE=edge"/>
<style>{BRAND_CSS}</style>
</head>
<body style="margin:0;padding:0;background:#F2F3F5;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F2F3F5;">
<tr><td align="center" style="padding:26px 14px;">
  <table role="presentation" width="720" cellpadding="0" cellspacing="0" style="width:720px;max-width:720px;background:#ffffff;border:1px solid #E5E5E7;border-radius:16px;overflow:hidden;">
    <!-- top band -->
    <tr><td style="background:#1A1A1B;padding:20px 32px;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
        <td align="left" valign="middle" style="font-family:{_FONT_HEAD};font-size:19px;font-weight:bold;color:#ffffff;">
          Bizplan Java Agent
          <div style="font-family:{_FONT_BODY};font-size:10px;font-weight:bold;color:#32BCAD;letter-spacing:2px;text-transform:uppercase;padding-top:3px;">Business Planning Circle Java</div>
        </td>
        <td align="right" valign="middle">
          <img src="cid:bizlogo" alt="IOH" width="120" style="display:block;width:120px;height:auto;border:0;outline:none;" />
        </td>
      </tr></table>
    </td></tr>
    <!-- body -->
    <tr><td style="padding:30px 32px 24px 32px;font-family:{_FONT_BODY};color:#1A1A1B;">
{content}
    </td></tr>
    <!-- footer -->
    <tr><td style="background:#FAFAFB;border-top:1px solid #E5E5E7;padding:16px 32px;text-align:center;font-family:{_FONT_BODY};font-size:11px;color:#9A9A9C;line-height:1.6;">
      Confidential &amp; Internal Use Only &middot; Do Not Capture &amp; Share<br/>
      Bizplan Java Agent &middot; Business Planning Circle Java &middot; Indosat Ooredoo Hutchison
    </td></tr>
  </table>
</td></tr>
</table>
</body></html>"""



def send_login_token(to: str, username: str, code: str) -> bool:
    html = _base_html(f"""
<h2>Login Token</h2>
<p>Hi <strong>{username}</strong>, ini adalah kode token untuk login Anda:</p>
<div style="text-align:center;margin:32px 0;">
    <span style="font-family:'Courier New',Courier,monospace;font-size:36px;font-weight:bold;letter-spacing:8px;background:#FAFAFB;padding:16px 24px;border:1px solid #E5E5E7;border-radius:12px;color:#1A1A1B;">{code}</span>
</div>
<p>Token ini hanya berlaku selama <strong>5 menit</strong>.</p>
<p class="muted">Jika Anda tidak mencoba login, abaikan email ini.</p>
""")
    return _send(to, "Kode Login — Bizplan Java Agent", html)


def send_reset_link(to: str, username: str, token: str) -> bool:
    reset_url = f"{APP_URL}/login?reset={token}"
    html = _base_html(f"""
<h2>Password Reset</h2>
<p>Hi <strong>{username}</strong>, kamu telah meminta reset password untuk akun Bizplan Java Agent.</p>
<p>Klik tombol di bawah untuk membuat password baru. Link ini berlaku selama <strong>30 menit</strong>.</p>
<p style="text-align:center;margin:28px 0"><a href="{reset_url}" class="btn">Reset Password</a></p>
<p class="muted">Jika kamu tidak meminta reset password, abaikan email ini. Akunmu tetap aman.</p>
<hr class="divider">
<p class="muted">Atau copy link berikut:<br><a href="{reset_url}" style="color:#ED1C24;word-break:break-all">{reset_url}</a></p>
""")
    return _send(to, "Reset Password — Bizplan Java Agent", html)


def send_welcome(to: str, username: str, full_name: str) -> bool:
    html = _base_html(f"""
<h2>Selamat Datang, {full_name or username}!</h2>
<p>Akun Bizplan Java Agent kamu telah dibuat oleh administrator.</p>
<div class="kv"><span class="k">Username</span><span class="v">{username}</span></div>
<div class="kv"><span class="k">Email</span><span class="v">{to}</span></div>
<p>Silakan login di link berikut dan segera ganti password default-mu.</p>
<p style="text-align:center;margin:28px 0"><a href="{APP_URL}/login" class="btn">Login Sekarang</a></p>
<p class="muted">Hubungi administrator jika kamu mengalami kendala login.</p>
""")
    return _send(to, "Akun Baru Bizplan Java Agent", html)


def send_chat_summary(to: str, username: str, question: str,
                      answer: str, domain: str | None = None,
                      sql: str | None = None, row_count: int | None = None) -> bool:
    domain_html = f'<span class="tag tag-red">{domain}</span>' if domain else ""
    sql_html = f'<hr class="divider"><p style="font-size:12px;font-weight:700;color:#7A7A7C;text-transform:uppercase;letter-spacing:0.06em">SQL Query</p><pre style="background:#1A1A1B;color:#E8E8EA;padding:14px;border-radius:10px;font-size:12px;overflow-x:auto;white-space:pre-wrap">{sql}</pre>' if sql else ""
    rows_html = f'<div class="kv"><span class="k">Rows returned</span><span class="v">{row_count:,}</span></div>' if row_count else ""

    answer_html = answer.replace("\n", "<br>") if answer else ""

    html = _base_html(f"""
<h2>Chat Summary {domain_html}</h2>
<hr class="divider">
<p style="font-size:12px;font-weight:700;color:#EC008C;text-transform:uppercase;letter-spacing:0.1em">Your Question</p>
<p style="background:#F7F7F8;padding:12px 16px;border-radius:10px;border-left:4px solid #ED1C24;font-size:14px">{question}</p>
<p style="font-size:12px;font-weight:700;color:#32BCAD;text-transform:uppercase;letter-spacing:0.1em;margin-top:20px">AI Answer</p>
<div style="font-size:14px;line-height:1.7;color:#1A1A1B">{answer_html}</div>
{rows_html}
{sql_html}
<hr class="divider">
<p class="muted">Dikirim oleh Bizplan Java Agent atas permintaan {username}.</p>
""")
    return _send(to, f"AI Summary: {question[:60]}…" if len(question) > 60 else f"AI Summary: {question}", html)


def send_notification(to: str, subject: str, message: str) -> bool:
    html = _base_html(f"""
<h2>{subject}</h2>
<div style="font-size:14px;line-height:1.7;color:#1A1A1B">{message}</div>
<hr class="divider">
<p class="muted">Notifikasi otomatis dari Bizplan Java Agent system.</p>
""")
    return _send(to, subject, html)


# ───────────────────────────────────────────────────────────────────────────
# Executive AI Summary — rich branded HTML email + PDF (cover + charts)
# Branding: Bizplan Java Agent.  Fonts: Poppins (headers) + Prompt (body).
# Palette: ink-dominant with teal/magenta/pink/yellow accents (red de-emphasised).
# ───────────────────────────────────────────────────────────────────────────

import io
import os
import re
import datetime
from email.mime.application import MIMEApplication

_ASSETS = os.path.join(os.path.dirname(__file__), "assets")
_LOGO = os.path.join(_ASSETS, "logo_ioh_color.png")
_LOGOGRAM = os.path.join(_ASSETS, "logogram_ioh.png")

# Brand palette (design-rule.txt). Accent order avoids red dominance.
_PAL = {
    "grey": "#4D4D4F", "red": "#ED1C24", "pink": "#EC008C", "yellow": "#FFCB05",
    "teal": "#32BCAD", "magenta": "#C6168D", "ink": "#1A1A1B", "mute": "#7A7A7C",
    "rule": "#E5E5E7", "panel": "#F7F7F8", "white": "#FFFFFF",
}
# Section accent rotation (teal -> magenta -> pink -> yellow -> grey); red kept minimal
_ACCENTS = [_PAL["teal"], _PAL["magenta"], _PAL["pink"], _PAL["yellow"], _PAL["grey"]]

_FONTS_READY = False


def _ensure_fonts():
    """Register Poppins + Prompt TTFs with reportlab once."""
    global _FONTS_READY
    if _FONTS_READY:
        return True
    try:
        from reportlab.pdfbase import pdfmetrics
        from reportlab.pdfbase.ttfonts import TTFont
        reg = [
            ("Poppins-Bold", "Poppins-Bold.ttf"),
            ("Poppins-SemiBold", "Poppins-SemiBold.ttf"),
            ("Prompt", "Prompt-Regular.ttf"),
            ("Prompt-Medium", "Prompt-Medium.ttf"),
            ("Prompt-SemiBold", "Prompt-SemiBold.ttf"),
        ]
        for name, fn in reg:
            p = os.path.join(_ASSETS, fn)
            if os.path.exists(p):
                pdfmetrics.registerFont(TTFont(name, p))
        _FONTS_READY = True
    except Exception as e:
        log.error(f"font register failed: {e}")
    return _FONTS_READY


def _send_with_pdf(to: str, subject: str, html_body: str,
                   pdf_bytes: bytes | None = None, pdf_name: str = "summary.pdf") -> bool:
    msg = MIMEMultipart("mixed")
    msg["From"] = SMTP_FROM
    msg["To"] = to
    msg["Subject"] = subject
    # related = html + inline CID logo
    related = MIMEMultipart("related")
    alt = MIMEMultipart("alternative")
    alt.attach(MIMEText(html_body, "html", "utf-8"))
    related.attach(alt)
    logo = _logo_part()
    if logo:
        related.attach(logo)
    msg.attach(related)
    if pdf_bytes:
        part = MIMEApplication(pdf_bytes, _subtype="pdf")
        part.add_header("Content-Disposition", "attachment", filename=pdf_name)
        msg.attach(part)
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as srv:
        srv.ehlo(); srv.starttls(); srv.ehlo()
        srv.login(SMTP_USER, SMTP_PASS)
        srv.sendmail(SMTP_USER, [to], msg.as_string())
    log.info(f"Summary email sent to {to}: {subject}")
    return True


def _num(v):
    """Parse a numeric value out of a key-number 'value' string for charting."""
    if v is None:
        return None
    s = str(v)
    mult = 1.0
    low = s.lower()
    if "miliar" in low or low.endswith("b") or " b" in low or "bn" in low:
        mult = 1e9
    elif "juta" in low or low.endswith("m") or " m" in low or "mn" in low:
        mult = 1e6
    elif "ribu" in low or low.endswith("k") or " k" in low:
        mult = 1e3
    m = re.search(r"-?\d[\d.,]*", s.replace(".", "").replace(",", "."))
    if not m:
        # fallback simpler parse
        m = re.search(r"-?\d+(?:\.\d+)?", s)
        if not m:
            return None
        return float(m.group(0)) * mult
    try:
        return float(m.group(0)) * mult
    except Exception:
        return None


def _summary_email_html(username: str, summary: dict, transcript: list | None = None) -> str:
    """Outlook-safe: bullet lists and key-number cards rendered as tables."""

    def eyebrow(text, color):
        return (f'<div style="font-family:{_FONT_HEAD};font-size:12px;font-weight:bold;'
                f'color:{color};letter-spacing:1px;text-transform:uppercase;'
                f'margin:22px 0 8px 0;">{text}</div>')

    def bullets(items, color):
        if not items:
            return ('<div style="font-size:13px;color:#7A7A7C;">—</div>')
        rows = ""
        for x in items:
            rows += (
                '<tr>'
                f'<td valign="top" width="14" style="padding:4px 0;">'
                f'<div style="width:6px;height:6px;background:{color};border-radius:50%;margin-top:7px;">&nbsp;</div></td>'
                f'<td valign="top" style="padding:4px 0 4px 8px;font-family:{_FONT_BODY};'
                f'font-size:14px;line-height:1.55;color:#1A1A1B;">{x}</td>'
                '</tr>'
            )
        return f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0">{rows}</table>'

    def section(text, items, color):
        return eyebrow(text, color) + bullets(items, color)

    # key-number cards as a 2-column table (Outlook renders tables reliably)
    kn = summary.get("key_numbers", [])
    cards_block = ""
    if kn:
        cells = []
        for i, n in enumerate(kn):
            acc = _ACCENTS[i % len(_ACCENTS)]
            cells.append(
                f'<td width="50%" valign="top" style="padding:5px;">'
                f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
                f'style="border:1px solid #E5E5E7;border-top:3px solid {acc};border-radius:10px;">'
                f'<tr><td style="padding:12px 14px;">'
                f'<div style="font-family:{_FONT_HEAD};font-size:10px;font-weight:bold;letter-spacing:1px;text-transform:uppercase;color:#7A7A7C;">{n.get("label","")}</div>'
                f'<div style="font-family:{_FONT_HEAD};font-size:22px;font-weight:bold;color:#1A1A1B;padding-top:3px;">{n.get("value","")}</div>'
                f'<div style="font-family:{_FONT_BODY};font-size:11px;color:#7A7A7C;padding-top:2px;">{n.get("note","")}</div>'
                f'</td></tr></table></td>'
            )
        rows_html = ""
        for j in range(0, len(cells), 2):
            pair = cells[j:j + 2]
            if len(pair) == 1:
                pair.append('<td width="50%">&nbsp;</td>')
            rows_html += f'<tr>{"".join(pair)}</tr>'
        cards_block = (eyebrow("Key Numbers", _PAL["magenta"]) +
                       f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
                       f'style="margin:0 -5px;">{rows_html}</table>')

    divider = '<div style="border-top:1px solid #E5E5E7;margin:18px 0;font-size:0;line-height:0;">&nbsp;</div>'
    title = summary.get("title", "Ringkasan Analisa")
    overview = summary.get("overview", "")

    content = (
        eyebrow("Executive Summary", _PAL["teal"]) +
        f'<h2 style="font-family:{_FONT_HEAD};font-size:21px;font-weight:bold;color:#1A1A1B;margin:0 0 8px 0;">{title}</h2>' +
        f'<p style="font-family:{_FONT_BODY};font-size:14px;line-height:1.65;color:#4D4D4F;margin:8px 0;">{overview}</p>' +
        divider +
        section("Key Points", summary.get("key_points", []), _PAL["teal"]) +
        cards_block +
        section("Findings", summary.get("findings", []), _PAL["magenta"]) +
        section("Insights", summary.get("insights", []), _PAL["pink"]) +
        section("Action Items / Key To-Do", summary.get("action_items", []), "#B8860B") +
        divider +
        f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:14px 0 4px;">'
        f'<a href="{APP_URL}" style="display:inline-block;padding:12px 30px;background:#32BCAD;color:#ffffff;'
        f'font-family:{_FONT_HEAD};font-weight:bold;font-size:14px;border-radius:10px;text-decoration:none;">Buka Bizplan Java Agent</a>'
        f'</td></tr></table>'
        f'<p style="font-family:{_FONT_BODY};font-size:12px;color:#7A7A7C;margin-top:14px;line-height:1.55;">'
        f'Ringkasan ini dibuat otomatis oleh Bizplan Java Agent (Analyst) atas permintaan {username}. '
        f'Seluruh riwayat percakapan beserta data penunjang lengkap (tabel & section profil) '
        f'terlampir dalam PDF.</p>'
    )
    return _base_html(content)


def _chart_keynumbers(summary, W, H):
    """Horizontal bar Drawing from key_numbers that parse to a value."""
    from reportlab.graphics.shapes import Drawing, String, Rect
    from reportlab.lib import colors
    pts = []
    for n in summary.get("key_numbers", []):
        v = _num(n.get("value"))
        if v is not None and v != 0:
            pts.append((n.get("label", "")[:22], v, str(n.get("value", ""))))
    pts = pts[:6]
    if len(pts) < 2:
        return None
    d = Drawing(W, H)
    accents = ["#32BCAD", "#C6168D", "#EC008C", "#FFCB05", "#4D4D4F", "#ED1C24"]
    maxv = max(abs(p[1]) for p in pts) or 1
    n = len(pts)
    gap = 8
    bar_h = (H - (n + 1) * gap) / n
    label_w = 150
    bar_max = W - label_w - 90
    for i, (lab, val, disp) in enumerate(pts):
        y = H - gap - (i + 1) * bar_h - i * gap
        d.add(String(0, y + bar_h / 2 - 4, lab, fontName="Prompt", fontSize=9,
                     fillColor=colors.HexColor("#1A1A1B")))
        bw = max((abs(val) / maxv) * bar_max, 2)
        d.add(Rect(label_w, y, bw, bar_h, fillColor=colors.HexColor(accents[i % len(accents)]),
                   strokeColor=None, rx=2, ry=2))
        d.add(String(label_w + bw + 6, y + bar_h / 2 - 4, disp, fontName="Poppins-SemiBold",
                     fontSize=9, fillColor=colors.HexColor("#1A1A1B")))
    return d


def _build_summary_pdf(username: str, summary: dict, transcript: list | None = None) -> bytes | None:
    """Branded multi-element PDF: black cover (logo top-right) + content with
    Poppins/Prompt fonts, accent palette, key-numbers table & bar chart, and a
    full chat-history + data appendix when `transcript` is provided."""
    try:
        _ensure_fonts()
        from reportlab.lib.pagesizes import A4
        from reportlab.lib.units import mm
        from reportlab.lib import colors
        from reportlab.lib.styles import ParagraphStyle
        from reportlab.lib.enums import TA_LEFT
        from reportlab.lib.utils import ImageReader
        from reportlab.platypus import (
            BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer,
            Table, TableStyle, ListFlowable, ListItem, PageBreak, NextPageTemplate,
        )

        HEAD = "Poppins-Bold"
        SUBH = "Poppins-SemiBold"
        BODY = "Prompt"
        BODYM = "Prompt-Medium"
        if not _FONTS_READY:
            HEAD = SUBH = "Helvetica-Bold"; BODY = BODYM = "Helvetica"

        ink = colors.HexColor(_PAL["ink"]); mute = colors.HexColor(_PAL["mute"])
        rule = colors.HexColor(_PAL["rule"]); teal = colors.HexColor(_PAL["teal"])
        magenta = colors.HexColor(_PAL["magenta"]); pink = colors.HexColor(_PAL["pink"])
        yellow = colors.HexColor(_PAL["yellow"]); panel = colors.HexColor(_PAL["panel"])
        grey = colors.HexColor(_PAL["grey"])

        buf = io.BytesIO()
        W, Hh = A4
        now = datetime.datetime.now()
        territory = summary.get("territory") or ""

        # ---- COVER page painter (black background, logogram + logo) ----
        def _cover(canvas, doc):
            from reportlab.pdfbase.pdfmetrics import stringWidth
            canvas.saveState()
            canvas.setFillColor(colors.HexColor("#101012"))
            canvas.rect(0, 0, W, Hh, fill=1, stroke=0)
            left = 22 * mm
            content_w = W - 2 * left

            # ---- large IOH logogram (replaces the bubble circles), bottom-left, subtle ----
            try:
                if os.path.exists(_LOGOGRAM):
                    g = ImageReader(_LOGOGRAM)
                    gw = 78 * mm; gh = gw  # square logogram
                    canvas.setFillAlpha(0.10)
                    canvas.drawImage(g, left - 10*mm, 24*mm, gw, gh,
                                     mask="auto", preserveAspectRatio=True)
                    canvas.setFillAlpha(1)
            except Exception:
                pass

            # ---- IOH color logo top-right (enlarged ~30%: 46mm -> 60mm) ----
            try:
                if os.path.exists(_LOGO):
                    img = ImageReader(_LOGO)
                    iw, ih = img.getSize(); ar = ih / iw
                    lw = 60 * mm; lh = lw * ar
                    canvas.drawImage(img, W - left - lw, Hh - 22*mm - lh, lw, lh,
                                     mask="auto", preserveAspectRatio=True)
            except Exception:
                pass

            # ---- eyebrow = "Executive Summary" (smaller, secondary) ----
            base_y = Hh * 0.50
            canvas.setFillColor(colors.HexColor("#32BCAD"))
            canvas.setFont(SUBH, 13)
            canvas.drawString(left, base_y + 14*mm, "EXECUTIVE SUMMARY")

            # ---- MAIN title = generated title (auto-wrap + auto-resize) ----
            ttl = (summary.get("title") or "Ringkasan Analisa").strip()
            # pick a font size that fits within ~2-3 wrapped lines
            def _wrap(text, font, size, max_w):
                words = text.split()
                lines, cur = [], ""
                for w in words:
                    trial = (cur + " " + w).strip()
                    if stringWidth(trial, font, size) <= max_w:
                        cur = trial
                    else:
                        if cur:
                            lines.append(cur)
                        cur = w
                if cur:
                    lines.append(cur)
                return lines
            size = 38
            while size >= 20:
                lines = _wrap(ttl, HEAD, size, content_w)
                if len(lines) <= 3:
                    break
                size -= 2
            lines = lines[:3]
            canvas.setFillColor(colors.white)
            canvas.setFont(HEAD, size)
            line_h = size * 1.16
            ty = base_y
            for ln in lines:
                canvas.drawString(left, ty, ln)
                ty -= line_h

            # ---- territory chip below the title ----
            if territory:
                canvas.setFillColor(colors.HexColor("#FFCB05"))
                canvas.setFont(SUBH, 13)
                canvas.drawString(left, ty - 3*mm, territory)

            # ---- "Business Planning Circle Java" — enlarged tagline ----
            canvas.setFillColor(colors.HexColor("#C9C9CC"))
            canvas.setFont(SUBH, 17)
            canvas.drawString(left, ty - 16*mm, "Business Planning Circle Java")

            # ---- bottom meta strip ----
            canvas.setStrokeColor(colors.HexColor("#3A3A3E")); canvas.setLineWidth(0.8)
            canvas.line(left, 22*mm, W - left, 22*mm)
            canvas.setFillColor(colors.HexColor("#9A9A9C")); canvas.setFont(BODY, 9)
            canvas.drawString(left, 16*mm, f"Bizplan Java Agent · Prepared for {username}")
            canvas.drawRightString(W - left, 16*mm, now.strftime("%d %B %Y · %H:%M"))
            canvas.setFillColor(colors.HexColor("#6A6A6C")); canvas.setFont(BODY, 7.5)
            canvas.drawString(left, 11*mm, "Confidential & Internal Use Only · Do Not Capture & Share")
            canvas.restoreState()

        # ---- CONTENT page chrome (light) ----
        def _content(canvas, doc):
            canvas.saveState()
            # slim ink header bar with a NARROW vertical teal accent bar at the left
            canvas.setFillColor(ink); canvas.rect(0, Hh - 16*mm, W, 16*mm, fill=1, stroke=0)
            canvas.setFillColor(teal); canvas.rect(0, Hh - 16*mm, 6*mm, 16*mm, fill=1, stroke=0)
            canvas.setFillColor(colors.white); canvas.setFont(SUBH, 11)
            canvas.drawString(14*mm, Hh - 10.5*mm, "BIZPLAN JAVA AGENT")
            canvas.setFont(BODY, 8); canvas.setFillColor(colors.HexColor("#C9C9CC"))
            canvas.drawRightString(W - 18*mm, Hh - 10.5*mm, "Executive Summary")
            # footer
            canvas.setStrokeColor(rule); canvas.setLineWidth(0.7)
            canvas.line(18*mm, 13*mm, W - 18*mm, 13*mm)
            canvas.setFillColor(mute); canvas.setFont(BODY, 7.5)
            canvas.drawString(18*mm, 9*mm, "Confidential & Internal Use Only · Do Not Capture & Share")
            canvas.drawRightString(W - 18*mm, 9*mm, f"Page {doc.page - 1}")
            canvas.restoreState()

        doc = BaseDocTemplate(buf, pagesize=A4, leftMargin=18*mm, rightMargin=18*mm,
                              topMargin=22*mm, bottomMargin=16*mm)
        cover_frame = Frame(0, 0, W, Hh, id="cover", leftPadding=0, rightPadding=0,
                            topPadding=0, bottomPadding=0)
        content_frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="c")
        doc.addPageTemplates([
            PageTemplate(id="cover", frames=[cover_frame], onPage=_cover),
            PageTemplate(id="content", frames=[content_frame], onPage=_content),
        ])

        h_title = ParagraphStyle("t", fontName=HEAD, fontSize=19, textColor=ink,
                                 spaceAfter=4, leading=23)
        eyebrow = ParagraphStyle("eb", fontName=SUBH, fontSize=10.5, textColor=teal,
                                 spaceBefore=14, spaceAfter=5, leading=13)
        body = ParagraphStyle("b", fontName=BODY, fontSize=10.5, textColor=ink,
                              leading=15, alignment=TA_LEFT)
        ov = ParagraphStyle("ov", parent=body, textColor=grey, fontSize=11, leading=16,
                            spaceAfter=6)
        bullet = ParagraphStyle("bl", parent=body, leftIndent=2, spaceAfter=3)

        story = [NextPageTemplate("content"), PageBreak()]  # page 1 = cover
        story.append(Paragraph(summary.get("title", "Ringkasan Analisa"), h_title))
        if territory:
            story.append(Paragraph(territory, ParagraphStyle("terr", fontName=SUBH,
                         fontSize=11, textColor=magenta, spaceAfter=6)))
        if summary.get("overview"):
            story.append(Paragraph(summary["overview"], ov))

        # Key numbers table
        kn = summary.get("key_numbers", [])
        if kn:
            story.append(Paragraph("KEY NUMBERS", eyebrow))
            data = [["Metric", "Value", "Note"]]
            for nrow in kn:
                data.append([nrow.get("label", ""), nrow.get("value", ""), nrow.get("note", "")])
            t = Table(data, colWidths=[58*mm, 42*mm, 74*mm])
            ts = [
                ("FONTNAME", (0, 0), (-1, 0), SUBH), ("FONTSIZE", (0, 0), (-1, 0), 8.5),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("BACKGROUND", (0, 0), (-1, 0), ink),
                ("FONTNAME", (0, 1), (-1, -1), BODY), ("FONTSIZE", (0, 1), (-1, -1), 9.5),
                ("TEXTCOLOR", (0, 1), (-1, -1), ink),
                ("FONTNAME", (1, 1), (1, -1), SUBH), ("TEXTCOLOR", (1, 1), (1, -1), teal),
                ("LINEBELOW", (0, 1), (-1, -1), 0.5, rule),
                ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, panel]),
            ]
            t.setStyle(TableStyle(ts))
            story.append(t)
            # bar chart of key numbers
            chart = _chart_keynumbers(summary, doc.width, 60*mm)
            if chart is not None:
                story.append(Paragraph("KEY NUMBERS — VISUAL", eyebrow))
                story.append(chart)

        def add_section(label, items, accent):
            if not items:
                return
            story.append(Paragraph(label.upper(),
                         ParagraphStyle("e", parent=eyebrow, textColor=accent)))
            story.append(ListFlowable(
                [ListItem(Paragraph(str(x), bullet), leftIndent=10, value="•",
                          bulletColor=accent) for x in items],
                bulletType="bullet", start="•"))

        add_section("Key Points", summary.get("key_points", []), teal)
        add_section("Findings", summary.get("findings", []), magenta)
        add_section("Insights", summary.get("insights", []), pink)
        add_section("Action Items / Key To-Do", summary.get("action_items", []), colors.HexColor("#B8860B"))

        story.append(Spacer(1, 8*mm))
        story.append(Paragraph(
            f"Generated by Bizplan Java Agent (Analyst) for {username} · {now.strftime('%d %b %Y %H:%M')}.",
            ParagraphStyle("ft", fontName=BODY, fontSize=8, textColor=mute)))

        doc.build(story)
        return buf.getvalue()
    except Exception as e:
        log.error(f"PDF build failed: {e}")
        import traceback; log.error(traceback.format_exc())
        return None


def send_executive_summary(to: str, username: str, summary: dict,
                           transcript: list | None = None) -> bool:
    """Send an AI executive summary email with a branded PDF attachment.
    When `transcript` is provided, the PDF appends the full chat history + data.
    Returns True only if the email was actually accepted by the SMTP server."""
    html = _summary_email_html(username, summary, transcript=transcript)
    pdf = _build_summary_pdf(username, summary, transcript=transcript)
    title = summary.get("title", "Executive Summary")
    subject = f"Bizplan Java Agent — {title}"[:120]
    pdf_name = "Bizplan_Summary_" + datetime.datetime.now().strftime("%Y%m%d_%H%M") + ".pdf"
    try:
        return _send_with_pdf(to, subject, html, pdf_bytes=pdf, pdf_name=pdf_name)
    except Exception as e:
        log.error(f"send_executive_summary failed to {to}: {e}")
        return False
