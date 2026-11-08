// v3 05 Tindak Lanjut (design/mockup-v3/features/05-tindak-lanjut.html, Android):
// my tasks by due date, field photo from the camera with GPS, the next nearest
// site of the task, and a quick update sheet (checklist and status).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/api_client.dart';
import '../../ui/mock_icons.dart';
import '../../ui/v2.dart';
import '../../ui/v3.dart';
import 'v3_nav.dart';

const _segs = [('mine', 'Milik saya'), ('team', 'Tim'), ('verify', 'Verifikasi'), ('done', 'Selesai')];
const _tone = {
  'a': (Color(0xFFFDECEC), Color(0xFFC42B2B)),
  'd': (Color(0xFFFFEDE7), Color(0xFFB5401F)),
  'b': (Color(0xFFFDF3E2), Color(0xFF8F5A10)),
  'p': (Color(0xFFF4FCE3), Color(0xFF5E8A12)),
};

class TindakScreen extends StatefulWidget {
  const TindakScreen({super.key, this.task, this.preview, this.previewNearest});
  final int? task;
  final Map<String, dynamic>? preview;
  final String? previewNearest;

  @override
  State<TindakScreen> createState() => _TindakScreenState();
}

class _TindakScreenState extends State<TindakScreen> {
  String _seg = 'mine';
  late int? _sel = widget.task;
  Map<String, dynamic>? _data;
  String? _error;
  final Map<int, String> _nearest = {};

