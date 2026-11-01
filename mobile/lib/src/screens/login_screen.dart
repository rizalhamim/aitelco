import 'dart:async';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../api/api_client.dart';
import '../ui/kit.dart';
import '../ui/mock_icons.dart';
import '../ui/v2.dart';

/// Android Login, Redesign v2 (design/mockup-v2/01-login, Android 390 x 844):
/// background video on the top 62 %, "Winning Every Second" with a bar that
/// follows the video seconds, and a white card rising from the bottom. After
/// "Masuk" the card asks for the 4-digit code the backend e-mails.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.playVideo = true});

  /// Off in widget tests, where no video platform exists; the poster shows.
  final bool playVideo;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _info;
  bool _codeSent = false;
  bool _remember = true;
  int _cooldown = 0;
  Timer? _timer;

  VideoPlayerController? _video;
  bool _paused = true;
  bool _playing = false;
  double _progress = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_video == null && widget.playVideo) {
      // reduced motion (Android "remove animations") starts paused on the poster
      _paused = MediaQuery.of(context).disableAnimations;
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final v = VideoPlayerController.asset('assets/video/login.mp4', videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _video = v;
    try {
      await v.initialize();
      await v.setLooping(true);
      await v.setVolume(0);
      v.addListener(_onVideo);
      if (!_paused) await v.play();
    } catch (_) {
      // no decoder: the poster stays
    }
    if (mounted) setState(() {});
  }

  void _onVideo() {
    final v = _video!.value;
    if (!mounted || !v.isInitialized || v.duration.inMilliseconds == 0) return;
    setState(() {
      if (v.isPlaying && v.position > Duration.zero) _playing = true;
      _progress = v.position.inMilliseconds / v.duration.inMilliseconds;
    });
  }

  void _toggleVideo() {
    setState(() => _paused = !_paused);
    final v = _video;
    if (v == null || !v.value.isInitialized) return;
    _paused ? v.pause() : v.play();
  }

  @override
  void dispose() {
    _video?.removeListener(_onVideo);
    _video?.dispose();
    _timer?.cancel();
    _user.dispose();
    _pass.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  String _msg(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _requestToken() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Isi username dan password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiClient.requestLoginToken(_user.text.trim(), _pass.text);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _info = (res['message'] ?? 'Kode terkirim ke email Anda.').toString();
      });
      _startCooldown();
    } catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyToken() async {
    if (_code.text.trim().length < 4) {
      setState(() => _error = 'Masukkan kode 4 digit dari email.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.verifyLoginToken(_user.text.trim(), _code.text.trim(), rememberMe: _remember);
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      setState(() => _error = _msg(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final ctrl = TextEditingController(text: _user.text.contains('@') ? _user.text : '');
    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 26 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Grab(),
          const SizedBox(height: 16),
          Text('Lupa password', style: V2.d(22, FontWeight.w700, V2.ink, lh: 1.2)),
          const SizedBox(height: 4),
          Text('Masukkan email kantor Anda. Tautan untuk membuat password baru akan dikirim ke sana.',
              style: V2.b(14, FontWeight.w400, V2.mute, lh: 1.55)),
          const SizedBox(height: 14),
          _V2Field(label: 'Email kantor', controller: ctrl, hint: 'nama@kantor.co.id', icon: 'mail', keyboard: TextInputType.emailAddress, autofocus: true),
          const SizedBox(height: 14),
          _Cta('Kirim tautan', onTap: () => Navigator.pop(ctx, ctrl.text.trim())),
        ]),
      ),
    );
    if (email == null || !email.contains('@')) return;
    try {
      final msg = await ApiClient.forgotPassword(email);
      if (mounted) showToast(context, msg);
    } catch (e) {
      if (mounted) showToast(context, _msg(e), ok: false);
    }
  }

  static const _regions = [('JAVA', 'Circle Java'), ('WEST JAVA', 'West Java'), ('CENTRAL JAVA', 'Central Java'), ('EAST JAVA', 'East Java')];
  static const _departments = ['Business Planning', 'Sales', 'Marketing', 'Network', 'Finance', 'Operations'];

  /// New users ask for an account; an Admin approves it on Statistik and the
  /// approval email carries the link to set a password.
  Future<void> _requestAccess() async {
    final name = TextEditingController(), email = TextEditingController();
    var dept = _departments.first, region = _regions.first.$1;
    String? err;
    var sending = false;
    Widget chips<T>(List<(T, String)> xs, T value, ValueChanged<T> on) => Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in xs)
            ChoiceChip(
              label: Text(x.$2, style: V2.d(12.5, FontWeight.w600, x.$1 == value ? Colors.white : V2.ink2, lh: 1)),
              selected: x.$1 == value,
              showCheckmark: false,
              selectedColor: V2.teal600,
              backgroundColor: Colors.white,
              side: BorderSide(color: x.$1 == value ? V2.teal600 : V2.rule),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
              onSelected: (_) => on(x.$1),
            ),
        ]);
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        Future<void> send() async {
          if (sending) return;
          final n = name.text.trim(), e = email.text.trim();
          if (n.length < 2 || !e.contains('@')) {
            set(() => err = 'Isi nama dan email kantor yang benar.');
            return;
          }
          set(() { sending = true; err = null; });
          try {
            final r = await ApiClient.requestAccess({'full_name': n, 'email': e, 'department': dept, 'region': region});
            if (ctx.mounted) Navigator.pop(ctx, (r['message'] ?? 'Permintaan terkirim.').toString());
          } catch (x) {
            set(() { sending = false; err = _msg(x); });
          }
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(22, 14, 22, 26 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _Grab(),
              const SizedBox(height: 16),
              Text('Minta akses', style: V2.d(22, FontWeight.w700, V2.ink, lh: 1.2)),
              const SizedBox(height: 4),
              Text('Admin akan meninjau permintaan Anda. Setelah disetujui, tautan untuk membuat password dikirim ke email.',
                  style: V2.b(14, FontWeight.w400, V2.mute, lh: 1.55)),
              const SizedBox(height: 14),
              _V2Field(label: 'Nama lengkap', controller: name, hint: 'Nama Anda', icon: 'luser', action: TextInputAction.next, autofocus: true),
              const SizedBox(height: 14),
              _V2Field(label: 'Email kantor', controller: email, hint: 'nama@kantor.co.id', icon: 'mail', keyboard: TextInputType.emailAddress),
              const SizedBox(height: 14),
              Text('Departemen', style: V2.d(13, FontWeight.w600, V2.ink2, lh: 1.2)),
              const SizedBox(height: 8),
              chips([for (final d in _departments) (d, d)], dept, (v) => set(() => dept = v)),
              const SizedBox(height: 14),
              Text('Region', style: V2.d(13, FontWeight.w600, V2.ink2, lh: 1.2)),
              const SizedBox(height: 8),
              chips(_regions, region, (v) => set(() => region = v)),
              if (err != null) ...[
                const SizedBox(height: 10),
                Text(err!, style: V2.d(13, FontWeight.w500, V2.red, lh: 1.4)),
              ],
              const SizedBox(height: 14),
              _Cta('Kirim permintaan', onTap: send, loading: sending),
            ]),
          ),
        );
      }),
    );
    // The controllers are left to the GC: the sheet still paints them while it animates out.
    if (done != null && mounted) showToast(context, done);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final top = mq.padding.top;
    final h = mq.size.height;
    final v = _video;
    final showVideo = v != null && v.value.isInitialized && _playing;
    return Scaffold(
      backgroundColor: V2.teal900,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        // video (or its poster) covers the top 62 % of the screen
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: h * .62,
          child: ClipRect(
            child: Stack(fit: StackFit.expand, children: [
              Image.asset('assets/img/login_poster.jpg', fit: BoxFit.cover),
              if (showVideo)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
                ),
            ]),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x8C04332E), Color(0x2604332E), Color(0x8C04332E), Color(0xFF04332E)],
                stops: [0, .28, .5, .64],
              ),
            ),
          ),
        ),
        Positioned(left: 24, top: top + 20, child: const _Brand()),
        Positioned(right: 18, top: top + 16, child: _VideoButton(paused: _paused, onTap: _toggleVideo)),
        Positioned(left: 24, right: 24, top: top + 164, child: _Hero(progress: _progress)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            reverse: true,
            child: _card(),
          ),
        ),
      ]),
    );
  }

  Widget _card() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _Grab(),
          const SizedBox(height: 16),
          ...(_codeSent ? _codeStep() : _passwordStep()),
          const SizedBox(height: 14),
          SizedBox(
            height: 20,
            child: _error == null && !_codeSent
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: _requestAccess,
                      child: Text.rich(
                        TextSpan(text: 'Belum punya akun? ', children: [
                          TextSpan(text: 'Minta akses', style: V2.d(13, FontWeight.w600, V2.teal700, lh: 1.4)),
                        ]),
                        maxLines: 1,
                        style: V2.d(13, FontWeight.w500, V2.mute, lh: 1.4),
                      ),
                    ),
                  )
                : Text(_error ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: V2.d(13, FontWeight.w500, _error != null ? V2.red : V2.teal700, lh: 1.4)),
          ),
          // room for the system gesture bar, like the mockup's home indicator
          const SizedBox(height: 22),
        ]),
      ),
    );
  }

  Widget _title(String t, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: V2.d(22, FontWeight.w700, V2.ink, lh: 1.2)),
        const SizedBox(height: 4),
        Text(sub, style: V2.b(14, FontWeight.w400, V2.mute, lh: 1.55)),
      ]);

  List<Widget> _passwordStep() => [
        _title('Masuk', 'Selamat datang kembali.'),
        const SizedBox(height: 14),
        _V2Field(label: 'Username', controller: _user, hint: 'nama.pengguna', icon: 'luser', action: TextInputAction.next),
        const SizedBox(height: 14),
        _V2Field(
          label: 'Password',
          controller: _pass,
          hint: '••••••••••',
          icon: 'llock',
          obscure: _obscure,
          onSubmit: _requestToken,
          trailing: Semantics(
            button: true,
            label: _obscure ? 'Tampilkan password' : 'Sembunyikan password',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _obscure = !_obscure),
              child: SizedBox(width: 31, height: 31, child: Center(child: MIcon(_obscure ? 'leye' : 'leyeoff', size: 19, color: V2.mute))),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 21,
          child: Row(children: [
            Semantics(
              toggled: _remember,
              label: 'Ingat saya',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _remember = !_remember),
                child: Row(children: [
                  _Switch(on: _remember),
                  const SizedBox(width: 9),
                  Text('Ingat saya', style: V2.d(13, FontWeight.w500, V2.ink2, lh: 1)),
                ]),
              ),
            ),
            const Spacer(),
            GestureDetector(onTap: _forgot, child: Text('Lupa password?', style: V2.d(13, FontWeight.w600, V2.teal700, lh: 1))),
          ]),
        ),
        const SizedBox(height: 14),
        _Cta('Masuk', onTap: _requestToken, loading: _loading),
      ];

  List<Widget> _codeStep() => [
        _title('Cek email Anda', _info ?? 'Kode 4 digit sudah dikirim.'),
        const SizedBox(height: 14),
        _V2Field(label: 'Kode masuk', controller: _code, hint: '0000', icon: 'shield', keyboard: TextInputType.number, autofocus: true, onSubmit: _verifyToken),
        const SizedBox(height: 14),
        SizedBox(
          height: 21,
          child: Row(children: [
            GestureDetector(
              onTap: _loading ? null : () => setState(() { _codeSent = false; _error = null; _code.clear(); }),
              child: Text('Ganti akun', style: V2.d(13, FontWeight.w600, V2.ink2, lh: 1)),
            ),
            const Spacer(),
            _cooldown > 0
                ? Text('Kirim ulang dalam $_cooldown dtk', style: V2.d(13, FontWeight.w500, V2.mute, lh: 1))
                : GestureDetector(onTap: _requestToken, child: Text('Kirim ulang kode', style: V2.d(13, FontWeight.w600, V2.teal700, lh: 1))),
          ]),
        ),
        const SizedBox(height: 14),
        _Cta('Verifikasi dan masuk', onTap: _verifyToken, loading: _loading),
      ];
}

