// Lucide icons drawn the way the mockup draws them: a 2 px stroke at every
// size. Lucide ships fixed-stroke fonts (weight 400 = 2 px at 24, 500 = 2.5,
// 600 = 3), so a 16 px icon uses the 600 font to keep a 2 px line.
// Every IconData here is const so release builds can still tree-shake fonts.
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';

class I3 {
  const I3(this.w400, this.w500, this.w600);
  final IconData w400, w500, w600;

  IconData forSize(double size) => size <= 17 ? w600 : (size <= 21 ? w500 : w400);
}

class Ic extends StatelessWidget {
  const Ic(this.icon, {super.key, this.size = 24, this.color});
  final I3 icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Icon(icon.forSize(size), size: size, color: color);
}

/// The icon set used by the redesign (names follow design/mockup "Icon/…").
class Icx {
  Icx._();
  static const activity = I3(LucideIcons400.activity, LucideIcons500.activity, LucideIcons600.activity);
  static const alertCircle = I3(LucideIcons400.circleAlert, LucideIcons500.circleAlert, LucideIcons600.circleAlert);
  static const alertTriangle = I3(LucideIcons400.triangleAlert, LucideIcons500.triangleAlert, LucideIcons600.triangleAlert);
  static const arrowRight = I3(LucideIcons400.arrowRight, LucideIcons500.arrowRight, LucideIcons600.arrowRight);
  static const barChart = I3(LucideIcons400.chartColumn, LucideIcons500.chartColumn, LucideIcons600.chartColumn);
  static const bell = I3(LucideIcons400.bell, LucideIcons500.bell, LucideIcons600.bell);
  static const bellRing = I3(LucideIcons400.bellRing, LucideIcons500.bellRing, LucideIcons600.bellRing);
  static const check = I3(LucideIcons400.check, LucideIcons500.check, LucideIcons600.check);
  static const chevronDown = I3(LucideIcons400.chevronDown, LucideIcons500.chevronDown, LucideIcons600.chevronDown);
  static const chevronLeft = I3(LucideIcons400.chevronLeft, LucideIcons500.chevronLeft, LucideIcons600.chevronLeft);
  static const chevronRight = I3(LucideIcons400.chevronRight, LucideIcons500.chevronRight, LucideIcons600.chevronRight);
  static const clock = I3(LucideIcons400.clock, LucideIcons500.clock, LucideIcons600.clock);
  static const copy = I3(LucideIcons400.copy, LucideIcons500.copy, LucideIcons600.copy);
  static const dashboard = I3(LucideIcons400.layoutDashboard, LucideIcons500.layoutDashboard, LucideIcons600.layoutDashboard);
  static const database = I3(LucideIcons400.database, LucideIcons500.database, LucideIcons600.database);
  static const download = I3(LucideIcons400.download, LucideIcons500.download, LucideIcons600.download);
  static const eye = I3(LucideIcons400.eye, LucideIcons500.eye, LucideIcons600.eye);
  static const eyeOff = I3(LucideIcons400.eyeOff, LucideIcons500.eyeOff, LucideIcons600.eyeOff);
  static const fileText = I3(LucideIcons400.fileText, LucideIcons500.fileText, LucideIcons600.fileText);
  static const history = I3(LucideIcons400.history, LucideIcons500.history, LucideIcons600.history);
  static const layers = I3(LucideIcons400.layers, LucideIcons500.layers, LucideIcons600.layers);
  static const locate = I3(LucideIcons400.locateFixed, LucideIcons500.locateFixed, LucideIcons600.locateFixed);
  static const lock = I3(LucideIcons400.lock, LucideIcons500.lock, LucideIcons600.lock);
  static const logOut = I3(LucideIcons400.logOut, LucideIcons500.logOut, LucideIcons600.logOut);
  static const mail = I3(LucideIcons400.mail, LucideIcons500.mail, LucideIcons600.mail);
  static const map = I3(LucideIcons400.map, LucideIcons500.map, LucideIcons600.map);
  static const mapPin = I3(LucideIcons400.mapPin, LucideIcons500.mapPin, LucideIcons600.mapPin);
  static const maximize = I3(LucideIcons400.maximize2, LucideIcons500.maximize2, LucideIcons600.maximize2);
  static const mic = I3(LucideIcons400.mic, LucideIcons500.mic, LucideIcons600.mic);
  static const minus = I3(LucideIcons400.minus, LucideIcons500.minus, LucideIcons600.minus);
  static const moon = I3(LucideIcons400.moon, LucideIcons500.moon, LucideIcons600.moon);
  static const plus = I3(LucideIcons400.plus, LucideIcons500.plus, LucideIcons600.plus);
  static const radio = I3(LucideIcons400.radio, LucideIcons500.radio, LucideIcons600.radio);
  static const refresh = I3(LucideIcons400.refreshCw, LucideIcons500.refreshCw, LucideIcons600.refreshCw);
  static const rocket = I3(LucideIcons400.rocket, LucideIcons500.rocket, LucideIcons600.rocket);
  static const search = I3(LucideIcons400.search, LucideIcons500.search, LucideIcons600.search);
  static const send = I3(LucideIcons400.send, LucideIcons500.send, LucideIcons600.send);
  static const share = I3(LucideIcons400.share2, LucideIcons500.share2, LucideIcons600.share2);
  static const sheet = I3(LucideIcons400.sheet, LucideIcons500.sheet, LucideIcons600.sheet);
  static const shield = I3(LucideIcons400.shieldCheck, LucideIcons500.shieldCheck, LucideIcons600.shieldCheck);
  static const sliders = I3(LucideIcons400.slidersHorizontal, LucideIcons500.slidersHorizontal, LucideIcons600.slidersHorizontal);
  static const smartphone = I3(LucideIcons400.smartphone, LucideIcons500.smartphone, LucideIcons600.smartphone);
  static const sparkles = I3(LucideIcons400.sparkles, LucideIcons500.sparkles, LucideIcons600.sparkles);
  static const square = I3(LucideIcons400.square, LucideIcons500.square, LucideIcons600.square);
  static const sun = I3(LucideIcons400.sun, LucideIcons500.sun, LucideIcons600.sun);
  static const trendDown = I3(LucideIcons400.trendingDown, LucideIcons500.trendingDown, LucideIcons600.trendingDown);
  static const trendUp = I3(LucideIcons400.trendingUp, LucideIcons500.trendingUp, LucideIcons600.trendingUp);
  static const user = I3(LucideIcons400.user, LucideIcons500.user, LucideIcons600.user);
  static const userPlus = I3(LucideIcons400.userPlus, LucideIcons500.userPlus, LucideIcons600.userPlus);
  static const users = I3(LucideIcons400.users, LucideIcons500.users, LucideIcons600.users);
  static const wallet = I3(LucideIcons400.wallet, LucideIcons500.wallet, LucideIcons600.wallet);
  static const x = I3(LucideIcons400.x, LucideIcons500.x, LucideIcons600.x);
}

/// The mockup's spreadsheet glyph: a frame, two rules and one column line
/// (Lucide's "sheet" draws two columns).
class SheetIcon extends StatelessWidget {
  const SheetIcon({super.key, this.size = 20, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _SheetPainter(color));
}

class _SheetPainter extends CustomPainter {
  const _SheetPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final k = s.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(3 * k, 3 * k, 18 * k, 18 * k), Radius.circular(2 * k)), paint);
    canvas.drawLine(Offset(3 * k, 9 * k), Offset(21 * k, 9 * k), paint);
    canvas.drawLine(Offset(3 * k, 15 * k), Offset(21 * k, 15 * k), paint);
    canvas.drawLine(Offset(9 * k, 3 * k), Offset(9 * k, 21 * k), paint);
  }

  @override
  bool shouldRepaint(covariant _SheetPainter old) => old.color != color;
}
