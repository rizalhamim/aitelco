import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../services/report_export.dart';
import '../ui/chart.dart' show monthsId;
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// One row of the Laporan library.
class ReportItem {
  const ReportItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.format,
    this.date,
    this.dateLabel,
    this.region,
    this.adhoc,
    this.route,
  });
  final String id;

  /// bulanan, mingguan, adhoc or analis.
  final String kind;
  final String title, format;
  final DateTime? date;
  final String? dateLabel;

  /// Region of a live performance report ("" = all of Java); null for ad-hoc.
  final String? region;
  final AdhocReport? adhoc;

  /// Opens another screen instead of exporting (Performance Outlook).
  final String? route;
}

const _kindLabel = {'bulanan': 'Bulanan', 'mingguan': 'Mingguan', 'adhoc': 'Ad-hoc', 'analis': 'Analis'};
const _weekdays = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const _monthsFull = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ')
    .replaceAll('Diy', 'DIY');

/// "Revenue Jawa Barat vs Sep" → "Revenue Jawa Barat vs September".
String expandMonth(String s) => s.replaceAllMapped(RegExp(r'\b(Jan|Feb|Mar|Apr|Mei|Jun|Jul|Agu|Sep|Okt|Nov|Des)\b$'),
    (m) => _monthsFull[monthsId.indexOf(m[1]!)]);

/// Android · Laporan: the scheduled report on a hero card, then live
/// performance reports, emailed runs and agent answers saved as ad-hoc
/// reports. Each exports to PDF or XLSX, or to a 7-day share link.
class ReportListScreen extends StatefulWidget {
  const ReportListScreen({
    super.key,
    this.previewOverview,
    this.previewSchedules,
    this.previewRuns,
    this.previewAdhoc,
    this.previewNow,
    this.onAsk,
  });

  final Map<String, dynamic>? previewOverview;
  final List<Map<String, dynamic>>? previewSchedules;
  final List<Map<String, dynamic>>? previewRuns;
  final List<AdhocReport>? previewAdhoc;
  final DateTime? previewNow;
  final void Function(String question)? onAsk;

  @override
  State<ReportListScreen> createState() => ReportListScreenState();
}

class ReportListScreenState extends State<ReportListScreen> {
  Map<String, dynamic>? _overview;
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _runs = [];
  List<AdhocReport> _adhoc = [];
  String _filter = 'semua';
  bool _searching = false;
  final _query = TextEditingController();
  bool _loading = false;

  bool get _preview => widget.previewOverview != null;
  DateTime get _now => widget.previewNow ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (_preview) {
      _overview = widget.previewOverview;
      _schedules = widget.previewSchedules ?? [];
      _runs = widget.previewRuns ?? [];
      _adhoc = widget.previewAdhoc ?? [];
    } else {
      reload();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (_preview) return;
    setState(() => _loading = true);
    final results = await Future.wait<Object?>([
      ApiClient.dashboardOverview().then<Object?>((v) => v).catchError((_) => null),
      ApiClient.reportSchedules().then<Object?>((v) => v).catchError((_) => <dynamic>[]),
      ApiClient.reportRuns().then<Object?>((v) => v).catchError((_) => <dynamic>[]),
      AdhocStore.load(),
    ]);
    if (!mounted) return;
    setState(() {
      final ov = results[0] as Map<String, dynamic>?;
      _overview = ov == null || ov['error'] != null ? null : ov;
      _schedules = (results[1] as List).cast<Map<String, dynamic>>();
      _runs = (results[2] as List).cast<Map<String, dynamic>>();
      _adhoc = results[3] as List<AdhocReport>;
      _loading = false;
    });
  }

