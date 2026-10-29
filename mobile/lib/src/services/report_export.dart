// Report files built on the device: a branded PDF of the live performance
// report (or of an agent answer) and a multi-sheet XLSX of the raw numbers.
// Mirrors the web's Laporan page (frontend/src/app/reports, lib/xlsx.ts).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../ui/chart.dart' show formatValue, idNum, shortNum, toNum, humanize;

/// One worksheet: header row from [columns], values from [rows].
class Sheet {
  const Sheet(this.name, this.columns, this.rows);
  final String name;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
}

/// An agent answer saved to Laporan (the "Ad-hoc" filter).
class AdhocReport {
  AdhocReport({required this.id, required this.title, required this.columns, required this.rows, required this.savedAt, this.format = 'XLSX'});
  final String id, title;

  /// The format it was last exported as (shown on the Laporan row).
  final String format;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final DateTime savedAt;

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'columns': columns, 'rows': rows, 'saved_at': savedAt.toIso8601String(), 'format': format};

  static AdhocReport fromJson(Map<String, dynamic> j) => AdhocReport(
        id: j['id'].toString(),
        title: j['title'].toString(),
        columns: (j['columns'] as List).map((e) => e.toString()).toList(),
        rows: (j['rows'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList(),
        savedAt: DateTime.tryParse(j['saved_at'].toString()) ?? DateTime.now(),
        format: (j['format'] ?? 'XLSX').toString(),
      );
}

/// Agent answers exported from the chat, kept per user on the device.
class AdhocStore {
  static const _max = 30;
  static String get _key => 'adhoc_reports::${AuthState.user?['username'] ?? 'anon'}';

  static Future<List<AdhocReport>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(AdhocReport.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<AdhocReport> add(String title, List<String> columns, List<Map<String, dynamic>> rows) async {
    final r = AdhocReport(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      columns: columns,
      rows: rows.take(5000).toList(),
      savedAt: DateTime.now(),
    );
    await _save([r, ...await load()].take(_max).toList());
    return r;
  }

  static Future<void> remove(String id) async => _save((await load()).where((e) => e.id != id).toList());

  static Future<void> setFormat(String id, String format) async => _save([
        for (final e in await load())
          e.id == id ? AdhocReport(id: e.id, title: e.title, columns: e.columns, rows: e.rows, savedAt: e.savedAt, format: format) : e,
      ]);

  static Future<void> _save(List<AdhocReport> all) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }
}

// ── XLSX ──

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');

String _col(int i) {
  var s = '';
  for (i += 1; i > 0; i = (i - 1) ~/ 26) {
    s = String.fromCharCode(65 + (i - 1) % 26) + s;
  }
  return s;
}

String _cell(String ref, dynamic v, [int style = 0]) {
  final st = style > 0 ? ' s="$style"' : '';
  if (v is num && v.isFinite) return '<c r="$ref"$st><v>$v</v></c>';
  if (v == null || v == '') return '';
  return '<c r="$ref" t="inlineStr"$st><is><t xml:space="preserve">${_esc(v.toString())}</t></is></c>';
}

/// A minimal .xlsx with a styled, frozen header row on every sheet.
Uint8List buildXlsx(List<Sheet> sheets) {
  const xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';
  const ns = 'http://schemas.openxmlformats.org';
  final archive = Archive();
  void add(String name, String content) => archive.addFile(ArchiveFile.string(name, content));

  add('[Content_Types].xml', '$xml<Types xmlns="$ns/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '${[for (var i = 1; i <= sheets.length; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>');
  add('_rels/.rels', '$xml<Relationships xmlns="$ns/package/2006/relationships">'
      '<Relationship Id="rId1" Type="$ns/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
  final used = <String>{};
  final names = [
    for (final s in sheets)
      () {
        var n = s.name.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ');
        n = n.length > 31 ? n.substring(0, 31) : n;
        while (!used.add(n)) {
          n = '${n.length > 28 ? n.substring(0, 28) : n} ${used.length}';
        }
        return n;
      }(),
  ];
  add('xl/workbook.xml', '$xml<workbook xmlns="$ns/spreadsheetml/2006/main" xmlns:r="$ns/officeDocument/2006/relationships"><sheets>'
      '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(names[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}</sheets></workbook>');
  add('xl/_rels/workbook.xml.rels', '$xml<Relationships xmlns="$ns/package/2006/relationships">'
      '${[for (var i = 0; i < sheets.length; i++) '<Relationship Id="rId${i + 1}" Type="$ns/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
      '<Relationship Id="rId${sheets.length + 1}" Type="$ns/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>');
  add('xl/styles.xml', '$xml<styleSheet xmlns="$ns/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts><fills count="3"><fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF0E8579"/></patternFill></fill></fills>'
      '<borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf/>'
      '<xf fontId="1" fillId="2" applyFont="1" applyFill="1"/></cellXfs></styleSheet>');
  for (var si = 0; si < sheets.length; si++) {
    final s = sheets[si];
    final head = '<row r="1">${[for (var i = 0; i < s.columns.length; i++) _cell('${_col(i)}1', s.columns[i], 1)].join()}</row>';
    final body = StringBuffer();
    for (var ri = 0; ri < s.rows.length; ri++) {
      body.write('<row r="${ri + 2}">');
      for (var i = 0; i < s.columns.length; i++) {
        body.write(_cell('${_col(i)}${ri + 2}', s.rows[ri][s.columns[i]]));
      }
      body.write('</row>');
    }
    final widths = [
      for (var i = 0; i < s.columns.length; i++)
        '<col min="${i + 1}" max="${i + 1}" width="${math.min(48, s.rows.take(200).fold<int>(s.columns[i].length, (m, r) => math.max(m, (r[s.columns[i]] ?? '').toString().length)) + 2)}" customWidth="1"/>',
    ].join();
    add('xl/worksheets/sheet${si + 1}.xml', '$xml<worksheet xmlns="$ns/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>'
        '${widths.isEmpty ? '' : '<cols>$widths</cols>'}<sheetData>$head$body</sheetData></worksheet>');
  }
  return ZipEncoder().encodeBytes(archive);
}

// ── Live performance report ──

String _title(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ')
    .replaceAll('Diy', 'DIY');

String _kpi(Map k, dynamic v) {
  final n = toNum(v);
  if (n == null) return '–';
  return switch (k['format']) {
    'currency' => formatValue(n, 'currency'),
    'gb' => n >= 1e6 ? '${idNum(n / 1e6, 1)} PB' : n >= 1e3 ? '${idNum(n / 1e3, 1)} TB' : '${idNum(n, 1)} GB',
    'percent' => '${idNum(n, 2)}%',
    _ => shortNum(n),
  };
}

String _delta(dynamic v, [String? unit]) {
  final n = toNum(v);
  if (n == null) return '';
  return '${n >= 0 ? '+' : '−'}${idNum(n.abs(), unit == 'pp' ? 2 : 1)}${unit == 'pp' ? ' pp' : '%'}';
}

/// Sheets of the live report: KPIs, per-region performance and monthly revenue.
List<Sheet> overviewSheets(Map<String, dynamic> ov) {
  final kpis = ((ov['kpis'] as List?) ?? const []).cast<Map>();
  final regions = ((ov['regions'] as List?) ?? const []).cast<Map>();
  final rr = (ov['revenue_by_region'] as Map?) ?? const {};
  final labels = ((rr['labels'] as List?) ?? const []).map((e) => e.toString()).toList();
  final targets = ov['has_targets'] == true;
  return [
    Sheet('KPI', const ['indikator', 'nilai', 'bulan_lalu', 'perubahan', 'satuan_perubahan'], [
      for (final k in kpis)
        {'indikator': k['label'], 'nilai': toNum(k['value']), 'bulan_lalu': toNum(k['prev']), 'perubahan': toNum(k['pct_change']),
            'satuan_perubahan': k['change_unit'] ?? '%'},
    ]),
    Sheet('Performa region', [
      'region', 'revenue', 'mom_pct', 'pelanggan_rgu90', 'payload_gb', 'availability_4g', targets ? 'pencapaian_target_pct' : 'kontribusi_pct',
    ], [
      for (final r in regions)
        {
          'region': _title(r['region'].toString()), 'revenue': toNum(r['revenue']), 'mom_pct': toNum(r['mom_pct']),
          'pelanggan_rgu90': toNum(r['subs']), 'payload_gb': toNum(r['payload_gb']), 'availability_4g': toNum(r['availability']),
          targets ? 'pencapaian_target_pct' : 'kontribusi_pct': toNum(targets ? r['achievement_pct'] : r['share_pct']),
        },
    ]),
    Sheet('Revenue bulanan', ['bulan', ...((rr['series'] as List?) ?? const []).cast<Map>().map((s) => _title(s['name'].toString()))], [
      for (var i = 0; i < labels.length; i++)
        {
          'bulan': labels[i],
          for (final s in ((rr['series'] as List?) ?? const []).cast<Map>()) _title(s['name'].toString()): toNum((s['values'] as List)[i]),
        },
    ]),
  ];
}

/// Sheets of an agent answer: the rows, per-column statistics and where it came from.
List<Sheet> adhocSheets(AdhocReport a) {
  final numeric = [
    for (final c in a.columns)
      if (a.rows.isNotEmpty && a.rows.every((r) => r[c] == null || toNum(r[c]) != null) && a.rows.any((r) => toNum(r[c]) != null)) c,
  ];
  return [
    Sheet('Hasil', a.columns, a.rows),
    Sheet('Ringkasan', const ['kolom', 'jumlah', 'rata_rata', 'minimum', 'maksimum'], [
      for (final c in numeric)
        () {
          final v = a.rows.map((r) => toNum(r[c])).whereType<double>().toList();
          final sum = v.fold<double>(0, (s, x) => s + x);
          return {'kolom': c, 'jumlah': sum, 'rata_rata': v.isEmpty ? null : sum / v.length, 'minimum': v.reduce(math.min), 'maksimum': v.reduce(math.max)};
        }(),
    ]),
    Sheet('Info', const ['keterangan', 'nilai'], [
      {'keterangan': 'Pertanyaan', 'nilai': a.title},
      {'keterangan': 'Disimpan', 'nilai': a.savedAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ')},
      {'keterangan': 'Jumlah baris', 'nilai': a.rows.length},
      {'keterangan': 'Sumber', 'nilai': 'Bizplan Java Agent (BigQuery)'},
    ]),
  ];
}

// ── PDF ──

const _teal = PdfColor.fromInt(0xFF0E8579);
const _tealDark = PdfColor.fromInt(0xFF074D45);
const _teal50 = PdfColor.fromInt(0xFFE6F7F5);
const _ink = PdfColor.fromInt(0xFF0F1F1D);
const _text2 = PdfColor.fromInt(0xFF3D4C49);
const _mute = PdfColor.fromInt(0xFF5A6B68);
const _rule = PdfColor.fromInt(0xFFE1E9E7);
const _up = PdfColor.fromInt(0xFF1F7A3A);
const _down = PdfColor.fromInt(0xFFC42B2B);
const _series = [PdfColor.fromInt(0xFF0E8579), PdfColor.fromInt(0xFF5BCEC3), PdfColor.fromInt(0xFFF5A623), PdfColor.fromInt(0xFF2F6FDB)];

Future<pw.ThemeData> _theme() async {
  Future<pw.Font> f(String w) async => pw.Font.ttf(await rootBundle.load('assets/fonts/Poppins-$w.ttf'));
  return pw.ThemeData.withFont(base: await f('Regular'), bold: await f('SemiBold'));
}

Future<pw.MemoryImage?> _logo() async {
  try {
    return pw.MemoryImage((await rootBundle.load('assets/icon_circle.png')).buffer.asUint8List());
  } catch (_) {
    return null;
  }
}

pw.Widget _head(pw.MemoryImage? logo, String eyebrow, String heading) => pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      margin: const pw.EdgeInsets.only(bottom: 16),
      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule))),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(eyebrow.toUpperCase(), style: pw.TextStyle(fontSize: 8, color: _teal, fontWeight: pw.FontWeight.bold, letterSpacing: .8)),
            pw.SizedBox(height: 4),
            pw.Text(heading, style: pw.TextStyle(fontSize: 18, color: _ink, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
        if (logo != null) pw.Image(logo, width: 30, height: 30),
      ]),
    );

pw.Widget _footer(pw.Context c, String note) => pw.Row(children: [
      pw.Expanded(child: pw.Text(note, style: const pw.TextStyle(fontSize: 7, color: _mute))),
      pw.Text('${c.pageNumber} / ${c.pagesCount}', style: const pw.TextStyle(fontSize: 7, color: _mute)),
    ]);

pw.Widget _deltaText(dynamic v, [String? unit]) {
  final n = toNum(v);
  if (n == null) return pw.SizedBox();
  return pw.Text(_delta(n, unit), style: pw.TextStyle(fontSize: 8, color: n >= 0 ? _up : _down, fontWeight: pw.FontWeight.bold));
}

/// Grouped bars of revenue per region per month.
pw.Widget _bars(List<String> labels, List<(String, List<double>)> series) {
  final hi = series.expand((s) => s.$2).fold<double>(0, math.max);
  final top = hi <= 0 ? 1.0 : hi * 1.1;
  const h = 150.0;
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.SizedBox(
      height: h + 16,
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        for (var g = 0; g < labels.length; g++)
          pw.Expanded(
            child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                for (var s = 0; s < series.length; s++)
                  pw.Container(
                    width: 8,
                    height: math.max(1, h * series[s].$2[g] / top),
                    margin: const pw.EdgeInsets.symmetric(horizontal: 1),
                    decoration: pw.BoxDecoration(
                      color: _series[s % _series.length],
                      borderRadius: const pw.BorderRadius.only(topLeft: pw.Radius.circular(3), topRight: pw.Radius.circular(3)),
                    ),
                  ),
              ]),
              pw.Container(height: 1, color: _rule),
              pw.SizedBox(height: 4),
              pw.Text(labels[g], style: const pw.TextStyle(fontSize: 7, color: _mute)),
            ]),
          ),
      ]),
    ),
    pw.SizedBox(height: 8),
    pw.Wrap(spacing: 12, children: [
      for (var s = 0; s < series.length; s++)
        pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
          pw.Container(width: 7, height: 7, decoration: pw.BoxDecoration(color: _series[s % _series.length], shape: pw.BoxShape.circle)),
          pw.SizedBox(width: 4),
          pw.Text(series[s].$1, style: const pw.TextStyle(fontSize: 8, color: _text2)),
        ]),
    ]),
  ]);
}

