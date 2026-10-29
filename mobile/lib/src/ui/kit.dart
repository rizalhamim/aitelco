// Shared building blocks of the redesign, sized from design/mockup/spec.
import 'package:flutter/material.dart';

import 'ds.dart';
import 'icons.dart';

/// The official Circle Java app icon on a white rounded tile.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44, this.radius = 14, this.border, this.borderWidth = 1.5, this.shadow = false});
  final double size, radius, borderWidth;
  final Color? border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border!, width: borderWidth),
        boxShadow: shadow ? const [BoxShadow(color: Color(0x40000000), offset: Offset(0, 10), blurRadius: 30)] : null,
        image: const DecorationImage(image: AssetImage('assets/icon_circle.png'), fit: BoxFit.cover),
      ),
    );
  }
}

/// Small rounded tile holding a domain icon (KPI tiles, alert cards, actions).
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, required this.bg, required this.fg, this.size = 32, this.radius = 11, this.iconSize = 18});
  final I3 icon;
  final Color bg, fg;
  final double size, radius, iconSize;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
        alignment: Alignment.center,
        child: Ic(icon, size: iconSize, color: fg),
      );
}

/// Domain tones used for icon tiles.
enum Tone { teal, amber, violet, green, blue, rose, danger, warning }

(Color, Color) toneColors(Pal p, Tone t) => switch (t) {
      Tone.teal => (p.teal50, p.teal700),
      Tone.amber => (p.amber50, p.amber700),
      Tone.violet => (p.violet50, p.violet600),
      Tone.green => (p.green50, p.green600),
      Tone.blue => (p.blue50, p.blue600),
      Tone.rose => (p.rose50, p.rose600),
      Tone.danger => (p.dangerTint, p.danger),
      Tone.warning => (p.warningTint, p.warningText),
    };

/// "↗ 3,8%" pill. [up] picks the color; [neutral] greys it out.
class DeltaPill extends StatelessWidget {
  const DeltaPill(this.text, {super.key, required this.up, this.good});
  final String text;
  final bool up;

  /// Whether the move is good news; defaults to [up].
  final bool? good;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final ok = good ?? up;
    final fg = ok ? p.success : p.danger;
    return Container(
      height: 22,
      padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
      decoration: BoxDecoration(color: ok ? p.successTint : p.dangerTint, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Ic(up ? Icx.trendUp : Icx.trendDown, size: 12, color: fg),
        const SizedBox(width: 2),
        Text(text, style: ts(12, w600, fg)),
      ]),
    );
  }
}

/// The muted KPI tile from Tanya Agent, Peta and Statistik (158 × 140).
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    this.caption,
    this.delta,
    this.deltaUp = true,
    this.deltaGood,
    this.iconSize = 18,
  });
  final I3 icon;
  final Tone tone;
  final String label, value;
  final String? caption, delta;
  final bool deltaUp;
  final bool? deltaGood;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final (bg, fg) = toneColors(p, tone);
    return Container(
      height: 140,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(color: p.surfaceMuted, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 32,
          child: Row(children: [
            IconTile(icon, bg: bg, fg: fg, iconSize: iconSize),
            const Spacer(),
            if (delta != null) DeltaPill(delta!, up: deltaUp, good: deltaGood),
          ]),
        ),
        const SizedBox(height: 6),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w500, p.text2, lh: 1.4)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, maxLines: 1, style: ts(22, w700, p.ink, lh: 1.2, ls: -.003, tabular: true)),
        ),
        const SizedBox(height: 5),
        if (caption != null) Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w400, p.mute)),
      ]),
    );
  }
}

/// Pill chip. Selected chips use teal-50 with a teal-200 outline.
class PillChip extends StatelessWidget {
  const PillChip(this.label, {super.key, this.selected = false, this.onTap, this.icon, this.height = 36, this.accent = false});
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final I3? icon;
  final double height;

  /// Suggestion style: white with a teal-200 outline and teal-700 text.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final fg = selected ? p.teal800 : (accent ? p.teal700 : p.text2);
    return Material(
      color: selected ? p.teal50 : p.surface,
      shape: StadiumBorder(side: BorderSide(color: selected || accent ? p.teal200 : p.rule)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: height,
          padding: EdgeInsets.only(left: icon != null ? 13 : 13, right: 15),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Ic(icon!, size: 16, color: p.teal600), const SizedBox(width: 6)],
            Text(label, style: ts(13, w500, fg)),
          ]),
        ),
      ),
    );
  }
}

/// Status badge: Kritis / Peringatan / Info / Wajib / Terbaru.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, required this.kind});
  final String label;
  final BadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final (bg, fg) = switch (kind) {
      BadgeKind.danger => (p.dangerTint, p.danger),
      BadgeKind.warning => (p.warningTint, p.warningText),
      BadgeKind.info => (p.teal50, p.teal700),
      BadgeKind.success => (p.successTint, p.success),
      BadgeKind.neutral => (p.surfaceMuted, p.text2),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: ts(12, w600, fg)),
    );
  }
}

enum BadgeKind { danger, warning, info, success, neutral }

/// Uppercase overline ("HARI INI", "CARA INSTAL").
class Overline extends StatelessWidget {
  const Overline(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: ts(11, w600, color ?? Pal.of(context).mute, lh: 1.3, ls: .08));
}

