import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/api_client.dart';
import '../services/report_export.dart';
import '../ui/chart.dart' show monthsId;
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../ui/mock_icons.dart';
import '../ui/v2.dart';
import 'report_doc_screen.dart';

/// One row of the Laporan library.
class ReportItem {
  const ReportItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.format,
    this.meta = '',
    this.region,
    this.adhoc,
    this.doc,
    this.kabupaten,
    this.pages,
    this.sections,
  });
  final String id;

  /// analis, bulanan, mingguan, profile, performance or adhoc.
  final String kind;
  final String title, format, meta;

  /// Region of a live performance report ("" = Circle Java); null for ad-hoc.
  final String? region;
  final AdhocReport? adhoc;

  /// Report document to preview ({kind, region, kabupaten}), from /api/report-docs.
  final Map<String, dynamic>? doc;

  /// Site Performance item: opens the Performa tab on this kabupaten.
  final String? kabupaten;
  final int? pages, sections;
}

class _Kind {
  const _Kind(this.label, this.bg, this.fg, this.icon);
  final String label, icon;
  final Color bg, fg;
}

const _kinds = {
  'analis': _Kind('Analis', Color(0xFFFCEDD3), Color(0xFFB7791F), 'bars'),
  'bulanan': _Kind('Bulanan', Color(0xFFE6F7F5), Color(0xFF0A6A5F), 'file'),
  'mingguan': _Kind('Mingguan', Color(0xFFE1ECFA), Color(0xFF2C6CB0), 'file'),
  'profile': _Kind('Profile wilayah', Color(0xFFFBE2DA), Color(0xFFB5401F), 'pin'),
  'performance': _Kind('Performance', Color(0xFFF4FCE3), Color(0xFF5E8A12), 'pulse'),
  'adhoc': _Kind('Ad-hoc', Color(0xFFECE5FA), Color(0xFF6A4CB5), 'table'),
};
// The phone shows the first five filters on screen; Mingguan and Ad-hoc scroll in.
const _filters = ['semua', 'analis', 'bulanan', 'profile', 'performance', 'mingguan', 'adhoc'];
const _weekdays = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const _monthsFull = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

String _titleCase(String s) => s
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ')
    .replaceAll('Diy', 'DIY');

/// "Revenue West Java vs Sep" → "Revenue West Java vs September".
String expandMonth(String s) => s.replaceAllMapped(RegExp(r'\b(Jan|Feb|Mar|Apr|Mei|Jun|Jul|Agu|Sep|Okt|Nov|Des)\b$'),
    (m) => _monthsFull[monthsId.indexOf(m[1]!)]);

/// WIB wall clock of an API timestamp.
DateTime _wib(String iso) => (DateTime.tryParse(iso) ?? DateTime.now()).toUtc().add(const Duration(hours: 7));

/// Android · Laporan (Redesign v2 page 06): the Performance Outlook on a
/// featured card, the library list, then the auto-send schedules. Tapping a
/// report opens its full-screen preview; ad-hoc answers export to PDF or XLSX.
class ReportListScreen extends StatefulWidget {
  const ReportListScreen({
    super.key,
    this.previewLibrary,
    this.previewSchedules,
    this.previewRuns,
    this.previewAdhoc,
    this.previewNow,
    this.onAsk,
    this.onOpenPerformance,
  });

  final Map<String, dynamic>? previewLibrary;
  final List<Map<String, dynamic>>? previewSchedules;
  final List<Map<String, dynamic>>? previewRuns;
  final List<AdhocReport>? previewAdhoc;
  final DateTime? previewNow;
  final void Function(String question)? onAsk;
  final void Function(String kabupaten)? onOpenPerformance;

  @override
  State<ReportListScreen> createState() => ReportListScreenState();
}

class ReportListScreenState extends State<ReportListScreen> {
  Map<String, dynamic>? _lib;
  String? _error;
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _runs = [];
  List<AdhocReport> _adhoc = [];
  String _filter = 'semua';
  final _query = TextEditingController();
  bool _loading = false;

