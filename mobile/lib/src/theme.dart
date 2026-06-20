import 'package:flutter/material.dart';

/// TEAL-PRIMARY design system.
/// Teal is primary (buttons, links, active, focus). Red is tertiary —
/// destructive / alerts only, used sparingly.
class IOH {
  // Teal scale (primary)
  static const teal50  = Color(0xFFE6F7F5);
  static const teal100 = Color(0xFFC0EDE8);
  static const teal200 = Color(0xFF8FDFD7);
  static const teal400 = Color(0xFF33BCAD); // hover
  static const teal500 = Color(0xFF15A697); // PRIMARY
  static const teal600 = Color(0xFF0E8579); // pressed
  static const teal700 = Color(0xFF0A6A5F); // deep accents
  static const teal800 = Color(0xFF074D45);

  // Legacy primary token `red` now points to TEAL (used app-wide as primary).
  // Use `danger` for real destructive/error states.
  static const red = Color(0xFF15A697);     // legacy primary -> teal
  static const danger = Color(0xFFE13838);  // tertiary red — errors/destructive only
  static const pink = Color(0xFF0E8579);    // secondary accent -> deep teal
  static const yellow = Color(0xFFF5A623);  // warnings (amber)
  static const teal = Color(0xFF15A697);
  static const magenta = Color(0xFF0A6A5F); // deep teal accent
  static const green = Color(0xFF2FA84F);   // success
  static const ink = Color(0xFF0F1F1D);
  static const grey = Color(0xFF5A6B68);
  static const mute = Color(0xFF5A6B68);
  static const rule = Color(0xFFE1E9E7);
  static const panel = Color(0xFFF5F9F8);
  static const white = Color(0xFFFFFFFF);

  static const darkInk = Color(0xFFF5F9F8);
  static const darkGrey = Color(0xFFC9CFCD);
  static const darkMute = Color(0xFF8A9996);
  static const darkRule = Color(0xFF2A3A37);
  static const darkPanel = Color(0xFF13201E);
  static const darkWhite = Color(0xFF0B1413);

  static Color domainColor(String? d) {
    switch (d) {
      case 'revenue': case 'site_performance': case 'kpi_summary': case 'customer_hvc': return teal500;
      case 'acquisition': case 'network': return teal600;
      case 'fwa': case 'ftth': return teal400;
      case '5g': case 'competitive': case 'sales_distribution': return teal700;
      case 'network_benchmark': return yellow;
      default: return mute;
    }
  }
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.light, fontFamily: 'Prompt');
    return base.copyWith(
      scaffoldBackgroundColor: IOH.panel,
      colorScheme: base.colorScheme.copyWith(primary: IOH.teal500, secondary: IOH.teal700, surface: IOH.white, error: IOH.danger),
      appBarTheme: const AppBarTheme(
        backgroundColor: IOH.white, foregroundColor: IOH.ink, elevation: 0,
        scrolledUnderElevation: 1, titleTextStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 18, color: IOH.ink),
      ),
      textTheme: base.textTheme.apply(bodyColor: IOH.ink, displayColor: IOH.ink, fontFamily: 'Prompt'),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Prompt');
    return base.copyWith(
      scaffoldBackgroundColor: IOH.darkWhite,
      colorScheme: base.colorScheme.copyWith(primary: IOH.teal400, secondary: IOH.teal200, surface: IOH.darkPanel, error: IOH.danger),
      appBarTheme: const AppBarTheme(
        backgroundColor: IOH.darkPanel, foregroundColor: IOH.darkInk, elevation: 0,
        scrolledUnderElevation: 1, titleTextStyle: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w800, fontSize: 18, color: IOH.darkInk),
      ),
      textTheme: base.textTheme.apply(bodyColor: IOH.darkInk, displayColor: IOH.darkInk, fontFamily: 'Prompt'),
    );
  }
}

extension ThemeExt on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get vInk => isDark ? IOH.darkInk : IOH.ink;
  Color get vGrey => isDark ? IOH.darkGrey : IOH.grey;
  Color get vMute => isDark ? IOH.darkMute : IOH.mute;
  Color get vRule => isDark ? IOH.darkRule : IOH.rule;
  Color get vPanel => isDark ? IOH.darkPanel : IOH.panel;
  Color get vWhite => isDark ? IOH.darkWhite : IOH.white;
  // Zebra / subtle highlight surfaces (theme-aware so text stays readable).
  Color get vZebra => isDark ? const Color(0xFF18211F) : const Color(0xFFFBFBF9);
  Color get vSubtle => isDark ? const Color(0xFF1E2A28) : const Color(0xFFF4FAF9);
  Color get vHeadline => isDark ? const Color(0xFF22302D) : const Color(0xFFEFF4F3);
}