/// White card with the hairline border and soft shadow.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = 20, this.color, this.borderColor, this.shadow = true});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color, borderColor;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? p.rule),
        boxShadow: shadow ? p.shadow : null,
      ),
      child: child,
    );
  }
}

/// Dark chart tooltip (title + colored rows), as drawn in the mockups.
class ChartTip extends StatelessWidget {
  const ChartTip({super.key, required this.title, required this.rows, this.width});
  final String title;
  final List<(Color, String, String)> rows;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xF00F1F1D),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x1A0F1F1D), offset: Offset(0, 16), blurRadius: 40, spreadRadius: -4),
          BoxShadow(color: Color(0x0D0F1F1D), offset: Offset(0, 2), blurRadius: 6),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: ts(12, w600, Colors.white)),
        for (final (c, label, value) in rows) ...[
          const SizedBox(height: 6),
          Row(mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max, children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            if (width == null)
              Text(label, style: ts(12, w400, const Color(0xFFC9D6D3)))
            else
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, w400, const Color(0xFFC9D6D3)))),
            if (width == null) const SizedBox(width: 16),
            Text(value, style: ts(12, w600, Colors.white, tabular: true)),
          ]),
        ],
      ]),
    );
  }
}

/// Square 44 icon button with a hairline border (header actions).
class SquareIconButton extends StatelessWidget {
  const SquareIconButton(this.icon, {super.key, this.onTap, this.size = 44, this.iconSize = 20, this.bordered = true, this.tooltip, this.color});
  final I3 icon;
  final VoidCallback? onTap;
  final double size, iconSize;
  final bool bordered;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final btn = Material(
      color: bordered ? p.surface : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: bordered ? BorderSide(color: p.rule) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Center(child: Ic(icon, size: iconSize, color: color ?? p.text2))),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Primary 52 px button (Masuk, Unduh PDF, Download APK).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton(this.label, {super.key, this.onTap, this.icon, this.loading = false, this.height = 52, this.color, this.fg, this.radius = 12});
  final String label;
  final VoidCallback? onTap;
  final I3? icon;
  final bool loading;
  final double height, radius;
  final Color? color, fg;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final f = fg ?? Colors.white;
    return Material(
      color: color ?? p.teal600,
      borderRadius: BorderRadius.circular(radius),
      shadowColor: const Color(0x0D0F1F1D),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: loading ? null : onTap,
        child: SizedBox(
          height: height,
          child: Center(
            child: loading
                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: f, strokeWidth: 2.4))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Ic(icon!, size: 22, color: f), const SizedBox(width: 10)],
                    Text(label, style: ts(14, w600, f)),
                  ]),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet grab handle.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(color: Pal.of(context).chartGrey, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

/// Simple sparkline with a soft area fill (Dashboard indicator cards).
class Sparkline extends StatelessWidget {
  const Sparkline(this.values, {super.key, required this.color, this.height = 40, this.fill = true, this.strokeWidth = 2});
  final List<double?> values;
  final Color color;
  final double height, strokeWidth;
  final bool fill;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: CustomPaint(painter: _SparkPainter(values, color, fill, strokeWidth), size: Size.infinite),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color, this.fill, this.strokeWidth);
  final List<double?> values;
  final Color color;
  final bool fill;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final v = values.whereType<double>().toList();
    if (v.length < 2) return;
    final lo = v.reduce((a, b) => a < b ? a : b), hi = v.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    final pad = strokeWidth;
    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final y = values[i];
      if (y == null) continue;
      pts.add(Offset(
        values.length == 1 ? 0 : i * size.width / (values.length - 1),
        pad + (1 - (y - lo) / span) * (size.height - pad * 2),
      ));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final cx = (a.dx + b.dx) / 2;
      path.cubicTo(cx, a.dy, cx, b.dy, b.dx, b.dy);
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(pts.last.dx, size.height)
        ..lineTo(pts.first.dx, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values || old.color != color;
}

/// Circle avatar with the user's initial.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.size = 44, this.bg, this.fg, this.fontSize = 16});
  final String name;
  final double size, fontSize;
  final Color? bg, fg;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg ?? p.teal100, shape: BoxShape.circle),
      child: Text(initial, style: ts(fontSize, w600, fg ?? p.teal800)),
    );
  }
}

/// Lightweight skeleton block for loading states.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height, radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Pal.of(context).surfaceMuted, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Inline error / empty message with a retry action.
class InlineMessage extends StatelessWidget {
  const InlineMessage(this.text, {super.key, this.onRetry, this.icon});
  final String text;
  final VoidCallback? onRetry;
  final I3? icon;

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Ic(icon ?? Icx.alertCircle, size: 24, color: p.mute),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: ts(13, w400, p.text2, lh: 1.5)),
        if (onRetry != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text('Coba lagi', style: ts(13, w600, p.teal700))),
        ],
      ]),
    );
  }
}

void showToast(BuildContext context, String msg, {bool ok = true}) {
  final p = Pal.of(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: ts(13, w500, Colors.white)),
    backgroundColor: ok ? p.teal800 : p.dangerSolid,
    behavior: SnackBarBehavior.floating,
  ));
}
