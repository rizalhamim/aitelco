// Redesign v1 design system: colors, type and the hero background, taken
// from design/mockup/spec (FigCraft export). Every new screen reads its
// colors through `Pal.of(context)` so light and dark follow the mockups.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Semantic palette for one mode (values from design/mockup/spec/tokens.json).
class Pal {
  const Pal._({
    required this.dark,
    required this.teal50, required this.teal100, required this.teal200, required this.teal300,
    required this.teal400, required this.teal500, required this.teal600, required this.teal700,
    required this.teal800, required this.teal900,
    required this.ink, required this.text2, required this.mute, required this.rule,
    required this.bg, required this.surface, required this.surfaceMuted,
    required this.danger, required this.dangerTint, required this.dangerSolid,
    required this.warning, required this.warningTint, required this.warningText,
    required this.success, required this.successTint, required this.successSolid,
    required this.chartGrey, required this.chartAmber,
    required this.blue50, required this.blue600, required this.violet50, required this.violet600,
    required this.amber50, required this.amber700, required this.rose50, required this.rose600,
    required this.green50, required this.green600,
  });

  final bool dark;
  final Color teal50, teal100, teal200, teal300, teal400, teal500, teal600, teal700, teal800, teal900;
  final Color ink, text2, mute, rule, bg, surface, surfaceMuted;
  final Color danger, dangerTint, dangerSolid, warning, warningTint, warningText;
  final Color success, successTint, successSolid, chartGrey, chartAmber;
  final Color blue50, blue600, violet50, violet600, amber50, amber700, rose50, rose600, green50, green600;

  Color get primary => teal600;
  Color get onPrimary => Colors.white;

  /// Soft card shadow: 0 4 14 rgba(15,31,29,.06).
  List<BoxShadow> get shadow => dark
      ? const []
      : const [BoxShadow(color: Color(0x0F0F1F1D), offset: Offset(0, 4), blurRadius: 14)];

  static const light = Pal._(
    dark: false,
    teal50: DSLight.teal50, teal100: DSLight.teal100, teal200: DSLight.teal200, teal300: DSLight.teal300,
    teal400: DSLight.teal400, teal500: DSLight.teal500, teal600: DSLight.teal600, teal700: DSLight.teal700,
    teal800: DSLight.teal800, teal900: DSLight.teal900,
    ink: DSLight.ink, text2: DSLight.textSecondary, mute: DSLight.textMute, rule: DSLight.rule,
    bg: DSLight.bg, surface: DSLight.surface, surfaceMuted: DSLight.surfaceMuted,
    danger: DSLight.danger, dangerTint: DSLight.dangerTint, dangerSolid: DSLight.dangerSolid,
    warning: DSLight.warning, warningTint: DSLight.warningTint, warningText: DSLight.warningText,
    success: DSLight.success, successTint: DSLight.successTint, successSolid: DSLight.successSolid,
    chartGrey: DSLight.chartGrey, chartAmber: DSLight.chartAmber,
    blue50: DSLight.blue50, blue600: DSLight.blue600, violet50: DSLight.violet50, violet600: DSLight.violet600,
    amber50: DSLight.amber50, amber700: DSLight.amber700, rose50: DSLight.rose50, rose600: DSLight.rose600,
    green50: DSLight.green50, green600: DSLight.green600,
  );

  static const darkPal = Pal._(
    dark: true,
    teal50: DSDark.teal50, teal100: DSDark.teal100, teal200: DSDark.teal200, teal300: DSDark.teal300,
    teal400: DSDark.teal400, teal500: DSDark.teal500, teal600: DSDark.teal600, teal700: DSDark.teal700,
    teal800: DSDark.teal800, teal900: DSDark.teal900,
    ink: DSDark.ink, text2: DSDark.textSecondary, mute: DSDark.textMute, rule: DSDark.rule,
    bg: DSDark.bg, surface: DSDark.surface, surfaceMuted: DSDark.surfaceMuted,
    danger: DSDark.danger, dangerTint: DSDark.dangerTint, dangerSolid: DSDark.dangerSolid,
    warning: DSDark.warning, warningTint: DSDark.warningTint, warningText: DSDark.warningText,
    success: DSDark.success, successTint: DSDark.successTint, successSolid: DSDark.successSolid,
    chartGrey: DSDark.chartGrey, chartAmber: DSDark.chartAmber,
    blue50: DSDark.blue50, blue600: DSDark.blue600, violet50: DSDark.violet50, violet600: DSDark.violet600,
    amber50: DSDark.amber50, amber700: DSDark.amber700, rose50: DSDark.rose50, rose600: DSDark.rose600,
    green50: DSDark.green50, green600: DSDark.green600,
  );

