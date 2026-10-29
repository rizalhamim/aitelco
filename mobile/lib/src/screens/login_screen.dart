import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../ui/ds.dart';
import '../ui/icons.dart';
import '../ui/kit.dart';

/// Android · Login: temple still under a teal overlay, "Winning Every
/// Second", and a white sheet with username and password. After "Masuk" the
/// sheet asks for the 4-digit code the backend e-mails (same flow as before).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _p = Pal.light; // the sheet is white in both themes

  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  String? _info;
  bool _codeSent = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
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
      await ApiClient.verifyLoginToken(_user.text.trim(), _code.text.trim(), rememberMe: true);
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
      backgroundColor: _p.surface,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SheetHandle(),
          const SizedBox(height: 20),
          Text('Lupa password', style: ts(18, w700, _p.ink, lh: 1.35)),
          const SizedBox(height: 6),
          Text('Masukkan email akun Anda. Tautan reset password akan dikirim ke email tersebut.',
              style: ts(13, w400, _p.text2, lh: 1.5)),
          const SizedBox(height: 16),
          _Field(controller: ctrl, hint: 'nama@ioh.co.id', icon: Icx.mail, keyboard: TextInputType.emailAddress, autofocus: true),
          const SizedBox(height: 16),
          PrimaryButton('Kirim tautan', onTap: () => Navigator.pop(ctx, ctrl.text.trim())),
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

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFF04332E),
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(builder: (context, c) {
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: IntrinsicHeight(
              child: Stack(children: [
                Positioned.fill(child: Image.asset('assets/img/still_temple.jpg', fit: BoxFit.cover)),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment(0, .5), // the overlay ends at 75 % of the frame
                        colors: [Color(0x6604332E), Color(0xCC04332E), Color(0xFF04332E)],
                        stops: [0, .5, 1],
                      ),
                    ),
                  ),
                ),
                Column(children: [
                  SizedBox(height: top),
                  _brand(),
                  const Spacer(),
                  _sheet(bottom),
                ]),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _brand() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 56, 28, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AppLogo(size: 64, radius: 17.92, border: Colors.white, borderWidth: 2, shadow: true),
        const SizedBox(height: 16),
        Text('Bizplan Java Agent', style: ts(16, w600, const Color(0xFFC0EDE8))),
        const SizedBox(height: 15.6),
        Text('Winning\nEvery Second', style: ts(48, w800, Colors.white, lh: 1.02, ls: -.01)),
        const SizedBox(height: 16),
        Container(width: 64, height: 4, decoration: BoxDecoration(color: const Color(0xFFF5A623), borderRadius: BorderRadius.circular(2))),
      ]),
    );
  }

  Widget _sheet(double bottomInset) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: _p.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.fromLTRB(24, 26, 24, 22 + bottomInset),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _codeSent ? _codeStep() : _passwordStep()),
      ),
    );
  }

  List<Widget> _passwordStep() => [
        _label('Username'),
        const SizedBox(height: 6),
        _Field(controller: _user, hint: 'nama.pengguna', icon: Icx.users, action: TextInputAction.next),
        const SizedBox(height: 14),
        _label('Password'),
        const SizedBox(height: 6),
        _Field(
          controller: _pass,
          hint: '••••••••••',
          icon: Icx.lock,
          obscure: _obscure,
          trailing: IconButton(
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Ic(_obscure ? Icx.eye : Icx.eyeOff, size: 18, color: _p.text2),
            tooltip: _obscure ? 'Tampilkan password' : 'Sembunyikan password',
          ),
          onSubmit: _requestToken,
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: _forgot,
            child: Text('Lupa password?', style: ts(13, w600, _p.teal700)),
          ),
        ),
        if (_error != null) _errorBox(),
        const SizedBox(height: 14),
        PrimaryButton('Masuk', onTap: _requestToken, loading: _loading),
      ];

  List<Widget> _codeStep() => [
        Text('Cek email Anda', style: ts(18, w700, _p.ink, lh: 1.35)),
        const SizedBox(height: 4),
        Text(_info ?? 'Kode 4 digit sudah dikirim.', style: ts(13, w400, _p.text2, lh: 1.5)),
        const SizedBox(height: 16),
        _label('Kode masuk'),
        const SizedBox(height: 6),
        _Field(controller: _code, hint: '0000', icon: Icx.shield, keyboard: TextInputType.number, autofocus: true, onSubmit: _verifyToken),
        const SizedBox(height: 14),
        Row(children: [
          GestureDetector(
            onTap: _loading ? null : () => setState(() { _codeSent = false; _error = null; _code.clear(); }),
            child: Text('Ganti akun', style: ts(13, w600, _p.text2)),
          ),
          const Spacer(),
          _cooldown > 0
              ? Text('Kirim ulang dalam $_cooldown dtk', style: ts(13, w400, _p.mute))
              : GestureDetector(onTap: _requestToken, child: Text('Kirim ulang kode', style: ts(13, w600, _p.teal700))),
        ]),
        if (_error != null) _errorBox(),
        const SizedBox(height: 14),
        PrimaryButton('Verifikasi & masuk', onTap: _verifyToken, loading: _loading),
      ];

  Widget _label(String t) => Text(t, style: ts(13, w600, _p.text2));

  Widget _errorBox() => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _p.dangerTint, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Ic(Icx.alertCircle, size: 18, color: _p.danger),
          const SizedBox(width: 10),
          Expanded(child: Text(_error!, style: ts(13, w500, _p.danger, lh: 1.4))),
        ]),
      );
}

/// 52 px input with a leading icon, as in the Login sheet.
class _Field extends StatelessWidget {
  const _Field({
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
  final TextEditingController controller;
  final String hint;
  final I3 icon;
  final bool obscure, autofocus;
  final Widget? trailing;
  final VoidCallback? onSubmit;
  final TextInputType? keyboard;
  final TextInputAction? action;

  @override
  Widget build(BuildContext context) {
    const p = Pal.light;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: p.rule));
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        keyboardType: keyboard,
        textInputAction: action ?? (onSubmit != null ? TextInputAction.done : null),
        onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
        style: ts(14, w400, p.ink, lh: 1.5),
        cursorColor: p.teal600,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: p.surface,
          hintText: hint,
          hintStyle: ts(14, w400, p.mute, lh: 1.5),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 15, right: 10),
            child: Ic(icon, size: 18, color: p.text2),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 43, minHeight: 18),
          suffixIcon: trailing,
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: p.teal600, width: 1.5)),
        ),
      ),
    );
  }
}
