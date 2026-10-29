import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../services/update_service.dart';
import '../ui/chart.dart' show idNum, monthsId;
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// Android · Unduh APK, reached from Profil after login: the latest release,
/// install steps, release notes and FAQ. The download button fetches the APK
/// from /api/app/download and opens the installer.
class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key, this.previewVersion, this.previewReleases});
  final Map<String, dynamic>? previewVersion;
  final List<Map<String, dynamic>>? previewReleases;

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  Map<String, dynamic>? _version;
  List<Map<String, dynamic>> _releases = [];
  double? _progress;
  int _openFaq = 0;

  static const _faq = [
    ('Kenapa harus izinkan “sumber tidak dikenal”?',
        'APK dibagikan internal, bukan lewat Play Store. Izin hanya untuk browser yang Anda pakai mengunduh.'),
    ('Apakah update otomatis?',
        'Aplikasi memeriksa versi baru setiap kali dibuka dan menawarkan pembaruan. Versi bertanda Wajib harus dipasang sebelum lanjut.'),
    ('Lupa password?', 'Ketuk "Lupa password?" di halaman masuk. Tautan untuk membuat password baru dikirim ke email kantor Anda.'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.previewVersion != null) {
      _version = widget.previewVersion;
      _releases = widget.previewReleases ?? [];
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final res = await Future.wait<Object>([
      ApiClient.appVersion().catchError((_) => <String, dynamic>{}),
      ApiClient.appReleases().catchError((_) => <dynamic>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _version = res[0] as Map<String, dynamic>;
      _releases = (res[1] as List).cast<Map<String, dynamic>>();
    });
  }

  String _date(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '' : '${d.day} ${monthsId[d.month - 1]} ${d.year}';
  }

  Future<void> _download() async {
    final v = _version;
    if (v == null || v['available'] != true) {
      showToast(context, 'APK belum tersedia di server. Hubungi admin.', ok: false);
      return;
    }
    final raw = (v['download_url'] ?? '/api/app/download').toString();
    final info = UpdateInfo(
      versionName: (v['version_name'] ?? '').toString(),
      versionCode: (v['version_code'] as num?)?.toInt() ?? 0,
      notes: (v['notes'] ?? '').toString(),
      mandatory: v['mandatory'] == true,
      downloadUrl: raw.startsWith('http') ? raw : '${AppConfig.apiBase}$raw',
      sizeBytes: (v['size_bytes'] as num?)?.toInt() ?? 0,
    );
    setState(() => _progress = 0);
    final err = await UpdateService.downloadAndInstall(info, onProgress: (x) {
      if (mounted) setState(() => _progress = x);
    });
    if (!mounted) return;
    setState(() => _progress = null);
    if (err != null) showToast(context, err, ok: false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(children: [
        Container(
          color: p.surface,
          padding: EdgeInsets.only(top: top),
          child: SizedBox(
            height: 60,
            child: Row(children: [
              const SizedBox(width: 8),
              SquareIconButton(Icx.chevronLeft, bordered: false, color: p.ink, tooltip: 'Kembali', onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 10),
              Expanded(child: Text('Unduh APK', style: ts(18, w700, p.ink, lh: 1.35))),
              const AppLogo(size: 36, radius: 10),
              const SizedBox(width: 12),
            ]),
          ),
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).padding.bottom), children: [
            _hero(p),
            _section(p, 'Cara instal', 28, [
              for (final (i, t, s) in const [
                (1, '1. Unduh file APK', 'Simpan di folder Unduhan.'),
                (2, '2. Izinkan sumber ini', 'Aktifkan di Setelan saat diminta.'),
                (3, '3. Buka & masuk', 'Instal, lalu login akun kantor.'),
              ]) ...[
                if (i > 1) const SizedBox(height: 12),
                _stepCard(p, i, t, s),
              ],
            ]),
            if (_releases.isNotEmpty)
              _section(p, 'Apa yang baru', 20, gap: 10, [
                for (final (i, r) in _releases.take(4).indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _release(p, r, i),
                ],
              ]),
            _section(p, 'FAQ', 20, gap: 8, [
              for (final (i, (q, a)) in _faq.indexed) ...[
                if (i > 0) const SizedBox(height: 8),
                _faqCard(p, i, q, a),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _hero(Pal p) {
    final v = _version ?? const {};
    final size = (v['size_bytes'] as num?)?.toDouble() ?? 0;
    final ver = (v['version_name'] ?? '').toString();
    return SizedBox(
      height: 720,
      child: ClipRect(
        child: HeroFill(
          kawung: .12,
          child: Stack(children: [
            const Positioned(left: 40, top: 360, width: 420, height: 420, child: Glow(color: Color(0xFF5BCEC3), alpha: .33)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (ver.isNotEmpty)
                  Container(
                    height: 28,
                    padding: const EdgeInsets.fromLTRB(11, 0, 13, 0),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withValues(alpha: .18)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Ic(Icx.rocket, size: 14, color: Color(0xFFF5A623)),
                      const SizedBox(width: 6),
                      Text('v$ver · ${_date(v['released_at']?.toString())}', style: ts(12, w600, Colors.white)),
                    ]),
                  ),
                const SizedBox(height: 16),
                Text('Winning Every Second, di ponsel Anda.', style: ts(30, w800, Colors.white, lh: 1.2, ls: -.005)),
                const SizedBox(height: 16),
                _downloadButton(size),
                const SizedBox(height: 16),
                Text('Android ${v['min_android'] ?? '8.0'}+ · ditandatangani IOH', style: ts(12, w400, const Color(0xFFC0EDE8))),
              ]),
            ),
            Positioned(left: 77, top: 330, child: _phone()),
          ]),
        ),
      ),
    );
  }

  Widget _downloadButton(double size) {
    final busy = _progress != null;
    const fg = Color(0xFF04332E);
    final label = busy
        ? 'Mengunduh… ${idNum((_progress! * 100).clamp(0, 100), 0)}%'
        : 'Download APK${size > 0 ? ' · ${idNum(size / 1048576, 1)} MB' : ''}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : _download,
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF5A623), Color(0xFFF0B54A)],
            ),
          ),
          child: Stack(children: [
            if (busy)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress!.clamp(0.0, 1.0),
                  child: DecoratedBox(decoration: BoxDecoration(color: Colors.white.withValues(alpha: .25), borderRadius: BorderRadius.circular(16))),
                ),
              ),
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Ic(Icx.download, size: 20, color: fg),
                const SizedBox(width: 10),
                Text(label, style: ts(16, w600, fg)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _phone() => Container(
        width: 236,
        height: 482,
        decoration: BoxDecoration(
          color: const Color(0xFF0B1513),
          borderRadius: BorderRadius.circular(35.2),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
          boxShadow: const [BoxShadow(color: Color(0x5904332E), offset: Offset(0, 30), blurRadius: 60, spreadRadius: -10)],
        ),
        padding: const EdgeInsets.all(7),
        child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(28.6),
            child: Image.asset('assets/img/scr_dash.webp', width: 220, height: 466, fit: BoxFit.cover, alignment: Alignment.topCenter),
          ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Color(0xFF0B1513), shape: BoxShape.circle))),
          ),
        ]),
      );

  Widget _section(Pal p, String title, double topPad, List<Widget> children, {double gap = 12}) => Padding(
        padding: EdgeInsets.fromLTRB(20, topPad, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Overline(title, color: p.teal700),
          SizedBox(height: gap),
          ...children,
        ]),
      );

  Widget _stepCard(Pal p, int i, String t, String s) => Container(
        height: 90,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.rule),
        ),
        child: Row(children: [
          Container(
            width: 96,
            height: 64,
            decoration: BoxDecoration(color: p.teal50, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/img/install_$i.webp', fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t, style: ts(13, w600, p.ink)),
              const SizedBox(height: 2),
              Text(s, style: ts(12, w400, p.mute)),
            ]),
          ),
        ]),
      );

  Widget _release(Pal p, Map<String, dynamic> r, int i) {
    final notes = ((r['notes'] as List?) ?? const []).map((e) => e.toString()).toList();
    if (i == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.teal300, width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x1A0E8579), offset: Offset(0, 0), blurRadius: 0, spreadRadius: 3)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('v${r['version_name']}', style: ts(16, w600, p.ink)),
            const SizedBox(width: 8),
            const StatusBadge('Terbaru', kind: BadgeKind.info),
            if (r['mandatory'] == true) ...[const SizedBox(width: 6), const StatusBadge('Wajib', kind: BadgeKind.warning)],
          ]),
          for (final n in notes) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 1), child: Ic(Icx.check, size: 14, color: p.teal600)),
              const SizedBox(width: 8),
              Expanded(child: Text(n, style: ts(12, w400, p.text2))),
            ]),
          ],
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: p.rule)),
      child: Row(children: [
        Expanded(child: Text('v${r['version_name']}', style: ts(13, w600, p.ink))),
        if (r['mandatory'] == true) ...[const StatusBadge('Wajib', kind: BadgeKind.warning), const SizedBox(width: 10)],
        Text(_date(r['released_at']?.toString()), style: ts(12, w400, p.mute)),
      ]),
    );
  }

  Widget _faqCard(Pal p, int i, String q, String a) {
    final open = _openFaq == i;
    return Material(
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.rule)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _openFaq = open ? -1 : i),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(q, style: ts(13, w600, p.ink))),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 1), child: Ic(open ? Icx.minus : Icx.plus, size: 16, color: p.text2)),
            ]),
            if (open) ...[
              const SizedBox(height: 6),
              Text(a, style: ts(12, w400, p.text2)),
            ],
          ]),
        ),
      ),
    );
  }
}