  static Pal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? darkPal : light;
}

/// Text style in the mockup's terms: Poppins, size, weight, line height (as a
/// multiple) and letter spacing (as a fraction of the size, Figma's "%").
TextStyle ts(double size, FontWeight weight, Color color, {double lh = 1.4, double ls = 0, bool tabular = false}) =>
    TextStyle(
      fontFamily: 'Poppins',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: lh,
      letterSpacing: ls * size,
      leadingDistribution: TextLeadingDistribution.even,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

const w400 = FontWeight.w400;
const w500 = FontWeight.w500;
const w600 = FontWeight.w600;
const w700 = FontWeight.w700;
const w800 = FontWeight.w800;

/// One gradient layer of a Figma fill, in the box's normalized coordinates.
class _Layer {
  const _Layer.linear(this.from, this.to, this.colors, this.stops) : radial = false, width = null;
  const _Layer.radial(this.from, this.to, this.colors, this.stops, {this.width}) : radial = true;
  final bool radial;
  final Offset from, to;

  /// Figma's third gradient handle; a radial becomes an ellipse whose second
  /// axis runs from [from] to this point.
  final Offset? width;
  final List<Color> colors;
  final List<double> stops;
}

/// The teal hero fill used by Splash, the KPI carousel, the agent orb and the
/// Unduh APK hero: a teal-900 → teal-700 diagonal, a teal glow top-right and
/// a faint amber glow bottom-left.
const _heroLayers = [
  _Layer.linear(Offset(0, 1), Offset(1, 0), [Color(0xFF04332E), Color(0xFF074D45), Color(0xFF0A6A5F)], [0, .5, 1]),
  _Layer.radial(Offset(.85, .1), Offset(.85, .9), [Color(0x6633BCAD), Color(0x0033BCAD)], [0, 1], width: Offset(1, .5)),
  _Layer.radial(Offset(.05, 1), Offset(.05, .3), [Color(0x33F5A623), Color(0x00F5A623)], [0, 1], width: Offset(1, .5)),
];

class _LayersPainter extends CustomPainter {
  const _LayersPainter(this.layers);
  final List<_Layer> layers;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Figma gradients live in the box's unit square, so they stretch with it.
    canvas.scale(size.width, size.height);
    const unit = Rect.fromLTWH(0, 0, 1, 1);
    canvas.clipRect(unit);
    for (final l in layers) {
      if (l.radial && l.width != null) {
        // Map the unit circle onto the ellipse spanned by the two handles.
        final u = l.to - l.from, v = l.width! - l.from;
        canvas.save();
        canvas.transform(Float64List.fromList([u.dx, u.dy, 0, 0, v.dx, v.dy, 0, 0, 0, 0, 1, 0, l.from.dx, l.from.dy, 0, 1]));
        canvas.drawRect(const Rect.fromLTRB(-50, -50, 50, 50),
            Paint()..shader = ui.Gradient.radial(Offset.zero, 1, l.colors, l.stops));
        canvas.restore();
        continue;
      }
      final shader = l.radial
          ? ui.Gradient.radial(l.from, (l.to - l.from).distance, l.colors, l.stops)
          : ui.Gradient.linear(l.from, l.to, l.colors, l.stops);
      canvas.drawRect(unit, Paint()..shader = shader);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LayersPainter old) => old.layers != layers;
}

/// Teal hero background, optionally with a still photo and the kawung motif.
class HeroFill extends StatelessWidget {
  const HeroFill({super.key, this.still, this.stillOpacity = .3, this.kawung = .12, this.child});
  final String? still;
  final double stillOpacity;
  final double kawung;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const CustomPaint(painter: _LayersPainter(_heroLayers)),
      if (still != null)
        Opacity(opacity: stillOpacity, child: Image.asset(still!, fit: BoxFit.cover)),
      if (kawung > 0) KawungMotif(opacity: kawung),
      if (child != null) child!,
    ]);
  }
}

/// The batik kawung motif, tiled at its native 480 × 480 from the top-left.
class KawungMotif extends StatelessWidget {
  const KawungMotif({super.key, this.opacity = .14});
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/img/kawung.webp'),
              repeat: ImageRepeat.repeat,
              alignment: Alignment.topLeft,
              scale: 2,
            ),
          ),
        ),
      ),
    );
  }
}

/// A soft radial glow, used behind headers ("Glow" ellipses in the spec).
class Glow extends StatelessWidget {
  const Glow({super.key, required this.color, this.alpha = .15});
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _LayersPainter([
          _Layer.radial(const Offset(.5, .5), const Offset(.5, 1),
              [color.withValues(alpha: alpha), color.withValues(alpha: 0)], const [0, 1]),
        ]),
      ),
    );
  }
}
