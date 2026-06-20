"""Export agent — generates branded XLSX and PDF reports from query results.

Design-aware features:
- Auto chart selection: bar (comparison), line (time series), pie (composition)
- Smart number formatting: thousands separator, %, currency
- Column type detection for alignment and formatting
- XLSX: openpyxl with IOH red/dark branding, auto-width, embedded charts
- PDF:  reportlab with IOH header/footer, table, and summary paragraph
"""
import io
import re
import datetime
from typing import Any

# ---- Column type detection ----

# Patterns for column classification
_TIME_COLS = re.compile(
    r"(^dt_id$|^date$|^month_id$|^month$|^week$|^year$|^period|^bulan|^tanggal|_date$|_dt$|_month$|_mth$|_dly$|_wly$)",
    re.IGNORECASE,
)
_PCT_COLS = re.compile(
    r"(^ms_|^pct_|^share_|_pct$|_share$|_rate$|_ratio$|percent|market_share|churn_rate|success_rate)",
    re.IGNORECASE,
)
_CURRENCY_COLS = re.compile(
    r"(^rev_|^revenue|^arpu|^price|^cost|^spend|_rev$|_revenue$|_arpu$|_price$)",
    re.IGNORECASE,
)
_COUNT_COLS = re.compile(
    r"(^total_|^count_|^cnt_|^sum_|^rgu_|^subs_|^site_|^ga_|^soga_|_count$|_total$|_rgu$|_subs$|_sites$|row_count)",
    re.IGNORECASE,
)
_GEO_COLS = re.compile(
    r"(^region$|^circle$|^branch$|^kec|^kabkota$|^kab_|^province|^area$|^zone$|^desa$|^village)",
    re.IGNORECASE,
)
_LABEL_COLS = re.compile(
    r"(^name$|^label$|^brand$|^operator$|^tier$|^segment$|^type$|^category$|^status$|^description)",
    re.IGNORECASE,
)


def _classify_col(col: str, sample_vals: list) -> str:
    """Classify a column as: time, pct, currency, count, geo, label, or number."""
    if _TIME_COLS.search(col):
        return "time"
    if _PCT_COLS.search(col):
        return "pct"
    if _CURRENCY_COLS.search(col):
        return "currency"
    if _COUNT_COLS.search(col):
        return "count"
    if _GEO_COLS.search(col):
        return "geo"
    if _LABEL_COLS.search(col):
        return "label"
    # infer from values
    numerics = [v for v in sample_vals if isinstance(v, (int, float))]
    if len(numerics) > len(sample_vals) * 0.6:
        # check if all values are 0-1 or 0-100 range → likely pct
        if numerics and all(0 <= abs(v) <= 1.05 for v in numerics):
            return "pct"
        return "number"
    return "label"


def _detect_chart_type(columns: list[str], rows: list[dict], col_types: dict[str, str]) -> str:
    """Pick the best chart type: bar, line, pie, or none."""
    if len(rows) < 2 or len(columns) < 2:
        return "none"

    has_time = any(t == "time" for t in col_types.values())
    num_cols = [c for c in columns if col_types.get(c) in ("number", "count", "currency", "pct")]
    label_cols = [c for c in columns if col_types.get(c) in ("label", "geo")]
    n_rows = len(rows)

    # time series → line
    if has_time and num_cols:
        return "line"
    # few categories (≤12) with numeric → bar
    if label_cols and num_cols and n_rows <= 20:
        # single numeric + few categories → pie candidate
        if len(num_cols) == 1 and n_rows <= 8:
            return "pie"
        return "bar"
    # many rows, no obvious pattern → bar (capped)
    if num_cols and n_rows <= 30:
        return "bar"
    return "none"


# ---- XLSX number formats ----

_XLSX_FMT = {
    "pct":      '0.0%',
    "currency": '#,##0',
    "count":    '#,##0',
    "number":   '#,##0.00',
}


# ---- XLSX via openpyxl ----