class _Grab extends StatelessWidget {
  const _Grab();
  @override
  Widget build(BuildContext context) => Center(
        child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFDCE6E3), borderRadius: BorderRadius.circular(4))),
      );
}

/// Old eagle logo tile and the "Agent Java" wordmark.
class _Brand extends StatelessWidget {
  const _Brand();
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(42 * .28),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [cssShadow(const Color(0x40000000), 0, 8, 24)],
        ),
        child: Image.asset('assets/icon_circle.png', width: 38 * .84, height: 38 * .84, fit: BoxFit.contain),
      ),
      const SizedBox(width: 12),
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Agent '),
          TextSpan(text: 'Java', style: V2.d(18, FontWeight.w700, V2.lime, lh: 1, ls: -.01)),
        ]),
        style: V2.d(18, FontWeight.w700, Colors.white, lh: 1, ls: -.01),
      ),
    ]);
  }
}

class _VideoButton extends StatelessWidget {
  const _VideoButton({required this.paused, required this.onTap});
  final bool paused;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: paused ? 'Putar video' : 'Jeda video',
      child: GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x5904332E),
                border: Border.all(color: const Color(0x47FFFFFF)),
              ),
              child: MIcon(paused ? 'play' : 'pause', size: 16, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Winning Every Second" and the seconds bar.
class _Hero extends StatelessWidget {
  const _Hero({required this.progress});
  final double progress;
  @override
  Widget build(BuildContext context) {
    final style = V2.d(44, FontWeight.w800, Colors.white, lh: 1, ls: -.03);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Winning', style: style),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text('Every ', style: style),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => const LinearGradient(colors: [V2.lime, Color(0xFF7EE8A2), V2.lagoon], stops: [0, .55, 1]).createShader(r),
          child: Text('Second', style: style),
        ),
      ]),
      const SizedBox(height: 14),
      Container(
        width: 120,
        height: 4,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(colors: [V2.lime, V2.lagoon]),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.on});
  final bool on;
  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 36,
      height: 21,
      decoration: BoxDecoration(color: on ? V2.teal600 : const Color(0xFFD5DFDC), borderRadius: BorderRadius.circular(99)),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 15,
          height: 15,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [cssShadow(const Color(0x40000000), 0, 1, 3)]),
        ),
      ),
    );
  }
}