  bool get _preview => widget.previewLibrary != null;
  DateTime get _now => (widget.previewNow ?? DateTime.now()).toUtc().add(const Duration(hours: 7));

  @override
  void initState() {
    super.initState();
    if (_preview) {
      _lib = widget.previewLibrary;
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
      ApiClient.reportLibrary().then<Object?>((v) => v).catchError((Object e) => e.toString()),
      ApiClient.reportSchedules().then<Object?>((v) => v).catchError((_) => <dynamic>[]),
      ApiClient.reportRuns().then<Object?>((v) => v).catchError((_) => <dynamic>[]),
      AdhocStore.load(),
    ]);
    if (!mounted) return;
    setState(() {
      final lib = results[0];
      _lib = lib is Map<String, dynamic> && lib['lead'] != null ? lib : _lib;
      _error = lib is Map<String, dynamic> && lib['lead'] != null ? null : 'Pustaka laporan belum bisa dimuat.';
      _schedules = (results[1] as List).cast<Map<String, dynamic>>();
      _runs = (results[2] as List).cast<Map<String, dynamic>>();
      _adhoc = results[3] as List<AdhocReport>;
      _loading = false;
    });
  }

  List<String> get _regions => [
        for (final i in [...?(_lib?['lead'] as List?), ...?(_lib?['rest'] as List?)])
          if ((i as Map)['doc']?['kind'] == 'bulanan' && (i['doc']['region'] ?? '').toString().isNotEmpty) i['doc']['region'].toString(),
      ];

  ReportItem _libItem(Map m) => ReportItem(
        id: m['id'].toString(),
        kind: m['kind'].toString(),
        title: m['title'].toString(),
        format: 'PDF',
        meta: (m['meta'] ?? '').toString(),
        region: (m['doc'] as Map?)?['region']?.toString() ?? '',
        doc: (m['doc'] as Map?)?.cast<String, dynamic>(),
        kabupaten: m['kabupaten']?.toString(),
        pages: (m['pages'] as num?)?.toInt(),
        sections: (m['sections'] as num?)?.toInt(),
      );

  String _sent(String iso) {
    final t = _wib(iso);
    final hm = '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
    return _now.difference(t).inHours < 7 * 24 ? '${_weekdays[t.weekday - 1]} $hm' : '${t.day} ${monthsId[t.month - 1]} $hm';
  }

  /// lead[0] is the featured Outlook; then the lead rows, the latest sent run,
  /// ad-hoc answers; [rest] goes under "Laporan lainnya" below the schedules.
  ({ReportItem? featured, List<ReportItem> main, List<ReportItem> rest}) get _groups {
    final lead = [for (final m in (_lib?['lead'] as List?) ?? const []) _libItem(m as Map)];
    final seen = <String>{};
    final runs = <ReportItem>[];
    for (final r in _runs) {
      final title = r['title'].toString();
      if (!seen.add(title)) continue;
      final outlook = title.toLowerCase().contains('outlook');
      final region = (r['region'] ?? '').toString();
      runs.add(ReportItem(
        id: 'run:${r['id']}',
        kind: r['kind'] == 'bulanan' ? 'bulanan' : r['kind'] == 'adhoc' ? 'adhoc' : 'mingguan',
        title: title,
        format: 'PDF',
        region: region,
        meta: r['status'] == 'gagal' ? 'Gagal terkirim · ${_sent(r['created_at'].toString())}' : 'Terkirim ${_sent(r['created_at'].toString())} · ${r['recipients']} penerima',
        doc: {'kind': outlook ? 'outlook' : 'bulanan', 'region': region},
      ));
    }
    final adhoc = [
      for (final a in _adhoc)
        ReportItem(id: 'adhoc:${a.id}', kind: 'adhoc', title: a.title, format: a.format, meta: '${a.format} ${a.rows.length} baris · dari chat', adhoc: a),
    ];
    return (
      featured: lead.isEmpty ? null : lead.first,
      main: [...lead.skip(1), ...runs.take(1), ...adhoc],
      rest: [for (final m in (_lib?['rest'] as List?) ?? const []) _libItem(m as Map), ...runs.skip(1)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final scope = V2Scope.maybeOf(context);
    final g = _groups;
    final all = [if (g.featured != null) g.featured!, ...g.main, ...g.rest];
    final q = _query.text.trim().toLowerCase();
    final filtering = q.isNotEmpty || _filter != 'semua';
    bool keep(ReportItem i) =>
        (_filter == 'semua' || i.kind == _filter) &&
        (q.isEmpty || '${i.title} ${i.meta} ${_kinds[i.kind]?.label ?? ''}'.toLowerCase().contains(q));
    final active = _schedules.where((s) => s['active'] != false).length;
    final shown = all.where(keep).toList();
    return ColoredBox(
      color: V2.bg,
      child: Column(children: [
        SizedBox(height: top),
        V2AppBar(
          title: 'Laporan',
          subtitle: _lib == null ? (_error ?? 'Memuat…') : '${all.length} laporan · $active jadwal aktif',
          subtitleDot: _lib == null ? const Color(0xFFE0A100) : const Color(0xFF2E9E57),
          alertCount: scope?.alerts ?? 0,
          onBell: scope == null ? null : () => scope.openAlerts(),
        ),
        Expanded(
          child: Stack(children: [
            RefreshIndicator(
              color: V2.teal600,
              onRefresh: reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                children: [
                  _searchBox(),
                  const SizedBox(height: 12),
                  _chips(all.length),
                  const SizedBox(height: 12),
                  if (_lib == null && _error == null && _loading)
                    Container(height: 316, decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(18)))
                  else if (_lib == null && _error != null)
                    _note(_error!)
                  else if (filtering) ...[
                    for (final it in shown) ...[_row(it), const SizedBox(height: 8)],
                    if (shown.isEmpty)
                      _note(_filter == 'adhoc'
                          ? 'Belum ada laporan ad-hoc. Tekan Export di jawaban agent untuk menyimpannya di sini.'
                          : 'Tidak ada laporan yang cocok.'),
                  ] else ...[
                    if (g.featured != null) ...[_featured(g.featured!), const SizedBox(height: 12)],
                    for (final it in g.main) ...[_row(it), const SizedBox(height: 8)],
                    const SizedBox(height: 4),
                    _sched(),
                    if (g.rest.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 8),
                        child: Text('Laporan lainnya', style: V2.d(13, FontWeight.w600, V2.ink2, lh: 1.2)),
                      ),
                      for (final it in g.rest) ...[_row(it), const SizedBox(height: 8)],
                    ],
                  ],
                ],
              ),
            ),
            Positioned(right: 16, bottom: 16, child: _fab()),
          ]),
        ),
      ]),
    );
  }

  Widget _note(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
        child: Text(t, textAlign: TextAlign.center, style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.5)),
      );

  Widget _searchBox() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: V2.rule)),
      child: Row(children: [
        const MIcon('search', size: 18, color: V2.mute),
        const SizedBox(width: 10),
        Expanded(
          child: Stack(alignment: Alignment.centerLeft, children: [
            if (_query.text.isEmpty) IgnorePointer(child: Text('Cari laporan', style: V2.b(13.5, FontWeight.w400, V2.mute, lh: 1))),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              style: V2.b(13.5, FontWeight.w400, V2.ink, lh: 1.2),
              cursorColor: V2.teal600,
              decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _chips(int total) {
    return SizedBox(
      height: 30,
      child: ListView(scrollDirection: Axis.horizontal, children: [
        for (final f in _filters) ...[
          GestureDetector(
            onTap: () => setState(() => _filter = f),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _filter == f ? V2.ink : Colors.white,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: _filter == f ? V2.ink : V2.rule),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(f == 'semua' ? 'Semua' : _kinds[f]!.label, style: V2.d(12, FontWeight.w500, _filter == f ? Colors.white : V2.ink2, lh: 1)),
                if (f == 'semua') ...[
                  const SizedBox(width: 6),
                  Text('$total', style: V2.d(11, FontWeight.w700, _filter == f ? V2.lime : V2.mute, lh: 1)),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ]),
    );
  }

  Widget _kd(String label, Color bg, Color fg) => Container(
        padding: const EdgeInsets.fromLTRB(7, 4, 7, 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(label, style: V2.d(10.5, FontWeight.w600, fg, lh: 1)),
      );

  Widget _texts(ReportItem it) {
    final k = _kinds[it.kind] ?? _kinds['bulanan']!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 17.5,
        child: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(13.5, FontWeight.w600, V2.ink, lh: 1.3)),
      ),
      Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _kd(k.label, k.bg, k.fg),
        Text(it.meta, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.35)),
      ]),
    ]);
  }

  Widget _ic2(ReportItem it) {
    final k = _kinds[it.kind] ?? _kinds['bulanan']!;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: k.bg, borderRadius: BorderRadius.circular(12)),
      child: MIcon(k.icon, size: 20, color: k.fg),
    );
  }

  Widget _row(ReportItem it) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: V2.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _open(it),
        onLongPress: it.adhoc == null ? null : () => _removeAdhoc(it.adhoc!),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          child: Row(children: [
            _ic2(it),
            const SizedBox(width: 12),
            Expanded(child: _texts(it)),
            const SizedBox(width: 12),
            it.adhoc != null ? const MIcon('pin', size: 16, color: Color(0xFFB5401F)) : const MIcon('chevr', size: 16, color: Color(0xFF8A9A97)),
          ]),
        ),
      ),
    );
  }

  Widget _thumb(int hi) {
    Widget u(bool c) => Container(
          height: c ? 18 : 4,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(color: c ? const Color(0xFF8FD6CB) : V2.rule, borderRadius: BorderRadius.circular(2)),
        );
    return Expanded(
      child: Container(
        height: 137,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: V2.rule)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(
            builder: (context, c) => Container(
              height: 35.1,
              decoration: BoxDecoration(gradient: cssLinear(135, const [V2.teal700, V2.teal900], Size(c.maxWidth, 35.1))),
            ),
          ),
          Padding(padding: const EdgeInsets.all(6), child: Column(children: [for (var i = 0; i < 4; i++) u(i == hi)])),
        ]),
      ),
    );
  }

  Widget _featured(ReportItem it) {
    final pages = it.pages ?? 6;
    final month = (_lib?['month_short'] ?? '').toString();
    final secs = it.sections ?? 9;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: V2.rule),
        boxShadow: [cssShadow(const Color(0x0A0F1F1D), 0, 4, 14)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          onTap: () => _open(it),
          child: Row(children: [
            _ic2(it),
            const SizedBox(width: 12),
            Expanded(child: _texts(ReportItem(id: it.id, kind: it.kind, title: it.title, format: it.format, meta: '$month · $pages hlm'))),
          ]),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _open(it),
          child: Row(children: [_thumb(2), const SizedBox(width: 8), _thumb(1), const SizedBox(width: 8), _thumb(3)]),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _kd('Performance', const Color(0xFFE6F7F5), const Color(0xFF0A6A5F)),
          _kd('Site productivity', const Color(0xFFF4FCE3), const Color(0xFF5E8A12)),
          _kd('Profile wilayah', const Color(0xFFFBE2DA), const Color(0xFFB5401F)),
          _kd('+${secs - 3} bagian', const Color(0xFFE1ECFA), const Color(0xFF2C6CB0)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _btn('Buka pratinjau', 'file', true, () => _open(it))),
          const SizedBox(width: 8),
          Expanded(child: _btn('Bagikan', 'share', false, () => _share(it))),
        ]),
      ]),
    );
  }

  Widget _btn(String label, String icon, bool primary, VoidCallback onTap) {
    final fg = primary ? Colors.white : V2.teal700;
    return Material(
      color: primary ? V2.teal600 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: primary ? BorderSide.none : const BorderSide(color: Color(0xFFDCEFEC)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            MIcon(icon, size: 15, color: fg),
            const SizedBox(width: 7),
            Text(label, style: V2.d(12.5, FontWeight.w600, fg, lh: 1)),
          ]),
        ),
      ),
    );
  }

  String _schedLine(Map<String, dynamic> s) {
    final monthly = s['frequency'] == 'bulanan';
    final when = monthly ? 'Tgl ${s['monthday']}' : _weekdays[((s['weekday'] as num?) ?? 0).toInt().clamp(0, 6)];
    final n = ((s['recipients'] as List?) ?? const []).length;
    if (s['active'] == false) return '$when · dijeda';
    return monthly ? '$when tiap bulan · $n penerima' : '$when ${((s['hour'] as num?) ?? 7).toInt().toString().padLeft(2, '0')}.00 · $n penerima';
  }

  Widget _sched() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: V2.rule)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 18,
          child: Row(children: [
            const MIcon('mail', size: 18, color: V2.teal700),
            const SizedBox(width: 8),
            Text('Jadwal kirim', style: V2.d(14, FontWeight.w600, V2.ink, lh: 1.2)),
            const Spacer(),
            GestureDetector(onTap: _manageSchedules, child: Text('+ Baru', style: V2.d(12, FontWeight.w500, V2.teal700, lh: 1))),
          ]),
        ),
        if (_schedules.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Belum ada jadwal. Agent bisa mengirim laporan lewat email tiap minggu atau tiap bulan.',
                style: V2.b(12, FontWeight.w400, V2.mute, lh: 1.4)),
          ),
        for (final s in _schedules) ...[
          const SizedBox(height: 10),
          InkWell(
            onTap: () => _scheduleActions(s),
            child: Container(
              // CSS border-top sits outside the 8 px padding
              padding: const EdgeInsets.fromLTRB(0, 9, 0, 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2.rule2))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['name'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(12.5, FontWeight.w600, V2.ink, lh: 1.3)),
                    const SizedBox(height: 2),
                    Text(_schedLine(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)),
                  ]),
                ),
                const SizedBox(width: 10),
                _toggle(s),
              ]),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _toggle(Map<String, dynamic> s) {
    final on = s['active'] != false;
    return GestureDetector(
      onTap: () async {
        setState(() => s['active'] = !on);
        if (!_preview) await ApiClient.updateSchedule(s['id'] as int, {'active': !on}).catchError((_) => <String, dynamic>{});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 20,
        decoration: BoxDecoration(color: on ? V2.teal600 : const Color(0xFFCBD6D3), borderRadius: BorderRadius.circular(10)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.all(2),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }

  Widget _fab() {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), boxShadow: [cssShadow(const Color(0x590E8579), 0, 10, 24)]),
      child: Material(
        color: V2.teal600,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _create,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const MIcon('plus', size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text('Buat laporan', style: V2.d(14, FontWeight.w600, Colors.white, lh: 1)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final p = Pal.of(context);
    final pick = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 16),
            Text('Buat laporan', style: ts(18, w700, p.ink, lh: 1.35)),
            const SizedBox(height: 16),
            PrimaryButton('Minta agent (ad-hoc)', icon: Icx.send, onTap: () => Navigator.pop(ctx, 'ask')),
            const SizedBox(height: 10),
            PrimaryButton('Jadwalkan kirim otomatis', color: p.surfaceMuted, fg: p.ink, onTap: () => Navigator.pop(ctx, 'sched')),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    if (pick == 'ask') widget.onAsk?.call('Buatkan laporan ');
    if (pick == 'sched') _manageSchedules();
  }

  Future<void> _share(ReportItem it) async {
    try {
      final url = await ApiClient.createReportLink(it.title, region: it.region ?? '');
      await Clipboard.setData(ClipboardData(text: url));
      await SharePlus.instance.share(ShareParams(text: '${it.title}\n$url', subject: it.title));
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  Future<void> _open(ReportItem it) async {
    if (it.kabupaten != null) {
      widget.onOpenPerformance?.call(it.kabupaten!);
      return;
    }
    if (it.doc != null) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportDocScreen(item: it)));
      return;
    }
    final p = Pal.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => ReportExportSheet(item: it),
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
    final regions = _regions;
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
                    activeThumbColor: Colors.white,
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
                PillChip(r.isEmpty ? 'Circle Java' : _titleCase(r), selected: _region == r, onTap: () => setState(() => _region = r)),
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