def export_xlsx(
    columns: list[str],
    rows: list[dict[str, Any]],
    title: str = "Query Result",
    sql: str = "",
    explanation: str = "",
    domain: str = "",
) -> bytes:
    """Return an in-memory .xlsx workbook as bytes with auto charts."""
    from openpyxl import Workbook
    from openpyxl.styles import Font, PatternFill, Alignment, Border, Side, numbers
    from openpyxl.utils import get_column_letter
    from openpyxl.chart import BarChart as XlBarChart, LineChart as XlLineChart, PieChart as XlPieChart, Reference

    wb = Workbook()
    ws = wb.active
    ws.title = "Data"

    # IOH brand colours
    RED = "ED1C24"
    DARK = "1A1A1B"
    TEAL = "32BCAD"
    WHITE_F = Font(color="FFFFFF", bold=True, size=11)
    RED_FILL = PatternFill("solid", fgColor=RED)
    DARK_FILL = PatternFill("solid", fgColor=DARK)
    TEAL_FILL = PatternFill("solid", fgColor=TEAL)
    THIN = Side(style="thin", color="333333")
    BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)

    # -- Classify columns --
    sample = rows[:20]
    col_types = {}
    for col in columns:
        vals = [r.get(col) for r in sample if r.get(col) is not None]
        col_types[col] = _classify_col(col, vals)

    # -- Title row (merged) --
    merge_end = max(len(columns), 3)
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=merge_end)
    title_cell = ws.cell(row=1, column=1, value=f"IOH Java Analyst — {title}")
    title_cell.font = Font(color="FFFFFF", bold=True, size=14)
    title_cell.fill = DARK_FILL
    title_cell.alignment = Alignment(horizontal="left", vertical="center")
    ws.row_dimensions[1].height = 36

    # Meta rows
    meta = [
        ("Domain", domain or "—"),
        ("Generated", datetime.datetime.now().strftime("%Y-%m-%d %H:%M")),
        ("Rows", str(len(rows))),
    ]
    if explanation:
        meta.append(("Explanation", explanation))
    for ri, (k, v) in enumerate(meta, start=2):
        ws.cell(row=ri, column=1, value=k).font = Font(bold=True, size=10, color="666666")
        ws.cell(row=ri, column=2, value=v).font = Font(size=10)

    header_row = len(meta) + 3  # leave a blank row

    # SQL row (optional)
    if sql:
        sql_row = header_row - 1
        ws.merge_cells(start_row=sql_row, start_column=1, end_row=sql_row, end_column=merge_end)
        c = ws.cell(row=sql_row, column=1, value=sql[:2000])
        c.font = Font(size=8, color="888888", italic=True)
        c.alignment = Alignment(wrap_text=True)

    # -- Header --
    for ci, col_name in enumerate(columns, start=1):
        c = ws.cell(row=header_row, column=ci, value=col_name)
        c.font = WHITE_F
        c.fill = RED_FILL
        c.alignment = Alignment(horizontal="center")
        c.border = BORDER

    # -- Data rows with smart formatting --
    for ri, row in enumerate(rows, start=header_row + 1):
        for ci, col_name in enumerate(columns, start=1):
            val = row.get(col_name)
            c = ws.cell(row=ri, column=ci, value=val)
            c.border = BORDER

            ct = col_types.get(col_name, "label")
            if isinstance(val, (int, float)):
                c.alignment = Alignment(horizontal="right")
                fmt = _XLSX_FMT.get(ct)
                if fmt:
                    c.number_format = fmt
            else:
                c.alignment = Alignment(horizontal="left")

            # alternate row stripe
            if (ri - header_row) % 2 == 0:
                c.fill = PatternFill("solid", fgColor="F5F5F5")

    # auto-width columns
    for ci, col_name in enumerate(columns, start=1):
        max_len = len(str(col_name))
        for ri in range(header_row + 1, header_row + 1 + min(len(rows), 50)):
            cell_val = ws.cell(row=ri, column=ci).value
            if cell_val is not None:
                max_len = max(max_len, len(str(cell_val)))
        ws.column_dimensions[get_column_letter(ci)].width = min(max_len + 4, 45)

    # Freeze header
    ws.freeze_panes = ws.cell(row=header_row + 1, column=1)

    # -- Auto chart --
    chart_type = _detect_chart_type(columns, rows, col_types)
    if chart_type != "none" and len(rows) >= 2:
        _add_xlsx_chart(ws, columns, rows, col_types, chart_type,
                        header_row, title, RED, TEAL, DARK)

    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