  List<ReportItem> get _items {
    final month = _overview?['month_label']?.toString() ?? '';
    final regions = ((_overview?['scope'] as Map?)?['regions'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final dated = <ReportItem>[
      for (final r in _runs)
        ReportItem(
          id: 'run:${r['id']}',
          kind: r['kind'] == 'bulanan' ? 'bulanan' : 'mingguan',
          title: r['title'].toString(),
          format: 'PDF',
          date: DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal(),
          region: (r['region'] ?? '').toString(),
        ),
      for (final a in _adhoc)
        ReportItem(id: 'adhoc:${a.id}', kind: 'adhoc', title: a.title, format: a.format, date: a.savedAt, adhoc: a),
    ]..sort((a, b) => (b.date ?? DateTime(2000)).compareTo(a.date ?? DateTime(2000)));
    return [
      ...dated,
      ReportItem(id: 'live:', kind: 'bulanan', title: 'Performa Bulanan Region Jawa', format: 'PDF', dateLabel: month, region: ''),
      for (final r in regions)
        ReportItem(id: 'live:$r', kind: 'bulanan', title: 'Performa Bulanan ${_titleCase(r)}', format: 'PDF', dateLabel: month, region: r),
      const ReportItem(id: 'outlook', kind: 'analis', title: 'Performance Outlook', format: 'Komprehensif', dateLabel: 'revenue · benchmark', route: '/reports'),
    ];
  }

  String _when(ReportItem it) {
    if (it.date == null) return it.dateLabel ?? '';
    final d = DateTime(it.date!.year, it.date!.month, it.date!.day);
    final days = DateTime(_now.year, _now.month, _now.day).difference(d).inDays;
    if (days == 0) return 'hari ini';
    if (days == 1) return 'kemarin';
    return '${it.date!.day} ${monthsId[it.date!.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    final items = _items;
    final q = _query.text.trim().toLowerCase();
    final shown = items.where((i) {
      if (q.isNotEmpty && !i.title.toLowerCase().contains(q)) return false;
      return _filter == 'semua' || i.kind == _filter;
    }).toList();
    final active = _schedules.where((s) => s['active'] != false).toList();
    return ColoredBox(
      color: p.bg,
      child: RefreshIndicator(
        color: p.teal600,
        onRefresh: reload,
        child: ListView(
          padding: EdgeInsets.only(top: top, bottom: 24),
          children: [
            SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                child: Row(children: [
                  Expanded(
                    child: _searching
                        ? TextField(
                            controller: _query,
                            autofocus: true,
                            onChanged: (_) => setState(() {}),
                            style: ts(15, w500, p.ink),
                            cursorColor: p.teal600,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Cari laporan…',
                              hintStyle: ts(15, w400, p.mute),
                            ),
                          )
                        : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Laporan', style: ts(18, w700, p.ink, lh: 1.35)),
                            Text('${items.length} laporan · ${active.length} terjadwal', style: ts(12, w400, p.mute)),
                          ]),
                  ),
                  SquareIconButton(_searching ? Icx.x : Icx.search, bordered: false, iconSize: 24, tooltip: 'Cari', color: p.text2, onTap: () {
                    setState(() {
                      _searching = !_searching;
                      if (!_searching) _query.clear();
                    });
                  }),
                  const SizedBox(width: 10),
                  SquareIconButton(Icx.sliders, bordered: false, iconSize: 24, tooltip: 'Jadwal laporan', color: p.text2, onTap: _manageSchedules),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 36,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                for (final (k, l) in const [('semua', 'Semua'), ('bulanan', 'Bulanan'), ('mingguan', 'Mingguan'), ('adhoc', 'Ad-hoc')]) ...[
                  PillChip(l, selected: _filter == k, onTap: () => setState(() => _filter = k)),
                  const SizedBox(width: 8),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _hero(p, active.isEmpty ? null : active.first)),
            const SizedBox(height: 14),
            if (_loading && _overview == null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [Skeleton(height: 74, radius: 16), SizedBox(height: 14), Skeleton(height: 74, radius: 16)]),
              ),
            for (final it in shown)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: _row(p, it)),
            if (shown.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _filter == 'adhoc' ? 'Belum ada laporan ad-hoc. Tekan Export di jawaban agent untuk menyimpannya di sini.' : 'Tidak ada laporan yang cocok.',
                  textAlign: TextAlign.center,
                  style: ts(13, w400, p.mute, lh: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _hero(Pal p, Map<String, dynamic>? s) {
    final when = s == null
        ? 'BELUM ADA JADWAL'
        : s['frequency'] == 'bulanan'
            ? 'TERJADWAL · TANGGAL ${s['monthday']}'
            : 'TERJADWAL · SETIAP ${_weekdays[(s['weekday'] as num? ?? 0).toInt().clamp(0, 6)].toUpperCase()}';
    final last = DateTime.tryParse(s?['last_sent_on']?.toString() ?? '');
    final meta = s == null
        ? 'Ketuk untuk kirim laporan ke email otomatis'
        : 'PDF · 2 hlm · ${last == null ? 'belum terkirim' : '${last.day} ${monthsId[last.month - 1]}'}';
    return Material(
      color: const Color(0xFF04332E),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: s == null ? _manageSchedules : () => _scheduleActions(s),
        child: SizedBox(
          height: 119,
          child: Stack(children: [
            const Positioned(left: 160, top: -100, width: 300, height: 260, child: Glow(color: Color(0xFF33BCAD), alpha: .3)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(when, style: ts(11, w600, const Color(0xFF8FDFD7), lh: 1.3, ls: .08)),
                    const SizedBox(height: 6),
                    Text(s == null ? 'Jadwalkan laporan performa' : s['name'].toString(),
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(16, w600, Colors.white)),
                    const SizedBox(height: 6),
                    Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w400, const Color(0xFFC0EDE8))),
                  ]),
                ),
                const SizedBox(width: 12),
                Image.asset('assets/img/empty_reports.webp', width: 96, height: 72),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(Pal p, ReportItem it) {
    final sheet = it.format == 'XLSX';
    final (bg, fg) = sheet ? (p.green50, p.green600) : (p.teal50, p.teal700);
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(it),
        onLongPress: it.adhoc == null ? null : () => _removeAdhoc(it.adhoc!),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: sheet ? SheetIcon(size: 20, color: fg) : Ic(it.kind == 'analis' ? Icx.barChart : Icx.fileText, size: 20, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w600, p.ink)),
                const SizedBox(height: 4),
                Row(children: [
                  StatusBadge(_kindLabel[it.kind] ?? it.kind, kind: BadgeKind.neutral),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${it.format} · ${_when(it)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w400, p.mute)),
                  ),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            SquareIconButton(it.route != null ? Icx.chevronRight : Icx.download,
                bordered: false, color: p.teal700, tooltip: it.route != null ? 'Buka' : 'Unduh', onTap: () => _open(it)),
          ]),
        ),
      ),
    );
  }

  Future<void> _open(ReportItem it) async {
    if (it.route != null) {
      Navigator.of(context).pushNamed(it.route!);
      return;
    }
    final p = Pal.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ReportExportSheet(item: it, overview: it.region == '' ? _overview : null),
    );
    if (it.adhoc != null) reload();
  }

