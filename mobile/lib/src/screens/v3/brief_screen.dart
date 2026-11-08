// v3 02 Brief Pagi (design/mockup-v3/features/02-brief-pagi.html, Android): the
// morning brief as stories, tap right for the next card, read aloud with TTS,
// and every card leads to "Kenapa?" or a follow-up task.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/api_client.dart';
import '../../ui/mock_icons.dart';
import '../../ui/v2.dart';
import '../../ui/v3.dart';
import 'diagnosa_screen.dart';
import 'tindak_screen.dart';
import 'v3_nav.dart';

const _tones = {
  'k': (Color(0xFFE85D3C), Color(0xFFB5401F), Color(0xFFC42B2B)),
  'w': (Color(0xFFF5A623), Color(0xFF8F5A10), Color(0xFFB7791F)),
  'g': (Color(0xFF2FA84F), Color(0xFF1F7A3A), Color(0xFF1F7A3A)),
};
const _pageSeconds = 9;

class BriefScreen extends StatefulWidget {
  const BriefScreen({super.key, this.preview, this.initialPage = 0, this.previewSeg, this.previewAudio});
  final Map<String, dynamic>? preview;
  final int initialPage;

  /// Golden tests: fill of the current story segment and seconds of audio played.
  final double? previewSeg;
  final int? previewAudio;

  @override
  State<BriefScreen> createState() => _BriefScreenState();
}

class _BriefScreenState extends State<BriefScreen> {
  Map<String, dynamic>? _d;
  String? _error;
  late int _page = widget.initialPage;
  double _seg = 0;
  Timer? _tick;
  FlutterTts? _tts;
  bool _playing = false;
  int _played = 0;

