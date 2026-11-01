// Redesign v2 (Agent Java) building blocks shared by every Android screen:
// the app bar with the alert bell and the profile avatar, and the five-tab
// bottom nav. Sizes and colors are taken from design/mockup-v2 so screens
// match the approved mockup PNGs.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import 'mock_icons.dart';

/// Mockup v2 palette (light). Dark mode reuses the existing Pal tokens.
class V2 {
  V2._();
  static const ink = Color(0xFF0F1F1D);
  static const ink2 = Color(0xFF3D4C49);
  static const mute = Color(0xFF5A6B68);
  static const rule = Color(0xFFE1E9E7);
  static const rule2 = Color(0xFFECF3F1);
  static const bg = Color(0xFFF5F9F8);
  static const surface = Colors.white;
  static const teal50 = Color(0xFFE6F7F5);
  static const teal100 = Color(0xFFC0EDE8);
  static const teal200 = Color(0xFF8FDFD7);
  static const teal500 = Color(0xFF15A697);
  static const teal600 = Color(0xFF0E8579);
  static const teal700 = Color(0xFF0A6A5F);
  static const teal900 = Color(0xFF04332E);
  static const lagoon = Color(0xFF22B8C9);
  static const lime = Color(0xFFC7F25E);
  static const lime700 = Color(0xFF5E8A12);
  static const coral = Color(0xFFFF7A59);
  static const red = Color(0xFFC42B2B);
  static const redSolid = Color(0xFFE04848);
  static const display = 'Poppins';
  static const body = 'Prompt';

  // letterSpacing is always explicit: Material 3 text themes add 0.25 to 0.5 px
  // that the mockups (CSS default 0) do not have. [ls] is in em, like CSS.
  // Leading is split evenly above and below the glyphs, as CSS line-height does.
  static TextStyle d(double size, FontWeight w, Color c, {double? lh, double ls = 0}) => TextStyle(
      fontFamily: display, fontSize: size, fontWeight: w, color: c, height: lh, letterSpacing: ls * size,
      leadingDistribution: TextLeadingDistribution.even);
  static TextStyle b(double size, FontWeight w, Color c, {double? lh, double ls = 0}) => TextStyle(
      fontFamily: body, fontSize: size, fontWeight: w, color: c, height: lh, letterSpacing: ls * size,
      leadingDistribution: TextLeadingDistribution.even);
}

/// Opens the profile from any tab (brief point 6: profile reachable everywhere).
void openProfile(BuildContext context) => Navigator.of(context).pushNamed('/profile');

/// Gradient initial avatar with the lime ring from the mockup.
class V2Avatar extends StatelessWidget {
  const V2Avatar({super.key, this.size = 34, this.onTap});
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = AuthState.user?['full_name'] as String? ?? AuthState.user?['username'] as String? ?? '';
    final initial = name.trim().isEmpty ? 'U' : name.trim()[0].toUpperCase();
    return Semantics(
      button: true,
      label: 'Profil',
      child: GestureDetector(
        onTap: onTap ?? () => openProfile(context),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          // CSS box-shadow rings (0 0 0 3px #fff, 0 0 0 4.5px lime) paint outside the
          // 34 px box without taking layout space, exactly like the mockup.
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [V2.teal500, V2.teal700]),
            boxShadow: [BoxShadow(color: V2.lime, spreadRadius: 4.5), BoxShadow(color: Colors.white, spreadRadius: 3)],
          ),
          child: Text(initial, style: V2.d(size * 13 / 34, FontWeight.w700, Colors.white, lh: 1)),
        ),
      ),
    );
  }
}

/// 38 px square icon button with an optional red count badge.
class V2IconButton extends StatelessWidget {
  const V2IconButton({super.key, required this.icon, required this.label, this.onTap, this.badge = 0});
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge baru' : label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: V2.rule)),
              child: MIcon(icon, size: 20, color: V2.ink2),
            ),
            if (badge > 0)
              Positioned(
                top: -5,
                right: -5,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: V2.redSolid, borderRadius: BorderRadius.circular(9), border: Border.all(color: Colors.white, width: 2)),
                  child: Text(badge > 99 ? '99+' : '$badge', style: V2.d(10, FontWeight.w700, Colors.white, lh: 1)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// The 62 px app bar every v2 screen uses: leading (logo tile or back), title,
/// subtitle, extra actions, then the alert bell and the profile avatar.
class V2AppBar extends StatelessWidget implements PreferredSizeWidget {
  const V2AppBar({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleDot,
    this.back = false,
    this.actions = const [],
    this.alertCount = 0,
    this.onBell,
    this.showBell = true,
    this.showAvatar = true,
  });

  final String title;
  final String? subtitle;
  final Color? subtitleDot;
  final bool back;
  final List<Widget> actions;
  final int alertCount;
  final VoidCallback? onBell;
  final bool showBell;
  final bool showAvatar;

  @override
  Size get preferredSize => const Size.fromHeight(62);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: V2.rule))),
      child: Row(children: [
        if (back)
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(11), border: Border.all(color: V2.rule)),
              child: const MIcon('chevl', size: 18, color: V2.ink2),
            ),
          )
        else
          Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(11), border: Border.all(color: V2.rule)),
            child: Image.asset('assets/icon_circle.png', fit: BoxFit.contain),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.d(16, FontWeight.w700, V2.ink, lh: 1.2)),
            if (subtitle != null)
              Row(children: [
                if (subtitleDot != null) ...[
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: subtitleDot, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                ],
                Flexible(child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: V2.b(11.5, FontWeight.w400, V2.mute, lh: 1.2))),
              ]),
          ]),
        ),
        for (final a in actions) ...[a, const SizedBox(width: 10)],
        if (showBell) ...[
          V2IconButton(icon: 'bell', label: 'Alert', badge: alertCount, onTap: onBell),
          const SizedBox(width: 10),
        ],
        if (showAvatar) const V2Avatar(),
      ]),
    );
  }
}