  @override
  void initState() {
    super.initState();
    _data = widget.preview;
    if (_data == null) _load();
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.v3Get('/api/tindak/tasks', {'view': _seg == 'mine' ? 'mine' : 'all'});
      if (mounted) setState(() { _data = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  List<Map<String, dynamic>> _cards() {
    final d = _data;
    if (d == null) return const [];
    List<Map<String, dynamic>> lane(String k) => [for (final c in ((d['lanes'] as Map?)?[k] as List? ?? const [])) Map<String, dynamic>.from(c as Map)];
    return switch (_seg) {
      'mine' => [...lane('baru'), ...lane('dikerjakan')].where((c) => c['mine'] == true).toList(),
      'team' => [...lane('baru'), ...lane('dikerjakan')],
      'verify' => lane('verifikasi'),
      _ => [for (final c in (d['done'] as List? ?? const [])) Map<String, dynamic>.from(c as Map)],
    };
  }

  @override
  Widget build(BuildContext context) {
    final stats = (_data?['stats'] as Map?) ?? const {};
    return V3Page(
      title: 'Tindak Lanjut',
      subtitle: '${stats['open_mine'] ?? 0} tugas milik kamu',
      body: _data == null
          ? (_error != null ? V3Message(text: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator(color: V2.teal600)))
          : RefreshIndicator(onRefresh: _load, color: V2.teal600, child: _list()),
    );
  }

  Widget _list() {
    const order = ['Hari ini', 'Minggu ini', 'Nanti', 'Tanpa tenggat', 'Menunggu data', 'Selesai'];
    String group(Map<String, dynamic> c) {
      if (_seg == 'verify') return 'Menunggu data';
      if (_seg == 'done') return 'Selesai';
      final late = ((c['due'] as Map?)?['late_days'] as num?)?.toInt();
      return late == null
          ? 'Tanpa tenggat'
          : late >= 0
              ? 'Hari ini'
              : late >= -7
                  ? 'Minggu ini'
                  : 'Nanti';
    }
    final groups = <String, List<Map<String, dynamic>>>{for (final g in order) g: []};
    for (final c in _cards()) {
      groups[group(c)]!.add(c);
    }
    groups.removeWhere((_, v) => v.isEmpty);
    final cards = [for (final v in groups.values) ...v];
    final sel = _sel ?? (cards.isNotEmpty && _seg != 'done' ? cards.first['id'] as int? : null);
    final children = <Widget>[
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in _segs)
          Semantics(
            button: true,
            selected: s.$1 == _seg,
            child: GestureDetector(
              onTap: () {
                setState(() { _seg = s.$1; _sel = null; });
                if (widget.preview == null) _load();
              },
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: s.$1 == _seg ? V2.teal600 : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: s.$1 == _seg ? V2.teal600 : V2.rule),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                  Text(s.$2, style: V2.d(12, FontWeight.w600, s.$1 == _seg ? Colors.white : V2.ink2, lh: 1)),
                ]),
              ),
            ),
          ),
      ]),
    ];
    if (cards.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text('Belum ada tugas di sini.', textAlign: TextAlign.center, style: V2.b(13, FontWeight.w400, V2.mute)),
      ));
    }
    for (final e in groups.entries) {
      children
        ..add(const SizedBox(height: 10))
        ..add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
          child: Text(e.key.toUpperCase(), style: V2.d(11.5, FontWeight.w600, V2.mute, lh: 1, ls: .06)),
        ));
      for (final c in e.value) {
        children
          ..add(const SizedBox(height: 10))
          ..add(_card(c, c['id'] == sel));
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), children: children);
  }

  Widget _org(Map<String, dynamic> c) {
    final t = _tone[c['origin_tone']] ?? _tone['b']!;
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: t.$1, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        MIcon('${c['origin_icon']}', size: 12, color: t.$2),
        const SizedBox(width: 5),
        Text('${c['origin_label']}', style: V2.d(10.5, FontWeight.w600, t.$2, lh: 1)),
      ]),
    );
  }

  Widget _av(Map<String, dynamic> pic) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: V3.hex(pic['color']?.toString()), shape: BoxShape.circle),
        child: Text('${pic['initial'] ?? '?'}', style: V2.d(10, FontWeight.w700, Colors.white, lh: 1)),
      );

  Widget _card(Map<String, dynamic> c, bool sel) {
    final pic = Map<String, dynamic>.from(c['pic'] as Map? ?? const {});
    final due = Map<String, dynamic>.from(c['due'] as Map? ?? const {});
    final mt = V2.d(11.5, FontWeight.w500, V2.mute, lh: 1);
    final id = (c['id'] as num).toInt();
    if (sel && widget.preview == null && !_nearest.containsKey(id)) _loadNearest(id);
    final nearest = widget.previewNearest ?? _nearest[id];
    final verify = c['verify'] as Map?;
    final children = <Widget>[
      _org(c),
      V2Lines(TextSpan(text: '${c['title']}', style: V2.d(13.5, FontWeight.w600, V2.ink, lh: 1.35)), lineHeight: 18.225, dy: 0, exactPitch: true),
      if (sel && verify != null)
        Row(children: [
          MIcon(verify['ok'] == true ? 'check' : 'hist', size: 13, color: verify['ok'] == true ? V3.green : V3.purple),
          const SizedBox(width: 6),
          Expanded(child: Text('${verify['text']}', style: V2.d(11, FontWeight.w600, verify['ok'] == true ? V3.green : V3.purple, lh: 1.3))),
        ])
      else if (sel && c['criterion'] != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: MIcon('check', size: 13, color: V2.teal600)),
            const SizedBox(width: 6),
            // "≥" and "−" come from a fallback font in Chrome, which grows the 16.1 px line to 18
            Expanded(child: V2Lines(TextSpan(text: '${c['criterion']}', style: V2.b(11.5, FontWeight.w400, V2.ink2, lh: 1.4)), lineHeight: _fb(c['criterion']) ? 18 : 16.1, dy: _fb(c['criterion']) ? 1.5 : 0, exactPitch: true)),
          ]),
        ),
      if (sel && c['progress'] != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 5,
            child: LinearProgressIndicator(value: (c['progress'] as num).toDouble(), backgroundColor: V2.rule2, color: V2.teal600, borderRadius: BorderRadius.circular(5)),
          ),
        ),
      Row(children: [
        _av(pic),
        const SizedBox(width: 8),
        Text(sel && (c['items_total'] as num? ?? 0) > 0 ? 'Checklist ${c['items_done']} dari ${c['items_total']}' : '${pic['name'] ?? ''}', style: mt),
        const Spacer(),
        if (sel) ...[
          MIcon('cam', size: 13, color: V2.mute),
          const SizedBox(width: 8),
          Text('${c['photos'] ?? 0} foto', style: mt),
        ] else if (c['done_label'] != null && (c['status'] == 'verifikasi' || c['status'] == 'selesai'))
          Text('${c['done_label']}', style: mt)
        else if (due['label'] != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            MIcon('cal', size: 13, color: due['urgent'] == true ? V2.red : V2.mute),
            const SizedBox(width: 4),
            Text('${due['label']}', style: due['urgent'] == true ? V2.d(11.5, FontWeight.w600, V2.red, lh: 1) : mt),
          ]),
      ]),
      if (sel && nearest != null)
        Row(children: [
          const MIcon('locate', size: 13, color: V2.teal600),
          const SizedBox(width: 6),
          Expanded(child: V2Lines(TextSpan(text: nearest, style: V2.d(11, FontWeight.w500, V2.mute, lh: 1.3)), lineHeight: 14.3, dy: 0, exactPitch: true)),
        ]),
      if (sel && c['status'] != 'selesai')
        Row(children: [
          Expanded(child: _cta('cam', 'Foto bukti', false, () => _photo(id))),
          const SizedBox(width: 8),
          Expanded(child: _cta('check', 'Update', true, () => _update(id))),
        ]),
    ];
    return Semantics(
      button: !sel,
      child: GestureDetector(
        onTap: sel ? null : () => setState(() => _sel = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: sel ? V2.teal600 : V2.rule, width: sel ? 2 : 1),
            boxShadow: [sel ? cssShadow(const Color(0x290E8579), 0, 10, 24) : cssShadow(const Color(0x0A0F1F1D), 0, 2, 8)],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 8), children[i]],
          ]),
        ),
      ),
    );
  }

  static bool _fb(Object? t) => RegExp('[≥≤−]').hasMatch('$t');

  Widget _cta(String icon, String label, bool pri, VoidCallback onTap) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              color: pri ? V2.teal600 : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: pri ? V2.teal600 : V2.rule),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              MIcon(icon, size: 16, color: pri ? Colors.white : V2.teal700),
              const SizedBox(width: 7),
              Text(label, style: V2.d(12.5, FontWeight.w600, pri ? Colors.white : V2.teal700, lh: 1)),
            ]),
          ),
        ),
      );

  Future<Position?> _position() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied || p == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)));
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadNearest(int id) async {
    _nearest[id] = '';
    final pos = await _position();
    if (pos == null) {
      if (mounted) setState(() => _nearest.remove(id));
      return;
    }
    try {
      final r = await ApiClient.v3Get('/api/tindak/tasks/$id/nearest', {'lat': '${pos.latitude}', 'lon': '${pos.longitude}'});
      if (mounted) setState(() => _nearest[id] = (r['text'] ?? '').toString());
    } catch (_) {
      if (mounted) setState(() => _nearest.remove(id));
    }
  }

  Future<void> _photo(int id) async {
    final img = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (img == null || !mounted) return;
    final caption = await _ask('Keterangan foto', 'Contoh: CKJ-012');
    final pos = await _position();
    final bytes = await img.readAsBytes();
    final now = DateTime.now();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    final day = '${now.day} ${months[now.month - 1]}';
    try {
      await ApiClient.v3Send('POST', '/api/tindak/tasks/$id/photos', {
        'data': 'data:image/jpeg;base64,${base64Encode(bytes)}',
        'caption': (caption ?? '').trim().isEmpty ? day : '${caption!.trim()} · $day',
        'lat': pos?.latitude,
        'lon': pos?.longitude,
      });
      if (!mounted) return;
      v3Toast(context, 'Foto bukti tersimpan');
      _nearest.remove(id);
      _load();
    } catch (e) {
      if (mounted) v3Toast(context, 'Foto gagal dikirim: ${e.toString().replaceFirst('Exception: ', '')}');
    }
  }

  Future<String?> _ask(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: V2.d(16, FontWeight.w700, V2.ink)),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Lewati')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Simpan')),
        ],
      ),
    );
  }

  Future<void> _update(int id) async {
    Map<String, dynamic> d;
    try {
      d = await ApiClient.v3Get('/api/tindak/tasks/$id');
    } catch (e) {
      if (mounted) v3Toast(context, 'Detail tugas gagal dimuat');
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _UpdateSheet(detail: d, onChanged: _load),
    );
  }
}

