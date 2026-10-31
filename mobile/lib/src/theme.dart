import 'package:flutter/material.dart';

/// TEAL-PRIMARY design system.
/// Teal is primary (buttons, links, active, focus). Red is tertiary,
/// destructive / alerts only, used sparingly.
class IOH {
  // Teal scale (primary)
  static const teal50 = Color(0xFFE6F7F5);
  static const teal100 = Color(0xFFC0EDE8);
  static const teal200 = Color(0xFF8FDFD7);
  static const teal400 = Color(0xFF33BCAD); // hover
  static const teal500 = Color(0xFF15A697); // PRIMARY
  static const teal600 = Color(0xFF0E8579); // pressed
  static const teal700 = Color(0xFF0A6A5F); // deep accents
  static const teal800 = Color(0xFF074D45);

  // Legacy primary token `red` now points to TEAL (used app-wide as primary).
  // Use `danger` for real destructive/error states.
  static const red = Color(0xFF15A697); // legacy primary -> teal
  static const danger =
      Color(0xFFE13838); // tertiary red, errors and destructive only
  static const pink = Color(0xFF0E8579); // secondary accent -> deep teal
  static const yellow = Color(0xFFF5A623); // warnings (amber)
  static const teal = Color(0xFF15A697);
  static const magenta = Color(0xFF0A6A5F); // deep teal accent
  static const green = Color(0xFF2FA84F); // success
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
      case 'revenue':
      case 'site_performance':
      case 'kpi_summary':
      case 'customer_hvc':
        return teal500;
      case 'acquisition':
      case 'network':
        return teal600;
      case 'fwa':
      case 'ftth':
        return teal400;
      case '5g':
      case 'competitive':
      case 'sales_distribution':
        return teal700;
      case 'network_benchmark':
        return yellow;
      default:
        return mute;
    }
  }
}

/// One brand identity: how an operator is named and coloured everywhere.
@immutable
class BrandIdentity {
  /// Canonical lowercase key: ioh, im3, 3id, tsel, xlsmart, industry.
  final String key;

  /// Display label in upper case.
  final String label;

  /// Text and band colour.
  final Color color;

  /// Readable foreground when [color] is used as a background.
  final Color onColor;

  const BrandIdentity(this.key, this.label, this.color, this.onColor);
}

/// Single source of truth for operator colours.
///
/// IOH teal, IM3 orange, 3ID magenta, TSEL red, XLSMART blue. XL and SF are
/// both XLSMART, so they resolve to the same identity.
class Brands {
  static const ioh =
      BrandIdentity('ioh', 'IOH', Color(0xFF15A697), Color(0xFFFFFFFF));
  static const im3 =
      BrandIdentity('im3', 'IM3', Color(0xFFF5A623), Color(0xFF161616));
  static const tri =
      BrandIdentity('3id', '3ID', Color(0xFFEB008B), Color(0xFFFFFFFF));
  static const tsel =
      BrandIdentity('tsel', 'TSEL', Color(0xFFE13838), Color(0xFFFFFFFF));
  static const xlsmart =
      BrandIdentity('xlsmart', 'XLSMART', Color(0xFF1B6FD4), Color(0xFFFFFFFF));
  static const industry = BrandIdentity(
      'industry', 'INDUSTRY', Color(0xFF5A6B68), Color(0xFFFFFFFF));

  /// Operator bands in the order the reports present them.
  static const List<BrandIdentity> all = [ioh, im3, tri, tsel, xlsmart];

  /// Resolves any spelling found in payloads or UI state. Never returns null.
  static BrandIdentity of(String? raw) {
    final key =
        (raw ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    switch (key) {
      case 'ioh':
      case 'indosat':
      case 'indosatooredoohutchison':
        return ioh;
      case 'im3':
      case 'im3ooredoo':
        return im3;
      case '3id':
      case 'tri':
      case '3':
      case 'three':
        return tri;
      case 'tsel':
      case 'telkomsel':
        return tsel;
      case 'xl':
      case 'sf':
      case 'smartfren':
      case 'xlsmart':
      case 'xlaxiata':
        return xlsmart;
      case 'industry':
      case 'total':
        return industry;
      default:
        return BrandIdentity(
            key, (raw ?? '').toUpperCase(), IOH.mute, IOH.white);
    }
  }

  static Color colorOf(String? raw) => of(raw).color;
}

class AppTheme {
  static ThemeData light() {
    final base = ThemeData(
        useMaterial3: true, brightness: Brightness.light, fontFamily: 'Prompt');
    return _compact(base.copyWith(
      scaffoldBackgroundColor: IOH.panel,
      colorScheme: base.colorScheme.copyWith(
          primary: IOH.teal500,
          secondary: IOH.teal700,
          surface: IOH.white,
          error: IOH.danger),
      appBarTheme: const AppBarTheme(
        backgroundColor: IOH.white,
        foregroundColor: IOH.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: IOH.ink),
      ),
      textTheme: base.textTheme.apply(
          bodyColor: IOH.ink, displayColor: IOH.ink, fontFamily: 'Prompt'),
    ));
  }

  static ThemeData dark() {
    final base = ThemeData(
        useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Prompt');
    return _compact(base.copyWith(
      scaffoldBackgroundColor: IOH.darkWhite,
      colorScheme: base.colorScheme.copyWith(
          primary: IOH.teal400,
          secondary: IOH.teal200,
          surface: IOH.darkPanel,
          error: IOH.danger),
      appBarTheme: const AppBarTheme(
        backgroundColor: IOH.darkPanel,
        foregroundColor: IOH.darkInk,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: IOH.darkInk),
      ),
      textTheme: base.textTheme.apply(
          bodyColor: IOH.darkInk,
          displayColor: IOH.darkInk,
          fontFamily: 'Prompt'),
    ));
  }

  static ThemeData _compact(ThemeData base) {
    final colors = base.colorScheme;
    final dark = base.brightness == Brightness.dark;
    final outline = dark ? IOH.darkRule : IOH.rule;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return base.copyWith(
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: base.appBarTheme.copyWith(
        toolbarHeight: 56,
        scrolledUnderElevation: 0,
        titleSpacing: 12,
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(fontSize: 16),
      ),
      cardTheme: CardTheme(
        color: colors.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: shape.copyWith(side: BorderSide(color: outline)),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? IOH.darkWhite : IOH.panel,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colors.primary, width: 1.5)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        minimumSize: const Size(48, 48),
        elevation: 0,
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      )),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: shape,
        side: BorderSide(color: outline),
      )),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: outline),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: colors.surface,
        indicatorColor: colors.primary.withValues(alpha: 0.12),
        indicatorShape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minVerticalPadding: 8,
        shape: shape,
      ),
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 16),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
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
  Color get vZebra =>
      isDark ? const Color(0xFF18211F) : const Color(0xFFFBFBF9);
  Color get vSubtle =>
      isDark ? const Color(0xFF1E2A28) : const Color(0xFFF4FAF9);
  Color get vHeadline =>
      isDark ? const Color(0xFF22302D) : const Color(0xFFEFF4F3);
}