class V2NavDest {
  const V2NavDest(this.label, this.icon, {this.isNew = false});
  final String label;
  final String icon;

  /// Lime dot for tabs that are new in v2 (Performa, Peta).
  final bool isNew;
}

/// Bottom nav order from the mockups: Agent, Dashboard, Performa, Peta, Laporan.
/// Alert moved to the bell in every app bar.
const v2NavDestinations = [
  V2NavDest('Agent', 'spark'),
  V2NavDest('Dashboard', 'grid'),
  V2NavDest('Performa', 'pulse', isNew: true),
  V2NavDest('Peta', 'map', isNew: true),
  V2NavDest('Laporan', 'file'),
];

class V2BottomNav extends StatelessWidget {
  const V2BottomNav({super.key, required this.index, required this.onTap});

  /// Selected tab, or -1 when a pushed screen (Alert, Profil) is showing.
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: V2.rule))),
      padding: EdgeInsets.fromLTRB(6, 8, 6, 14 + bottom),
      child: SizedBox(
        height: 57,
        child: Row(children: [
          for (var i = 0; i < v2NavDestinations.length; i++) Expanded(child: _item(i)),
        ]),
      ),
    );
  }

  Widget _item(int i) {
    final d = v2NavDestinations[i];
    final on = i == index;
    final c = on ? V2.teal700 : V2.mute;
    return Semantics(
      selected: on,
      button: true,
      label: d.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(i),
        child: Stack(clipBehavior: Clip.none, children: [
          Align(
            alignment: Alignment.topCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 54,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: on ? V2.teal100 : Colors.transparent, borderRadius: BorderRadius.circular(15)),
                child: MIcon(d.icon, size: 20, color: c),
              ),
              const SizedBox(height: 4),
              Text(d.label, maxLines: 1, style: V2.d(11, on ? FontWeight.w700 : FontWeight.w500, c, lh: 1.2)),
            ]),
          ),
          if (d.isNew)
            Positioned(
              top: 0,
              right: 14,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: V2.lime, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Gives every tab screen the alert count and a way to open Watchlist dan Alert,
/// so its [V2AppBar] bell works wherever the screen is shown.
class V2Scope extends InheritedWidget {
  const V2Scope({super.key, required this.alerts, required this.openAlerts, required super.child});
  final int alerts;
  final Future<void> Function([String? question]) openAlerts;

  static V2Scope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<V2Scope>();

  @override
  bool updateShouldNotify(V2Scope old) => old.alerts != alerts;
}

/// CSS `linear-gradient(<deg>deg, ...)` on a box of [size]: same angle and the same
/// gradient line length as the browser, so mockup gradients land on the same pixels.
LinearGradient cssLinear(double deg, List<Color> colors, Size size, {List<double>? stops}) {
  final a = deg * math.pi / 180;
  final dx = math.sin(a), dy = -math.cos(a);
  final len = (size.width * dx).abs() + (size.height * dy).abs();
  final ex = size.width == 0 ? 0.0 : (dx * len / 2) / (size.width / 2);
  final ey = size.height == 0 ? 0.0 : (dy * len / 2) / (size.height / 2);
  return LinearGradient(begin: Alignment(-ex, -ey), end: Alignment(ex, ey), colors: colors, stops: stops);
}

/// CSS `box-shadow: dx dy blur spread color`. CSS blur radius r is a Gaussian with
/// sigma r / 2; Flutter turns blurRadius b into sigma 0.57735 b + 0.5, so convert.
BoxShadow cssShadow(Color color, double dx, double dy, double blur, [double spread = 0]) => BoxShadow(
      color: color,
      offset: Offset(dx, dy),
      blurRadius: blur <= 1 ? 0 : (blur / 2 - 0.5) / 0.57735,
      spreadRadius: spread,
    );