class _UpdateSheet extends StatefulWidget {
  const _UpdateSheet({required this.detail, required this.onChanged});
  final Map<String, dynamic> detail;
  final Future<void> Function() onChanged;

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> {
  late Map<String, dynamic> d = widget.detail;
  bool _busy = false;

  Future<void> _send(String method, String path, Map<String, dynamic> body, [String? ok]) async {
    setState(() => _busy = true);
    try {
      d = await ApiClient.v3Send(method, path, body);
      await widget.onChanged();
      if (ok != null && mounted) v3Toast(context, ok);
    } catch (e) {
      if (mounted) v3Toast(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.detail['id'];
    final items = [for (final i in (d['items'] as List? ?? const [])) Map<String, dynamic>.from(i as Map)];
    final status = (d['status'] ?? 'baru').toString();
    const next = {'baru': ('dikerjakan', 'Mulai kerjakan'), 'dikerjakan': ('verifikasi', 'Selesai dikerjakan')};
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${d['title']}', style: V2.d(17, FontWeight.w700, V2.ink, lh: 1.3)),
          const SizedBox(height: 4),
          Text('${d['criterion'] ?? 'Ditutup manual oleh PIC atau admin'}', style: V2.b(12.5, FontWeight.w400, V2.mute, lh: 1.4)),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('CHECKLIST', style: V2.d(12, FontWeight.w600, V2.mute, lh: 1, ls: .06)),
            for (final it in items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: V2.teal600,
                value: it['done'] == true,
                onChanged: _busy ? null : (v) => _send('PATCH', '/api/tindak/tasks/$id/items/${it['id']}', {'done': v == true}),
                title: Text('${it['text']}', style: V2.b(13, FontWeight.w400, it['done'] == true ? V2.mute : V2.ink, lh: 1.35)),
              ),
          ],
          const SizedBox(height: 12),
          if (next.containsKey(status))
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: V2.teal600, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))),
                onPressed: _busy ? null : () => _send('PATCH', '/api/tindak/tasks/$id', {'status': next[status]!.$1}, 'Status diperbarui'),
                child: Text(next[status]!.$2, style: V2.d(14, FontWeight.w600, Colors.white)),
              ),
            )
          else
            Text(status == 'verifikasi' ? 'Menunggu verifikasi KPI otomatis.' : 'Tugas sudah ditutup.', style: V2.b(13, FontWeight.w400, V2.ink2)),
        ]),
      ),
    );
  }
}
