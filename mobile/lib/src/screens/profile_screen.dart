// Redesign v2 page 08 (Android): Profil, opened from the avatar in every app
// bar. Identity card, the installed app, then grouped settings rows (Akun,
// Preferensi, Admin, Tentang) that open sheets. Preferences are saved on the
// server (/api/profile/prefs) so the web Profil page shows the same choices.
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_client.dart';
import '../app_state.dart';
import '../services/update_service.dart';
import '../ui/mock_icons.dart';
import '../ui/v2.dart';
import '../widgets/update_dialog.dart';

/// The public site: links shared from the phone must open anywhere.
const _publicSite = 'https://agent.bizplan-java.com';
const _brown = Color(0xFFB5401F);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.alerts, this.preview, this.previewInstalled});

  /// Open alert count for the bell (the opener passes it).
  final int? alerts;

  /// /api/profile answer to render instead of fetching (golden tests).
  final Map<String, dynamic>? preview;
  final String? previewInstalled;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _p;
  Map<String, dynamic> _ver = const {};
  String _installed = '';
  String? _error;
  int _alerts = 0;

  bool get _preview => widget.preview != null;
  Map<String, dynamic> get _user => (_p?['user'] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get _prefs => (_p?['prefs'] as Map?)?.cast<String, dynamic>() ?? const {};

  @override
  void initState() {
    super.initState();
    _alerts = widget.alerts ?? 0;
    if (_preview) {
      _p = widget.preview;
      _installed = widget.previewInstalled ?? '';
      _ver = {'version_name': _installed.split(' ').first, 'version_code': 69};
      return;
    }
    _load();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _installed = '${i.version} (${i.buildNumber})');
    }).catchError((_) {});
    ApiClient.appVersion().then((v) {
      if (mounted) setState(() => _ver = v);
    }).catchError((_) {});
    if (widget.alerts == null) {
      ApiClient.alertCount().then((n) {
        if (mounted) setState(() => _alerts = n);
      }).catchError((_) {});
    }
  }

  Future<void> _load() async {
    try {
      final d = await ApiClient.profile();
      if (!mounted) return;
      setState(() {
        _p = d;
        _error = null;
      });
      final pr = (d['prefs'] as Map?) ?? const {};
      if (pr['theme'] is String && pr['theme'] != AppState.I.themeName) AppState.I.setTheme(pr['theme'] as String);
      if (pr['animation'] is bool && pr['animation'] != AppState.I.animations) AppState.I.setAnimations(pr['animation'] as bool);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _savePrefs(Map<String, dynamic> patch) async {
    setState(() {
      final next = Map<String, dynamic>.from(_prefs)..addAll(patch);
      if (patch['notify'] is Map) {
        next['notify'] = {
          ...((_prefs['notify'] as Map?) ?? const {}),
          for (final e in (patch['notify'] as Map).entries)
            e.key: {...(((_prefs['notify'] as Map?)?[e.key] as Map?) ?? const {}), ...(e.value as Map)},
        };
      }
      _p = {...?_p, 'prefs': next};
    });
    if (patch['theme'] is String) AppState.I.setTheme(patch['theme'] as String);
    if (patch['animation'] is bool) AppState.I.setAnimations(patch['animation'] as bool);
    if (_preview) return;
    try {
      await ApiClient.saveProfilePrefs(patch);
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? V2.red : V2.teal700));
  }

  String get _regionLabel => (_user['default_region_label'] ?? 'Circle Java').toString();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final admin = (_p?['admin'] as Map?)?.cast<String, dynamic>();
    return Scaffold(
      backgroundColor: V2.bg,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: top, color: Colors.white),
        V2AppBar(
          title: 'Profil',
          subtitle: 'Akun dan pengaturan',
          back: true,
          showAvatar: false,
          alertCount: _alerts,
          onBell: () => Navigator.of(context).pop('alerts'),
        ),
        Expanded(
          child: RefreshIndicator(
            color: V2.teal600,
            onRefresh: _preview ? () async {} : _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              children: _gap([
                if (_error != null && _p == null) _message('Profil belum bisa dimuat: $_error'),
                _identity(),
                _apk(),
                _group('Akun', [
                  _li('user', V2.teal50, V2.teal700, 'Informasi akun', 'Nama, email, departemen', onTap: _accountSheet),
                  _li('pin', const Color(0xFFE1ECFA), const Color(0xFF2C6CB0), 'Wilayah default', 'Dashboard dan Peta',
                      value: _regionLabel, onTap: _regionSheet),
                  _li('lock', const Color(0xFFFCEDD3), const Color(0xFFB7791F), 'Keamanan',
                      'Password, ${(_p?['devices'] as List?)?.length ?? 0} perangkat masuk', onTap: _securitySheet),
                ]),
                _group('Preferensi', [
                  _themeRow(),
                  _li('globe', const Color(0xFFE3F7FA), const Color(0xFF0E6F7C), 'Bahasa', 'Bahasa aplikasi dan jawaban agent',
                      value: AppState.I.lang == 'en' ? 'English' : 'Indonesia', onTap: _langSheet),
                  _li('bell', const Color(0xFFFBE2E8), const Color(0xFFB33A5B), 'Notifikasi', _notifySummary(), onTap: _notifySheet),
                  _li('spark', V2.rule2, V2.ink2, 'Animasi transisi', 'Perpindahan halus antar layar',
                      toggle: _prefs['animation'] != false, onToggle: (v) => _savePrefs({'animation': v})),
                ]),
                if (admin != null)
                  _group('Admin', [
                    _li('bars', const Color(0xFFECE5FA), const Color(0xFF6A4CB5), 'Statistik aplikasi',
                        '${admin['active_users_7d'] ?? 0} pengguna aktif 7 hari', onTap: () async {
                          // A bottom-nav tap on Statistik closes it and Profil, then switches tab.
                          final r = await Navigator.of(context).pushNamed('/stats');
                          if (r is int && context.mounted) Navigator.of(context).pop(r);
                        }),
                    _li('users', const Color(0xFFE1ECFA), const Color(0xFF2C6CB0), 'Pengguna dan akses',
                        (admin['pending'] ?? 0) > 0
                            ? '${admin['pending']} menunggu persetujuan'
                            : '${admin['accounts'] ?? 0} akun · ${admin['inactive'] ?? 0} nonaktif',
                        // Approvals live on Statistik; user management stays on the web admin page.
                        onTap: (admin['pending'] ?? 0) > 0
                            ? () async {
                                final r = await Navigator.of(context).pushNamed('/stats');
                                if (r is int && context.mounted) Navigator.of(context).pop(r);
                              }
                            : () => launchUrl(Uri.parse('$_publicSite/admin'), mode: LaunchMode.externalApplication)),
                  ]),
                _group('Tentang', [
                  _li('info', V2.teal50, V2.teal700, 'Tentang Agent Java', 'Versi, catatan rilis, kebijakan data', onTap: _aboutSheet),
                ]),
                _logoutButton(),
                Text('Agent Java ${_installed.isEmpty ? '-' : _installed} · $_regionLabel',
                    textAlign: TextAlign.center, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.4)),
              ]),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: V2BottomNav(index: -1, onTap: (i) => Navigator.of(context).pop(i)),
    );
  }

  List<Widget> _gap(List<Widget> xs) => [
        for (var i = 0; i < xs.length; i++) ...[if (i > 0) const SizedBox(height: 12), xs[i]],
      ];

  Widget _message(String s) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(14)),
        child: Text(s, style: V2.b(13, FontWeight.w400, V2.red, lh: 1.4)),
      );

  // ── Identity ──

  Widget _identity() {
    final name = (_user['full_name'] ?? _user['username'] ?? '').toString();
    final dept = (_user['department'] ?? '').toString();
    Widget tag(String s, {bool lime = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: lime ? V2.lime : const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(99)),
          child: Text(s, style: V2.d(11.5, FontWeight.w600, lime ? V2.teal900 : Colors.white, lh: 1)),
        );
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, 125.5);
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: cssLinear(160, const [V2.teal700, V2.teal900], size),
        ),
        child: Stack(children: [
          Positioned(
            right: -70,
            top: -80,
            width: 220,
            height: 220,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x8C22B8C9), Color(0x0022B8C9)], stops: [0, .7]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                SizedBox(
                  width: 58,
                  height: 58,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: cssLinear(135, const [V2.lime, V2.lagoon], const Size(58, 58)),
                      ),
                      child: Text((name.trim().isEmpty ? 'U' : name.trim()[0]).toUpperCase(),
                          style: V2.d(22, FontWeight.w700, V2.teal900, lh: 1)),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: V2.teal700, width: 2)),
                        child: const MIcon('cam', size: 13, color: V2.teal700),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(18, FontWeight.w700, Colors.white, lh: 1.2)),
                    Text('@${_user['username'] ?? ''}${dept.isEmpty ? '' : ' · $dept'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(12.5, FontWeight.w400, V2.teal100, lh: 1.4)),
                    Text((_user['email'] ?? '').toString(),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(12.5, FontWeight.w400, V2.teal100, lh: 1.4)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                tag(_user['role'] == 'admin' ? 'Admin' : 'Pengguna', lime: true),
                tag(_regionLabel),
                tag('Akses semua region'),
              ]),
            ]),
          ),
        ]),
      );
    });
  }

  // ── Installed app ──

  bool get _upToDate {
    final latest = (_ver['version_name'] ?? '').toString();
    return latest.isEmpty || _installed.startsWith(latest);
  }

  Widget _apk() {
    final shown = _installed.isEmpty ? (_ver['version_name'] ?? '-').toString() : _installed.split(' ').first;
    final sub = _upToDate ? 'Versi terbaru sudah terpasang' : 'Versi ${_ver['version_name']} tersedia, ketuk untuk memperbarui';
    return GestureDetector(
      onTap: _upToDate ? null : _checkUpdate,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: V2.rule)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 5.2),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: V2.teal50, borderRadius: BorderRadius.circular(12)),
              child: const MIcon('phone', size: 20, color: V2.teal700),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Agent Java $shown', maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(14, FontWeight.w600, V2.ink, lh: 1.25)),
              const SizedBox(height: 3),
              V2Lines(TextSpan(text: sub, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3)), lineHeight: 14.95, dy: 0),
            ]),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 20.5),
            child: _linkButton('share', 'Bagikan', () => SharePlus.instance.share(ShareParams(
                text: 'Unduh Agent Java untuk Android: $_publicSite/unduh', subject: 'Agent Java untuk Android'))),
          ),
        ]),
      ),
    );
  }

  Widget _linkButton(String icon, String label, VoidCallback onTap) => Semantics(
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: V2.rule)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              MIcon(icon, size: 16, color: V2.teal700),
              const SizedBox(width: 7),
              Text(label, style: V2.d(12.5, FontWeight.w600, V2.teal700, lh: 1)),
            ]),
          ),
        ),
      );

  Future<void> _checkUpdate() async {
    try {
      final info = await UpdateService.check();
      if (!mounted) return;
      if (info != null) {
        await showUpdateDialog(context, info);
      } else {
        _toast('Aplikasi sudah versi terbaru.');
      }
    } on UpdateCheckException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Gagal memeriksa pembaruan.', error: true);
    }
  }

  // ── Grouped rows ──

  Widget _group(String title, List<Widget> rows) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: V2.rule)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 6),
            child: Text(title.toUpperCase(), style: V2.d(11, FontWeight.w600, V2.teal700, lh: 1, ls: .06)),
          ),
          for (var i = 0; i < rows.length; i++)
            if (i == 0) rows[i] else Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: V2.rule2))),
              child: rows[i],
            ),
        ]),
      );

  /// One settings row (mockup .li): icon over title and subtitle, then a value
  /// and chevron or a switch, both centred on the subtitle.
  Widget _li(String icon, Color bg, Color fg, String title, String sub,
      {String? value, VoidCallback? onTap, bool? toggle, ValueChanged<bool>? onToggle}) {
    final subStyle = V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3);
    final valueStyle = V2.d(12, FontWeight.w500, V2.mute, lh: 1);
    return Semantics(
      button: onTap != null,
      toggled: toggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? (toggle != null ? () => onToggle?.call(!toggle) : null),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: LayoutBuilder(builder: (context, c) {
            final valueW = value == null || value.isEmpty ? 0.0 : _textW(value, valueStyle);
            final trailingW = toggle != null ? 12 + 38.0 : 12 + valueW + 12 + 16;
            final textW = c.maxWidth - 34 - 12 - trailingW;
            final lines = _lines(sub, subStyle, textW);
            final subH = lines * 14.95;
            final trailH = toggle != null ? 22.0 : 16.0;
            final spanH = subH + 2 > trailH ? subH + 2 : trailH;
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 34,
                height: 16.9 + 2 + subH,
                child: Center(
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                    child: MIcon(icon, size: 17, color: fg),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: textW,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(height: 16.9, child: Text(title, maxLines: 1, style: V2.d(13.5, FontWeight.w600, V2.ink, lh: 1.25))),
                  const SizedBox(height: 2),
                  SizedBox(height: subH, child: Text(sub, style: subStyle)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 18.9),
                child: SizedBox(
                  height: spanH,
                  child: toggle != null
                      ? Row(children: [const SizedBox(width: 12), Center(child: _switch(toggle, onToggle))])
                      : Row(children: [
                          const SizedBox(width: 12),
                          if (valueW > 0) Center(child: Text(value!, style: valueStyle)),
                          const SizedBox(width: 12),
                          const Center(child: MIcon('chevr', size: 16, color: Color(0xFF9AAAA6))),
                        ]),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  double _textW(String s, TextStyle st) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  int _lines(String s, TextStyle st, double w) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))
      ..layout(maxWidth: w);
    final n = tp.computeLineMetrics().length;
    tp.dispose();
    return n < 1 ? 1 : n;
  }

  Widget _switch(bool on, ValueChanged<bool>? onChanged) => GestureDetector(
        onTap: onChanged == null ? null : () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 22,
          decoration: BoxDecoration(color: on ? V2.teal600 : const Color(0xFFCBD6D3), borderRadius: BorderRadius.circular(11)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ),
        ),
      );

  Widget _themeRow() {
    final theme = (_prefs['theme'] ?? AppState.I.themeName).toString();
    Widget seg(String key, String label, String? icon) {
      final on = theme == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => _savePrefs({'theme': key}),
          child: Container(
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              boxShadow: on ? [cssShadow(const Color(0x1F0F1F1D), 0, 1, 3)] : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[MIcon(icon, size: 14, color: on ? V2.teal700 : V2.ink2), const SizedBox(width: 6)],
              Text(label, style: V2.d(12, FontWeight.w600, on ? V2.teal700 : V2.ink2, lh: 1)),
            ]),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: const Color(0xFFF4FCE3), borderRadius: BorderRadius.circular(10)),
            child: const MIcon('palette', size: 17, color: V2.lime700),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 16.9, child: Text('Tema', style: V2.d(13.5, FontWeight.w600, V2.ink, lh: 1.25))),
            const SizedBox(height: 2),
            SizedBox(height: 14.95, child: Text('Berlaku juga di web', style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.3))),
          ]),
        ]),
        const SizedBox(height: 8),
        Container(
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: V2.rule2, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            seg('light', 'Terang', 'sun'),
            const SizedBox(width: 2),
            seg('dark', 'Gelap', 'moon'),
            const SizedBox(width: 2),
            seg('system', 'Sistem', null),
          ]),
        ),
        const SizedBox(height: 2),
      ]),
    );
  }

  String _notifySummary() {
    final n = (_prefs['notify'] as Map?) ?? const {};
    final push = n.values.any((v) => v is Map && v['push'] == true);
    final quiet = _prefs['quiet_hours'] != false;
    return '${push ? 'Push aktif' : 'Push mati'}${quiet ? ', jam tenang 22.00 sampai 06.00' : ''}';
  }

  Widget _logoutButton() => Semantics(
        button: true,
        child: GestureDetector(
          onTap: _logout,
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6F3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF3C9BC)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const MIcon('logout', size: 16, color: _brown),
              const SizedBox(width: 8),
              Text('Keluar', style: V2.d(13.5, FontWeight.w600, _brown, lh: 1)),
            ]),
          ),
        ),
      );

  Future<void> _logout() async {
    if (_preview) return;
    await AuthState.clear();
    if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // ── Sheets ──

  Future<T?> _sheet<T>(String title, Widget Function(BuildContext ctx, StateSetter set) body) => showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, set) => Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(width: 36, height: 4, decoration: BoxDecoration(color: V2.rule, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  Text(title, style: V2.d(18, FontWeight.w700, V2.ink, lh: 1.3)),
                  const SizedBox(height: 12),
                  body(ctx, set),
                ]),
              ),
            ),
          ),
        ),
      );

  InputDecoration _deco(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFD5E0DD))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFD5E0DD))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: V2.teal600)),
      );

  Widget _primary(String label, VoidCallback? onTap, {bool busy = false}) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: V2.teal600,
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: busy ? null : onTap,
        child: Text(busy ? 'Menyimpan...' : label, style: V2.d(14, FontWeight.w600, Colors.white)),
      );

  Future<void> _accountSheet() async {
    final name = TextEditingController(text: (_user['full_name'] ?? '').toString());
    final email = TextEditingController(text: (_user['email'] ?? '').toString());
    var dept = (_user['department'] ?? '').toString();
    final depts = {...(((_p?['options'] as Map?)?['departments'] as List?) ?? const []).map((e) => e.toString()), if (dept.isNotEmpty) dept}.toList();
    var busy = false;
    await _sheet<void>('Informasi akun', (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, decoration: _deco('Nama lengkap')),
          const SizedBox(height: 10),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: _deco('Email')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: dept.isEmpty ? null : dept,
            decoration: _deco('Departemen'),
            items: [for (final d in depts) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => set(() => dept = v ?? dept),
          ),
          const SizedBox(height: 8),
          Text('Username @${_user['username'] ?? ''} tidak bisa diubah. Peran diatur Admin.',
              style: V2.b(12, FontWeight.w400, V2.mute, lh: 1.4)),
          const SizedBox(height: 14),
          _primary('Simpan perubahan', () async {
            set(() => busy = true);
            try {
              await ApiClient.updateProfile(fullName: name.text.trim(), email: email.text.trim(), department: dept);
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('Profil disimpan.');
              _load();
            } catch (e) {
              set(() => busy = false);
              _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
            }
          }, busy: busy),
        ]));
  }

  Future<void> _regionSheet() async {
    final regions = (((_p?['options'] as Map?)?['regions'] as List?) ?? const []).cast<Map>();
    final cur = (_user['default_region'] ?? 'JAVA').toString();
    final pick = await _sheet<String>('Wilayah default', (ctx, set) => Column(children: [
          Text('Dipakai sebagai wilayah awal di Dashboard dan Peta.', style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.4)),
          const SizedBox(height: 8),
          for (final r in regions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r['label'].toString(), style: V2.d(14, FontWeight.w500, V2.ink)),
              trailing: r['key'] == cur ? const MIcon('check', size: 18, color: V2.teal600) : null,
              onTap: () => Navigator.pop(ctx, r['key'].toString()),
            ),
        ]));
    if (pick == null || pick == cur) return;
    await _savePrefs({'default_region': pick});
    _load();
  }

  Future<void> _securitySheet() async {
    final devices = ((_p?['devices'] as List?) ?? const []).cast<Map>();
    final sec = (_p?['security'] as Map?) ?? const {};
    final oldPw = TextEditingController(), newPw = TextEditingController(), newPw2 = TextEditingController();
    var busy = false;
    await _sheet<void>('Keamanan', (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(sec['password_days'] != null ? 'Password diubah ${sec['password_days']} hari lalu' : 'Password belum pernah diubah',
              style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.4)),
          const SizedBox(height: 8),
          for (final d in devices)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MIcon(d['kind'] == 'android' ? 'phone' : 'monitor', size: 20, color: V2.ink2),
              title: Text('${d['name']}${d['current'] == true ? ' (perangkat ini)' : ''}', style: V2.d(13.5, FontWeight.w600, V2.ink)),
              subtitle: Text(d['sub'].toString(), style: V2.b(12, FontWeight.w400, V2.mute)),
              trailing: d['can_sign_out'] == true && d['id'] is int
                  ? TextButton(
                      onPressed: () async {
                        await ApiClient.signOutDevice(d['id'] as int).catchError((_) => <String, dynamic>{});
                        if (ctx.mounted) Navigator.pop(ctx);
                        _toast('Perangkat dikeluarkan.');
                        _load();
                      },
                      child: Text('Keluarkan', style: V2.d(12, FontWeight.w600, _brown)),
                    )
                  : null,
            ),
          const SizedBox(height: 8),
          Text('Ubah password', style: V2.d(14, FontWeight.w600, V2.ink)),
          const SizedBox(height: 8),
          TextField(controller: oldPw, obscureText: true, decoration: _deco('Password lama')),
          const SizedBox(height: 10),
          TextField(controller: newPw, obscureText: true, decoration: _deco('Password baru (min. 6 karakter)')),
          const SizedBox(height: 10),
          TextField(controller: newPw2, obscureText: true, decoration: _deco('Ulangi password baru')),
          const SizedBox(height: 14),
          _primary('Simpan password', () async {
            if (newPw.text.length < 6 || newPw.text != newPw2.text) {
              _toast(newPw.text.length < 6 ? 'Password baru minimal 6 karakter.' : 'Konfirmasi password tidak sama.', error: true);
              return;
            }
            set(() => busy = true);
            try {
              await ApiClient.changePassword(oldPw.text, newPw.text);
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('Password diubah.');
              _load();
            } catch (e) {
              set(() => busy = false);
              _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
            }
          }, busy: busy),
        ]));
  }

  Future<void> _langSheet() async {
    final pick = await _sheet<String>('Bahasa', (ctx, set) => Column(children: [
          for (final (k, l) in const [('id', 'Indonesia'), ('en', 'English')])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l, style: V2.d(14, FontWeight.w500, V2.ink)),
              trailing: AppState.I.lang == k ? const MIcon('check', size: 18, color: V2.teal600) : null,
              onTap: () => Navigator.pop(ctx, k),
            ),
        ]));
    if (pick == null) return;
    await AppState.I.setLang(pick);
    if (mounted) setState(() {});
  }

  Future<void> _notifySheet() async {
    List<dynamic> inbox = const [];
    if (!_preview) inbox = await ApiClient.notifications().catchError((_) => <dynamic>[]);
    final unread = inbox.whereType<Map>().where((n) => n['is_read'] != true).toList();
    const kinds = [
      ('alert_kritis', 'Alert kritis', 'Dari Watchlist'),
      ('alert_peringatan', 'Alert peringatan', 'Dari Watchlist'),
      ('laporan', 'Laporan terjadwal', 'Setelah laporan terkirim'),
      ('versi', 'Versi aplikasi baru', 'APK Android'),
    ];
    await _sheet<void>('Notifikasi', (ctx, set) {
      final n = (_prefs['notify'] as Map?) ?? const {};
      Widget box(String kind, String ch) {
        final on = (n[kind] as Map?)?[ch] == true;
        return Checkbox(
          value: on,
          activeColor: V2.teal600,
          onChanged: (v) async {
            await _savePrefs({'notify': {kind: {ch: v == true}}});
            set(() {});
          },
        );
      }

      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('In-app selalu aktif. Pilih kanal tambahan per jenis.', style: V2.b(13, FontWeight.w400, V2.mute, lh: 1.4)),
        const SizedBox(height: 6),
        Row(children: [
          const Expanded(child: SizedBox()),
          SizedBox(width: 56, child: Text('Email', textAlign: TextAlign.center, style: V2.d(11, FontWeight.w600, V2.mute))),
          SizedBox(width: 56, child: Text('Push', textAlign: TextAlign.center, style: V2.d(11, FontWeight.w600, V2.mute))),
        ]),
        for (final (k, l, s) in kinds)
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l, style: V2.d(13.5, FontWeight.w600, V2.ink)),
                Text(s, style: V2.b(11.5, FontWeight.w400, V2.mute)),
              ]),
            ),
            SizedBox(width: 56, child: box(k, 'email')),
            SizedBox(width: 56, child: box(k, 'push')),
          ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Jam tenang 22.00 sampai 06.00', style: V2.d(13.5, FontWeight.w600, V2.ink)),
              Text('Push ditahan, kecuali alert kritis', style: V2.b(11.5, FontWeight.w400, V2.mute)),
            ]),
          ),
          _switch(_prefs['quiet_hours'] != false, (v) async {
            await _savePrefs({'quiet_hours': v});
            set(() {});
          }),
        ]),
        if (unread.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text('Pesan belum dibaca (${unread.length})', style: V2.d(14, FontWeight.w600, V2.ink))),
            TextButton(
              onPressed: () async {
                await ApiClient.markAllNotificationsRead();
                set(() => unread.clear());
              },
              child: Text('Tandai dibaca', style: V2.d(12, FontWeight.w600, V2.teal700)),
            ),
          ]),
          for (final m in unread.take(5))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: V2.bg, borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((m['title'] ?? '').toString(), style: V2.d(13, FontWeight.w600, V2.ink)),
                Text((m['message'] ?? '').toString(), style: V2.b(12, FontWeight.w400, V2.ink2, lh: 1.4)),
              ]),
            ),
        ],
      ]);
    });
    if (mounted) setState(() {});
  }

  Future<void> _aboutSheet() async {
    await _sheet<void>('Tentang Agent Java', (ctx, set) {
      Widget row(String a, String b) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(a, style: V2.b(13, FontWeight.w400, V2.mute))),
              Text(b.isEmpty ? '-' : b, style: V2.d(13, FontWeight.w600, V2.ink)),
            ]),
          );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        row('Versi terpasang', _installed),
        row('Versi terbaru', (_ver['version_name'] ?? '').toString()),
        row('Tanggal rilis', (_ver['released_at'] ?? '').toString()),
        const SizedBox(height: 8),
        Text('Data dibaca dari BigQuery secara read-only. Kolom data pribadi pelanggan selalu diblokir.',
            style: V2.b(12, FontWeight.w400, V2.mute, lh: 1.4)),
        const SizedBox(height: 14),
        _primary('Cek pembaruan', () {
          Navigator.pop(ctx);
          _checkUpdate();
        }),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.of(context).pushNamed('/download');
          },
          child: Text('Catatan rilis', style: V2.d(13, FontWeight.w600, V2.teal700)),
        ),
      ]);
    });
  }
}
