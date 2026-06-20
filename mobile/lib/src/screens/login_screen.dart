import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../config.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _code = TextEditingController();
  
  bool _loading = false;
  bool _remember = false;
  bool _obscure = true;
  String? _error;
  bool _codeSent = false;
  bool _canResend = false;
  int _cooldown = 0;

  void _startCooldown() {
    setState(() {
      _canResend = false;
      _cooldown = 60;
    });
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_cooldown > 0) {
        setState(() => _cooldown--);
        _tick();
      } else {
        setState(() => _canResend = true);
      }
    });
  }

  Future<void> _requestToken() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Isi username & password.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      // Need to add this endpoint to ApiClient
      final res = await ApiClient.requestLoginToken(_user.text.trim(), _pass.text);
      if (mounted) {
        setState(() {
          _codeSent = true;
          _error = null;
        });
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['message'] ?? 'Kode terkirim.'),
          backgroundColor: IOH.teal,
        ));
      }
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyToken() async {
    if (_code.text.trim().isEmpty) {
      setState(() => _error = 'Masukkan kode 4 digit.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.verifyLoginToken(_user.text.trim(), _code.text.trim(), rememberMe: _remember);
      if (mounted) Navigator.of(context).pushReplacementNamed('/chat');
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final ctrl = TextEditingController(text: _user.text.contains('@') ? _user.text : '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: IOH.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Lupa Password', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 18, color: IOH.ink)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Masukkan email akun Anda. Link reset password akan dikirim ke email tersebut.',
              style: TextStyle(fontSize: 13, color: IOH.grey)),
          const SizedBox(height: 14),
          TextField(controller: ctrl, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline), border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal', style: TextStyle(color: IOH.mute))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: IOH.red, foregroundColor: Colors.white),
            onPressed: () async {
              final email = ctrl.text.trim();
              if (email.isEmpty || !email.contains('@')) return;
              Navigator.pop(ctx);
              try {
                final msg = await ApiClient.forgotPassword(email);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: IOH.teal, behavior: SnackBarBehavior.floating));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: IOH.danger, behavior: SnackBarBehavior.floating));
              }
            },
            child: const Text('Kirim Link'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IOH.ink,
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 18),
                    Center(child: Image.asset('assets/logo_color.png', width: 150)),
                    const SizedBox(height: 26),
                    const Text('Bizplan Java Agent',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 6),
                    const Text(AppConfig.appSub,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Poppins', color: IOH.teal, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: IOH.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Selamat datang kembali',
                              style: TextStyle(fontFamily: 'Poppins', fontSize: 20, fontWeight: FontWeight.w800, color: IOH.ink)),
                          const SizedBox(height: 4),
                          const Text('Masuk untuk lanjut ke AI analyst',
                              style: TextStyle(fontSize: 13, color: IOH.mute)),
                          const SizedBox(height: 22),
                          
                          if (!_codeSent) ...[
                            _field(_user, 'Username', Icons.person_outline),
                            const SizedBox(height: 14),
                            _field(_pass, 'Password', Icons.lock_outline, obscure: _obscure, suffix: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: IOH.mute, size: 20),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ), onSubmit: _requestToken),
                          ] else ...[
                            _field(_code, 'Kode 4-Digit (Cek Email)', Icons.pin_outlined, onSubmit: _verifyToken, keyboardType: TextInputType.number),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (!_canResend) 
                                  Text('Kirim ulang dalam $_cooldown s', style: const TextStyle(fontSize: 12, color: IOH.mute))
                                else
                                  TextButton(
                                    onPressed: _requestToken,
                                    child: const Text('Kirim ulang kode', style: TextStyle(fontSize: 12, color: IOH.teal, fontWeight: FontWeight.bold)),
                                  ),
                              ]
                            )
                          ],

                          const SizedBox(height: 6),
                          if (!_codeSent) Row(children: [
                            Checkbox(value: _remember, activeColor: IOH.red,
                                onChanged: (v) => setState(() => _remember = v ?? false),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                            const Text('Ingat saya (24 jam)', style: TextStyle(fontSize: 13, color: IOH.grey)),
                            const Spacer(),
                            TextButton(onPressed: _forgot,
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                child: const Text('Lupa password?', style: TextStyle(fontSize: 13, color: IOH.red, fontWeight: FontWeight.w600))),
                          ]),
                          
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(color: const Color(0xFFFDECEC), borderRadius: BorderRadius.circular(8),
                                  border: Border(left: BorderSide(color: IOH.danger, width: 4))),
                              child: Row(children: [
                                const Icon(Icons.error_outline, color: IOH.danger, size: 16), const SizedBox(width: 8),
                                Expanded(child: Text(_error!, style: const TextStyle(color: IOH.danger, fontSize: 13))),
                              ]),
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _loading ? null : (_codeSent ? _verifyToken : _requestToken),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: IOH.red, foregroundColor: Colors.white, elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: _loading
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4))
                                  : Text(_codeSent ? 'Verifikasi & Masuk' : 'Minta Kode Login', style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 16)),
                            ),
                          ),
                          if (_codeSent && !_loading) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () => setState(() {
                                _codeSent = false;
                                _error = null;
                              }),
                              child: const Text('Ganti Akun / Kembali', style: TextStyle(color: IOH.mute)),
                            )
                          ]
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Confidential · Internal Use Only',
                        textAlign: TextAlign.center, style: TextStyle(color: IOH.mute, fontSize: 10, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon, {bool obscure = false, Widget? suffix, VoidCallback? onSubmit, TextInputType? keyboardType}) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboardType,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true, fillColor: IOH.panel,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: IOH.red, width: 1.5)),
      ),
    );
  }
}
