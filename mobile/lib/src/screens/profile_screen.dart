import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../api/api_client.dart';
import '../app_state.dart';
import '../theme.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _department = TextEditingController();

  final _oldPw = TextEditingController();
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  bool _obscureOld = true, _obscureNew = true, _obscureConfirm = true;

  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPw = false;
  List<dynamic> _notifs = [];

  String _appVersion = '';
  String _latestVersion = '';
  String _releasedAt = '';
  bool _checkingUpdate = false;

  bool get _id => AppState.I.lang == 'id';

  @override
  void initState() {
    super.initState();
    _load();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = '${info.version} (${info.buildNumber})');
    } catch (_) {}
    try {
      final m = await ApiClient.appVersion();
      if (mounted) {
        setState(() {
          _latestVersion = (m['version_name'] ?? '').toString();
          _releasedAt = (m['released_at'] ?? '').toString();
        });
      }
    } catch (_) {}
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final info = await UpdateService.check();
      if (!mounted) return;
      if (info != null) {
        await showUpdateDialog(context, info);
      } else {
        _toast(_id ? 'Aplikasi sudah versi terbaru.' : 'App is up to date.');
      }
    } on UpdateCheckException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (e) {
      if (mounted) _toast(_id ? 'Gagal memeriksa pembaruan.' : 'Failed to check updates.', error: true);
    }
    if (mounted) setState(() => _checkingUpdate = false);
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _department.dispose();
    _oldPw.dispose();
    _newPw.dispose();
    _confirmPw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final me = await ApiClient.getMe();
      _fullName.text = (me['full_name'] ?? '').toString();
      _email.text = (me['email'] ?? '').toString();
      _department.text = (me['department'] ?? '').toString();
    } catch (_) {
      final u = AuthState.user ?? {};
      _fullName.text = (u['full_name'] ?? '').toString();
      _email.text = (u['email'] ?? '').toString();
      _department.text = (u['department'] ?? '').toString();
    }
    try {
      _notifs = await ApiClient.notifications();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? IOH.red : IOH.teal,
    ));
  }

  Future<void> _saveProfile() async {
    setState(() => _savingProfile = true);
    try {
      await ApiClient.updateProfile(
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        department: _department.text.trim(),
      );
      _toast(_id ? 'Profil berhasil disimpan.' : 'Profile saved.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    if (_newPw.text.length < 6) {
      _toast(_id ? 'Password baru minimal 6 karakter.' : 'New password must be at least 6 chars.', error: true);
      return;
    }
    if (_newPw.text != _confirmPw.text) {
      _toast(_id ? 'Konfirmasi password tidak cocok.' : 'Password confirmation does not match.', error: true);
      return;
    }
    setState(() => _savingPw = true);
    try {
      final msg = await ApiClient.changePassword(_oldPw.text, _newPw.text);
      _toast(msg);
      _oldPw.clear();
      _newPw.clear();
      _confirmPw.clear();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _savingPw = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = AuthState.user ?? {};
    final uname = (u['username'] ?? 'user').toString();
    final role = (u['role'] ?? 'end_user').toString();
    return Scaffold(
      backgroundColor: context.vPanel,
      appBar: AppBar(
        title: Text(_id ? 'Profil Saya' : 'My Profile',
            style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: IOH.red))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _headerCard(uname, role),
                const SizedBox(height: 16),
                _aboutCard(),
                const SizedBox(height: 16),
                _preferencesCard(),
                const SizedBox(height: 16),
                _card(
                  title: _id ? 'Informasi Akun' : 'Account Information',
                  icon: Icons.badge_outlined,
                  children: [
                    _field(_id ? 'Nama Lengkap' : 'Full Name', _fullName),
                    _field('Email', _email, keyboard: TextInputType.emailAddress),
                    _field(_id ? 'Departemen' : 'Department', _department),
                    const SizedBox(height: 12),
                    _primaryButton(
                      label: _id ? 'Simpan Perubahan' : 'Save Changes',
                      busy: _savingProfile,
                      onTap: _saveProfile,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _card(
                  title: _id ? 'Ubah Password' : 'Change Password',
                  icon: Icons.lock_outline,
                  children: [
                    _pwField(_id ? 'Password Lama' : 'Old Password', _oldPw, _obscureOld,
                        () => setState(() => _obscureOld = !_obscureOld)),
                    _pwField(_id ? 'Password Baru' : 'New Password', _newPw, _obscureNew,
                        () => setState(() => _obscureNew = !_obscureNew)),
                    _pwField(_id ? 'Konfirmasi Password Baru' : 'Confirm New Password', _confirmPw, _obscureConfirm,
                        () => setState(() => _obscureConfirm = !_obscureConfirm)),
                    const SizedBox(height: 12),
                    _primaryButton(
                      label: _id ? 'Ubah Password' : 'Change Password',
                      busy: _savingPw,
                      onTap: _savePassword,
                    ),
                  ],
                ),
                if (_notifs.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _notifCard(),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _aboutCard() {
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.vMute))),
            Text(value.isEmpty ? '—' : value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.vInk)),
          ]),
        );
    return _card(
      title: _id ? 'Tentang Aplikasi' : 'About App',
      icon: Icons.info_outline,
      children: [
        row(_id ? 'Versi Terpasang' : 'Installed Version', _appVersion),
        row(_id ? 'Versi Terbaru' : 'Latest Version', _latestVersion),
        row(_id ? 'Tanggal Rilis' : 'Release Date', _releasedAt),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _checkingUpdate ? null : _checkForUpdate,
            style: OutlinedButton.styleFrom(
              foregroundColor: IOH.red,
              side: const BorderSide(color: IOH.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _checkingUpdate
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: IOH.red))
                : const Icon(Icons.system_update_alt, size: 18),
            label: Text(_checkingUpdate
                ? (_id ? 'Memeriksa…' : 'Checking…')
                : (_id ? 'Cek Pembaruan' : 'Check for Update')),
          ),
        ),
      ],
    );
  }

  Widget _preferencesCard() {
    return AnimatedBuilder(
      animation: AppState.I,
      builder: (context, _) {
        final dark = AppState.I.themeMode == ThemeMode.dark;
        return _card(
          title: _id ? 'Preferensi' : 'Preferences',
          icon: Icons.tune,
          children: [
            // Dark mode toggle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Icon(dark ? Icons.dark_mode : Icons.light_mode_outlined, size: 19, color: IOH.red),
                const SizedBox(width: 10),
                Expanded(child: Text(_id ? 'Mode Gelap' : 'Dark Mode', style: TextStyle(fontSize: 13, color: context.vInk))),
                Switch(
                  value: dark,
                  activeColor: IOH.red,
                  onChanged: (_) => AppState.I.toggleTheme(),
                ),
              ]),
            ),
            Divider(height: 14, color: context.vRule),
            // Language segmented
            Row(children: [
              Icon(Icons.language, size: 19, color: IOH.red),
              const SizedBox(width: 10),
              Expanded(child: Text(_id ? 'Bahasa' : 'Language', style: TextStyle(fontSize: 13, color: context.vInk))),
              _langChip('id', 'ID'),
              const SizedBox(width: 6),
              _langChip('en', 'EN'),
            ]),
          ],
        );
      },
    );
  }

  Widget _langChip(String code, String label) {
    final active = AppState.I.lang == code;
    return GestureDetector(
      onTap: () => AppState.I.setLang(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? IOH.red : context.vWhite,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? IOH.red : context.vRule),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? Colors.white : context.vMute)),
      ),
    );
  }

  Widget _headerCard(String uname, String role) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [IOH.red, IOH.magenta]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.white,
          child: Text(uname.substring(0, 1).toUpperCase(),
              style: const TextStyle(color: IOH.red, fontWeight: FontWeight.w800, fontSize: 24, fontFamily: 'Poppins')),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_fullName.text.isEmpty ? uname : _fullName.text,
                style: const TextStyle(color: Colors.white, fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 2),
            Text('@$uname', style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(999)),
              child: Text(role.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _card({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.vWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.vRule),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: IOH.red),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 15, color: context.vInk)),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, {TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        style: TextStyle(color: context.vInk),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: context.vMute),
          filled: true,
          fillColor: context.vPanel,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.vRule)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.vRule)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: IOH.red)),
        ),
      ),
    );
  }

  Widget _pwField(String label, TextEditingController c, bool obscure, VoidCallback toggle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        style: TextStyle(color: context.vInk),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: context.vMute),
          filled: true,
          fillColor: context.vPanel,
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: context.vMute, size: 20),
            onPressed: toggle,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.vRule)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: context.vRule)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: IOH.red)),
        ),
      ),
    );
  }

  Widget _primaryButton({required String label, required bool busy, required VoidCallback onTap}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: IOH.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _notifCard() {
    return _card(
      title: _id ? 'Notifikasi' : 'Notifications',
      icon: Icons.notifications_outlined,
      children: [
        for (final n in _notifs.take(10))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.vPanel,
              borderRadius: BorderRadius.circular(10),
              border: Border(left: BorderSide(color: IOH.red, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((n['title'] ?? '').toString(),
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 13, color: context.vInk)),
              if ((n['message'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text((n['message']).toString(), style: TextStyle(fontSize: 12, color: context.vMute)),
              ],
            ]),
          ),
        TextButton(
          onPressed: () async {
            await ApiClient.markAllNotificationsRead();
            setState(() => _notifs = []);
          },
          child: Text(_id ? 'Tandai semua dibaca' : 'Mark all as read', style: const TextStyle(color: IOH.red)),
        ),
      ],
    );
  }
}
