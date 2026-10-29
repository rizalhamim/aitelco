import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../app_state.dart';
import '../services/keep_alive_service.dart';
import '../ui/chart.dart';
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';
import '../widgets/collapsible.dart';
import '../widgets/data_table_view.dart';
import 'location_sheet.dart';

/// Android · Tanya Agent: header, conversation with answer cards (pipeline
/// meta, validated chip, KPI tiles, chart, Export / Pantau), follow-up chips
/// and the composer. Lives in the home shell's first tab.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.preview, this.previewTouch, this.onWatch});

  /// Messages to show instead of a live session (golden tests and demos).
  final List<ChatMessage>? preview;
  final int? previewTouch;

  /// Opens the Alert tab to create a watch rule for a question.
  final void Function(String question)? onWatch;

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
            setState(() => a.result = ResultTable(cols, rows, (data['row_count'] as int?) ?? rows.length,
                chart: data['chart'] is Map ? Map<String, dynamic>.from(data['chart'] as Map) : null));
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
              a.elapsed = a.startedAt == null ? null : DateTime.now().difference(a.startedAt!);
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

  Future<void> _exportCsv(int i) async {
    final r = _messages[i].result;
    if (r == null) return;
    final q = i > 0 ? _messages[i - 1].content : 'hasil';
    final slug = q.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    String cell(dynamic v) {
      final s = (v ?? '').toString();
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final csv = StringBuffer()..writeln(r.columns.map(cell).join(','));
    for (final row in r.rows) {
      csv.writeln(r.columns.map((c) => cell(row[c])).join(','));
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final name = 'bizplan-${slug.isEmpty ? 'hasil' : (slug.length > 40 ? slug.substring(0, 40) : slug)}.csv';
      final f = File('${dir.path}/$name');
      await f.writeAsString('﻿$csv');
      ApiClient.logExport('csv', q);
      await OpenFilex.open(f.path);
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

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    return ColoredBox(
      color: p.bg,
      child: Column(children: [
        SizedBox(height: top),
        _header(p),
        Expanded(
          child: Stack(children: [
            Positioned(left: 160, top: -120, width: 360, height: 300, child: Glow(color: p.teal400, alpha: .13)),
            _messages.isEmpty ? _welcome(p) : _conversation(p),
          ]),
        ),
        if (!_busy && _messages.isNotEmpty && !_messages.last.isUser && _messages.last.error == null) _followUps(p),
        _composer(p),
      ]),
    );
  }

  Widget _header(Pal p) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.rule))),
      child: Row(children: [
        AppLogo(size: 44, radius: 14, border: p.teal200),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Tanya Agent', style: ts(16, w600, p.ink)),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: _busy ? p.warning : p.successSolid, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(_busy ? 'Menganalisis · Region Jawa' : 'Online · Region Jawa', style: ts(12, w400, p.mute)),
            ]),
          ]),
        ),
        SquareIconButton(Icx.history, tooltip: 'Riwayat & menu', onTap: _openMenu),
      ]),
    );
  }

  Widget _conversation(Pal p) {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _messages[i].isUser ? _userBubble(p, _messages[i]) : _answer(p, i),
    );
  }

  Widget _userBubble(Pal p, ChatMessage m) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 68),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: p.teal600,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18), topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18), bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(m.content, style: ts(14, w400, Colors.white, lh: 1.5)),
      ),
    );
  }

  Widget _answer(Pal p, int i) {
    final m = _messages[i];
    final live = m.status != null;
    final spec = m.result?.chart == null ? null : ChartSpec(m.result!.chart!);
    final rows = m.result?.rows ?? const <Map<String, dynamic>>[];
    final tiles = spec != null && spec.type != 'kpi' ? periodTotals(spec, m.result!.columns, rows) : const <KpiItem>[];
    final secs = m.elapsed == null ? null : m.elapsed!.inMilliseconds / 1000;
    final meta = live
        ? m.status!
        : [
            if (m.steps > 0) '${m.steps} langkah',
            if (secs != null) '${idNum(secs < .1 ? .1 : secs, 1)} dtk',
          ].join(' · ');
    final okSections = m.profileResults.where((s) => s.status == 'ok' && s.rows.isNotEmpty).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.rule),
        boxShadow: p.shadow,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 28,
          child: Row(children: [
            const _AiDot(),
            const SizedBox(width: 6),
            if (live) ...[
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: p.teal600)),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w600, p.mute))),
            if (!live && m.validated && m.error == null) _validatedChip(p),
          ]),
        ),
        if (m.content.isNotEmpty) ...[
          const SizedBox(height: 12),
          MarkdownBody(
            data: m.content,
            styleSheet: MarkdownStyleSheet(
              p: ts(14, w400, p.text2, lh: 1.5),
              strong: ts(14, w600, p.ink, lh: 1.5),
              h1: ts(18, w700, p.ink, lh: 1.35),
              h2: ts(16, w600, p.ink),
              h3: ts(14, w600, p.ink),
              listBullet: ts(14, w400, p.text2, lh: 1.5),
              tableColumnWidth: const IntrinsicColumnWidth(),
              tableHead: ts(12, w600, p.ink),
              tableBody: ts(12, w400, p.text2),
              tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              tableBorder: TableBorder.all(color: p.rule, width: 1),
              tableScrollbarThumbVisibility: true,
            ),
          ),
        ] else if (live && m.result == null) ...[
          const SizedBox(height: 12),
          const Skeleton(width: 280),
          const SizedBox(height: 8),
          const Skeleton(width: 220),
          const SizedBox(height: 8),
          const Skeleton(width: 160),
        ],
        if (tiles.isNotEmpty) ...[const SizedBox(height: 12), KpiGrid(items: tiles)],
        if (spec != null && spec.type != 'none' && rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          SmartChart(
            spec: spec,
            rows: rows,
            height: spec.type == 'line' || spec.type == 'area' ? 130 : 180,
            touchIndex: widget.previewTouch,
          ),
        ],
        if (m.result != null && rows.isNotEmpty && widget.preview == null)
          Collapsible(
            title: 'Data (${m.result!.rowCount} baris)',
            icon: Icons.table_chart_outlined,
            accent: p.teal700,
            child: DataTableView(columns: m.result!.columns, rows: rows),
          ),
        for (final s in okSections) ...[
          const SizedBox(height: 12),
          Text(s.title, style: ts(13, w600, p.ink)),
          const SizedBox(height: 8),
          if (s.chart != null && ChartSpec(s.chart!).type != 'none')
            SmartChart(spec: ChartSpec(s.chart!), rows: s.rows, height: 150)
          else
            DataTableView(columns: s.columns, rows: s.rows, maxRows: 10),
        ],
        if (m.locationResult != null) LocationResultView(data: m.locationResult!, lang: _lang),
        if (m.sql != null && AuthState.canViewSql && widget.preview == null)
          Collapsible(
            title: 'SQL',
            icon: Icons.code,
            accent: p.mute,
            child: SelectableText(m.sql!, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: p.ink)),
          ),
        if (m.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: p.dangerTint, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Ic(Icx.alertCircle, size: 18, color: p.danger),
              const SizedBox(width: 10),
              Expanded(child: Text(m.error!, style: ts(13, w500, p.danger, lh: 1.4))),
            ]),
          ),
        ],
        if (!live && m.error == null && (m.result != null || m.content.isNotEmpty)) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _ActionButton(
                icon: Icx.download,
                label: 'Export',
                onTap: m.result != null && AuthState.canExport ? () => _exportCsv(i) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: _ActionButton(icon: Icx.bellRing, label: 'Pantau', tint: true, onTap: () => _watch(i))),
          ]),
        ],
      ]),
    );
  }

  Widget _validatedChip(Pal p) => Container(
        height: 28,
        padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
        decoration: BoxDecoration(color: p.teal50, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Ic(Icx.check, size: 14, color: p.teal600),
          const SizedBox(width: 6),
          Text('Tervalidasi', style: ts(12, w600, p.teal800)),
        ]),
      );

  /// Follow-up questions built from the answer: why the named place moved,
  /// next month's projection, and the neighbouring region for comparison.
  List<String> _suggestions(ChatMessage m) {
    final spec = m.result?.chart == null ? null : ChartSpec(m.result!.chart!);
    final rows = m.result?.rows ?? const [];
    final text = m.content;
    final out = <String>[];
    final named = RegExp(r'\*\*([A-Za-z][A-Za-z .\-]{2,30})\*\*').allMatches(text).map((x) => x[1]!.trim())
        .where((w) => !RegExp(r'\d').hasMatch(w) && !RegExp(r'^(naik|turun|revenue)', caseSensitive: false).hasMatch(w)).toList();
    if (named.isNotEmpty) {
      out.add('Kenapa ${named.first} ${RegExp(r'turun|−|-\d').hasMatch(text) ? 'turun' : 'naik'}?');
    } else {
      final key = spec?.mapKey ?? spec?.x;
      if (spec != null && key != null && rows.isNotEmpty && spec.type != 'line' && spec.type != 'area') {
        final top = (rows.first[key] ?? '').toString();
        if (top.isNotEmpty) out.add('Kenapa ${_title(top)} seperti ini?');
      }
    }
    final d = spec?.x == null || rows.isEmpty ? null : parseDate(rows.last[spec!.x]);
    out.add(d == null ? 'Proyeksi bulan depan' : 'Proyeksi ${_monthLong[d.$2 % 12]}');
    const regions = [('Jawa Barat', 'Jabar'), ('Jawa Tengah', 'Jateng'), ('Jawa Timur', 'Jatim'), ('Jabodetabek', 'Jabodetabek')];
    final i = regions.indexWhere((r) => text.contains(r.$1) || text.contains(r.$2));
    out.add(i < 0 ? 'Bandingkan dengan bulan lalu' : 'Bandingkan ${regions[(i + 1) % regions.length].$2}');
    return out;
  }

  static const _monthLong = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

  String _title(String s) => s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');

  Widget _followUps(Pal p) {
    final items = _suggestions(_messages.last);
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => PillChip(items[i], icon: Icx.sparkles, accent: true, onTap: () => _send(items[i])),
      ),
    );
  }

  Widget _welcome(Pal p) {
    const starters = [
      ('Revenue', 'Performa revenue Jawa Barat bulan ini vs bulan lalu?'),
      ('Site', 'Site dengan availability terendah minggu ini di Jawa Tengah'),
      ('Market share', 'Market share IM3 vs kompetitor per kabupaten di Jawa Timur'),
      ('Profil', 'Tampilkan profil lengkap kota Surabaya'),
    ];
    final name = (AuthState.user?['full_name'] ?? AuthState.user?['username'] ?? '').toString().split(' ').first;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 24, 16, 16), children: [
      const Center(child: SizedBox(width: 132, height: 132, child: Image(image: AssetImage('assets/img/ai_orb.webp')))),
      const SizedBox(height: 8),
      Text(name.isEmpty ? 'Mau tahu apa hari ini?' : 'Halo, $name. Mau tahu apa hari ini?',
          textAlign: TextAlign.center, style: ts(18, w700, p.ink, lh: 1.35)),
      const SizedBox(height: 6),
      Text('Tanyakan revenue, site, network, market share atau sales di Jawa. Agent menulis query, mengambil data, lalu menyajikan angka dan grafiknya.',
          textAlign: TextAlign.center, style: ts(13, w400, p.text2, lh: 1.5)),
      const SizedBox(height: 20),
      for (final (t, q) in starters)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: p.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.rule)),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _send(q),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  IconTile(Icx.sparkles, bg: p.teal50, fg: p.teal700, size: 36, radius: 10),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t, style: ts(13, w600, p.ink)),
                      Text(q, style: ts(12, w400, p.text2)),
                    ]),
                  ),
                  Ic(Icx.chevronRight, size: 16, color: p.mute),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _composer(Pal p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 59),
        padding: const EdgeInsets.fromLTRB(18, 0, 7, 0),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.teal200, width: 1.5),
          boxShadow: [
            BoxShadow(color: const Color(0xFF15A697).withValues(alpha: .2), blurRadius: 24),
            const BoxShadow(color: Color(0x0F0F1F1D), offset: Offset(0, 4), blurRadius: 14),
          ],
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: ts(14, w400, p.ink, lh: 1.5),
              cursorColor: p.teal600,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Tanya tentang bisnis Jawa…',
                hintStyle: ts(14, w400, p.mute, lh: 1.5),
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
              tooltip: _listening ? 'Berhenti mendengarkan' : 'Input suara',
              onPressed: _busy ? null : _voice,
              style: IconButton.styleFrom(
                backgroundColor: _listening ? p.teal50 : Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Ic(Icx.mic, size: 18, color: _listening ? p.teal700 : p.mute),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: p.teal600,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _busy ? _stop : () => _send(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Ic(_busy ? Icx.square : Icx.send, size: 18, color: Colors.white)),
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

/// The gradient AI dot with a sparkle that leads each answer card.
class _AiDot extends StatelessWidget {
  const _AiDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment(-.75, -.875), end: Alignment(.75, 1), colors: [Color(0xFF15A697), Color(0xFF0A6A5F)]),
        ),
        alignment: Alignment.center,
        child: const Ic(Icx.sparkles, size: 12, color: Colors.white),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, this.onTap, this.tint = false});
  final I3 icon;
  final String label;
  final VoidCallback? onTap;
  final bool tint;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = tint ? p.teal700 : p.ink;
    return Opacity(
      opacity: onTap == null ? .5 : 1,
      child: Material(
        color: tint ? p.teal50 : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: tint ? BorderSide.none : BorderSide(color: p.rule),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Ic(icon, size: 24, color: fg),
              const SizedBox(width: 8),
              Text(label, style: ts(13, w600, fg)),
            ]),
          ),
        ),
      ),
    );
  }
}