  Future<void> _removeAdhoc(AdhocReport a) async {
    final p = Pal.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('Hapus dari Laporan?', style: ts(18, w700, p.ink)),
        content: Text('"${a.title}" dihapus dari daftar ad-hoc di ponsel ini.', style: ts(14, w400, p.text2, lh: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Batal', style: ts(14, w600, p.text2))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Hapus', style: ts(14, w600, p.danger))),
        ],
      ),
    );
    if (ok == true) {
      await AdhocStore.remove(a.id);
      reload();
    }
  }

  // ── Schedules ──

  Future<void> _scheduleActions(Map<String, dynamic> s) async {
    final p = Pal.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 16),
            Text(s['name'].toString(), style: ts(18, w700, p.ink, lh: 1.35)),
            const SizedBox(height: 4),
            Text('${s['description'] ?? ''} · ke ${((s['recipients'] as List?) ?? const []).join(', ')}', style: ts(13, w400, p.text2, lh: 1.5)),
            const SizedBox(height: 20),
            PrimaryButton('Kirim sekarang', icon: Icx.send, onTap: () => Navigator.pop(ctx, 'send')),
            const SizedBox(height: 10),
            PrimaryButton('Unduh laporan ini', icon: Icx.download, color: p.surfaceMuted, fg: p.ink, onTap: () => Navigator.pop(ctx, 'open')),
            const SizedBox(height: 10),
            PrimaryButton('Nonaktifkan jadwal', color: p.surfaceMuted, fg: p.danger, onTap: () => Navigator.pop(ctx, 'off')),
          ]),
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'send') {
        final r = await ApiClient.sendScheduleNow(s['id'] as int);
        if (mounted) showToast(context, 'Terkirim ke ${r['sent']} dari ${r['recipients']} penerima.');
      } else if (action == 'off') {
        await ApiClient.updateSchedule(s['id'] as int, {'active': false});
      } else if (action == 'open') {
        final region = (s['region'] ?? '').toString();
        await _open(ReportItem(id: 'sched:${s['id']}', kind: s['frequency'].toString(), title: s['name'].toString(), format: 'PDF', region: region));
      }
      reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  Future<void> _manageSchedules() async {
    final p = Pal.of(context);
    final regions = ((_overview?['scope'] as Map?)?['regions'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _ScheduleSheet(schedules: _schedules, regions: regions, email: AuthState.user?['email']?.toString() ?? ''),
    );
    if (body == null) {
      reload();
      return;
    }
    try {
      await ApiClient.createSchedule(body);
      if (mounted) showToast(context, 'Jadwal disimpan. Laporan dikirim ke email sesuai jadwal.');
      reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }
}

/// "Ekspor laporan": PDF, XLSX or a share link, then the download button.
class ReportExportSheet extends StatefulWidget {
  const ReportExportSheet({super.key, required this.item, this.overview});
  final ReportItem item;

  /// Live overview already loaded for this region, if any.
  final Map<String, dynamic>? overview;

  @override
  State<ReportExportSheet> createState() => _ReportExportSheetState();
}

class _ReportExportSheetState extends State<ReportExportSheet> {
  late String _choice = widget.item.format == 'XLSX' ? 'xlsx' : 'pdf';
  bool _busy = false;

  AdhocReport? get _adhoc => widget.item.adhoc;

  Future<Map<String, dynamic>> _ov() async {
    if (widget.overview != null) return widget.overview!;
    final ov = await ApiClient.dashboardOverview(region: widget.item.region ?? '');
    if (ov['error'] != null) throw Exception(ov['error']);
    return ov;
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    final it = widget.item;
    try {
      if (_choice == 'link') {
        final url = await ApiClient.createReportLink(expandMonth(it.title),
            region: it.region ?? '', columns: _adhoc?.columns, rows: _adhoc?.rows);
        await Clipboard.setData(ClipboardData(text: url));
        await SharePlus.instance.share(ShareParams(text: '${expandMonth(it.title)}\n$url', subject: it.title));
        if (mounted) Navigator.pop(context);
        return;
      }
      final name = 'bizplan-${slug(it.title)}';
      if (_choice == 'pdf') {
        final bytes = _adhoc != null
            ? await buildTablePdf(it.title, _adhoc!.columns, _adhoc!.rows)
            : await buildOverviewPdf(await _ov(), it.title);
        await saveAndOpen('$name.pdf', bytes);
      } else {
        final sheets = _adhoc != null ? adhocSheets(_adhoc!) : overviewSheets(await _ov());
        await saveAndOpen('$name.xlsx', buildXlsx(sheets));
      }
      if (_adhoc != null) await AdhocStore.setFormat(_adhoc!.id, _choice.toUpperCase());
      ApiClient.logExport(_choice.toUpperCase(), it.title);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, 'Ekspor gagal: ${e.toString().replaceFirst('Exception: ', '')}', ok: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final pages = _adhoc != null ? tablePdfPages(_adhoc!.rows.length) : 2;
    const sheets = 3;
    final options = [
      ('pdf', Icx.fileText, 'PDF', 'Untuk dibagikan · $pages halaman'),
      ('xlsx', Icx.sheet, 'XLSX', 'Data mentah · $sheets sheet'),
      ('link', Icx.share, 'Bagikan tautan', 'Berlaku 7 hari'),
    ];
    final cta = switch (_choice) { 'pdf' => 'Unduh PDF', 'xlsx' => 'Unduh XLSX', _ => 'Salin & bagikan tautan' };
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Center(child: SheetHandle()),
          const SizedBox(height: 12),
          Text('Ekspor laporan', style: ts(18, w700, p.ink, lh: 1.35)),
          const SizedBox(height: 12),
          Text(expandMonth(widget.item.title), style: ts(12, w400, p.mute)),
          for (final (k, icon, label, caption) in options) ...[
            const SizedBox(height: 12),
            Material(
              color: _choice == k ? p.teal50 : p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: _choice == k ? p.teal400 : p.rule, width: _choice == k ? 1.5 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _choice = k),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: p.dark ? p.surfaceMuted : Colors.white, borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: label == 'XLSX' ? SheetIcon(size: 20, color: p.teal700) : Ic(icon, size: 20, color: p.teal700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: ts(13, w600, p.ink)),
                        Text(caption, style: ts(12, w400, p.mute)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          PrimaryButton(cta, icon: _choice == 'link' ? Icx.share : Icx.download, height: 44, loading: _busy, onTap: _busy ? null : _go),
        ]),
      ),
    );
  }
}

