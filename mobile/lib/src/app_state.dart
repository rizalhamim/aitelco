import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global app settings: theme mode + response language. Persisted.
class AppState extends ChangeNotifier {
  static final AppState I = AppState._();
  AppState._();

  ThemeMode themeMode = ThemeMode.light;
  String lang = 'id';
  bool animations = true;

  /// 'light' | 'dark' | 'system', the names the Profil page and the server use.
  String get themeName => switch (themeMode) { ThemeMode.dark => 'dark', ThemeMode.system => 'system', _ => 'light' };

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final tm = p.getString('theme_mode');
    themeMode = tm == 'dark' ? ThemeMode.dark : tm == 'system' ? ThemeMode.system : ThemeMode.light;
    lang = p.getString('lang') ?? 'id';
    animations = p.getBool('animations') ?? true;
  }

  Future<void> setTheme(String name) async {
    themeMode = name == 'dark' ? ThemeMode.dark : name == 'system' ? ThemeMode.system : ThemeMode.light;
    final p = await SharedPreferences.getInstance();
    await p.setString('theme_mode', themeName);
    notifyListeners();
  }

  Future<void> setAnimations(bool on) async {
    animations = on;
    final p = await SharedPreferences.getInstance();
    await p.setBool('animations', on);
    notifyListeners();
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