  @override
  void initState() {
    super.initState();
    _d = widget.preview;
    _seg = widget.previewSeg ?? 0;
    _played = widget.previewAudio ?? 0;
    _playing = widget.previewAudio != null;
    if (_d == null) {
      _load();
    }
    if (widget.preview == null) _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _advance());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tts?.stop();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.v3Get('/api/brief');
      if (!mounted) return;
      setState(() { _d = d; _error = null; });
      ApiClient.v3Send('POST', '/api/brief/open', {'channel': 'android'}).catchError((_) => <String, dynamic>{});
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<Map<String, dynamic>> get _stories => [for (final s in (_d?['stories'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)];
  int get _pages => 1 + _stories.length + 1;

  void _advance() {
    if (!mounted || _d == null) return;
    setState(() {
      if (_playing) {
        final total = ((_d!['audio'] as Map?)?['seconds'] as num?)?.toInt() ?? 60;
        _played = (_played + 1).clamp(0, total * 4);
      }
      _seg += .25 / _pageSeconds;
      if (_seg >= 1) {
        if (_page < _pages - 1) {
          _page++;
          _seg = 0;
        } else {
          _seg = 1;
        }
      }
    });
  }

  void _go(int dir) => setState(() {
        _page = (_page + dir).clamp(0, _pages - 1);
        _seg = 0;
      });

  Future<void> _toggleAudio() async {
    final text = ((_d?['audio'] as Map?)?['text'] ?? '').toString();
    _tts ??= FlutterTts();
    if (_playing) {
      await _tts!.stop();
      setState(() => _playing = false);
      return;
    }
    try {
      await _tts!.setLanguage('id-ID');
      await _tts!.setSpeechRate(.5);
      _tts!.setCompletionHandler(() {
        if (mounted) setState(() => _playing = false);
      });
      setState(() { _playing = true; _played = 0; });
      await _tts!.speak(text);
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  String _shareText() {
    final d = _d!;
    final head = (d['headline'] as List? ?? const []).map((s) => (s as Map)['t']).join();
    final lines = [for (final s in _stories) '${s['n']}. ${s['title']} (${s['value_label']})'];
    return 'Brief Pagi Agent Java, ${d['date_short'] ?? ''}\n$head\n\n${lines.join('\n')}';
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: V2.teal900,
      body: Column(children: [
        Container(height: top, color: Colors.white),
        Expanded(
          child: V3CssBg(
            deg: 160,
            colors: const [V2.teal700, V2.teal900, V2.teal900],
            stops: const [0, .7, 1],
            glows: const [V3Glow(0, 1, 280, 240, Color(0xFFC7F25E), .18), V3Glow(.9, .08, 300, 260, Color(0xFFFF7A59), .45)],
            child: _d == null
                ? (_error != null
                    ? Theme(data: ThemeData.dark(), child: V3Message(text: _error!, onRetry: _load))
                    : const Center(child: CircularProgressIndicator(color: Colors.white)))
                : _story(),
          ),
        ),
      ]),
    );
  }

  Widget _story() {
    final d = _d!;
    final stories = _stories;
    final storyIdx = _page - 1;
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (e) => _go(e.localPosition.dx > MediaQuery.of(context).size.width * .4 ? 1 : -1),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                for (var i = 0; i < _pages; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: i < _page ? 1 : i == _page ? _seg : 0,
                          color: Colors.white,
                          backgroundColor: Colors.white.withValues(alpha: .28),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              _head(d),
              const SizedBox(height: 18),
              if (storyIdx >= 0 && storyIdx < stories.length) ...[
                _card(stories[storyIdx], d),
                const SizedBox(height: 14),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Transform.rotate(angle: -1.5708, child: const MIcon('chev', size: 14, color: V2.teal100)),
                  const SizedBox(width: 6),
                  Text('Ketuk kanan untuk kartu berikutnya', style: V2.d(12, FontWeight.w500, V2.teal100, lh: 1)),
                ]),
                for (var k = 1; k <= 2 && storyIdx + k < stories.length; k++) ...[
                  SizedBox(height: k == 1 ? 12 : 8),
                  Opacity(opacity: k == 2 ? .8 : 1, child: _peek(stories[storyIdx + k])),
                ],
              ] else if (storyIdx < 0)
                _intro(d)
              else
                _outro(d),
            ]),
          ),
        ),
      ),
      Positioned(left: 14, right: 14, bottom: 30, child: _mini(d)),
    ]);
  }

  Widget _head(Map<String, dynamic> d) {
    Widget x(String icon, String label, VoidCallback onTap, {double angle = 0}) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(10)),
              child: Transform.rotate(angle: angle, child: MIcon(icon, size: 18, color: Colors.white)),
            ),
          ),
        );
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        padding: const EdgeInsets.all(2.6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9.5), border: Border.all(color: V2.rule)),
        child: Image.asset('assets/icon_circle.png', fit: BoxFit.contain),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Brief Pagi', style: V2.d(14, FontWeight.w600, Colors.white, lh: 1.2)),
          Text('${d['date_short'] ?? ''} · ${_page + 1} dari $_pages', maxLines: 1, overflow: TextOverflow.ellipsis, strutStyle: v3Strut, style: V2.b(11.5, FontWeight.w400, V2.teal100, lh: 1.2)),
        ]),
      ),
      x('share', 'Bagikan', () => SharePlus.instance.share(ShareParams(text: _shareText()))),
      const SizedBox(width: 10),
      x('plus', 'Tutup', () => Navigator.of(context).maybePop(), angle: .7854),
    ]);
  }

  /// The story card is a CSS grid: its track is never narrower than the widest
  /// fixed child (the 314 px sparkline), so on narrow phones the content runs into
  /// the right padding exactly like the mockup.
  Widget _white(List<Widget> kids, {double minTrack = 0}) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: [cssShadow(const Color(0x47000000), 0, 24, 50)]),
        child: LayoutBuilder(builder: (context, c) {
          final col = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < kids.length; i++) ...[if (i > 0) const SizedBox(height: 10), kids[i]],
          ]);
          if (c.maxWidth >= minTrack) return col;
          return OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: minTrack,
            maxWidth: minTrack,
            fit: OverflowBoxFit.deferToChild,
            child: col,
          );
        }),
      );

  Widget _card(Map<String, dynamic> s, Map<String, dynamic> d) {
    final t = _tones[s['tone']] ?? _tones['w']!;
    final period = (((d['basis'] as Map?)?['period']) ?? s['value_note'] ?? '').toString().replaceFirst(' vs ', '\nvs ');
    final spark = [for (final v in (s['spark'] as List? ?? const [])) (v as num).toDouble()];
    return _white([
      Row(children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.$1, borderRadius: BorderRadius.circular(8)),
          child: Text('${s['n']}', style: V2.d(12, FontWeight.w600, Colors.white, lh: 1)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text('${s['tone_label']} · ${s['topic']}'.toUpperCase(), style: V2.d(11, FontWeight.w600, t.$2, lh: 1, ls: .06))),
      ]),
      Text('${s['title']}', style: V2.d(20, FontWeight.w700, V2.ink, lh: 1.3)),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text('${s['value_label']}', style: V2.d(34, FontWeight.w800, t.$3, lh: 1)),
        const SizedBox(width: 8),
        Flexible(child: Text(period, style: V2.b(12.5, FontWeight.w500, V2.mute, lh: 1.3))),
      ]),
      if (spark.length > 1) V3Spark(values: spark, color: t.$3 == V3.green ? V3.green2 : (s['tone'] == 'w' ? V3.amber : t.$3), width: 314, height: 70),
      V2Lines(TextSpan(text: '${s['text']}', style: V2.b(13.5, FontWeight.w400, V2.ink2, lh: 1.5)), lineHeight: 20.25, dy: 0, exactPitch: true),
      Row(children: [
        Expanded(child: _act('spark', 'Kenapa?', const Color(0xFFFFEDE7), const Color(0xFFB5401F), () => _why(s))),
        const SizedBox(width: 8),
        Expanded(child: _act('check', 'Tindak lanjut', V2.teal600, Colors.white, () => _task(s))),
      ]),
    ], minTrack: spark.length > 1 ? 314 : 0);
  }

  Widget _act(String icon, String label, Color bg, Color fg, VoidCallback onTap) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(13)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              MIcon(icon, size: 16, color: fg),
              const SizedBox(width: 7),
              Text(label, style: V2.d(13, FontWeight.w600, fg, lh: 1)),
            ]),
          ),
        ),
      );

  void _why(Map<String, dynamic> s) {
    final g = Map<String, dynamic>.from(s['diagnosa'] as Map? ?? const {});
    V3Nav.push(context, DiagnosaScreen(
      metric: (g['metric'] ?? 'revenue').toString(),
      region: (g['region'] ?? '').toString(),
      kabupaten: (g['kabupaten'] ?? '').toString(),
      basis: (g['basis'] ?? 'mtd').toString(),
    ));
  }

  Future<void> _task(Map<String, dynamic> s) async {
    final body = Map<String, dynamic>.from(s['task'] as Map? ?? const {});
    if (body.isEmpty) return;
    try {
      final t = await ApiClient.v3Send('POST', '/api/tindak/tasks', body);
      if (mounted) V3Nav.push(context, TindakScreen(task: (t['id'] as num?)?.toInt()));
    } catch (_) {
      if (mounted) v3Toast(context, 'Tugas gagal dibuat');
    }
  }

  Widget _peek(Map<String, dynamic> s) {
    final t = _tones[s['tone']] ?? _tones['w']!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .16)),
      ),
      child: Row(children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: t.$1 == const Color(0xFFE85D3C) ? t.$1 : t.$1, borderRadius: BorderRadius.circular(8)),
          child: Text('${s['n']}', style: V2.d(12, FontWeight.w700, Colors.white, lh: 1)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s['tone_label']} · ${s['short_title'] ?? s['topic']}'.toUpperCase(), style: V2.d(10.5, FontWeight.w500, V2.teal100, lh: 1.2, ls: .05)),
            Text('${s['peek'] ?? s['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, strutStyle: v3Strut, style: V2.d(13, FontWeight.w600, Colors.white, lh: 1.3)),
          ]),
        ),
      ]),
    );
  }

  Widget _intro(Map<String, dynamic> d) => _white([
        Text('${d['greeting'] ?? 'Selamat pagi'}', style: V2.d(20, FontWeight.w700, V2.ink, lh: 1.3)),
        Text.rich(v3Rich(d['headline'] as List?,
            base: V2.b(14, FontWeight.w400, V2.ink2, lh: 1.55), b: V2.b(14, FontWeight.w600, V3.green, lh: 1.55), e: V2.b(14, FontWeight.w600, V2.red, lh: 1.55))),
        Text('${(d['basis'] as Map?)?['period'] ?? ''}', style: V2.b(12, FontWeight.w400, V2.mute, lh: 1.4)),
      ]);

  Widget _outro(Map<String, dynamic> d) {
    final targets = [for (final t in (d['targets'] as List? ?? const [])) Map<String, dynamic>.from(t as Map)];
    final agenda = [for (final a in (d['agenda'] as List? ?? const [])) Map<String, dynamic>.from(a as Map)];
    return _white([
      Text('${d['target_title'] ?? 'Posisi terhadap target'}', style: V2.d(17, FontWeight.w700, V2.ink, lh: 1.3)),
      for (final t in targets)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${t['label']}', style: V2.d(13, FontWeight.w600, V2.ink, lh: 1.3))),
            Text('${t['value_label']}', style: V2.d(12, FontWeight.w600, V2.ink2, lh: 1.3)),
          ]),
          const SizedBox(height: 6),
          V3Bullet(fraction: ((t['tick_pct'] as num?) ?? 0).toDouble() * .8 / 100, color: V3.hex(t['color']?.toString())),
          const SizedBox(height: 4),
          Text('${t['note'] ?? ''}', style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.4)),
        ]),
      if (agenda.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text('AGENDA HARI INI', style: V2.d(11, FontWeight.w600, V2.mute, lh: 1, ls: .06)),
        for (final a in agenda)
          Row(children: [
            MIcon('${a['icon'] ?? 'check'}', size: 16, color: a['urgent'] == true ? V2.red : V2.teal600),
            const SizedBox(width: 8),
            Expanded(child: Text('${a['title']}', style: V2.d(13, FontWeight.w500, V2.ink, lh: 1.3))),
            Text('${a['time'] ?? ''}', style: V2.d(11.5, FontWeight.w600, a['urgent'] == true ? V2.red : V2.mute, lh: 1.3)),
          ]),
      ],
    ]);
  }

  String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _mini(Map<String, dynamic> d) {
    final total = ((d['audio'] as Map?)?['seconds'] as num?)?.toInt() ?? 60;
    final played = widget.previewAudio ?? (_played / 4).floor();
    final frac = total == 0 ? 0.0 : (played / total).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: .2)),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Row(children: [
          Semantics(
            button: true,
            label: _playing ? 'Jeda' : 'Dengarkan',
            child: GestureDetector(
              onTap: _toggleAudio,
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: V2.lime, borderRadius: BorderRadius.circular(13)),
                child: MIcon(_playing ? 'pause' : 'play', size: 18, color: V2.teal900),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_playing ? 'Mendengarkan brief' : 'Dengarkan brief', style: V2.d(13, FontWeight.w600, Colors.white, lh: 1.2)),
              Text('${_clock(played)} dari ${_clock(total)}', style: V2.b(11, FontWeight.w400, V2.teal100, lh: 1.2)),
            ]),
          ),
          Semantics(
            button: true,
            label: 'Bagikan',
            child: GestureDetector(
              onTap: () => SharePlus.instance.share(ShareParams(text: _shareText())),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                child: const MIcon('share', size: 17, color: Colors.white),
              ),
            ),
          ),
        ]),
        Positioned(
          left: 52,
          right: 50,
          bottom: -2,
          height: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: frac, color: V2.lime, backgroundColor: Colors.white.withValues(alpha: .2)),
          ),
        ),
      ]),
    );
  }
}
