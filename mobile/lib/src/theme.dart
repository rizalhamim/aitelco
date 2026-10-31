import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'design_tokens.dart';

export 'design_tokens.dart';

/// TEAL-PRIMARY design system.
/// Teal is primary (buttons, links, active, focus). Red is tertiary,
/// destructive / alerts only, used sparingly.
class IOH {
  // Values come from design_tokens.dart (generated from design/tokens.json).
  // Teal scale (primary)
  static const teal50  = DSColor.teal50;
  static const teal100 = DSColor.teal100;
  static const teal200 = DSColor.teal200;
  static const teal400 = DSColor.teal400; // hover
  static const teal500 = DSColor.teal500; // PRIMARY
  static const teal600 = DSColor.teal600; // pressed
  static const teal700 = DSColor.teal700; // deep accents
  static const teal800 = DSColor.teal800;

  // Legacy primary token `red` now points to TEAL (used app-wide as primary).
  // Use `danger` for real destructive/error states.
  static const red = DSColor.teal600;       // legacy primary -> teal (button teal per Redesign v1)
  static const danger = DSColor.red500;     // tertiary red, errors and destructive only
  static const pink = DSColor.teal600;      // secondary accent -> deep teal
  static const yellow = DSColor.amber500;   // warnings (amber)
  static const teal = DSColor.teal500;
  static const magenta = DSColor.teal700;   // deep teal accent
  static const green = DSColor.green500;    // success
  static const ink = DSLight.ink;
  static const grey = DSLight.mute;
  static const mute = DSLight.mute;
  static const rule = DSLight.rule;
  static const panel = DSLight.bg;
  static const white = DSLight.surface;

  static const darkInk = DSDark.ink;
  static const darkGrey = DSDark.textSecondary;
  static const darkMute = DSDark.textMute;
  static const darkRule = DSDark.rule;
  static const darkPanel = DSDark.surface;
  static const darkWhite = DSDark.bg;

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
  static ThemeData light() => _build(
        brightness: Brightness.light,
        primary: DSLight.teal600,
        secondary: DSLight.teal700,
        ink: IOH.ink,
        mute: IOH.mute,
        rule: IOH.rule,
        background: IOH.panel,
        surface: IOH.white,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        primary: DSDark.teal600,
        secondary: DSDark.teal700,
        ink: IOH.darkInk,
        mute: IOH.darkMute,
        rule: IOH.darkRule,
        background: IOH.darkWhite,
        surface: IOH.darkPanel,
      );

  /// One builder for both modes so every component gets the same shape,
  /// spacing and motion; only the colors differ.
  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color secondary,
    required Color ink,
    required Color mute,
    required Color rule,
    required Color background,
    required Color surface,
  }) {
    final base = ThemeData(useMaterial3: true, brightness: brightness, fontFamily: DSFont.body);
    final onPrimary = brightness == Brightness.dark ? DSDark.onPrimary : DSLight.onPrimary;
    final shapeMd = RoundedRectangleBorder(borderRadius: BorderRadius.circular(DSRadius.md));
    const buttonPadding = EdgeInsets.symmetric(horizontal: DSSpace.s5, vertical: DSSpace.s3);
    const buttonText = TextStyle(fontFamily: DSFont.display, fontWeight: FontWeight.w600, fontSize: 14);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(
        primary: primary, onPrimary: onPrimary, secondary: secondary,
        surface: surface, error: IOH.danger, outlineVariant: rule,
      ),
      dividerColor: rule,
      appBarTheme: AppBarTheme(
        backgroundColor: surface, foregroundColor: ink, elevation: 0,
        scrolledUnderElevation: 1, surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontFamily: DSFont.display, fontWeight: FontWeight.w800, fontSize: 18, color: ink),
      ),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink, fontFamily: DSFont.body),
      // Fluid, consistent screen transitions on Android (shared-axis-like zoom).
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
      splashFactory: InkSparkle.splashFactory,
      cardTheme: CardThemeData(
        color: surface, elevation: 0, margin: EdgeInsets.zero, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DSRadius.lg),
          side: BorderSide(color: rule),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary, foregroundColor: onPrimary, elevation: 0,
          padding: buttonPadding, shape: shapeMd, textStyle: buttonText,
          animationDuration: DSMotion.base,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary, foregroundColor: onPrimary,
          padding: buttonPadding, shape: shapeMd, textStyle: buttonText,
          animationDuration: DSMotion.base,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary, side: BorderSide(color: rule),
          padding: buttonPadding, shape: shapeMd, textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary, shape: shapeMd, textStyle: buttonText),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: DSSpace.s4, vertical: DSSpace.s3),
        hintStyle: TextStyle(color: mute),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(DSRadius.md), borderSide: BorderSide(color: rule)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(DSRadius.md), borderSide: BorderSide(color: rule)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(DSRadius.md), borderSide: BorderSide(color: primary, width: 1.5)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(), side: BorderSide(color: rule),
        labelStyle: TextStyle(fontFamily: DSFont.body, fontSize: DSType.labelSize, color: ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shapeMd,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface, surfaceTintColor: Colors.transparent, showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(DSRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface, surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DSRadius.lg)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface, surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.14),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
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
