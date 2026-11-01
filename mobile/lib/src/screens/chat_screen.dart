import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_state.dart';
import '../services/keep_alive_service.dart';
import '../services/report_export.dart';
import '../ui/answer_v2.dart';
import '../ui/chart.dart';
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../ui/mock_icons.dart';
import '../ui/v2.dart';
import '../widgets/chart_panel.dart';
import 'location_sheet.dart';
import 'report_list_screen.dart';

/// Android · Tanya Agent v2 (design/mockup-v2/02-tanya-agent): app bar with
/// history, bell and profile; conversation with answer cards (validated and
/// step pills, headline KPIs, Grafik / Tabel / Peta, actions); follow-up chips
/// and the composer docked over a fade. Lives in the home shell's first tab.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.preview, this.previewTouch, this.onWatch, this.onOpenMap});

  /// Messages to show instead of a live session (golden tests and demos).
  final List<ChatMessage>? preview;
  final int? previewTouch;

  /// Opens the Alert tab to create a watch rule for a question.
  final void Function(String question)? onWatch;

  /// Switches to the Peta Agent tab.
  final VoidCallback? onOpenMap;

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  String _sessionId = '';
  List<dynamic> _history = [];
  StreamSubscription? _sub;
  final SpeechToText _speech = SpeechToText();
  bool _listening = false;

  String get _lang => AppState.I.lang;

  @override
  void initState() {
    super.initState();
    if (widget.preview != null) {
      _messages.addAll(widget.preview!);
    } else {
      _init();
    }
  }

  Future<void> _init() async {
    final p = await SharedPreferences.getInstance();
    final uname = AuthState.user?['username'] ?? 'anon';
    _sessionId = _newId();
    await p.setString('session::$uname', _sessionId);
    if (mounted) setState(() {});
    _loadHistory();
  }

  String _newId() => 'm_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';

  Future<void> _loadHistory() async {
    try {
      final h = await ApiClient.historySessions();
      if (mounted) setState(() => _history = h);
    } catch (_) {}
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void newChat() {
    if (_busy) return;
    setState(() {
      _messages.clear();
      _sessionId = _newId();
    });
    SharedPreferences.getInstance().then((p) {
      final uname = AuthState.user?['username'] ?? 'anon';
      p.setString('session::$uname', _sessionId);
    });
  }

  /// Ask a question from elsewhere (Dashboard "Tanya detail", quick actions).
  void ask(String q) => _send(q);

  ChatMessage get _assistant => _messages.lastWhere((m) => !m.isUser);

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _messages.add(ChatMessage(isUser: true, content: text));
      _messages.add(ChatMessage(isUser: false, status: 'Menganalisis…')..startedAt = DateTime.now());
      _busy = true;
    });
    _scrollDown();
    KeepAliveService.start(text: 'Menganalisis pertanyaan Anda…');

    final history = _messages
        .where((m) => m.content.trim().isNotEmpty)
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.content.length > 1500 ? m.content.substring(0, 1500) : m.content})
        .toList();

    var gotDone = false, gotContent = false;
    try {
      _sub = ApiClient.chatStream(text, _sessionId, _lang, history: history).listen((ev) {
        final event = ev.key;
        final data = ev.value;
        final a = _assistant;
        switch (event) {
          case 'step_start':
            setState(() {
              a.steps++;
              a.status = (data['label'] ?? data['step'] ?? 'Memproses').toString();
            });
          case 'route':
            a.domain = data['domain']?.toString();
            a.domainLabel = data['label']?.toString();
          case 'sql':
            a.sql = data['sql']?.toString();
          case 'result':
            final cols = (data['columns'] as List?)?.map((e) => e.toString()).toList() ?? [];
            final rows = (data['rows'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
            setState(() {
              a.result = ResultTable(cols, rows, (data['row_count'] as int?) ?? rows.length,
                  chart: data['chart'] is Map ? Map<String, dynamic>.from(data['chart'] as Map) : null);
              a.kpis = (data['kpis'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ?? [];
              a.source = data['source']?.toString();
            });
          case 'chart_spec':
            // Server builds the chart spec after the result (build_chart_spec);
            // kept as a fallback when the result carries no Redesign chart.
            if ((data['mode'] ?? 'none').toString() != 'none') {
              setState(() => a.chartSpec = Map<String, dynamic>.from(data));
            }
          case 'profile_domain_result':
            a.profileResults.add(ProfileSection(
              title: (data['section_title'] ?? '').toString(),
              domain: (data['domain'] ?? '').toString(),
              status: (data['status'] ?? 'ok').toString(),
              rowCount: (data['row_count'] as int?) ?? 0,
              columns: (data['columns'] as List?)?.map((e) => e.toString()).toList() ?? [],
              rows: (data['rows'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
              error: data['error']?.toString(),
              chart: data['chart'] is Map ? Map<String, dynamic>.from(data['chart'] as Map) : null,
            ));
            setState(() {});
          case 'reflect':
            final verdict = (data['verdict'] ?? '').toString();
            setState(() {
              a.validated = verdict == 'ok';
              a.status = verdict == 'ok' ? 'Jawaban relevan' : 'Mencari jawaban lebih baik…';
            });
          case 'reroute':
            setState(() => a.status = 'Mengalihkan ke domain lain…');
          case 'clarify':
            a.status = 'Menunggu konfirmasi…';
          case 'token':
            gotContent = true;
            setState(() {
              a.status = null;
              a.content += (data['t'] ?? '').toString();
            });
            _scrollDown();
          case 'done':
            gotDone = true;
            setState(() {
              a.status = null;
              final ms = data['elapsed_ms'];
              a.elapsed = ms is num
                  ? Duration(milliseconds: ms.toInt())
                  : a.startedAt == null
                      ? null
                      : DateTime.now().difference(a.startedAt!);
              if (a.error == null) a.validated = true;
            });
          case 'error':
            setState(() {
              a.error = (data['error'] ?? 'error').toString();
              a.status = null;
            });
        }
      }, onError: (e) {
        if (!gotDone && !gotContent) setState(() => _assistant.error = 'Koneksi terputus: $e');
        _finish();
      }, onDone: _finish);
    } catch (e) {
      setState(() => _assistant.error = 'Koneksi terputus: $e');
      _finish();
    }
  }

  void _finish() {
    KeepAliveService.stop();
    if (!mounted) return;
    setState(() {
      _busy = false;
      final a = _messages.isEmpty ? null : _assistant;
      if (a != null) {
        a.status = null;
        a.elapsed ??= a.startedAt == null ? null : DateTime.now().difference(a.startedAt!);
      }
    });
    _loadHistory();
    _scrollDown();
  }

  void _stop() {
    _sub?.cancel();
    _finish();
  }

  /// Saves the answer to Laporan (Ad-hoc) and opens the export sheet.
  Future<void> _export(int i) async {
    final r = _messages[i].result;
    if (r == null) return;
    final q = i > 0 ? _messages[i - 1].content : 'Hasil agent';
    final rows = [for (final row in r.rows) Map<String, dynamic>.from(row)];
    try {
      final saved = await AdhocStore.add(q.length > 120 ? '${q.substring(0, 117)}…' : q, r.columns, rows);
      if (!mounted) return;
      final p = Pal.of(context);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: p.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (_) => ReportExportSheet(
          item: ReportItem(id: 'adhoc:${saved.id}', kind: 'adhoc', title: saved.title, format: 'XLSX', date: saved.savedAt, adhoc: saved),
        ),
      );
    } catch (e) {
      if (mounted) showToast(context, 'Export gagal: $e', ok: false);
    }
  }

  void _watch(int i) {
    final q = i > 0 ? _messages[i - 1].content : '';
    if (widget.onWatch != null) {
      widget.onWatch!(q);
    } else {
      showToast(context, 'Buka tab Alert untuk membuat watchlist.');
    }
  }

  /// Scope named in the conversation ("West Java"), shown under the title.
  String get _scope {
    const names = ['West Java', 'Central Java', 'East Java', 'Jabodetabek'];
    for (final m in _messages.reversed.where((m) => m.isUser)) {
      for (final n in names) {
        if (m.content.toLowerCase().contains(n.toLowerCase())) return n;
      }
    }
    return 'Circle Java';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final scope = V2Scope.maybeOf(context);
    final showSugg = !_busy && _messages.isNotEmpty && !_messages.last.isUser && _messages.last.error == null;
    return ColoredBox(
      color: V2.bg,
      child: Column(children: [
        SizedBox(height: top),
        V2AppBar(
          title: 'Tanya Agent',
          subtitle: '${_busy ? 'Menganalisis' : 'Online'} · $_scope',
          subtitleDot: _busy ? const Color(0xFFE0A100) : const Color(0xFF2E9E57),
          alertCount: scope?.alerts ?? 0,
          onBell: scope == null ? null : () => scope.openAlerts(),
          actions: [V2IconButton(icon: 'hist', label: 'Riwayat dan menu', onTap: _openMenu)],
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: _messages.isEmpty ? _welcome() : _conversation()),
            // the dock fades the conversation out above the composer (mockup .dfade)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 150,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00F5F9F8), V2.bg],
                      stops: [0, .4],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (showSugg) ...[_followUps(), const SizedBox(height: 14)],
                _composer(),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _conversation() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 170),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _messages[i].isUser ? _userBubble(_messages[i]) : _answer(i),
    );
  }

  Widget _userBubble(ChatMessage m) {
    return LayoutBuilder(builder: (context, c) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: c.maxWidth * .85),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.fromLTRB(15, 12, 15, 12),
          decoration: BoxDecoration(
            color: V2.teal600,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20), topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20), bottomRight: Radius.circular(6),
            ),
            boxShadow: [cssShadow(const Color(0x330E8579), 0, 6, 16)],
          ),
          child: Text(m.content, style: V2.b(14, FontWeight.w400, Colors.white, lh: 1.5)),
        ),
      );
    });
  }

  Widget _pill(String text, {String? icon, Color bg = V2.rule2, Color fg = V2.ink2, Widget? lead, VoidCallback? onTap}) {
    final child = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (lead != null) ...[lead, const SizedBox(width: 6)],
        if (icon != null) ...[MIcon(icon, size: 14, color: fg), const SizedBox(width: 6)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(12, FontWeight.w600, fg, lh: 1))),
      ]),
    );
    return onTap == null ? child : GestureDetector(onTap: onTap, child: child);
  }

  Widget _answer(int i) {
    final m = _messages[i];
    final live = m.status != null;
    final spec = m.result?.chart == null ? null : ChartSpec(m.result!.chart!);
    final rows = m.result?.rows ?? const <Map<String, dynamic>>[];
    final kpis = m.kpis.map(HeadlineKpi.fromJson).whereType<HeadlineKpi>().toList();
    final secs = m.elapsed == null ? null : m.elapsed!.inMilliseconds / 1000;
    final meta = [
      if (m.steps > 0) '${m.steps} langkah',
      if (secs != null) '${idNum(secs < .1 ? .1 : secs, 1)} dtk',
    ].join(' · ');
    final okSections = m.profileResults.where((s) => s.status == 'ok' && s.rows.isNotEmpty).toList();
    final spans = answerSpans(m.content);
    final showSql = m.sql != null && AuthState.canViewSql && widget.preview == null;
    final gap = const SizedBox(height: 11);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: V2.rule),
        boxShadow: [cssShadow(const Color(0x0D0F1F1D), 0, 4, 14)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 6, children: [
          if (live)
            _pill(m.status!, bg: V2.teal50, fg: V2.teal700,
                lead: const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: V2.teal700)))
          else if (m.validated && m.error == null)
            _pill('Tervalidasi', icon: 'check', bg: const Color(0xFFE6F4EA), fg: const Color(0xFF1F7A3A)),
          if (!live && meta.isNotEmpty) _pill(meta, onTap: showSql ? () => setState(() => m.showSql = !m.showSql) : null),
          if (!live && m.source != null) _pill(m.source!, icon: 'db', bg: const Color(0xFFE3F7FA), fg: const Color(0xFF0E6F7C)),
        ]),
        if (m.content.isNotEmpty) ...[
          gap,
          if (spans != null)
            // Flutter rounds each 21.7 px line up to 22 while CSS keeps 21.7, and puts
            // Prompt glyphs 1 px lower than the browser; size and place the block like
            // CSS so the text and the cards below sit where the mockup puts them.
            LayoutBuilder(builder: (context, c) {
              final tp = TextPainter(text: spans, textDirection: TextDirection.ltr)..layout(maxWidth: c.maxWidth);
              final lines = tp.computeLineMetrics().length;
              tp.dispose();
              return SizedBox(
                height: lines * 14 * 1.55,
                child: OverflowBox(alignment: Alignment.topLeft, maxHeight: double.infinity, child: Transform.translate(offset: const Offset(0, -1.0), child: Text.rich(spans))),
              );
            })
          else
            MarkdownBody(
              data: m.content,
              styleSheet: MarkdownStyleSheet(
                p: V2.b(14, FontWeight.w400, V2.ink, lh: 1.55),
                strong: V2.b(14, FontWeight.w600, V2.ink, lh: 1.55),
                h1: V2.d(17, FontWeight.w700, V2.ink, lh: 1.3),
                h2: V2.d(15, FontWeight.w700, V2.ink, lh: 1.3),
                h3: V2.d(14, FontWeight.w600, V2.ink, lh: 1.3),
                listBullet: V2.b(14, FontWeight.w400, V2.ink, lh: 1.55),
                tableColumnWidth: const IntrinsicColumnWidth(),
                tableHead: V2.d(11.5, FontWeight.w600, V2.mute),
                tableBody: V2.b(12.5, FontWeight.w400, V2.ink),
                tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                tableBorder: TableBorder.all(color: V2.rule, width: 1),
              ),
            ),
        ] else if (live && m.result == null) ...[
          gap,
          const Skeleton(width: 280),
          const SizedBox(height: 8),
          const Skeleton(width: 220),
        ],
        if (kpis.isNotEmpty) ...[gap, KpiGridV2(kpis: kpis)],
        if (m.result != null && rows.isNotEmpty) ...[
          gap,
          AnswerVizV2(
            key: ValueKey('viz$i'),
            columns: m.result!.columns,
            rows: rows,
            spec: spec,
            initialHover: widget.previewTouch,
            onOpenMap: widget.onOpenMap,
            chartFallback: spec != null && spec.type != 'none' && spec.type != 'kpi'
                ? SmartChart(spec: spec, rows: rows, height: spec.type == 'hbar' ? 220 : 170)
                : m.chartSpec != null
                    ? ChartPanel(columns: m.result!.columns, rows: rows, spec: m.chartSpec)
                    : null,
          ),
        ],
        for (final s in okSections) ...[
          gap,
          Text(s.title, style: V2.d(13, FontWeight.w600, V2.ink)),
          const SizedBox(height: 8),
          AnswerVizV2(
            columns: s.columns,
            rows: s.rows,
            spec: s.chart == null ? null : ChartSpec(s.chart!),
            chartFallback: s.chart != null && ChartSpec(s.chart!).type != 'none' ? SmartChart(spec: ChartSpec(s.chart!), rows: s.rows, height: 150) : null,
          ),
        ],
        if (m.locationResult != null) LocationResultView(data: m.locationResult!, lang: _lang),
        if (showSql && m.showSql) ...[
          gap,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: V2.rule2)),
            child: SelectableText(m.sql!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: V2.ink)),
          ),
        ],
        if (m.error != null) ...[
          gap,
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const MIcon('warn', size: 18, color: V2.red),
              const SizedBox(width: 10),
              Expanded(child: Text(m.error!, style: V2.b(13, FontWeight.w500, V2.red, lh: 1.4))),
            ]),
          ),
        ],
        if (!live && m.error == null && (m.result != null || m.content.isNotEmpty)) ...[
          gap,
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ActionButton(icon: 'copy', label: 'Salin', onTap: () => _copy(m)),
            _ActionButton(icon: 'dl', label: 'Ekspor', onTap: m.result != null && AuthState.canExport ? () => _export(i) : null),
            _ActionButton(icon: 'bellplus', label: 'Pantau', tint: true, onTap: () => _watch(i)),
            if (m.result != null && widget.onOpenMap != null) _ActionButton(icon: 'map', label: 'Peta Agent', onTap: widget.onOpenMap),
          ]),
        ],
      ]),
    );
  }

  Future<void> _copy(ChatMessage m) async {
    await Clipboard.setData(ClipboardData(text: m.content.replaceAll('**', '')));
    if (mounted) showToast(context, 'Jawaban disalin.');
  }

  /// Follow-up questions built from the answer: why the named place moved, the
  /// headline count KPI, next month's projection, and a neighbouring region.
  List<String> _suggestions(ChatMessage m) {
    final spec = m.result?.chart == null ? null : ChartSpec(m.result!.chart!);
    final rows = m.result?.rows ?? const [];
    final text = m.content;
    final out = <String>[];
    final named = RegExp(r'\*\*([A-Z][A-Za-z .\-]{2,30}?)(?:\s*\([^)]*\))?\*\*').allMatches(text).map((x) => x[1]!.trim())
        .where((w) => !RegExp(r'\d').hasMatch(w) && !RegExp(r'^(naik|turun|revenue|rp)\b', caseSensitive: false).hasMatch(w)).toList();
    if (named.isNotEmpty) {
      out.add('Kenapa ${named.first} ${RegExp(r'turun|−\d|-\d').hasMatch(text) ? 'turun' : 'naik'}?');
    } else {
      final key = spec?.mapKey ?? spec?.x;
      if (spec != null && key != null && rows.isNotEmpty && spec.type != 'line' && spec.type != 'area') {
        final top = (rows.first[key] ?? '').toString();
        if (top.isNotEmpty) out.add('Kenapa ${_title(top)} seperti ini?');
      }
    }
    for (final k in m.kpis.map(HeadlineKpi.fromJson).whereType<HeadlineKpi>()) {
      if (k.format == 'number' && k.value == k.value.roundToDouble() && RegExp(r'bawah|below|gagal|fail|outage', caseSensitive: false).hasMatch(k.column)) {
        out.add('${idNum(k.value, 0)} ${k.label().toLowerCase()}');
        break;
      }
    }
    final d = spec?.x == null || rows.isEmpty ? null : parseDate(rows.last[spec!.x]);
    out.add(d == null ? 'Proyeksi bulan depan' : 'Proyeksi ${_monthLong[d.$2 % 12]}');
    const regions = ['West Java', 'Central Java', 'East Java', 'Jabodetabek'];
    final i = regions.indexWhere((r) => text.contains(r));
    out.add(i < 0 ? 'Bandingkan dengan bulan lalu' : 'Bandingkan dengan ${regions[(i + 1) % regions.length]}');
    return out;
  }

  static const _monthLong = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  String _title(String s) => s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');

  Widget _followUps() {
    final items = _suggestions(_messages.last);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Semantics(
          button: true,
          child: GestureDetector(
            onTap: () => _send(items[i]),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFFFFC2AF))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const MIcon('spark', size: 16, color: V2.coral),
                const SizedBox(width: 8),
                Text(items[i], style: V2.d(12.5, FontWeight.w500, V2.ink, lh: 1)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    const starters = [
      ('wallet', Color(0xFFFCEDD3), Color(0xFFB7791F), 'Revenue', 'Revenue West Java bulan ini vs bulan lalu?'),
      ('tower', Color(0xFFFBE2E8), Color(0xFFC23A5B), 'Site', 'Site dengan availability terendah minggu ini di Central Java'),
      ('pulse', Color(0xFFE6F7F5), V2.teal700, 'Performance', 'Site productivity terendah di East Java bulan ini'),
      ('map', Color(0xFFE3F7FA), Color(0xFF0E6F7C), 'Profil wilayah', 'Tampilkan profil lengkap kota Surabaya'),
    ];
    final name = (AuthState.user?['full_name'] ?? AuthState.user?['username'] ?? '').toString().split(' ').first;
    return ListView(padding: const EdgeInsets.fromLTRB(14, 24, 14, 170), children: [
      Text(name.isEmpty ? 'Mau tahu apa hari ini?' : 'Halo, $name. Mau tahu apa hari ini?', style: V2.d(20, FontWeight.w700, V2.ink, lh: 1.3)),
      const SizedBox(height: 6),
      Text('Tanya revenue, site, performance, market share atau profil wilayah di Circle Java. Agent menulis query, mengambil data, lalu menyajikan angka, grafik dan peta.',
          style: V2.b(13.5, FontWeight.w400, V2.ink2, lh: 1.5)),
      const SizedBox(height: 18),
      for (final (icon, bg, fg, t, q) in starters)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => _send(q),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: V2.rule)),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                  child: MIcon(icon, size: 18, color: fg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t, style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.3)),
                    Text(q, style: V2.b(12.5, FontWeight.w400, V2.ink2, lh: 1.4)),
                  ]),
                ),
                const MIcon('chevr', size: 16, color: V2.mute),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: V2.teal200),
          boxShadow: [cssShadow(const Color(0x2404332E), 0, 10, 26)],
        ),
        child: Row(children: [
          Semantics(
            button: true,
            label: 'Lampiran dan menu',
            child: GestureDetector(
              onTap: _openMenu,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: const MIcon('clip', size: 20, color: V2.ink2),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            // The placeholder is drawn beside the field, centered like the mockup's
            // two-line 14 px hint, so typed text can keep a comfortable line height.
            child: Stack(alignment: Alignment.centerLeft, children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (_, v, __) => v.text.isNotEmpty
                    ? const SizedBox.shrink()
                    : IgnorePointer(
                        child: Text('Tanya tentang bisnis Circle Java…',
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: V2.b(14, FontWeight.w400, const Color(0xFF8A9A97), lh: 1)),
                      ),
              ),
              Semantics(
                label: 'Tanya tentang bisnis Circle Java',
                textField: true,
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: V2.b(14, FontWeight.w400, V2.ink, lh: 1.4),
                  cursorColor: V2.teal600,
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: _listening ? 'Berhenti mendengarkan' : 'Input suara',
            child: GestureDetector(
              onTap: _busy ? null : _voice,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: _listening ? V2.teal50 : null, borderRadius: BorderRadius.circular(12)),
                child: MIcon('mic', size: 19, color: _listening ? V2.teal700 : V2.mute),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: _busy ? 'Hentikan' : 'Kirim',
            child: GestureDetector(
              onTap: _busy ? _stop : () => _send(),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: cssLinear(135, const [V2.teal600, Color(0xFF1597A8)], const Size(44, 44)),
                ),
                child: _busy
                    ? Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)))
                    : const MIcon('send', size: 20, color: Colors.white),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _voice() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(onStatus: (s) {
      if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
    });
    if (!ok) {
      if (mounted) showToast(context, 'Input suara tidak tersedia di perangkat ini.', ok: false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: _lang == 'en' ? 'en_US' : 'id_ID'),
      onResult: (r) {
        _input.text = r.recognizedWords;
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        if (r.finalResult && mounted) setState(() => _listening = false);
      },
    );
  }

  Future<void> _shareLocation() async {
    final coord = await getCurrentCoord(context);
    if (coord == null) return;
    setState(() {
      _messages.add(ChatMessage(isUser: true, content: 'Lokasi saya (${coord.$1.toStringAsFixed(5)}, ${coord.$2.toStringAsFixed(5)})'));
      _messages.add(ChatMessage(isUser: false, status: 'Mencari kecamatan & lokasi terdekat…')..startedAt = DateTime.now());
    });
    _scrollDown();
    try {
      final data = await ApiClient.geoLocate(coord.$1, coord.$2);
      final a = _assistant;
      final kec = data['kecamatan'];
      setState(() {
        a.status = null;
        a.elapsed = DateTime.now().difference(a.startedAt!);
        a.content = kec != null
            ? '**Kecamatan ${kec['kecamatan'] ?? '-'}**, ${kec['kabkota'] ?? '-'}'
            : 'Lokasi tidak terpetakan ke kecamatan.';
        a.locationResult = data;
      });
    } catch (e) {
      setState(() {
        _assistant.status = null;
        _assistant.error = 'Gagal: $e';
      });
    }
    _scrollDown();
  }

  Future<void> _summarize() async {
    final turns = _messages
        .where((m) => m.content.trim().isNotEmpty || m.result != null)
        .map((m) => {
              'role': m.isUser ? 'user' : 'assistant',
              'content': m.content,
              'domain': m.domain,
              'row_count': m.result?.rowCount,
              'result': m.result == null
                  ? null
                  : {'columns': m.result!.columns, 'rows': m.result!.rows.take(50).toList(), 'row_count': m.result!.rowCount},
            })
        .toList();
    if (turns.isEmpty) {
      showToast(context, 'Belum ada percakapan untuk diringkas.');
      return;
    }
    showToast(context, 'Membuat ringkasan dan mengirim email…');
    try {
      final res = await ApiClient.summarizeChat(turns, _lang);
      if (mounted) showToast(context, res['message']?.toString() ?? 'Email terkirim.');
    } catch (e) {
      if (mounted) showToast(context, e.toString().replaceFirst('Exception: ', ''), ok: false);
    }
  }

  void _openMenu() {
    final p = Pal.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .92,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          const SheetHandle(),
          const SizedBox(height: 16),
          Text('Percakapan', style: ts(18, w700, p.ink, lh: 1.35)),
          const SizedBox(height: 12),
          _menuItem(p, Icx.plus, 'Chat baru', () { Navigator.pop(ctx); newChat(); }),
          _menuItem(p, Icx.mail, 'Ringkas & kirim email', () { Navigator.pop(ctx); _summarize(); }),
          _menuItem(p, Icx.mapPin, 'Bagikan lokasi saya', () { Navigator.pop(ctx); _shareLocation(); }),
          _menuItem(p, Icx.radio, 'Performa site', () { Navigator.pop(ctx); Navigator.pushNamed(context, '/site'); }),
          _menuItem(p, Icx.download, 'Unduh APK', () { Navigator.pop(ctx); Navigator.pushNamed(context, '/download'); }),
          const SizedBox(height: 12),
          const Overline('Riwayat'),
          const SizedBox(height: 8),
          if (_history.isEmpty) Text('Belum ada riwayat.', style: ts(13, w400, p.mute)),
          for (final h in _history)
            _menuItem(
              p,
              Icx.history,
              (h['title'] ?? 'Chat').toString(),
              () { Navigator.pop(ctx); _openSession(h['session_id'].toString()); },
              sub: '${h['message_count'] ?? 0} pesan',
              selected: h['session_id'] == _sessionId,
            ),
        ]),
      ),
    );
  }

  Widget _menuItem(Pal p, I3 icon, String label, VoidCallback onTap, {String? sub, bool selected = false}) {
    return Material(
      color: selected ? p.teal50 : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(children: [
            Ic(icon, size: 18, color: p.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, w500, p.ink)),
                if (sub != null) Text(sub, style: ts(12, w400, p.mute)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openSession(String sid) async {
    if (_busy) return;
    final msgs = await ApiClient.sessionMessages(sid);
    setState(() {
      _sessionId = sid;
      _messages.clear();
      for (final m in msgs) {
        _messages.add(ChatMessage(
          isUser: m['role'] == 'user',
          content: (m['content'] ?? '').toString(),
          domain: m['domain'],
          sql: m['sql_query'],
        ));
      }
    });
    final pr = await SharedPreferences.getInstance();
    final uname = AuthState.user?['username'] ?? 'anon';
    await pr.setString('session::$uname', sid);
    _scrollDown();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

/// Answer card action: outlined, or teal-tinted for Pantau.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, this.onTap, this.tint = false});
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    final fg = tint ? V2.teal700 : V2.ink2;
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: tint ? V2.teal50 : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: tint ? null : Border.all(color: V2.rule),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MIcon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(label, style: V2.d(12.5, FontWeight.w600, fg, lh: 1)),
            ]),
          ),
        ),
      ),
    );
  }
}
