import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/chart.dart';
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// Android · Watchlist & Alert: alerts grouped by day (Aktif tab) and the
/// user's watch rules (Watchlist tab), with "Buat alert" to add a rule.
/// Backed by /api/watchlist/*.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key, this.previewAlerts, this.previewRules, this.previewNow, this.onAsk, this.onCountChanged});

  /// Alerts and rules to render instead of fetching (golden tests).
  final List<Map<String, dynamic>>? previewAlerts;
  final List<Map<String, dynamic>>? previewRules;
  final DateTime? previewNow;

  /// Sends a question to the Agent tab.
  final void Function(String question)? onAsk;

  /// Reports the number of open, unread alerts (for the nav badge).
  final ValueChanged<int>? onCountChanged;

  @override
  State<WatchlistScreen> createState() => WatchlistScreenState();
}

class WatchlistScreenState extends State<WatchlistScreen> {
  List<Map<String, dynamic>> _alerts = [];
  List<Map<String, dynamic>> _rules = [];
  Map<String, dynamic>? _meta;
  bool _loading = false;
  String? _error;
  int _tab = 0;
  String _severity = 'semua';

  bool get _preview => widget.previewAlerts != null;
  DateTime get _now => widget.previewNow ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    if (_preview) {
      _alerts = widget.previewAlerts!;
      _rules = widget.previewRules ?? [];
    } else {
      reload();
    }
  }

  Future<void> reload() async {
    if (_preview) return;
    setState(() { _loading = true; _error = null; });
    try {
      final res = await Future.wait([ApiClient.watchAlerts(status: 'all'), ApiClient.watchRules()]);
      if (!mounted) return;
      setState(() {
        _alerts = res[0].cast<Map<String, dynamic>>();
        _rules = res[1].cast<Map<String, dynamic>>();
      });
      widget.onCountChanged?.call(_openCount);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _openCount => _alerts.where((a) => a['resolved'] != true && a['severity'] != 'pulih').length;

  /// Opens "Buat alert", prefilled from an agent question when given.
  Future<void> createFrom([String? question]) async {
    setState(() => _tab = 1);
    _meta ??= _preview ? null : await ApiClient.watchMeta().catchError((_) => <String, dynamic>{});
    if (!mounted) return;
    final body = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.of(context).surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _RuleSheet(meta: _meta ?? const {}, question: question),
    );
    if (body == null) return;
    try {
      await ApiClient.createWatchRule(body);
      if (!mounted) return;
      showToast(context, 'Alert disimpan. Agent akan memantau setiap hari.');
      reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    return ColoredBox(
      color: p.bg,
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: top),
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              child: Row(children: [
                Expanded(child: Text('Watchlist & Alert', style: ts(18, w700, p.ink, lh: 1.35))),
                SquareIconButton(Icx.sliders, bordered: false, iconSize: 24, tooltip: 'Filter', onTap: _filter),
              ]),
            ),
          ),
          _tabs(p),
          Expanded(
            child: RefreshIndicator(
              color: p.teal600,
              onRefresh: reload,
              child: _tab == 0 ? _alertList(p) : _ruleList(p),
            ),
          ),
        ]),
        Positioned(right: 38, bottom: 18, child: _fab(p)),
      ]),
    );
  }

  Widget _tabs(Pal p) {
    Widget tab(int i, String label) {
      final on = _tab == i;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = i),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: on ? p.teal600 : Colors.transparent, width: 3)),
            ),
            child: Padding(
              padding: EdgeInsets.only(top: on ? 0 : 3),
              child: Text(label, style: on ? ts(14, w600, p.teal800) : ts(14, w500, p.mute, lh: 1.5)),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.rule))),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        tab(0, 'Aktif · $_openCount'),
        tab(1, 'Watchlist · ${_rules.length}'),
      ]),
    );
  }

  Widget _fab(Pal p) => Material(
        color: p.teal600,
        elevation: 0,
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => createFrom(),
          child: Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(18, 0, 20, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0x1F0F1F1D), offset: Offset(0, 6), blurRadius: 24)],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Ic(Icx.plus, size: 24, color: Colors.white),
              const SizedBox(width: 10),
              Text('Buat alert', style: ts(14, w600, Colors.white)),
            ]),
          ),
        ),
      );

  // ── Aktif ──

  String _group(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    final today = DateTime(_now.year, _now.month, _now.day);
    final days = today.difference(d).inDays;
    if (days <= 0) return 'Hari ini';
    if (days == 1) return 'Kemarin';
    if (days < 7) return 'Minggu ini';
    return 'Sebelumnya';
  }

  String _ago(DateTime t) {
    final m = _now.difference(t).inMinutes;
    if (_group(t) == 'Hari ini') {
      if (m < 1) return 'baru saja';
      if (m < 60) return '$m mnt';
      return '${m ~/ 60} jam';
    }
    if (_group(t) == 'Kemarin') return '${t.hour.toString().padLeft(2, '0')}.${t.minute.toString().padLeft(2, '0')}';
    return '${t.day} ${monthsId[t.month - 1]}';
  }

  Widget _alertList(Pal p) {
    if (_alerts.isEmpty && _loading) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        Skeleton(height: 116, radius: 16), SizedBox(height: 12), Skeleton(height: 116, radius: 16),
      ]);
    }
    if (_error != null && _alerts.isEmpty) return ListView(children: [const SizedBox(height: 60), InlineMessage(_error!, onRetry: reload)]);
    final shown = _alerts.where((a) {
      final s = a['severity'] == 'pulih' ? 'info' : a['severity'];
      return _severity == 'semua' || s == _severity;
    }).toList();
    final children = <Widget>[];
    String? group;
    for (final a in shown) {
      final t = (DateTime.tryParse(a['created_at']?.toString() ?? '') ?? _now).toLocal();
      final g = _group(t);
      if (g != group) {
        children.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Overline(g)));
        group = g;
      }
      children.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: _alertCard(p, a, _ago(t))));
    }
    children.add(Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 96),
      child: Column(children: [
        const SizedBox(height: 12),
        Image.asset('assets/img/empty_alert.webp', width: 168, height: 120),
        const SizedBox(height: 8),
        Text(shown.isEmpty ? 'Belum ada alert. Buat alert untuk metrik yang ingin dipantau.' : 'Tidak ada alert lain minggu ini',
            textAlign: TextAlign.center, style: ts(13, w500, p.mute)),
      ]),
    ));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), children: children);
  }

  (I3, Tone, Color, String, BadgeKind) _sev(String? s) => switch (s) {
        'kritis' => (Icx.alertTriangle, Tone.danger, const Color(0xFFE04848), 'Kritis', BadgeKind.danger),
        'peringatan' => (Icx.alertCircle, Tone.warning, const Color(0xFFF5A623), 'Peringatan', BadgeKind.warning),
        _ => (Icx.activity, Tone.teal, const Color(0xFF15A697), 'Info', BadgeKind.info),
      };

  Widget _alertCard(Pal p, Map<String, dynamic> a, String when) {
    final (icon, tone, accent, label, kind) = _sev(a['severity']?.toString());
    final (bg, fg) = toneColors(p, tone);
    final title = (a['title'] ?? '').toString().replaceFirst(RegExp(r'^Pulih: '), '');
    final meta = [a['scope_label'], a['metric_label']].where((e) => e != null && '$e'.isNotEmpty).join(' · ');
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.rule)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAlert(a),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 15, 17, 15),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  IconTile(icon, bg: bg, fg: fg, size: 36, radius: 10, iconSize: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(title, style: ts(13, w600, p.ink))),
                        const SizedBox(width: 8),
                        Text(when, style: ts(12, w400, p.mute)),
                      ]),
                      const SizedBox(height: 4),
                      Text((a['message'] ?? '').toString(), style: ts(12, w400, p.text2)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 26,
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          StatusBadge(label, kind: kind),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w400, p.mute)),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openAlert(Map<String, dynamic> a) async {
    final p = Pal.of(context);
    final (_, _, _, label, kind) = _sev(a['severity']?.toString());
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            Row(children: [StatusBadge(label, kind: kind), const Spacer()]),
            const SizedBox(height: 10),
            Text((a['title'] ?? '').toString(), style: ts(18, w700, p.ink, lh: 1.35)),
            const SizedBox(height: 6),
            Text((a['message'] ?? '').toString(), style: ts(14, w400, p.text2, lh: 1.5)),
            const SizedBox(height: 20),
            PrimaryButton('Tanya agent kenapa', icon: Icx.sparkles, onTap: () => Navigator.pop(ctx, 'ask')),
            if (a['acknowledged'] != true && a['resolved'] != true) ...[
              const SizedBox(height: 10),
              PrimaryButton('Tandai sudah dibaca', color: p.surfaceMuted, fg: p.ink, onTap: () => Navigator.pop(ctx, 'ack')),
            ],
          ]),
        ),
      ),
    );
    if (action == 'ask') {
      widget.onAsk?.call('Kenapa ${(a['title'] ?? '').toString().replaceFirst(RegExp(r'^Pulih: '), '')}? Jelaskan penyebab dan apa yang perlu dilakukan.');
    } else if (action == 'ack' && a['id'] is int) {
      try {
        await ApiClient.ackAlert(a['id'] as int);
        reload();
      } catch (e) {
        if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
      }
    }
  }

  Future<void> _filter() async {
    final p = Pal.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 16),
            Text('Tampilkan alert', style: ts(18, w700, p.ink, lh: 1.35)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, l) in const [('semua', 'Semua'), ('kritis', 'Kritis'), ('peringatan', 'Peringatan'), ('info', 'Info')])
                PillChip(l, selected: _severity == k, onTap: () => Navigator.pop(ctx, k)),
            ]),
          ]),
        ),
      ),
    );
    if (picked != null) setState(() { _severity = picked; _tab = 0; });
  }

  // ── Watchlist ──

  Widget _ruleList(Pal p) {
    if (_rules.isEmpty) {
      return ListView(padding: const EdgeInsets.fromLTRB(32, 48, 32, 96), children: [
        Image.asset('assets/img/empty_alert.webp', width: 168, height: 120),
        const SizedBox(height: 12),
        Text('Belum ada metrik yang dipantau', textAlign: TextAlign.center, style: ts(15, w600, p.ink)),
        const SizedBox(height: 4),
        Text('Ketuk "Buat alert", atau tekan Pantau di jawaban agent.', textAlign: TextAlign.center, style: ts(13, w400, p.mute, lh: 1.5)),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _rules.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ruleCard(p, _rules[i]),
    );
  }

  Widget _ruleCard(Pal p, Map<String, dynamic> r) {
    final status = (r['status'] ?? 'normal').toString();
    final (label, kind) = switch (status) {
      'kritis' => ('Kritis', BadgeKind.danger),
      'peringatan' => ('Peringatan', BadgeKind.warning),
      'nonaktif' => ('Nonaktif', BadgeKind.neutral),
      _ => ('Normal', BadgeKind.success),
    };
    final (icon, tone) = kpiIcon(r['metric']?.toString() ?? '');
    final (bg, fg) = toneColors(p, tone);
    final trend = ((r['trend'] as List?) ?? const []).map(toNum).toList();
    final active = r['active'] != false;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      radius: 16,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconTile(icon, bg: bg, fg: fg, size: 36, radius: 10, iconSize: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((r['name'] ?? '${r['metric_label']} ${r['scope_label']}').toString(), style: ts(13, w600, p.ink)),
            const SizedBox(height: 2),
            Text('${r['scope_label'] ?? ''} · ${r['threshold_label'] ?? ''}', style: ts(12, w400, p.text2)),
            const SizedBox(height: 8),
            Row(children: [
              StatusBadge(label, kind: kind),
              const SizedBox(width: 8),
              if (r['value_label'] != null) Text('Terakhir ${r['value_label']}', style: ts(12, w400, p.mute)),
            ]),
            if (trend.whereType<double>().length > 1) ...[
              const SizedBox(height: 8),
              Sparkline(trend, color: status == 'normal' ? p.teal600 : p.dangerSolid, height: 28),
            ],
          ]),
        ),
        Column(children: [
          Switch(
            value: active,
            activeColor: Colors.white,
            activeTrackColor: p.teal600,
            onChanged: _preview ? null : (v) => _patch(r, {'active': v}),
          ),
          IconButton(
            tooltip: 'Hapus',
            onPressed: _preview ? null : () => _delete(r),
            icon: Ic(Icx.x, size: 18, color: p.mute),
          ),
        ]),
      ]),
    );
  }

  Future<void> _patch(Map<String, dynamic> r, Map<String, dynamic> patch) async {
    try {
      await ApiClient.updateWatchRule(r['id'] as int, patch);
      reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  Future<void> _delete(Map<String, dynamic> r) async {
    final p = Pal.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: p.surface,
        title: Text('Hapus alert ini?', style: ts(18, w700, p.ink)),
        content: Text('Agent berhenti memantau ${r['metric_label']} ${r['scope_label']}.', style: ts(14, w400, p.text2, lh: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Batal', style: ts(14, w600, p.text2))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Hapus', style: ts(14, w600, p.danger))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiClient.deleteWatchRule(r['id'] as int);
      reload();
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }
}

/// "Buat alert" form: metric, territory, condition and threshold.
class _RuleSheet extends StatefulWidget {
  const _RuleSheet({required this.meta, this.question});
  final Map<String, dynamic> meta;
  final String? question;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  static const _fallbackMetrics = [
    {'key': 'revenue', 'label': 'Revenue'},
    {'key': 'payload', 'label': 'Payload data'},
    {'key': 'subs', 'label': 'Pelanggan aktif (RGU 90D)'},
    {'key': 'gross_add', 'label': 'Gross add'},
    {'key': 'availability', 'label': 'Site availability 4G'},
  ];
  static const _levels = [('circle', 'Jawa'), ('region', 'Region'), ('branch', 'Branch'), ('kabkota', 'Kab/Kota')];
  static const _conditions = [('turun', 'Turun'), ('naik', 'Naik'), ('berubah', 'Berubah'), ('di_bawah', 'Di bawah'), ('di_atas', 'Di atas')];

  late String _metric;
  String _level = 'circle';
  String _condition = 'turun';
  final _scope = TextEditingController();
  final _threshold = TextEditingController(text: '5');
  int _days = 1;
  bool _email = false;

  List<Map> get _metrics => ((widget.meta['metrics'] as List?) ?? _fallbackMetrics).cast<Map>();

  @override
  void initState() {
    super.initState();
    // Guess the metric and territory from the agent's question.
    final q = (widget.question ?? '').toLowerCase();
    _metric = q.contains('payload') ? 'payload'
        : q.contains('gross add') ? 'gross_add'
        : q.contains('availability') || q.contains('site') ? 'availability'
        : q.contains('pelanggan') || q.contains('rgu') ? 'subs'
        : 'revenue';
    if (_metric == 'availability') { _condition = 'di_bawah'; _threshold.text = '99'; }
    for (final r in ['jawa barat', 'jawa tengah', 'jawa timur', 'jabodetabek']) {
      if (q.contains(r)) { _level = 'region'; _scope.text = r.toUpperCase(); }
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    _threshold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final unit = _condition.startsWith('di_') ? (_metric == 'availability' ? '%' : '') : (_metric == 'availability' ? 'pp' : '%');
    Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(t, style: ts(13, w600, p.text2)));
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.rule));
    InputDecoration deco(String hint, {String? suffix}) => InputDecoration(
          isDense: true,
          filled: true,
          fillColor: p.surface,
          hintText: hint,
          suffixText: suffix,
          hintStyle: ts(14, w400, p.mute),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: p.teal600, width: 1.5)),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Center(child: SheetHandle()),
            const SizedBox(height: 16),
            Text('Buat alert', style: ts(18, w700, p.ink, lh: 1.35)),
            if (widget.question != null) ...[
              const SizedBox(height: 4),
              Text('Dari pertanyaan: "${widget.question}"', maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(12, w400, p.mute)),
            ],
            label('Metrik'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in _metrics)
                PillChip(m['label'].toString(), selected: _metric == m['key'], onTap: () => setState(() => _metric = m['key'].toString())),
            ]),
            label('Wilayah'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, l) in _levels) PillChip(l, selected: _level == k, onTap: () => setState(() => _level = k)),
            ]),
            if (_level != 'circle') ...[
              const SizedBox(height: 8),
              TextField(controller: _scope, textCapitalization: TextCapitalization.characters, style: ts(14, w400, p.ink),
                  decoration: deco(_level == 'region' ? 'mis. JAWA BARAT' : _level == 'branch' ? 'mis. BANDUNG' : 'mis. GARUT')),
            ],
            label('Kondisi'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (k, l) in _conditions) PillChip(l, selected: _condition == k, onTap: () => setState(() => _condition = k)),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _threshold,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: ts(14, w400, p.ink),
                  decoration: deco('Ambang', suffix: unit),
                ),
              ),
              const SizedBox(width: 12),
              Text('selama', style: ts(13, w400, p.text2)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _days,
                underline: const SizedBox(),
                dropdownColor: p.surface,
                style: ts(14, w600, p.ink),
                items: [for (final d in const [1, 2, 3, 5, 7]) DropdownMenuItem(value: d, child: Text('$d hari'))],
                onChanged: (v) => setState(() => _days = v ?? 1),
              ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _email,
              activeColor: Colors.white,
              activeTrackColor: p.teal600,
              onChanged: (v) => setState(() => _email = v),
              title: Text('Kirim juga ke email', style: ts(14, w500, p.ink)),
            ),
            const SizedBox(height: 8),
            PrimaryButton('Simpan alert', icon: Icx.bellRing, onTap: () {
              final t = double.tryParse(_threshold.text.replaceAll(',', '.'));
              if (t == null || (_level != 'circle' && _scope.text.trim().isEmpty)) {
                showToast(context, 'Lengkapi wilayah dan ambang.', ok: false);
                return;
              }
              Navigator.pop(context, {
                'metric': _metric,
                'scope_level': _level,
                'scope_value': _level == 'circle' ? 'JAVA' : _scope.text.trim().toUpperCase(),
                'condition': _condition,
                'threshold': t,
                'days': _days,
                'notify_inapp': true,
                'notify_email': _email,
                if (widget.question != null) 'source_question': widget.question,
              });
            }),
          ]),
        ),
      ),
    );
  }
}
