import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../services/report_export.dart';
import '../ui/chart.dart' show idNum, monthsId, toNum;
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// Android · Statistik (admin): downloads, installs, DAU and failed logins
/// against the previous period, version adoption with a reminder for users
/// on old versions, and users inactive for more than 14 days.
/// Backed by GET /api/admin/app-stats.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.preview, this.previewNow});
  final Map<String, dynamic>? preview;
  final DateTime? previewNow;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _days = 30;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  bool _reminding = false;

  DateTime get _now => widget.previewNow ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _data = widget.preview;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await ApiClient.appStats(days: _days);
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final d = _data;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              child: Row(children: [
                SquareIconButton(Icx.chevronLeft, bordered: false, tooltip: 'Kembali', color: p.ink, onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Statistik', style: ts(18, w700, p.ink, lh: 1.35)),
                    Text(widget.preview != null ? 'Admin · data ilustrasi' : 'Admin · ${_loading ? 'memuat…' : 'aplikasi Android'}',
                        style: ts(12, w400, p.mute)),
                  ]),
                ),
                SquareIconButton(Icx.sliders, bordered: false, iconSize: 24, tooltip: 'Ekspor pengguna', color: p.text2,
                    onTap: d == null ? null : () => _export(d)),
              ]),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: p.teal600,
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.of(context).padding.bottom),
                children: [
                  _segmented(p),
                  const SizedBox(height: 14),
                  if (d == null && _error != null)
                    InlineMessage(_error!, onRetry: _load)
                  else if (d == null)
                    const Column(children: [Skeleton(height: 290, radius: 16), SizedBox(height: 14), Skeleton(height: 255, radius: 20)])
                  else ...[
                    _kpis(p, d),
                    const SizedBox(height: 14),
                    _adoption(p, d),
                    const SizedBox(height: 14),
                    _inactive(p, d),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _segmented(Pal p) => Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          for (final n in const [7, 30, 90]) ...[
            GestureDetector(
              onTap: () {
                if (_days == n || widget.preview != null) return;
                setState(() => _days = n);
                _load();
              },
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _days == n ? p.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: _days == n && !p.dark ? const [BoxShadow(color: Color(0x0D0F1F1D), offset: Offset(0, 1), blurRadius: 2)] : null,
                ),
                child: Text('$n hari', style: _days == n ? ts(13, w600, p.ink) : ts(13, w500, p.mute)),
              ),
            ),
            const SizedBox(width: 2),
          ],
        ]),
      );

  Widget _kpis(Pal p, Map d) {
    final k = (d['kpis'] as Map?) ?? const {};
    final t = (d['trend'] as Map?) ?? const {};
    Widget tile(String key, I3 icon, Tone tone, String label) {
      final c = toNum(t[key]);
      return KpiTile(
        icon: icon,
        tone: tone,
        iconSize: 24,
        label: label,
        value: idNum(toNum(k[key]) ?? 0, 0),
        caption: '$_days hari',
        delta: c == null ? null : '${c.abs().toStringAsFixed(1).replaceAll('.', ',')}%',
        deltaUp: (c ?? 0) >= 0,
      );
    }

    return Column(children: [
      Row(children: [
        Expanded(child: tile('downloads_period', Icx.download, Tone.green, 'Unduhan')),
        const SizedBox(width: 10),
        Expanded(child: tile('devices_installed', Icx.smartphone, Tone.blue, 'Terpasang')),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: tile('dau', Icx.users, Tone.teal, 'DAU')),
        const SizedBox(width: 10),
        Expanded(child: tile('failed_logins', Icx.lock, Tone.rose, 'Gagal')),
      ]),
    ]);
  }

  /// Versions grouped as the mockup shows them: latest, the two minors
  /// before it, and everything older.
  List<(String, int, Color)> _versionGroups(Pal p, Map d) {
    final latest = ((d['latest_release'] as Map?)?['version_name'] ?? '').toString();
    final versions = ((d['versions'] as List?) ?? const []).cast<Map>();
    List<int> parts(String v) => v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lp = parts(latest);
    final minors = <String, int>{};
    var onLatest = 0;
    for (final v in versions) {
      final name = v['version'].toString();
      final n = (toNum(v['users']) ?? 0).toInt();
      if (name == latest) {
        onLatest += n;
      } else {
        final vp = parts(name);
        final key = vp.length >= 2 ? '${vp[0]}.${vp[1]}' : name;
        minors[key] = (minors[key] ?? 0) + n;
      }
    }
    final keys = minors.keys.toList()
      ..sort((a, b) {
        final pa = parts(a), pb = parts(b);
        for (var i = 0; i < math.min(pa.length, pb.length); i++) {
          if (pa[i] != pb[i]) return pb[i].compareTo(pa[i]);
        }
        return 0;
      });
    final colors = [p.teal300, p.chartAmber];
    final out = <(String, int, Color)>[if (latest.isNotEmpty) ('v$latest', onLatest, p.teal600)];
    for (var i = 0; i < keys.length && i < 2; i++) {
      out.add(('v${keys[i]}.x', minors[keys[i]]!, colors[i]));
    }
    if (keys.length > 2) {
      final rest = keys.skip(2).fold<int>(0, (s, k) => s + minors[k]!);
      final top = keys[2];
      out.add(('≤ v$top', rest, p.dark ? const Color(0xFF4A5A57) : const Color(0xFFB9C6C3)));
    }
    if (lp.isEmpty) return out;
    return out;
  }

  Widget _adoption(Pal p, Map d) {
    final rel = (d['latest_release'] as Map?) ?? const {};
    final groups = _versionGroups(p, d);
    final total = groups.fold<int>(0, (s, g) => s + g.$2);
    final pct = toNum((d['kpis'] as Map?)?['pct_on_latest']) ?? (total == 0 ? 0 : 100.0 * groups.first.$2 / total);
    final outdated = ((d['outdated_users'] as List?) ?? const []).cast<Map>();
    final released = DateTime.tryParse(rel['released_at']?.toString() ?? '');
    final since = released == null ? '' : ' sejak ${released.day} ${monthsId[released.month - 1]}';
    final sub = rel['version_name'] == null
        ? 'Belum ada rilis APK'
        : 'v${rel['version_name']} ${rel['mandatory'] == true ? 'wajib' : 'terbaru'}$since';
    return _card(p, 'Adopsi versi', sub, [
      SizedBox(
        height: 120,
        child: Row(children: [
          SizedBox(
            width: 120,
            height: 120,
            child: CustomPaint(
              painter: _DonutPainter([for (final g in groups) (g.$2.toDouble(), g.$3)], gap: p.surface),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${idNum(pct, 0)}%', style: ts(28, w700, p.ink, lh: 1.2, ls: -.005)),
                  Text('terbaru', style: ts(12, w400, p.mute)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final (i, g) in groups.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: g.$3, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(g.$1, style: ts(12, w400, p.text2))),
                  Text(idNum(g.$2.toDouble(), 0), style: ts(12, w600, p.ink)),
                ]),
              ],
            ]),
          ),
        ]),
      ),
      if (outdated.isNotEmpty) ...[
        const SizedBox(height: 12),
        Material(
          color: p.teal50,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _reminding || widget.preview != null ? null : () => _remind(outdated),
            child: SizedBox(
              height: 36,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _reminding
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: p.teal700))
                    : Ic(Icx.bellRing, size: 24, color: p.teal700),
                const SizedBox(width: 8),
                Text('Kirim pengingat ke ${outdated.length} pengguna', style: ts(13, w600, p.teal700)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }

  Future<void> _remind(List<Map> users) async {
    setState(() => _reminding = true);
    try {
      final n = await ApiClient.remindUsers([for (final u in users) (u['id'] as num).toInt()]);
      if (mounted) showToast(context, 'Pengingat update terkirim ke $n pengguna.');
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    } finally {
      if (mounted) setState(() => _reminding = false);
    }
  }

  int? _idleDays(Map u) {
    final t = DateTime.tryParse((u['last_seen'] ?? u['last_login'] ?? '').toString());
    return t == null ? null : _now.difference(t.toLocal()).inDays;
  }

  Widget _inactive(Pal p, Map d) {
    final users = ((d['users'] as List?) ?? const []).cast<Map>().where((u) => u['status'] == 'tidak_aktif' && u['is_active'] != false).toList()
      ..sort((a, b) => (_idleDays(b) ?? 9999).compareTo(_idleDays(a) ?? 9999));
    return _card(p, 'Tidak aktif > 14 hari', '${users.length} pengguna', gap: 10, [
      if (users.isEmpty) Text('Semua pengguna aktif dalam 14 hari terakhir.', style: ts(13, w400, p.text2)),
      for (final (i, u) in users.take(8).indexed) ...[
        if (i > 0) const SizedBox(height: 10),
        InkWell(
          onTap: () => _userSheet(u),
          child: SizedBox(
            height: 36,
            child: Row(children: [
              InitialAvatar((u['full_name'] ?? u['username']).toString(), size: 36, bg: p.surfaceMuted, fg: p.text2, fontSize: 13),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text((u['full_name'] ?? u['username']).toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w600, p.ink)),
                  Text(
                    [
                      if ((u['department'] ?? '').toString().isNotEmpty) u['department'],
                      _idleDays(u) == null ? 'belum pernah masuk' : '${_idleDays(u)} hari',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(12, w400, p.mute),
                  ),
                ]),
              ),
              Ic(Icx.chevronRight, size: 18, color: p.text2),
            ]),
          ),
        ),
      ],
    ]);
  }

  Future<void> _userSheet(Map u) async {
    final p = Pal.of(context);
    String row(String k, dynamic v) => '$k: ${v ?? '–'}';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 16),
            Text((u['full_name'] ?? u['username']).toString(), style: ts(18, w700, p.ink, lh: 1.35)),
            const SizedBox(height: 8),
            for (final line in [
              row('Email', u['email']),
              row('Departemen', u['department']),
              row('Login terakhir', (u['last_login'] ?? '').toString().replaceFirst('T', ' ').split('.').first),
              row('Perangkat', u['device_model']),
              row('Versi aplikasi', u['app_version']),
            ])
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(line, style: ts(13, w400, p.text2, lh: 1.5))),
          ]),
        ),
      ),
    );
  }

  Future<void> _export(Map d) async {
    final users = ((d['users'] as List?) ?? const []).cast<Map>();
    const cols = ['nama', 'username', 'email', 'departemen', 'role', 'status', 'platform', 'versi_app', 'perangkat', 'login_terakhir', 'jumlah_login'];
    try {
      await saveAndOpen('bizplan-pengguna-$_days-hari.xlsx', buildXlsx([
        Sheet('Pengguna', cols, [
          for (final u in users)
            {
              'nama': u['full_name'], 'username': u['username'], 'email': u['email'], 'departemen': u['department'], 'role': u['role'],
              'status': u['status'] == 'aktif' ? 'Aktif' : 'Tidak aktif', 'platform': u['platform'], 'versi_app': u['app_version'],
              'perangkat': u['device_model'], 'login_terakhir': u['last_login'], 'jumlah_login': u['login_count'],
            },
        ]),
        Sheet('Versi', const ['versi', 'pengguna'], [
          for (final v in ((d['versions'] as List?) ?? const []).cast<Map>()) {'versi': v['version'], 'pengguna': v['users']},
        ]),
      ]));
      ApiClient.logExport('XLSX', 'Statistik pengguna $_days hari');
    } catch (e) {
      if (mounted) showToast(context, 'Ekspor gagal: $e', ok: false);
    }
  }

  Widget _card(Pal p, String title, String sub, List<Widget> children, {double gap = 12}) => Container(
        padding: const EdgeInsets.fromLTRB(17, 17, 17, 17),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.rule),
          boxShadow: p.shadow,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: ts(16, w600, p.ink)),
          const SizedBox(height: 2),
          Text(sub, style: ts(12, w400, p.mute)),
          SizedBox(height: gap),
          ...children,
        ]),
      );
}

/// Ring chart starting at 12 o'clock, with a thin gap between segments.
class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.parts, {required this.gap});
  final List<(double, Color)> parts;
  final Color gap;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2 - stroke / 2);
    final total = parts.fold<double>(0, (s, e) => s + e.$1);
    if (total <= 0) {
      canvas.drawArc(rect, 0, 2 * math.pi, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0xFFE1E9E7));
      return;
    }
    var a = -math.pi / 2;
    for (final (v, c) in parts) {
      if (v <= 0) continue;
      final sweep = 2 * math.pi * v / total;
      canvas.drawArc(rect, a, sweep, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = c);
      // White separator at the end of each segment.
      final end = a + sweep;
      final o = rect.center;
      final r = rect.width / 2;
      canvas.drawLine(o + Offset(math.cos(end), math.sin(end)) * (r - stroke / 2 - 1),
          o + Offset(math.cos(end), math.sin(end)) * (r + stroke / 2 + 1), Paint()
            ..color = gap
            ..strokeWidth = 2.5);
      a = end;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.parts != parts;
}
