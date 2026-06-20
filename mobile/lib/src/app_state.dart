import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app settings: theme mode + response language. Persisted.
class AppState extends ChangeNotifier {
  static final AppState I = AppState._();
  AppState._();

  ThemeMode themeMode = ThemeMode.light;
  String lang = 'id';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final tm = p.getString('theme_mode');
    themeMode = tm == 'dark' ? ThemeMode.dark : ThemeMode.light;
    lang = p.getString('lang') ?? 'id';
  }

  Future<void> toggleTheme() async {
    themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final p = await SharedPreferences.getInstance();
    await p.setString('theme_mode', themeMode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setLang(String l) async {
    lang = l;
    final p = await SharedPreferences.getInstance();
    await p.setString('lang', l);
    notifyListeners();
  }
}