/// New schedule form, with the user's existing schedules listed above it.
class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({required this.schedules, required this.regions, required this.email});
  final List<Map<String, dynamic>> schedules;
  final List<String> regions;
  final String email;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  String _frequency = 'mingguan';
  String _region = '';
  int _weekday = 0;
  int _monthday = 1;
  int _hour = 8;
  late final _recipients = TextEditingController(text: widget.email);

  @override
  void dispose() {
    _recipients.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(t, style: ts(13, w600, p.text2)));
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.rule));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 16),
            Text('Jadwal laporan', style: ts(18, w700, p.ink, lh: 1.35)),
            const SizedBox(height: 4),
            Text('Agent menyusun laporan performa dan mengirimkannya ke email.', style: ts(13, w400, p.text2, lh: 1.5)),
            for (final s in widget.schedules) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.rule)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s['name'].toString(), style: ts(13, w600, p.ink)),
                      Text('${s['description'] ?? ''}${s['active'] == false ? ' · nonaktif' : ''}', style: ts(12, w400, p.mute)),
                    ]),
                  ),
                  Switch(
                    value: s['active'] != false,
                    activeColor: Colors.white,
                    activeTrackColor: p.teal600,
                    onChanged: (v) async {
                      await ApiClient.updateSchedule(s['id'] as int, {'active': v}).catchError((_) => <String, dynamic>{});
                      setState(() => s['active'] = v);
                    },
                  ),
                  IconButton(
                    tooltip: 'Hapus jadwal',
                    icon: Ic(Icx.x, size: 18, color: p.mute),
                    onPressed: () async {
                      await ApiClient.deleteSchedule(s['id'] as int).catchError((_) {});
                      setState(() => widget.schedules.remove(s));
                    },
                  ),
                ]),
              ),
            ],
            label('Frekuensi'),
            Wrap(spacing: 8, children: [
              PillChip('Mingguan', selected: _frequency == 'mingguan', onTap: () => setState(() => _frequency = 'mingguan')),
              PillChip('Bulanan', selected: _frequency == 'bulanan', onTap: () => setState(() => _frequency = 'bulanan')),
            ]),
            label(_frequency == 'mingguan' ? 'Hari' : 'Tanggal'),
            if (_frequency == 'mingguan')
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < 7; i++) PillChip(_weekdays[i].substring(0, 3), selected: _weekday == i, onTap: () => setState(() => _weekday = i)),
              ])
            else
              DropdownButton<int>(
                value: _monthday,
                dropdownColor: p.surface,
                style: ts(14, w600, p.ink),
                items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('Tanggal $d'))],
                onChanged: (v) => setState(() => _monthday = v ?? 1),
              ),
            label('Jam kirim (WIB)'),
            DropdownButton<int>(
              value: _hour,
              dropdownColor: p.surface,
              style: ts(14, w600, p.ink),
              items: [for (var h = 5; h <= 21; h++) DropdownMenuItem(value: h, child: Text('${h.toString().padLeft(2, '0')}.00'))],
              onChanged: (v) => setState(() => _hour = v ?? 8),
            ),
            label('Wilayah'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in ['', ...widget.regions])
                PillChip(r.isEmpty ? 'Jawa' : _titleCase(r), selected: _region == r, onTap: () => setState(() => _region = r)),
            ]),
            label('Penerima (pisahkan dengan koma)'),
            TextField(
              controller: _recipients,
              keyboardType: TextInputType.emailAddress,
              style: ts(14, w400, p.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'nama@ioh.co.id',
                hintStyle: ts(14, w400, p.mute),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(borderSide: BorderSide(color: p.teal600, width: 1.5)),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton('Simpan jadwal', icon: Icx.clock, onTap: () {
              Navigator.pop(context, {
                'region': _region,
                'frequency': _frequency,
                'weekday': _weekday,
                'monthday': _monthday,
                'hour': _hour,
                'recipients': _recipients.text.trim(),
              });
            }),
          ]),
        ),
      ),
    );
  }
}