/// Gradient call to action: 56 px, label plus arrow, spinner while busy.
class _Cta extends StatelessWidget {
  const _Cta(this.label, {required this.onTap, this.loading = false});
  final String label;
  final VoidCallback onTap;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: loading ? null : onTap,
        child: LayoutBuilder(builder: (context, c) {
          return Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: cssLinear(100, const [V2.teal600, V2.teal500, Color(0xFF1597A8)], Size(c.maxWidth, 56), stops: const [0, .5, 1]),
              boxShadow: [cssShadow(const Color(0x590E8579), 0, 12, 26)],
            ),
            child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white, backgroundColor: Color(0x59FFFFFF)))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(label, style: V2.d(16, FontWeight.w600, Colors.white, lh: 1)),
                    const SizedBox(width: 10),
                    const MIcon('arrowr', size: 19, color: Colors.white),
                  ]),
          );
        }),
      ),
    );
  }
}

/// Label plus the 52 px input of the login card.
class _V2Field extends StatelessWidget {
  const _V2Field({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.trailing,
    this.onSubmit,
    this.keyboard,
    this.action,
    this.autofocus = false,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final String icon;
  final bool obscure, autofocus;
  final Widget? trailing;
  final VoidCallback? onSubmit;
  final TextInputType? keyboard;
  final TextInputAction? action;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: V2.d(13, FontWeight.w600, V2.ink2, lh: 1)),
      const SizedBox(height: 7),
      _Focusable(
        builder: (focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          padding: EdgeInsets.only(left: 14, right: trailing != null ? 8 : 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: focused ? V2.teal500 : const Color(0xFFDCE6E3), width: 1.5),
            boxShadow: focused ? const [BoxShadow(color: Color(0x2E22B8C9), spreadRadius: 4)] : null,
          ),
          child: Row(children: [
            MIcon(icon, size: 19, color: V2.mute),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                obscuringCharacter: '•',
                autofocus: autofocus,
                keyboardType: keyboard,
                textInputAction: action ?? (onSubmit != null ? TextInputAction.done : null),
                onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
                style: V2.b(15, FontWeight.w400, V2.ink, lh: 1.2),
                cursorColor: V2.teal600,
                decoration: InputDecoration.collapsed(hintText: hint, hintStyle: V2.b(15, FontWeight.w400, const Color(0xFF8A9A97), lh: 1.2)),
              ),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    ]);
  }
}

/// Rebuilds its child with whether any descendant has focus (for the focus ring).
class _Focusable extends StatefulWidget {
  const _Focusable({required this.builder});
  final Widget Function(bool focused) builder;
  @override
  State<_Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<_Focusable> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) =>
      Focus(skipTraversal: true, canRequestFocus: false, onFocusChange: (f) => setState(() => _focused = f), child: widget.builder(_focused));
}