/// The live performance report, as on the web's Laporan page.
Future<Uint8List> buildOverviewPdf(Map<String, dynamic> ov, String name) async {
  final theme = await _theme();
  final logo = await _logo();
  final scope = (ov['scope'] as Map?)?['region']?.toString();
  final heading = '${scope == null || scope.isEmpty ? 'Region Jawa' : _title(scope)} · ${ov['month_label'] ?? ''}';
  final kpis = ((ov['kpis'] as List?) ?? const []).cast<Map>();
  final regions = ((ov['regions'] as List?) ?? const []).cast<Map>();
  final rr = (ov['revenue_by_region'] as Map?) ?? const {};
  final labels = ((rr['labels'] as List?) ?? const []).map((e) => e.toString()).toList();
  final series = [
    for (final s in ((rr['series'] as List?) ?? const []).cast<Map>().take(4))
      (_title(s['name'].toString()), [for (final v in (s['values'] as List)) toNum(v) ?? 0.0]),
  ];
  final summary = ((ov['summary'] as Map?)?['text'] ?? '').toString();
  final targets = ov['has_targets'] == true;
  const note = 'Angka MTD dibandingkan bulan lalu. Sumber: BigQuery · Bizplan Java Agent.';

  final doc = pw.Document(theme: theme, title: name, author: 'Bizplan Java Agent');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
    footer: (c) => _footer(c, note),
    build: (c) => [
      _head(logo, name, heading),
      pw.Row(children: [
        for (final k in kpis)
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 6),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF5F9F8), borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(k['label'].toString(), style: const pw.TextStyle(fontSize: 8, color: _mute)),
                pw.SizedBox(height: 2),
                pw.Text(_kpi(k, k['value']), style: pw.TextStyle(fontSize: 14, color: _ink, fontWeight: pw.FontWeight.bold)),
                _deltaText(k['pct_change'], k['change_unit']?.toString()),
              ]),
            ),
          ),
      ]),
      pw.SizedBox(height: 18),
      pw.Text('Revenue per region', style: pw.TextStyle(fontSize: 11, color: _ink, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 10),
      if (labels.isNotEmpty && series.isNotEmpty) _bars(labels, series),
      pw.SizedBox(height: 16),
      pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(color: _teal50, borderRadius: pw.BorderRadius.circular(8)),
        child: pw.RichText(
          text: pw.TextSpan(style: const pw.TextStyle(fontSize: 9, color: _tealDark, lineSpacing: 2), children: [
            pw.TextSpan(text: 'Ringkasan oleh agent. ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            for (final (i, part) in summary.split('**').indexed)
              pw.TextSpan(text: part, style: i.isOdd ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null),
          ]),
        ),
      ),
      pw.NewPage(),
      _head(logo, name, 'Performa per region'),
      pw.TableHelper.fromTextArray(
        headers: ['Region', 'Revenue', 'MoM', 'Pelanggan', 'Payload', targets ? 'Target' : 'Kontribusi'],
        data: [
          for (final r in regions)
            [
              _title(r['region'].toString()),
              formatValue(toNum(r['revenue']) ?? 0, 'currency'),
              _delta(r['mom_pct']),
              shortNum(toNum(r['subs']) ?? 0),
              _kpi({'format': 'gb'}, r['payload_gb']),
              '${idNum(toNum(targets ? r['achievement_pct'] : r['share_pct']) ?? 0, 1)}%',
            ],
        ],
        headerStyle: pw.TextStyle(fontSize: 8, color: _mute, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
        headerDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule))),
        rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule, width: .5))),
        cellAlignments: {for (var i = 1; i < 6; i++) i: pw.Alignment.centerRight},
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        border: null,
      ),
      ...[
        for (final k in kpis.where((k) => k['key'] == 'availability'))
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 16),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule), borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Text(
              'Site availability 4G ${_kpi(k, k['value'])} · target ${idNum(toNum(k['target']) ?? 99.5, 1)}%'
              '${toNum(k['pct_change']) == null ? '' : ' · ${_delta(k['pct_change'], 'pp')} dari ${ov['prev_label'] ?? 'bulan lalu'}'}',
              style: const pw.TextStyle(fontSize: 9, color: _text2),
            ),
          ),
      ],
    ],
  ));
  return doc.save();
}