def _add_xlsx_chart(ws, columns, rows, col_types, chart_type,
                    header_row, title, red_hex, teal_hex, dark_hex):
    """Insert an auto-selected chart into the XLSX worksheet."""
    from openpyxl.chart import BarChart as XlBarChart, LineChart as XlLineChart
    from openpyxl.chart import PieChart as XlPieChart, Reference
    from openpyxl.chart.series import DataPoint
    from openpyxl.chart.label import DataLabelList

    num_cols = [c for c in columns if col_types.get(c) in ("number", "count", "currency", "pct")]
    label_cols = [c for c in columns if col_types.get(c) in ("label", "geo", "time")]

    if not num_cols:
        return

    # Use first label column for categories, first numeric for values
    cat_col = label_cols[0] if label_cols else columns[0]
    val_col = num_cols[0]
    cat_ci = columns.index(cat_col) + 1
    val_ci = columns.index(val_col) + 1
    data_end = header_row + len(rows)

    cats = Reference(ws, min_col=cat_ci, min_row=header_row, max_row=data_end)
    vals = Reference(ws, min_col=val_ci, min_row=header_row, max_row=data_end)

    # IOH palette for chart series
    ioh_palette = [red_hex, teal_hex, "EC008C", "FFCB05", "C6168D", "9A9A9C"]

    chart_row = data_end + 2
    chart_anchor = f"A{chart_row}"

    if chart_type == "pie":
        chart = XlPieChart()
        chart.title = f"{val_col} by {cat_col}"
        chart.add_data(vals, titles_from_data=True)
        chart.set_categories(cats)
        chart.width = 18
        chart.height = 12
        chart.style = 10
        # color slices
        for i in range(min(len(rows), len(ioh_palette))):
            pt = DataPoint(idx=i)
            pt.graphicalProperties.solidFill = ioh_palette[i]
            chart.series[0].data_points.append(pt)
        chart.series[0].dLbls = DataLabelList()
        chart.series[0].dLbls.showPercent = True

    elif chart_type == "line":
        chart = XlLineChart()
        chart.title = f"{val_col} over {cat_col}"
        chart.add_data(vals, titles_from_data=True)
        chart.set_categories(cats)
        chart.width = 22
        chart.height = 12
        chart.y_axis.title = val_col
        chart.x_axis.title = cat_col
        chart.style = 10
        if chart.series:
            chart.series[0].graphicalProperties.line.solidFill = red_hex

        # add second numeric if available
        if len(num_cols) > 1:
            val2_ci = columns.index(num_cols[1]) + 1
            vals2 = Reference(ws, min_col=val2_ci, min_row=header_row, max_row=data_end)
            chart.add_data(vals2, titles_from_data=True)
            if len(chart.series) > 1:
                chart.series[1].graphicalProperties.line.solidFill = teal_hex

    else:  # bar
        chart = XlBarChart()
        chart.type = "col"
        chart.grouping = "clustered"
        chart.title = f"{val_col} by {cat_col}"
        chart.add_data(vals, titles_from_data=True)
        chart.set_categories(cats)
        chart.width = 22
        chart.height = 12
        chart.y_axis.title = val_col
        chart.style = 10
        if chart.series:
            chart.series[0].graphicalProperties.solidFill = red_hex

        # add second numeric column if present
        if len(num_cols) > 1:
            val2_ci = columns.index(num_cols[1]) + 1
            vals2 = Reference(ws, min_col=val2_ci, min_row=header_row, max_row=data_end)
            chart.add_data(vals2, titles_from_data=True)
            if len(chart.series) > 1:
                chart.series[1].graphicalProperties.solidFill = teal_hex

    ws.add_chart(chart, chart_anchor)


# ---- PDF via reportlab ----

