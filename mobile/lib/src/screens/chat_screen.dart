import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../api/models.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/pipeline_view.dart';
import '../widgets/data_table_view.dart';
import '../widgets/chart_panel.dart';
import '../widgets/collapsible.dart';
import '../services/update_service.dart';
import '../services/keep_alive_service.dart';
import '../widgets/update_dialog.dart';
import 'location_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final List<FlowStep> _flow = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _busy = false;
  int? _tokens;
  String _sessionId = '';
  List<dynamic> _history = [];
  StreamSubscription? _sub;

  String get _lang => AppState.I.lang;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Always open the app on a fresh chat. Previous conversations remain
    // available from the history drawer.
    final p = await SharedPreferences.getInstance();
    final uname = AuthState.user?['username'] ?? 'anon';
    _sessionId = _newId();
    await p.setString('session::$uname', _sessionId);
    if (mounted) setState(() {});
    _loadHistory();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      final info = await UpdateService.check();
      if (info != null && mounted) {
        await showUpdateDialog(context, info);
      }
    } catch (_) {}
  }

  String _newId() => 'm_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';

  Future<void> _loadHistory() async {
    final h = await ApiClient.historySessions();
    if (mounted) setState(() => _history = h);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  void _newChat() {
    if (_busy) return;
    setState(() { _messages.clear(); _flow.clear(); _sessionId = _newId(); _tokens = null; });
    SharedPreferences.getInstance().then((p) {
      final uname = AuthState.user?['username'] ?? 'anon';
      p.setString('session::$uname', _sessionId);
    });
  }

  ChatMessage get _assistant => _messages.lastWhere((m) => !m.isUser);

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _messages.add(ChatMessage(isUser: true, content: text));
      _messages.add(ChatMessage(isUser: false, status: 'Menganalisis…'));
      _flow.clear();
      _flow.add(FlowStep('user', 'User query', feedback: text.length > 48 ? '${text.substring(0, 48)}…' : text, done: true));
      _tokens = null; _busy = true;
    });
    _scrollDown();
    // Keep the process alive while loading so backgrounding (opening another
    // app) doesn't pause/kill the in-flight stream.
    KeepAliveService.start(text: 'Menganalisis pertanyaan Anda…');

    final history = _messages.where((m) => m.content.trim().isNotEmpty)
        .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.content.length > 1500 ? m.content.substring(0, 1500) : m.content}).toList();

    var gotDone = false, gotContent = false;
    try {
      _sub = ApiClient.chatStream(text, _sessionId, _lang, history: history).listen((ev) {
        final event = ev.key; final data = ev.value; final a = _assistant;
        switch (event) {
          case 'step_start':
            final kind = (data['step'] ?? '').toString();
            a.status = '${data['label'] ?? kind} — ${data['desc'] ?? ''}';
            setState(() { for (final f in _flow) { f.done = true; } _flow.add(FlowStep(kind, (data['label'] ?? kind).toString(), feedback: data['desc']?.toString())); });
            break;
          case 'route':
            _trackTokens(data); a.domain = data['domain']?.toString(); _updateFlow('router', feedback: data['reason']?.toString());
            final dom = a.domain;
            if (dom == 'PROFILE') { setState(() => _flow.add(FlowStep('agent', 'Profile Mode'))); }
            else if (dom != null && dom != 'none') { setState(() => _flow.add(FlowStep('agent', dom))); }
            break;
          case 'analyst': _trackTokens(data); _updateFlow('analyst', feedback: data['validated_query']?.toString()); break;
          case 'sql': _trackTokens(data); a.sql = data['sql']?.toString(); _updateFlow('sql_write', feedback: data['explanation']?.toString()); break;
          case 'result':
            final cols = (data['columns'] as List?)?.map((e) => e.toString()).toList() ?? [];
            final rows = (data['rows'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
            setState(() => a.result = ResultTable(cols, rows, (data['row_count'] as int?) ?? rows.length));
            break;
          case 'profile_domain_result':
            a.profileResults.add(ProfileSection(
              title: (data['section_title'] ?? '').toString(), domain: (data['domain'] ?? '').toString(),
              status: (data['status'] ?? 'ok').toString(), rowCount: (data['row_count'] as int?) ?? 0,
              columns: (data['columns'] as List?)?.map((e) => e.toString()).toList() ?? [],
              rows: (data['rows'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [],
              error: data['error']?.toString()));
            setState(() {});
            break;
          case 'advisor_support': setState(() => _flow.add(FlowStep('bq_exec', 'Data: ${data['domain']}', feedback: data['question']?.toString()))); break;
          case 'scope': {
            final verdict = (data['verdict'] ?? '').toString();
            final reason = (data['reason'] ?? '').toString();
            final msg = verdict == 'answerable'
                ? 'Domain sesuai ✓'
                : verdict == 'reroute'
                    ? 'Domain tidak punya datanya — mengalihkan…'
                    : 'Perlu konfirmasi pertanyaan…';
            a.status = msg;
            setState(() { for (final f in _flow) { f.done = true; } _flow.add(FlowStep('scope', 'Domain Check', feedback: reason.isNotEmpty ? reason : msg)); });
            break;
          }
          case 'reroute': {
            final to = (data['to'] ?? '').toString();
            a.status = to.isNotEmpty ? 'Mengalihkan ke domain $to…' : 'Mencari domain lain…';
            setState(() { for (final f in _flow) { f.done = true; } _flow.add(FlowStep('reroute', 'Re-route', feedback: '${data['from'] ?? ''} → ${to.isEmpty ? '—' : to}')); });
            break;
          }
          case 'reflect': {
            final verdict = (data['verdict'] ?? '').toString();
            final reason = (data['reason'] ?? '').toString();
            final msg = verdict == 'ok'
                ? 'Jawaban relevan ✓'
                : verdict == 'refine'
                    ? 'Belum optimal — mencari jawaban lebih baik…'
                    : 'Data tidak tersedia — menyiapkan alternatif…';
            a.status = msg;
            setState(() { for (final f in _flow) { f.done = true; } _flow.add(FlowStep('reflect', 'Quality Check', feedback: reason.isNotEmpty ? reason : msg)); });
            break;
          }
          case 'clarify': a.status = 'Menunggu konfirmasi…'; break;
          case 'retry': setState(() { for (final f in _flow) { f.done = true; } _flow.add(FlowStep('retry', 'Retry', feedback: (data['error'] ?? '').toString())); }); break;
          case 'token': gotContent = true; a.status = null; setState(() => a.content += (data['t'] ?? '').toString()); _scrollDown(); break;
          case 'done': gotDone = true; _trackTokens(data); setState(() { a.status = null; for (final f in _flow) { f.done = true; } }); break;
          case 'error': setState(() { a.error = (data['error'] ?? 'error').toString(); a.status = null; }); break;
        }
      }, onError: (e) {
        if (!gotDone && !gotContent) setState(() => _assistant.error = 'Network error: $e');
        _finish();
      }, onDone: _finish);
    } catch (e) { setState(() => _assistant.error = 'Network error: $e'); _finish(); }
  }

  void _updateFlow(String kind, {String? feedback}) {
    setState(() { for (final f in _flow) { if (f.kind == kind && feedback != null && feedback.isNotEmpty) f.feedback = feedback; } });
  }

  void _trackTokens(Map<String, dynamic> data) {
    final u = data['_usage'];
    if (u is Map && (u['total_tokens'] ?? 0) != 0) setState(() => _tokens = u['total_tokens'] as int?);
  }

  void _finish() { KeepAliveService.stop(); setState(() => _busy = false); _loadHistory(); _scrollDown(); }

  Future<void> _summarize() async {
    final turns = _messages.where((m) => m.content.trim().isNotEmpty || m.result != null || m.profileResults.isNotEmpty).map((m) => {
      'role': m.isUser ? 'user' : 'assistant', 'content': m.content, 'domain': m.domain, 'row_count': m.result?.rowCount,
      'result': m.result == null ? null : {'columns': m.result!.columns, 'rows': m.result!.rows.take(50).toList(), 'row_count': m.result!.rowCount},
      'profile_sections': m.profileResults.isEmpty ? null : m.profileResults.where((p) => p.status == 'ok').map((p) => {'section_title': p.title, 'columns': p.columns, 'rows': p.rows.take(30).toList(), 'row_count': p.rowCount}).toList(),
    }).toList();
    if (turns.isEmpty) { _toast('Belum ada chat untuk diringkas.'); return; }
    _toast('Membuat ringkasan & mengirim email…');
    try { final res = await ApiClient.summarizeChat(turns, _lang); _toast(res['message']?.toString() ?? 'Email terkirim.', ok: true); }
    catch (e) { _toast(e.toString().replaceFirst('Exception: ', ''), ok: false); }
  }

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: ok ? IOH.teal : IOH.danger, behavior: SnackBarBehavior.floating));
  }

  void _logout() async { await AuthState.clear(); if (mounted) Navigator.of(context).pushReplacementNamed('/login'); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _historyDrawer(),
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(children: [
          Image.asset('assets/icon_circle.png', width: 24, height: 24),
          const SizedBox(width: 8),
          const Expanded(child: Text('Bizplan Java Agent', style: TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w800))),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.add_comment_outlined), tooltip: 'Chat baru', onPressed: _busy ? null : _newChat),
        ],
      ),
      body: Column(children: [
        Expanded(child: _messages.isEmpty ? _welcome() : ListView.builder(
          controller: _scroll, padding: const EdgeInsets.all(12),
          itemCount: _messages.length, itemBuilder: (_, i) => _bubble(_messages[i], i == _messages.length - 1)),
        ),
        _composer(),
      ]),
    );
  }

  Widget _welcome() {
    final examples = [
      'Tampilkan profile lengkap kota Surabaya',
      'Trend revenue daily 30 hari terakhir kota Surabaya',
      'Market share IM3 vs Telkomsel per kabkota',
      'Top 10 site revenue tertinggi di Surabaya',
    ];
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 16),
      Center(child: Image.asset('assets/logo_color.png', width: 120)),
      const SizedBox(height: 16),
      Text('Ask data, get answers.', textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Poppins', fontSize: 22, fontWeight: FontWeight.w800, color: context.vInk)),
      const SizedBox(height: 6),
      Text('Tanya revenue, market share, 5G, forecast, KPI — AI agent akan menjawab.', textAlign: TextAlign.center, style: TextStyle(color: context.vMute, fontSize: 14)),
      const SizedBox(height: 24),
      for (final e in examples)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: context.vWhite, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.vRule)),
          child: ListTile(
            leading: const Icon(Icons.auto_awesome, color: IOH.red, size: 20),
            title: Text(e, style: TextStyle(fontSize: 13.5, color: context.vInk)),
            trailing: Icon(Icons.arrow_forward_ios, size: 13, color: context.vMute),
            onTap: () => _send(e),
          ),
        ),
    ]);
  }

  Widget _bubble(ChatMessage m, bool isLast) {
    if (m.isUser) {
      return Align(alignment: Alignment.centerRight, child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: const BoxDecoration(color: IOH.red, borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4))),
        child: Text(m.content, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ));
    }
    final okSections = m.profileResults.where((p) => p.status == 'ok' && p.rows.isNotEmpty).toList();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 1. Agent Pipeline
        if (isLast && _flow.isNotEmpty) PipelineView(steps: _flow, live: _busy, tokens: _tokens),
        // domain pill
        if (m.domain != null && m.domain != 'none')
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: IOH.domainColor(m.domain), borderRadius: BorderRadius.circular(999)),
            child: Text(m.domain == 'PROFILE' ? 'Profile' : (m.domainLabel ?? m.domain!),
                style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        // status (running)
        if (m.status != null)
          Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: IOH.red)),
            const SizedBox(width: 8),
            Flexible(child: Text(m.status!, style: const TextStyle(color: IOH.red, fontSize: 12, fontWeight: FontWeight.w600))),
          ])),
        // 2. SQL (collapsed, only analyst/admin)
        if (m.sql != null && AuthState.canViewSql)
          Collapsible(title: 'SQL Query', icon: Icons.code, accent: IOH.mute,
              child: SelectableText(m.sql!, style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: context.vInk))),
        // 3. Row Data (collapsed by default)
        if (m.result != null && m.result!.rows.isNotEmpty)
          Collapsible(title: 'Row Data', icon: Icons.table_chart_outlined, accent: IOH.pink, badge: '${m.result!.rowCount}',
              child: DataTableView(columns: m.result!.columns, rows: m.result!.rows)),
        for (final p in okSections)
          Collapsible(title: p.title, icon: Icons.table_rows_outlined, accent: IOH.pink, badge: '${p.rowCount}',
              child: DataTableView(columns: p.columns, rows: p.rows, maxRows: 30)),
        // 4. Chart
        if (m.result != null && m.result!.rows.isNotEmpty)
          ChartPanel(columns: m.result!.columns, rows: m.result!.rows),
        // 5. AI summary (the streamed answer)
        if (m.content.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: context.vWhite, border: Border.all(color: context.vRule),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16))),
            child: MarkdownBody(data: m.content, styleSheet: MarkdownStyleSheet(
              p: TextStyle(fontFamily: 'Prompt', fontSize: 14, height: 1.55, color: context.vInk),
              h1: TextStyle(fontFamily: 'Poppins', fontSize: 18, fontWeight: FontWeight.w800, color: context.vInk),
              h2: TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: context.vInk),
              h3: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: context.vInk),
              strong: const TextStyle(fontWeight: FontWeight.w700),
              listBullet: TextStyle(fontFamily: 'Prompt', fontSize: 14, color: context.vInk),
              // Tables: size each column to its content (no text wrapping) and
              // let the whole table scroll horizontally instead of cramming +
              // wrapping cells. Smaller cell font keeps rows compact & legible.
              tableColumnWidth: const IntrinsicColumnWidth(),
              tableHead: TextStyle(fontFamily: 'Prompt', fontSize: 12.5, fontWeight: FontWeight.w700, color: context.vInk),
              tableBody: TextStyle(fontFamily: 'Prompt', fontSize: 12.5, height: 1.3, color: context.vInk),
              tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              tableBorder: TableBorder.all(color: context.vRule, width: 1),
              tableScrollbarThumbVisibility: true,
            )),
          ),
        if (m.locationResult != null) LocationResultView(data: m.locationResult!, lang: _lang),
        if (m.error != null)
          Container(margin: const EdgeInsets.only(top: 6), padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(8), border: const Border(left: BorderSide(color: IOH.danger, width: 4))),
            child: Row(children: [const Icon(Icons.error_outline, color: IOH.danger, size: 16), const SizedBox(width: 8),
              Expanded(child: Text(m.error!, style: const TextStyle(color: IOH.danger, fontSize: 13)))])),
      ]),
    );
  }

  Widget _composer() {
    return SafeArea(top: false, child: Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(color: context.vWhite, border: Border(top: BorderSide(color: context.vRule))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        IconButton(icon: const Icon(Icons.add_circle_outline, color: IOH.red), onPressed: _busy ? null : _showAttach),
        Expanded(child: TextField(
          controller: _input, minLines: 1, maxLines: 4, textInputAction: TextInputAction.send,
          onSubmitted: (_) => _send(), style: TextStyle(fontSize: 15, color: context.vInk),
          decoration: InputDecoration(
            hintText: 'Tanya revenue, network, market share…', filled: true, fillColor: context.vPanel,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none)),
        )),
        const SizedBox(width: 6),
        CircleAvatar(radius: 22, backgroundColor: IOH.red, child: IconButton(
          icon: Icon(_busy ? Icons.stop : Icons.send, color: Colors.white, size: 20),
          onPressed: _busy ? () { _sub?.cancel(); _finish(); } : () => _send())),
      ]),
    ));
  }

  void _showAttach() {
    showModalBottomSheet(context: context, backgroundColor: context.vWhite,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(width: 40, height: 4, decoration: BoxDecoration(color: context.vRule, borderRadius: BorderRadius.circular(2))),
        ListTile(leading: const Icon(Icons.my_location, color: IOH.red),
          title: Text('Share Location', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: context.vInk)),
          subtitle: Text('Profil kecamatan + site & outlet terdekat', style: TextStyle(color: context.vMute)),
          onTap: () { Navigator.pop(context); _shareLocation(); }),
        const SizedBox(height: 8),
      ])));
  }

  Future<void> _shareLocation() async {
    final coord = await getCurrentCoord(context);
    if (coord == null) return;
    setState(() {
      _messages.add(ChatMessage(isUser: true, content: '📍 Share lokasi (${coord.$1.toStringAsFixed(5)}, ${coord.$2.toStringAsFixed(5)})'));
      _messages.add(ChatMessage(isUser: false, status: 'Mencari kecamatan & lokasi terdekat…'));
    });
    _scrollDown();
    try {
      final data = await ApiClient.geoLocate(coord.$1, coord.$2);
      final a = _assistant; final kec = data['kecamatan'];
      setState(() {
        a.status = null;
        a.content = kec != null
            ? '### Lokasi Terdeteksi\n**Kecamatan:** ${kec['kecamatan'] ?? '-'} · **Kab/Kota:** ${kec['kabkota'] ?? '-'}'
            : '### Lokasi Terdeteksi\nTidak terpetakan ke kecamatan.';
        a.locationResult = data;
      });
    } catch (e) { setState(() { _assistant.status = null; _assistant.error = 'Gagal: $e'; }); }
    _scrollDown();
  }

  Widget _navItem(IconData ic, String label, Color color, VoidCallback onTap) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
      leading: Icon(ic, size: 18, color: color),
      title: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.vInk)),
      onTap: onTap,
    );
  }

  Widget _historyDrawer() {
    final uname = (AuthState.user?['full_name'] ?? AuthState.user?['username'] ?? 'User').toString();
    void go(String route) { Navigator.pop(context); Navigator.pushNamed(context, route); }
    return Drawer(backgroundColor: context.vWhite, child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header: brand
      Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 10), child: Row(children: [
        Image.asset('assets/icon_circle.png', width: 26), const SizedBox(width: 10),
        Expanded(child: Text('Bizplan Java', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 15, color: context.vInk))),
      ])),
      // Top: navigation buttons
      _navItem(Icons.add_comment_outlined, 'Chat Baru', IOH.red, () { Navigator.pop(context); if (!_busy) _newChat(); }),
      _navItem(Icons.map_outlined, 'Map Query', IOH.magenta, () => go('/map')),
      _navItem(Icons.bar_chart_outlined, 'Performance Outlook', IOH.teal600, () => go('/reports')),
      _navItem(Icons.cell_tower, 'Site Performance', IOH.teal600, () => go('/site')),
      _navItem(Icons.mail_outline, 'Summary & Send Mail', IOH.red, () { Navigator.pop(context); _summarize(); }),
      Divider(height: 12, color: context.vRule),
      // Section label
      Padding(padding: const EdgeInsets.fromLTRB(16, 2, 16, 6), child: Text('RIWAYAT CHAT',
          style: TextStyle(fontFamily: 'Poppins', fontSize: 10, fontWeight: FontWeight.w700, color: context.vMute, letterSpacing: 0.8))),
      // History list (fills remaining space)
      Expanded(child: _history.isEmpty
        ? Align(alignment: Alignment.topLeft, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text('Belum ada riwayat', style: TextStyle(color: context.vMute, fontSize: 12))))
        : ListView(padding: EdgeInsets.zero, children: [for (final h in _history) ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: Icon(Icons.chat_bubble_outline, size: 16, color: context.vMute),
            title: Text((h['title'] ?? 'Chat').toString(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.vInk, fontSize: 12.5)),
            subtitle: Text('${h['message_count'] ?? 0} pesan', style: TextStyle(fontSize: 10, color: context.vMute)),
            selected: h['session_id'] == _sessionId,
            onTap: () => _openSession(h['session_id'].toString()))])),
      // Bottom: account row → profile + logout
      Divider(height: 1, color: context.vRule),
      ListTile(
        dense: true,
        leading: CircleAvatar(radius: 14, backgroundColor: IOH.red, child: Text(uname.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
        title: Text(uname, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.vInk), maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(icon: const Icon(Icons.logout, size: 18, color: IOH.red), tooltip: 'Logout', onPressed: () { Navigator.pop(context); _logout(); }),
        onTap: () => go('/profile'),
      ),
    ])));
  }

  Future<void> _openSession(String sid) async {
    Navigator.pop(context);
    if (_busy) return;
    final msgs = await ApiClient.sessionMessages(sid);
    setState(() {
      _sessionId = sid; _messages.clear(); _flow.clear();
      for (final m in msgs) { _messages.add(ChatMessage(isUser: m['role'] == 'user', content: (m['content'] ?? '').toString(), domain: m['domain'], sql: m['sql_query'])); }
    });
    final p = await SharedPreferences.getInstance();
    final uname = AuthState.user?['username'] ?? 'anon';
    await p.setString('session::$uname', sid);
    _scrollDown();
  }

  @override
  void dispose() { _sub?.cancel(); _input.dispose(); _scroll.dispose(); super.dispose(); }
}