/// An agent answer as a table, 28 rows per page.
Future<Uint8List> buildTablePdf(String title, List<String> columns, List<Map<String, dynamic>> rows) async {
  final theme = await _theme();
  final logo = await _logo();
  final cols = columns.take(7).toList();
  final doc = pw.Document(theme: theme, title: title, author: 'Bizplan Java Agent');
  doc.addPage(pw.MultiPage(
    pageFormat: cols.length > 4 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 28),
    footer: (c) => _footer(c, 'Hasil Bizplan Java Agent · ${rows.length} baris${columns.length > cols.length ? ' · ${columns.length - cols.length} kolom lain ada di XLSX' : ''}'),
    build: (c) => [
      _head(logo, 'Laporan ad-hoc dari agent', title),
      pw.TableHelper.fromTextArray(
        headers: [for (final c in cols) humanize(c)],
        data: [
          for (final r in rows.take(1000))
            [for (final c in cols) r[c] is num ? idNum((r[c] as num).toDouble(), (r[c] as num) % 1 == 0 ? 0 : 2) : (r[c] ?? '').toString()],
        ],
        headerStyle: pw.TextStyle(fontSize: 8, color: _mute, fontWeight: pw.FontWeight.bold),
        cellStyle: const pw.TextStyle(fontSize: 8, color: _ink),
        headerDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule))),
        rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _rule, width: .5))),
        cellPadding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        border: null,
      ),
    ],
  ));
  return doc.save();
}

/// Pages a table report will have (for the export sheet's caption).
int tablePdfPages(int rows) => math.max(1, (rows / 28).ceil());

String slug(String s) {
  final out = s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  return out.isEmpty ? 'laporan' : (out.length > 48 ? out.substring(0, 48) : out);
}

/// Writes [bytes] to the app's documents folder and opens it.
Future<File> saveAndOpen(String filename, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/$filename');
  await f.writeAsBytes(bytes, flush: true);
  await OpenFilex.open(f.path);
  return f;
}