def export_pdf(
    columns: list[str],
    rows: list[dict[str, Any]],
    title: str = "Query Result",
    summary: str = "",
    sql: str = "",
    explanation: str = "",
    domain: str = "",
) -> bytes:
    """Return an in-memory PDF as bytes."""
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import A4, landscape
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib.units import mm
    from reportlab.platypus import (
        SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer,
    )

    # Classify columns for formatting
    sample = rows[:20]
    col_types = {}
    for col in columns:
        vals = [r.get(col) for r in sample if r.get(col) is not None]
        col_types[col] = _classify_col(col, vals)

    buf = io.BytesIO()
    page = landscape(A4) if len(columns) > 5 else A4
    doc = SimpleDocTemplate(buf, pagesize=page,
                            topMargin=25 * mm, bottomMargin=20 * mm,
                            leftMargin=15 * mm, rightMargin=15 * mm)

    styles = getSampleStyleSheet()
    ioh_red = colors.HexColor("#ED1C24")
    ioh_dark = colors.HexColor("#1A1A1B")

    # custom styles
    title_style = ParagraphStyle(
        "IOHTitle", parent=styles["Heading1"],
        fontSize=16, textColor=ioh_red, spaceAfter=4,
    )
    sub_style = ParagraphStyle(
        "IOHSub", parent=styles["Normal"],
        fontSize=9, textColor=colors.grey,
    )
    body_style = ParagraphStyle(
        "IOHBody", parent=styles["Normal"],
        fontSize=9, leading=13,
    )
    sql_style = ParagraphStyle(
        "IOHSQL", parent=styles["Code"],
        fontSize=7, textColor=colors.grey, leading=9,
    )

    elements: list = []

    # Header
    elements.append(Paragraph(f"IOH Java Analyst — {title}", title_style))
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
    elements.append(Paragraph(
        f"Domain: {domain or '—'} &nbsp;|&nbsp; Generated: {now} &nbsp;|&nbsp; Rows: {len(rows)}",
        sub_style,
    ))
    elements.append(Spacer(1, 6 * mm))

    # Summary paragraph
    if summary:
        elements.append(Paragraph(summary.replace("\n", "<br/>"), body_style))
        elements.append(Spacer(1, 4 * mm))

    # Explanation
    if explanation:
        elements.append(Paragraph(f"<b>Computation:</b> {explanation}", body_style))
        elements.append(Spacer(1, 3 * mm))

    # SQL
    if sql:
        elements.append(Paragraph(f"SQL: {sql[:800]}", sql_style))
        elements.append(Spacer(1, 3 * mm))

    # Table (cap at 200 rows for PDF readability)
    display_rows = rows[:200]
    table_data = [columns]
    for row in display_rows:
        table_data.append([_fmt_pdf(row.get(c), col_types.get(c, "label")) for c in columns])

    # dynamic column widths — give numeric cols less width, labels more
    avail = page[0] - 30 * mm
    ncol = len(columns)
    if ncol:
        weights = []
        for c in columns:
            ct = col_types.get(c, "label")
            if ct in ("label", "geo"):
                weights.append(2.0)
            elif ct == "time":
                weights.append(1.5)
            else:
                weights.append(1.0)
        total_w = sum(weights)
        col_widths = [avail * (w / total_w) for w in weights]
        # cap max
        col_widths = [min(cw, 70 * mm) for cw in col_widths]
    else:
        col_widths = [avail]

    # Alignment per column
    num_types = {"pct", "currency", "count", "number"}
    style_cmds = [
        ("BACKGROUND", (0, 0), (-1, 0), ioh_red),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTSIZE", (0, 0), (-1, 0), 8),
        ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
        ("FONTSIZE", (0, 1), (-1, -1), 7),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F5F5F5")]),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#CCCCCC")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    # right-align numeric columns
    for ci, c in enumerate(columns):
        if col_types.get(c) in num_types:
            style_cmds.append(("ALIGN", (ci, 1), (ci, -1), "RIGHT"))

    t = Table(table_data, colWidths=col_widths, repeatRows=1)
    t.setStyle(TableStyle(style_cmds))
    elements.append(t)

    if len(rows) > 200:
        elements.append(Spacer(1, 3 * mm))
        elements.append(Paragraph(
            f"<i>Menampilkan 200 dari {len(rows)} baris. Download XLSX untuk data lengkap.</i>",
            sub_style,
        ))

    # Footer
    elements.append(Spacer(1, 8 * mm))
    elements.append(Paragraph(
        "Confidential — Internal Use Only — Indosat Ooredoo Hutchison",
        ParagraphStyle("footer", parent=sub_style, alignment=1, textColor=colors.grey),
    ))

    doc.build(elements)
    return buf.getvalue()


def _fmt_pdf(v: Any, col_type: str = "label") -> str:
    """Format a cell value for PDF rendering, type-aware."""
    if v is None:
        return "—"
    if isinstance(v, float):
        if col_type == "pct":
            # values 0-1 → multiply, values > 1 → as-is
            pv = v * 100 if abs(v) <= 1.05 else v
            return f"{pv:.1f}%"
        if col_type == "currency":
            if abs(v) >= 1_000_000_000:
                return f"{v / 1_000_000_000:,.1f}B"
            if abs(v) >= 1_000_000:
                return f"{v / 1_000_000:,.1f}M"
            return f"{v:,.0f}"
        if col_type == "count":
            return f"{v:,.0f}"
        if abs(v) >= 1_000_000:
            return f"{v:,.0f}"
        if v == int(v):
            return f"{int(v):,}"
        return f"{v:,.2f}"
    if isinstance(v, int):
        return f"{v:,}"
    return str(v)


# Backward compat alias
_fmt = _fmt_pdf
